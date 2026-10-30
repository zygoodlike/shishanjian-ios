import Combine
import Foundation

@MainActor
final class MeViewModel: ObservableObject {
    @Published var profile: Profile?
    @Published var loading = true
    @Published var saving = false
    @Published var error: String?
    @Published var avatarRejected = false

    private let services = AppServices.shared
    private var lastLoadedAt: Date?

    /// 回到「我的」时只在超过 60 秒才静默刷新；登录态缓存保证页面立即有内容。
    func loadIfStale() async {
        if let last = lastLoadedAt, Date().timeIntervalSince(last) < 60 { return }
        await load()
    }

    func load(bypassCache: Bool = false) async {
        loading = profile == nil
        error = nil
        avatarRejected = false
        do {
            let value = try await services.api.profile(bypassCache: bypassCache)
            profile = value
            lastLoadedAt = Date()
            services.auth.updateUsername(value.user?.username)
            services.auth.updateNickname(value.user?.nickname)
            services.auth.updateAvatar(value.user?.avatarKey)
            ProfileCache.shared.update(
                userId: value.user?.id,
                nickname: value.user?.nickname,
                avatar: value.user?.avatarKey
            )
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }

    func logout() async {
        try? await services.api.logout()
        services.auth.clear()
    }

    func saveProfile(nickname: String, bio: String) async -> Bool {
        saving = true
        error = nil
        avatarRejected = false
        do {
            let updated = try await services.api.updateProfile(
                UpdateProfileRequest(
                    nickname: nickname.isEmpty ? nil : nickname,
                    bio: bio.isEmpty ? nil : bio
                )
            )
            profile = updated
            services.auth.updateNickname(updated.user?.nickname)
            services.auth.updateAvatar(updated.user?.avatarKey)
            ProfileCache.shared.update(
                userId: updated.user?.id,
                nickname: updated.user?.nickname,
                avatar: updated.user?.avatarKey
            )
            saving = false
            return true
        } catch {
            saving = false
            self.error = error.localizedDescription
            return false
        }
    }

    func uploadAvatar(_ data: Data) async -> Bool {
        saving = true
        error = nil
        avatarRejected = false
        do {
            let media = try await services.repository.uploadAvatar(data)
            await load(bypassCache: true)
            saving = false
            if media.status == 0 {
                error = "头像审核中，通过后会自动显示"
            } else if media.status == 2 {
                avatarRejected = true
                error = "头像未通过审核，请更换后重试"
            }
            return true
        } catch {
            saving = false
            self.error = error.localizedDescription
            avatarRejected = (error as? ApiException)?.code == "AVATAR_REJECTED"
                || (error as? ApiException)?.code == "IMAGE_REJECTED"
            return false
        }
    }
}

@MainActor
final class MyCardsViewModel: ObservableObject {
    @Published var group = "active"
    @Published var cards: [Card] = []
    @Published var loading = true
    @Published var error: String?

    private let api = AppServices.shared.api
    private var lastLoadedAt: Date?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 审核结果或他人操作改了状态时，页面内静默刷新当前分组。
        AppServices.shared.realtime.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self, case .cardStatusChanged = event else { return }
                Task { await self.load(self.group, bypassCache: true) }
            }
            .store(in: &cancellables)
    }

    /// 页面出现时调用：首次加载；回到页面只在超过 60 秒新鲜期时静默刷新当前分组。
    func loadIfStale() async {
        if let last = lastLoadedAt, Date().timeIntervalSince(last) < 60 { return }
        await load(group)
    }

    func load(_ group: String, bypassCache: Bool = false) async {
        let switching = self.group != group
        self.group = group
        loading = cards.isEmpty || switching
        error = nil
        do {
            cards = try await api.myCards(group: group, bypassCache: bypassCache)
            lastLoadedAt = Date()
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class MyInterestsViewModel: ObservableObject {
    @Published var interests: [Interest] = []
    @Published var loading = true
    @Published var error: String?

    private let api = AppServices.shared.api
    private let throttle = RefreshThrottle()
    private var lastLoadedAt: Date?

    func loadIfStale() async {
        if let last = lastLoadedAt, Date().timeIntervalSince(last) < 60 { return }
        await load()
    }

    func load(manual: Bool = false) async {
        if manual && !throttle.tryAcquire() { return }
        loading = !manual && interests.isEmpty
        error = nil
        do {
            interests = try await api.myInterests(bypassCache: manual)
            lastLoadedAt = Date()
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }

    /// 撤回后本地改状态，不再整页重查。
    func withdraw(id: Int64) async {
        do {
            try await api.withdrawInterest(id: id)
            if let index = interests.firstIndex(where: { $0.id == id }) {
                interests[index].status = 3
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class ReceivedInterestsViewModel: ObservableObject {
    @Published var interests: [Interest] = []
    @Published var loading = true
    @Published var actionId: Int64?
    @Published var error: String?

    private let api = AppServices.shared.api
    private let realtime = AppServices.shared.realtime
    private var cancellables = Set<AnyCancellable>()
    private let throttle = RefreshThrottle()

    init() {
        realtime.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self, case .newInterest(let item) = event, item.status == 0 else { return }
                    ProfileCache.shared.update(
                        userId: item.userId,
                        nickname: item.nickname,
                        avatar: item.avatar
                    )
                    if !self.interests.contains(where: { $0.id == item.id }) {
                        self.interests.insert(item, at: 0)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private var lastLoadedAt: Date?

    func loadIfStale() async {
        if let last = lastLoadedAt, Date().timeIntervalSince(last) < 60 { return }
        await load()
    }

    func load(manual: Bool = false) async {
        if manual && !throttle.tryAcquire() { return }
        loading = !manual && interests.isEmpty
        error = nil
        do {
            interests = try await api.receivedInterests(bypassCache: manual)
            lastLoadedAt = Date()
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }

    /// 同意后本地改状态并写入会话 ID；满员导致的其他意向失效在下次进入页面时同步。
    func accept(id: Int64) async -> Int64? {
        actionId = id
        error = nil
        do {
            let result = try await api.acceptInterest(id: id)
            actionId = nil
            if let index = interests.firstIndex(where: { $0.id == id }) {
                interests[index].status = 1
                interests[index].conversationId = result.conversationId
            }
            lastLoadedAt = nil
            return result.conversationId
        } catch {
            actionId = nil
            self.error = error.localizedDescription
            return nil
        }
    }

    func ignore(id: Int64) async {
        actionId = id
        error = nil
        do {
            try await api.ignoreInterest(id: id)
            actionId = nil
            if let index = interests.firstIndex(where: { $0.id == id }) {
                interests[index].status = 2
            }
        } catch {
            actionId = nil
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class ReceivedCommentsViewModel: ObservableObject {
    @Published var comments: [ReceivedComment] = []
    @Published var loading = true
    @Published var error: String?

    private let api = AppServices.shared.api
    private let realtime = AppServices.shared.realtime
    private var cancellables = Set<AnyCancellable>()
    private let throttle = RefreshThrottle()

    init() {
        realtime.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self, case .newComment(let comment, let cardTitle) = event else { return }
                    ProfileCache.shared.update(
                        userId: comment.userId,
                        nickname: comment.nickname,
                        avatar: comment.avatar
                    )
                    guard !self.comments.contains(where: { $0.id == comment.id }) else { return }
                    let item = ReceivedComment(
                        id: comment.id,
                        cardId: comment.cardId,
                        cardTitle: cardTitle,
                        userId: comment.userId,
                        nickname: comment.nickname,
                        avatar: comment.avatar,
                        content: comment.content,
                        parentId: comment.parentId,
                        replyToNickname: comment.replyToNickname,
                        createdAt: comment.createdAt
                    )
                    self.comments.insert(item, at: 0)
                }
            }
            .store(in: &cancellables)
    }

    private var lastLoadedAt: Date?

    func loadIfStale() async {
        if let last = lastLoadedAt, Date().timeIntervalSince(last) < 60 { return }
        await load()
    }

    func load(manual: Bool = false) async {
        if manual && !throttle.tryAcquire() { return }
        loading = !manual && comments.isEmpty
        error = nil
        do {
            comments = try await api.receivedComments(bypassCache: manual)
            lastLoadedAt = Date()
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class DevicesViewModel: ObservableObject {
    @Published var sessions: [DeviceSession] = []
    @Published var loading = true
    @Published var error: String?

    private let services = AppServices.shared

    func load() async {
        loading = sessions.isEmpty
        error = nil
        do {
            sessions = try await services.api.sessions()
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }

    func revoke(sid: String) async {
        do {
            try await services.api.revokeSession(sid: sid)
            sessions.removeAll { $0.sid == sid }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func revokeAll() async {
        do {
            try await services.api.revokeAllSessions()
            services.auth.clear()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() async {
        try? await services.api.logout()
        services.auth.clear()
    }

    func deleteAccount(password: String) async -> Bool {
        error = nil
        do {
            try await services.api.deleteAccount(DeleteAccountRequest(password: password))
            services.auth.clear()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
