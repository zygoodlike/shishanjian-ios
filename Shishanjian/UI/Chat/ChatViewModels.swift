import Combine
import Foundation

@MainActor
final class ChatListViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var loading = true
    @Published var error: String?

    private let api = AppServices.shared.api
    private let realtime = AppServices.shared.realtime
    private let throttle = RefreshThrottle()
    private var cancellables = Set<AnyCancellable>()
    private var lastLoadedAt: Date?
    private var inflight: Task<Void, Never>?

    init() {
        realtime.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .connected:
                        // 重连后补拉一次；刚加载过（与回到前台/首次打开撞在一起）就跳过
                        guard let last = self.lastLoadedAt, Date().timeIntervalSince(last) > 5 else { return }
                        await self.refresh()
                    case .newMessage(let convId, let message, let senderName, _):
                        self.applyMessage(convId: convId, message: message, senderName: senderName)
                    case .recalled(let convId, let message, _, _):
                        self.applyRecall(convId: convId, message: message)
                    case .read(let convId, let userId):
                        self.applyRead(convId: convId, userId: userId)
                    case .profileChanged(let userId, let nickname, let avatar):
                        self.applyProfile(userId: userId, nickname: nickname, avatar: avatar)
                    case .newComment(_, _), .newInterest(_), .disconnected, .cardStatusChanged:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    private var currentUserId: Int64? { AppServices.shared.auth.userId }

    private func applyMessage(convId: Int64, message: Message, senderName: String?) {
        guard let index = conversations.firstIndex(where: { $0.id == convId }) else {
            Task { await refresh() }
            return
        }
        var item = conversations[index]
        if message.type == 2 {
            item.lastMessage = "[图片]"
        } else if message.type == 3 {
            let text = message.content ?? ""
            item.lastMessage = text.isEmpty ? "[图片]" : text + " [图片]"
        } else {
            item.lastMessage = message.content ?? ""
        }
        item.lastMsgId = message.id
        item.lastMsgAt = message.createdAt ?? item.lastMsgAt
        if message.senderId != currentUserId {
            item.unread += 1
        }
        if let senderName, !senderName.isEmpty, item.otherNickname != senderName {
            item.otherNickname = senderName
        }
        conversations.remove(at: index)
        conversations.insert(item, at: 0)
    }

    private func applyRecall(convId: Int64, message: Message) {
        guard let index = conversations.firstIndex(where: { $0.id == convId }),
              conversations[index].lastMsgId == message.id else { return }
        conversations[index].lastMessage = "消息已撤回"
    }

    private func applyRead(convId: Int64, userId: Int64) {
        guard userId == currentUserId,
              let index = conversations.firstIndex(where: { $0.id == convId }) else { return }
        conversations[index].unread = 0
    }

    private func applyProfile(userId: Int64, nickname: String?, avatar: String?) {
        guard let index = conversations.firstIndex(where: { $0.otherUserId == userId }) else { return }
        if let nickname, !nickname.isEmpty { conversations[index].otherNickname = nickname }
        conversations[index].otherAvatar = avatar
    }

    /// 首次打开加载；之后切回消息 tab 时，长连接在线且 60 秒内加载过就不请求。
    func loadIfNeeded() async {
        if let last = lastLoadedAt,
           realtime.isConnected,
           Date().timeIntervalSince(last) < 60 {
            return
        }
        await refresh()
    }

    /// 同一时刻只保留一个在途请求，重复调用直接等待它完成。
    func refresh(manual: Bool = false) async {
        if manual && !throttle.tryAcquire() { return }
        if let inflight {
            await inflight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(manual: manual)
        }
        inflight = task
        await task.value
        inflight = nil
    }

    private func performRefresh(manual: Bool) async {
        loading = !manual && conversations.isEmpty
        error = nil
        do {
            let list = try await api.conversations(bypassCache: manual)
            ProfileCache.shared.updateMany(list.map {
                ProfileUpdate(userId: $0.otherUserId, nickname: $0.otherNickname, avatar: $0.otherAvatar)
            })
            conversations = list
            lastLoadedAt = Date()
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class ChatDetailViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var loading = true
    @Published var sending = false
    @Published var loadingOlder = false
    @Published var hasOlder = false
    @Published var error: String?
    @Published var conversationStatus: Int
    @Published var title: String?
    @Published var otherAvatar: String?
    @Published var cardTitle: String?
    /// 本地缓存已经读过（有没有内容都算），读完前不显示骨架，避免闪一下。
    @Published private(set) var cacheChecked = false

    private let api = AppServices.shared.api
    private let realtime = AppServices.shared.realtime
    private var cancellables = Set<AnyCancellable>()
    private var messageIds = Set<Int64>()
    private var openedAt: Date?
    private var conversationLoaded = false
    let convId: Int64
    let otherUserId: Int64?

    init(
        convId: Int64,
        initialStatus: Int,
        title: String? = nil,
        cardTitle: String? = nil,
        otherUserId: Int64? = nil
    ) {
        self.convId = convId
        self.conversationStatus = initialStatus
        self.title = title
        self.cardTitle = cardTitle
        self.otherUserId = otherUserId
        observeRealtime()
    }

    /// 页面首次出现：读本地缓存 → 拉增量 → 拉一次会话信息。再次出现不重复请求。
    func open() async {
        guard openedAt == nil else { return }
        openedAt = Date()
        let cached = await ChatCache.load(userId: AppServices.shared.auth.userId, convId: convId)
        if !cached.isEmpty, messages.isEmpty {
            setMessages(cached)
            loading = false
        }
        cacheChecked = true
        await loadInitial()
        await loadConversation()
    }

    /// 对方改昵称后，重新进入会话或收到消息时刷新标题。
    func loadConversation() async {
        guard let conversation = try? await api.conversation(id: convId) else { return }
        conversationLoaded = true
        title = conversation.otherNickname
        otherAvatar = conversation.otherAvatar
        cardTitle = conversation.cardTitle
        conversationStatus = conversation.status
        ProfileCache.shared.update(
            userId: conversation.otherUserId,
            nickname: conversation.otherNickname,
            avatar: conversation.otherAvatar
        )
    }

    private func observeRealtime() {
        realtime.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .connected:
                        // 页面没打开或刚打开不到 5 秒（open 已经在拉）时不重复补拉
                        guard let opened = self.openedAt, Date().timeIntervalSince(opened) > 5 else { return }
                        await self.fetchAfterLatest()
                        if !self.conversationLoaded { await self.loadConversation() }
                    case .newMessage(let convId, let message, let senderName, _):
                        guard convId == self.convId else { return }
                        if let senderName, !senderName.isEmpty { self.title = senderName }
                        if self.append(message) { self.persist() }
                        self.realtime.sendRead(convId: self.convId)
                    case .recalled(let convId, let message, _, _):
                        guard convId == self.convId else { return }
                        self.applyRecall(message)
                    case .profileChanged(let userId, let nickname, let avatar):
                        guard userId == self.otherUserId else { break }
                        if let nickname, !nickname.isEmpty { self.title = nickname }
                        self.otherAvatar = avatar
                    case .newComment(_, _), .newInterest(_), .read, .disconnected, .cardStatusChanged:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func fetchAfterLatest() async {
        guard let lastId = messages.last?.id else {
            await loadInitial()
            return
        }
        guard let page = try? await api.messages(conversationId: convId, afterId: lastId, limit: 50) else {
            return
        }
        let incoming = (page.items ?? []).sorted { $0.id < $1.id }
        var added = false
        for message in incoming where append(message) {
            added = true
        }
        if added {
            persist()
            await markRead()
        }
    }

    func loadInitial() async {
        if !messages.isEmpty {
            await fetchAfterLatest()
            return
        }
        loading = true
        error = nil
        do {
            let page = try await api.messages(conversationId: convId, limit: 30)
            setMessages((page.items ?? []).sorted { $0.id < $1.id })
            hasOlder = page.hasMore
            loading = false
            persist()
            await markRead()
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }

    func loadOlder() async {
        guard !loadingOlder, hasOlder, let firstId = messages.first?.id else { return }
        loadingOlder = true
        do {
            let page = try await api.messages(conversationId: convId, beforeId: firstId, limit: 30)
            let older = (page.items ?? [])
                .filter { !messageIds.contains($0.id) }
                .sorted { $0.id < $1.id }
            older.forEach { messageIds.insert($0.id) }
            messages = older + messages
            hasOlder = page.hasMore
            loadingOlder = false
            persist()
        } catch {
            loadingOlder = false
        }
    }

    func send(content: String, imageIds: [Int64], replyToId: Int64?) async -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageIds.isEmpty else { return false }
        sending = true
        error = nil
        do {
            let message = try await api.sendMessage(
                conversationId: convId,
                body: SendMessageRequest(
                    content: trimmed.isEmpty ? nil : trimmed,
                    imageIds: imageIds.isEmpty ? nil : imageIds,
                    replyToId: replyToId,
                    clientMsgId: UUID().uuidString
                )
            )
            if append(message) { persist() }
            sending = false
            return true
        } catch {
            sending = false
            self.error = error.localizedDescription
            return false
        }
    }

    func recall(messageId: Int64) async {
        do {
            let updated = try await api.recallMessage(id: messageId)
            applyRecall(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyRecall(_ updated: Message) {
        if let index = messages.firstIndex(where: { $0.id == updated.id }) {
            messages[index] = updated
        }
        for index in messages.indices {
            guard var reply = messages[index].replyTo, reply.id == updated.id else { continue }
            reply.preview = "消息已撤回"
            reply.status = 1
            messages[index].replyTo = reply
        }
        persist()
    }

    func block() async -> Bool {
        do {
            try await api.blockConversation(id: convId)
            conversationStatus = 1
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func markRead() async {
        try? await api.markRead(conversationId: convId)
    }

    private func setMessages(_ list: [Message]) {
        messages = list
        messageIds = Set(list.map(\.id))
    }

    /// 按 ID 去重追加，返回是否真的新增。
    @discardableResult
    private func append(_ message: Message) -> Bool {
        guard messageIds.insert(message.id).inserted else { return false }
        messages.append(message)
        return true
    }

    private func persist() {
        ChatCache.save(userId: AppServices.shared.auth.userId, convId: convId, messages: messages)
    }
}
