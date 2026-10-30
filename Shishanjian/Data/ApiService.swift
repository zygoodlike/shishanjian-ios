import Foundation

enum ApiConfig {
    static let baseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let value = (raw?.isEmpty == false ? raw! : "http://127.0.0.1:8080/")
        return URL(string: value.hasSuffix("/") ? value : value + "/")!
    }()

    static func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: baseURL)?.absoluteURL
    }
}

struct ApiException: LocalizedError {
    let code: String?
    let message: String
    var errorDescription: String? { message }

    init(code: String?, message: String) {
        self.code = code
        self.message = message
        Task { @MainActor in
            AppNoticeCenter.shared.error(message)
        }
    }
}

@MainActor
final class ApiService {
    private let auth: AuthStore
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(auth: AuthStore, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: - Auth

    func captchaChallenge(_ body: CaptchaChallengeRequest) async throws -> CaptchaChallenge {
        try await send("api/v1/auth/captcha/challenge", method: "POST", body: encoder.encode(body))
    }

    func captchaVerify(_ body: CaptchaVerifyRequest) async throws -> CaptchaVerifyResult {
        try await send("api/v1/auth/captcha/verify", method: "POST", body: encoder.encode(body))
    }

    func emailCode(_ body: EmailCodeRequest) async throws -> EmailCodeResponse {
        try await send("api/v1/auth/email-code", method: "POST", body: encoder.encode(body))
    }

    func register(_ body: RegisterRequest) async throws -> AuthResponse {
        try await send("api/v1/auth/register", method: "POST", body: encoder.encode(body))
    }

    func login(_ body: LoginRequest) async throws -> AuthResponse {
        try await send("api/v1/auth/login", method: "POST", body: encoder.encode(body))
    }

    func resetPassword(_ body: ResetPasswordRequest) async throws {
        try await sendVoid("api/v1/auth/password/reset", method: "POST", body: encoder.encode(body))
    }

    func deleteMedia(id: Int64) async throws {
        try await sendVoid("api/v1/media/\(id)", method: "DELETE")
    }

    func logout() async throws {
        try await sendVoid("api/v1/auth/logout", method: "POST")
    }

    func publicConfigs() async throws -> PublicConfig {
        try await send("api/v1/config/public")
    }

    func me() async throws -> User {
        try await send("api/v1/me")
    }

    func userProfile(id: Int64) async throws -> UserProfile {
        try await send("api/v1/users/\(id)/profile")
    }

    // MARK: - Profile

    func profile(bypassCache: Bool = false) async throws -> Profile {
        try await send("api/v1/me/profile", bypassCache: bypassCache)
    }

    func updateProfile(_ body: UpdateProfileRequest) async throws -> Profile {
        try await send("api/v1/me/profile", method: "PATCH", body: encoder.encode(body))
    }

    func updateScenes(_ body: ScenesRequest) async throws -> Profile {
        try await send("api/v1/me/scenes", method: "PUT", body: encoder.encode(body))
    }

    func uploadAvatar(data: Data, mime: String) async throws -> MediaInfo {
        try await upload(path: "api/v1/me/avatar", purpose: nil, data: data, mime: mime, filename: "avatar.jpg")
    }

    func deleteAccount(_ body: DeleteAccountRequest) async throws {
        try await sendVoid("api/v1/me/delete", method: "POST", body: encoder.encode(body))
    }

    // MARK: - Cards

    func createCard(_ body: CreateCardRequest) async throws -> Card {
        try await send("api/v1/cards", method: "POST", body: encoder.encode(body))
    }

    func hall(
        scene: String? = nil,
        whenType: String? = nil,
        place: String? = nil,
        keyword: String? = nil,
        page: Int = 1,
        size: Int = 20,
        bypassCache: Bool = false
    ) async throws -> CardPage {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size)),
        ]
        if let scene, !scene.isEmpty { query.append(URLQueryItem(name: "scene", value: scene)) }
        if let whenType, !whenType.isEmpty { query.append(URLQueryItem(name: "when", value: whenType)) }
        if let place, !place.isEmpty { query.append(URLQueryItem(name: "place", value: place)) }
        if let keyword, !keyword.isEmpty { query.append(URLQueryItem(name: "keyword", value: keyword)) }
        return try await send("api/v1/cards", query: query, bypassCache: bypassCache)
    }

    func card(_ id: Int64, bypassCache: Bool = false) async throws -> Card {
        try await send("api/v1/cards/\(id)", bypassCache: bypassCache)
    }

    func updateCard(_ id: Int64, body: CreateCardRequest) async throws -> Card {
        try await send("api/v1/cards/\(id)", method: "PATCH", body: encoder.encode(body))
    }

    func deleteCard(_ id: Int64) async throws {
        try await sendVoid("api/v1/cards/\(id)", method: "DELETE")
    }

    func pauseCard(_ id: Int64) async throws -> Card {
        try await send("api/v1/cards/\(id)/pause", method: "POST")
    }

    func resumeCard(_ id: Int64) async throws -> Card {
        try await send("api/v1/cards/\(id)/resume", method: "POST")
    }

    func closeCard(_ id: Int64) async throws -> Card {
        try await send("api/v1/cards/\(id)/close", method: "POST")
    }

    func myCards(group: String, bypassCache: Bool = false) async throws -> [Card] {
        try await send(
            "api/v1/me/cards",
            query: [URLQueryItem(name: "group", value: group)],
            bypassCache: bypassCache
        )
    }

    // MARK: - Interests

    func sendInterest(cardId: Int64, note: String?) async throws -> Interest {
        try await send(
            "api/v1/cards/\(cardId)/interests",
            method: "POST",
            body: encoder.encode(SendInterestRequest(note: note))
        )
    }

    func cardInterests(cardId: Int64, bypassCache: Bool = false) async throws -> [Interest] {
        try await send("api/v1/me/cards/\(cardId)/interests", bypassCache: bypassCache)
    }

    func conversation(id: Int64) async throws -> Conversation {
        try await send("api/v1/conversations/\(id)")
    }

    func myInterests(bypassCache: Bool = false) async throws -> [Interest] {
        try await send("api/v1/me/interests", bypassCache: bypassCache)
    }

    func receivedInterests(bypassCache: Bool = false) async throws -> [Interest] {
        try await send("api/v1/me/received-interests", bypassCache: bypassCache)
    }

    func acceptInterest(id: Int64) async throws -> AcceptResponse {
        try await send("api/v1/interests/\(id)/accept", method: "POST")
    }

    func ignoreInterest(id: Int64) async throws {
        try await sendVoid("api/v1/interests/\(id)/ignore", method: "POST")
    }

    func withdrawInterest(id: Int64) async throws {
        try await sendVoid("api/v1/interests/\(id)/withdraw", method: "POST")
    }

    // MARK: - Comments

    func comments(cardId: Int64, bypassCache: Bool = false) async throws -> [Comment] {
        try await send("api/v1/cards/\(cardId)/comments", bypassCache: bypassCache)
    }

    func createComment(cardId: Int64, body: CreateCommentRequest) async throws -> Comment {
        try await send("api/v1/cards/\(cardId)/comments", method: "POST", body: encoder.encode(body))
    }

    func replyComment(id: Int64, body: CreateCommentRequest) async throws -> Comment {
        try await send("api/v1/comments/\(id)/reply", method: "POST", body: encoder.encode(body))
    }

    func deleteComment(id: Int64) async throws {
        try await sendVoid("api/v1/comments/\(id)", method: "DELETE")
    }

    func receivedComments(bypassCache: Bool = false) async throws -> [ReceivedComment] {
        try await send("api/v1/me/received-comments", bypassCache: bypassCache)
    }

    func setCommentMode(cardId: Int64, mode: String) async throws {
        try await sendVoid(
            "api/v1/cards/\(cardId)/comment-mode",
            method: "PATCH",
            body: encoder.encode(CommentModeRequest(mode: mode))
        )
    }

    // MARK: - Chat

    func conversations(bypassCache: Bool = false) async throws -> [Conversation] {
        try await send("api/v1/conversations", bypassCache: bypassCache)
    }

    func messages(
        conversationId: Int64,
        beforeId: Int64? = nil,
        afterId: Int64? = nil,
        limit: Int = 20
    ) async throws -> MessagePage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let beforeId { query.append(URLQueryItem(name: "beforeId", value: String(beforeId))) }
        if let afterId { query.append(URLQueryItem(name: "afterId", value: String(afterId))) }
        return try await send("api/v1/conversations/\(conversationId)/messages", query: query)
    }

    func sendMessage(conversationId: Int64, body: SendMessageRequest) async throws -> Message {
        try await send("api/v1/conversations/\(conversationId)/messages", method: "POST", body: encoder.encode(body))
    }

    func sendImageMessage(conversationId: Int64, body: SendImageMessageRequest) async throws -> Message {
        try await send("api/v1/conversations/\(conversationId)/messages/image", method: "POST", body: encoder.encode(body))
    }

    func markRead(conversationId: Int64) async throws {
        try await sendVoid("api/v1/conversations/\(conversationId)/read", method: "POST")
    }

    func blockConversation(id: Int64) async throws {
        try await sendVoid("api/v1/conversations/\(id)/block", method: "POST")
    }

    func recallMessage(id: Int64) async throws -> Message {
        try await send("api/v1/messages/\(id)/recall", method: "POST")
    }

    func uploadMedia(purpose: String, data: Data, mime: String) async throws -> MediaInfo {
        try await upload(path: "api/v1/media", purpose: purpose, data: data, mime: mime, filename: "image.jpg")
    }

    // MARK: - Reports and sessions

    func report(_ body: CreateReportRequest) async throws -> ReportInfo {
        try await send("api/v1/reports", method: "POST", body: encoder.encode(body))
    }

    func submitFeedback(_ body: CreateFeedbackRequest) async throws -> Feedback {
        try await send("api/v1/feedback", method: "POST", body: encoder.encode(body))
    }

    func myFeedback(bypassCache: Bool = false) async throws -> [Feedback] {
        try await send("api/v1/me/feedback", bypassCache: bypassCache)
    }

    func sessions(bypassCache: Bool = false) async throws -> [DeviceSession] {
        try await send("api/v1/me/sessions", bypassCache: bypassCache)
    }

    func revokeSession(sid: String) async throws {
        try await sendVoid("api/v1/me/sessions/\(sid)", method: "DELETE")
    }

    func revokeAllSessions() async throws {
        try await sendVoid("api/v1/me/sessions/revoke-all", method: "POST")
    }

    // MARK: - Networking

    private func send<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        bypassCache: Bool = false
    ) async throws -> T {
        let data = try await perform(
            path: path,
            method: method,
            query: query,
            body: body,
            bypassCache: bypassCache
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ApiException(code: "DECODE_ERROR", message: "服务器返回的数据格式不正确")
        }
    }

    private func sendVoid(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws {
        _ = try await perform(path: path, method: method, query: query, body: body)
    }

    private func perform(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        bypassCache: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(
            url: URL(string: path, relativeTo: ApiConfig.baseURL)?.absoluteURL ?? ApiConfig.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw ApiException(code: "URL_INVALID", message: "请求地址不正确")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw ApiException(code: "URL_INVALID", message: "请求地址不正确")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = auth.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        // `path` 本身就是相对接口路径（如 api/v1/cards），不含部署前缀 /shishanjian/；
        // 统一成 /api/v1/... 再匹配 TTL 和排除规则。
        let apiPath = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // 只有设了 TTL 的 GET 才读写磁盘缓存；消息等实时数据由本地聊天缓存负责。
        let ttl = method == "GET" ? cacheTTL(apiPath: apiPath) : 0
        let cacheFile = ttl > 0 ? ApiDiskCache.file(url: url.absoluteString, userId: auth.userId) : nil
        let cacheGeneration = ApiDiskCache.currentGeneration()
        if let cacheFile, !bypassCache,
           let entry = await ApiDiskCache.read(cacheFile),
           entry.age <= ttl {
            return entry.data
        }
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if let cacheFile, let entry = await ApiDiskCache.read(cacheFile) {
                return entry.data
            }
            throw ApiException(code: "NETWORK", message: "网络不可用，请检查网络后重试")
        }
        let data = result.0
        guard let http = result.1 as? HTTPURLResponse else {
            throw ApiException(code: "NETWORK", message: "网络请求失败")
        }
        if let renewed = http.value(forHTTPHeaderField: "X-Renewed-Token"), !renewed.isEmpty {
            auth.updateToken(renewed)
        }
        if (200..<300).contains(http.statusCode) {
            if let cacheFile, !data.isEmpty {
                ApiDiskCache.write(data, to: cacheFile, generation: cacheGeneration)
            }
            if method != "GET", invalidatesCache(apiPath: apiPath) {
                ApiDiskCache.clearUser(auth.userId)
            }
            return data
        }
        if http.statusCode >= 500,
           let cacheFile,
           let entry = await ApiDiskCache.read(cacheFile) {
            return entry.data
        }
        if http.statusCode == 401, !(auth.token ?? "").isEmpty {
            auth.clear()
            throw ApiException(code: "UNAUTHORIZED", message: "登录已失效，请重新登录")
        }
        let apiError = try? decoder.decode(ApiErrorBody.self, from: data)
        let fallback: String
        switch http.statusCode {
        case 403: fallback = "没有权限执行这个操作"
        case 404: fallback = "内容不存在或已被删除"
        case 429: fallback = "操作太频繁，请稍后再试"
        default: fallback = "请求失败，请稍后重试"
        }
        throw ApiException(code: apiError?.code, message: errorMessage(apiError, fallback: fallback))
    }

    private func errorMessage(_ apiError: ApiErrorBody?, fallback: String) -> String {
        guard let message = apiError?.message, !message.isEmpty else { return fallback }
        var seen = Set<String>()
        let signals = (apiError?.details?.signals ?? [])
            .map { raw -> String in
                guard let index = raw.firstIndex(of: ":") else { return raw }
                return String(raw[raw.index(after: index)...])
            }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(3)
        guard !signals.isEmpty else { return message }
        return message + "\n可能原因：" + signals.joined(separator: "、")
    }

    /// 本地优先 TTL，与 Android `ApiCacheInterceptor` 保持一致；消息不设 TTL。
    /// `apiPath` 已去掉部署前缀，形如 `/api/v1/cards`。
    private func cacheTTL(apiPath path: String) -> TimeInterval {
        guard path.hasPrefix("/api/v1/"),
              !path.hasPrefix("/api/v1/auth/"),
              !path.hasPrefix("/api/v1/media") else { return 0 }
        if path == "/api/v1/config/public" { return 86_400 }
        if path == "/api/v1/conversations" { return 15 }
        if path == "/api/v1/me/feedback" { return 60 }
        if path == "/api/v1/me/sessions" { return 60 }
        if path == "/api/v1/cards" { return 20 }
        if path.hasPrefix("/api/v1/users/") { return 120 }
        if path == "/api/v1/me/profile" { return 60 }
        if path.hasPrefix("/api/v1/me/cards") { return 30 }
        if path.hasPrefix("/api/v1/me/interests") { return 30 }
        if path.hasPrefix("/api/v1/me/received") { return 30 }
        if path.hasPrefix("/api/v1/cards/") && path.hasSuffix("/comments") { return 30 }
        if path.hasPrefix("/api/v1/cards/") { return 20 }
        return 0
    }

    /// 写操作成功后清空本账号接口缓存；登录、上传、私聊类写操作不影响缓存的列表数据。
    private func invalidatesCache(apiPath path: String) -> Bool {
        path.hasPrefix("/api/v1/")
            && !path.hasPrefix("/api/v1/auth/")
            && !path.hasPrefix("/api/v1/media")
            && !path.hasPrefix("/api/v1/conversations")
            && !path.hasPrefix("/api/v1/messages")
    }

    private func upload(
        path: String,
        purpose: String?,
        data: Data,
        mime: String,
        filename: String
    ) async throws -> MediaInfo {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var query: [URLQueryItem] = []
        if let purpose { query.append(URLQueryItem(name: "purpose", value: purpose)) }

        guard var components = URLComponents(
            url: URL(string: path, relativeTo: ApiConfig.baseURL)?.absoluteURL ?? ApiConfig.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw ApiException(code: "URL_INVALID", message: "请求地址不正确")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw ApiException(code: "URL_INVALID", message: "请求地址不正确")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = auth.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw ApiException(code: "NETWORK", message: "图片上传失败，请检查网络")
        }
        let responseData = result.0
        guard let http = result.1 as? HTTPURLResponse else {
            throw ApiException(code: "NETWORK", message: "图片上传失败")
        }
        if let renewed = http.value(forHTTPHeaderField: "X-Renewed-Token"), !renewed.isEmpty {
            auth.updateToken(renewed)
        }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? decoder.decode(ApiErrorBody.self, from: responseData)
            throw ApiException(
                code: apiError?.code,
                message: errorMessage(apiError, fallback: "图片上传失败")
            )
        }
        do {
            return try decoder.decode(MediaInfo.self, from: responseData)
        } catch {
            throw ApiException(code: "DECODE_ERROR", message: "图片上传返回格式不正确")
        }
    }
}
