import Combine
import Foundation

struct FlatComment: Identifiable {
    let comment: Comment
    let depth: Int

    var id: Int64 { comment.id }
}

@MainActor
final class CardDetailViewModel: ObservableObject {
    @Published var card: Card?
    /// 评论树；赋值时同步展开成 `flatComments`，界面不在每次渲染时重新展开。
    @Published var comments: [Comment] = [] {
        didSet { flatComments = Self.flatten(comments) }
    }
    @Published private(set) var flatComments: [FlatComment] = []
    @Published var interests: [Interest] = []
    @Published var loading = true
    @Published var actionLoading = false
    @Published var error: String?
    @Published var rejected = false
    @Published var notice: String?

    private let api = AppServices.shared.api
    private var cancellables = Set<AnyCancellable>()
    private var lastLoadedAt: Date?
    private var inflight: Task<Void, Never>?
    let cardId: Int64

    init(cardId: Int64) {
        self.cardId = cardId
        AppServices.shared.realtime.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .newComment(let comment, _):
                        guard comment.cardId == self.cardId else { return }
                        ProfileCache.shared.update(
                            userId: comment.userId,
                            nickname: comment.nickname,
                            avatar: comment.avatar
                        )
                        guard !Self.contains(self.comments, id: comment.id) else { return }
                        self.comments = self.insertComment(self.comments, comment)
                        if var card = self.card {
                            card.commentCount += 1
                            self.card = card
                        }
                    case .newInterest(let interest):
                        guard interest.cardId == self.cardId,
                              !self.interests.contains(where: { $0.id == interest.id }) else { return }
                        ProfileCache.shared.update(
                            userId: interest.userId,
                            nickname: interest.nickname,
                            avatar: interest.avatar
                        )
                        self.interests.append(interest)
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func insertComment(_ list: [Comment], _ comment: Comment) -> [Comment] {
        guard let parentId = comment.parentId else { return list + [comment] }
        var inserted = false
        var result: [Comment] = []
        for item in list {
            if item.id == parentId {
                var parent = item
                parent.children = (parent.children ?? []) + [comment]
                result.append(parent)
                inserted = true
            } else {
                var parent = item
                let children = parent.children ?? []
                let updated = insertComment(children, comment)
                if updated.count != children.count {
                    inserted = true
                    parent.children = updated
                }
                result.append(parent)
            }
        }
        return inserted ? result : list + [comment]
    }

    /// 本地删除评论：被删的节点去掉，子回复上提到它的位置，与服务端过滤后的展示一致。
    private static func removeComment(_ list: [Comment], id: Int64) -> [Comment] {
        var result: [Comment] = []
        for item in list {
            if item.id == id {
                result.append(contentsOf: item.children ?? [])
            } else {
                var copy = item
                if let children = copy.children, !children.isEmpty {
                    copy.children = removeComment(children, id: id)
                }
                result.append(copy)
            }
        }
        return result
    }

    private static func contains(_ list: [Comment], id: Int64) -> Bool {
        list.contains { $0.id == id || contains($0.children ?? [], id: id) }
    }

    private static func flatten(_ list: [Comment], depth: Int = 1) -> [FlatComment] {
        var result: [FlatComment] = []
        for comment in list {
            result.append(FlatComment(comment: comment, depth: depth))
            if let children = comment.children, !children.isEmpty {
                result.append(contentsOf: flatten(children, depth: min(3, depth + 1)))
            }
        }
        return result
    }

    /// 页面出现时调用：首次加载；之后只在超过 30 秒新鲜期时静默刷新。
    func loadIfStale() async {
        if let last = lastLoadedAt, Date().timeIntervalSince(last) < 30 { return }
        await load()
    }

    /// 同一时刻只有一个在途加载；需求、评论、意向并行请求。
    func load() async {
        if let inflight {
            await inflight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        inflight = task
        await task.value
        inflight = nil
    }

    private func performLoad() async {
        loading = card == nil
        error = nil
        rejected = false
        do {
            async let cardRequest = api.card(cardId)
            async let commentsRequest = api.comments(cardId: cardId)
            let card = try await cardRequest
            let comments = try await commentsRequest
            let interests = card.mine ? try await api.cardInterests(cardId: cardId) : []
            self.card = card
            self.comments = comments
            self.interests = interests
            // 一次性写入资料缓存：只发一次变更、写一次盘
            var updates: [ProfileUpdate] = []
            for item in flatComments where !item.comment.deleted && item.comment.nickname != nil {
                updates.append(ProfileUpdate(
                    userId: item.comment.userId,
                    nickname: item.comment.nickname,
                    avatar: item.comment.avatar
                ))
            }
            for interest in interests {
                updates.append(ProfileUpdate(
                    userId: interest.userId,
                    nickname: interest.nickname,
                    avatar: interest.avatar
                ))
            }
            ProfileCache.shared.updateMany(updates)
            lastLoadedAt = Date()
            loading = false
        } catch {
            loading = false
            fail(error)
        }
    }

    func join() async {
        guard !actionLoading else { return }
        actionLoading = true
        error = nil
        rejected = false
        do {
            _ = try await api.sendInterest(cardId: cardId, note: nil)
            if var card {
                card.interestExpressed = true
                card.interestStatus = 0
                self.card = card
            }
            notice = "已发送，等待回应"
        } catch {
            fail(error)
        }
        actionLoading = false
    }

    /// 同意意向：本地改状态和已接受人数；满员时需求结束、其余待处理意向失效（与服务端规则一致）。
    func acceptInterest(id: Int64) async -> Int64? {
        guard !actionLoading else { return nil }
        actionLoading = true
        do {
            let result = try await api.acceptInterest(id: id)
            notice = "已同意，可以开始聊天了"
            if let index = interests.firstIndex(where: { $0.id == id }) {
                interests[index].status = 1
                interests[index].conversationId = result.conversationId
            }
            if var card {
                card.acceptedCount += 1
                if card.acceptedCount >= card.headcount {
                    card.status = 3
                    card.statusLabel = "已结束"
                    for index in interests.indices where interests[index].status == 0 {
                        interests[index].status = 4
                    }
                }
                self.card = card
            }
            actionLoading = false
            return result.conversationId
        } catch {
            fail(error)
            actionLoading = false
            return nil
        }
    }

    func ignoreInterest(id: Int64) async {
        actionLoading = true
        do {
            try await api.ignoreInterest(id: id)
            if let index = interests.firstIndex(where: { $0.id == id }) {
                interests[index].status = 2
            }
        } catch {
            fail(error)
        }
        actionLoading = false
    }

    /// 发评论/回复：把接口返回的评论直接插进本地树，不再整页重查。
    func submitComment(
        _ content: String,
        replyTo: Comment?,
        imageIds: [Int64] = []
    ) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !imageIds.isEmpty else { return false }
        actionLoading = true
        error = nil
        rejected = false
        do {
            let created: Comment
            if let replyTo {
                created = try await api.replyComment(
                    id: replyTo.id,
                    body: CreateCommentRequest(
                        content: text,
                        parentId: replyTo.id,
                        imageIds: imageIds.isEmpty ? nil : imageIds
                    )
                )
            } else {
                created = try await api.createComment(
                    cardId: cardId,
                    body: CreateCommentRequest(
                        content: text,
                        imageIds: imageIds.isEmpty ? nil : imageIds
                    )
                )
            }
            if !Self.contains(comments, id: created.id) {
                comments = insertComment(comments, created)
                if var card {
                    card.commentCount += 1
                    self.card = card
                }
            }
            actionLoading = false
            return true
        } catch {
            fail(error)
            actionLoading = false
            return false
        }
    }

    func deleteComment(id: Int64) async {
        do {
            try await api.deleteComment(id: id)
            if Self.contains(comments, id: id) {
                comments = Self.removeComment(comments, id: id)
                if var card {
                    card.commentCount = max(0, card.commentCount - 1)
                    self.card = card
                }
            }
        } catch {
            fail(error)
        }
    }

    func pause() async {
        await cardAction { try await self.api.pauseCard(self.cardId) }
    }

    func resume() async {
        await cardAction { try await self.api.resumeCard(self.cardId) }
    }

    func close() async {
        await cardAction { try await self.api.closeCard(self.cardId) }
    }

    func deleteCard() async -> Bool {
        actionLoading = true
        do {
            try await api.deleteCard(cardId)
            actionLoading = false
            return true
        } catch {
            fail(error)
            actionLoading = false
            return false
        }
    }

    /// 改评论区模式只影响之后的评论，已有评论不变；本地改字段即可。
    func setCommentMode(_ mode: String) async {
        do {
            try await api.setCommentMode(cardId: cardId, mode: mode)
            if var card {
                card.commentMode = mode
                self.card = card
            }
        } catch {
            fail(error)
        }
    }

    /// 暂停/恢复/结束：接口返回最新需求，直接替换本地。
    private func cardAction(_ block: @escaping () async throws -> Card) async {
        actionLoading = true
        error = nil
        rejected = false
        do {
            card = try await block()
        } catch {
            fail(error)
        }
        actionLoading = false
    }

    private func fail(_ error: Error) {
        self.error = error.localizedDescription
        let code = (error as? ApiException)?.code
        rejected = code == "CONTENT_REJECTED"
            || code == "AVATAR_REJECTED"
            || code == "IMAGE_REJECTED"
    }
}
