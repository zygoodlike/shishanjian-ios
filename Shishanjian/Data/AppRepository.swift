import Foundation

@MainActor
final class AppRepository {
    private let api: ApiService
    private let defaults = UserDefaults.standard

    init(api: ApiService) {
        self.api = api
    }

    var deviceId: String {
        if let existing = defaults.string(forKey: "device_id"), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: "device_id")
        return id
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        try await api.login(
            LoginRequest(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                platform: "ios",
                deviceId: deviceId
            )
        )
    }

    func register(
        username: String,
        password: String,
        email: String,
        code: String,
        nickname: String
    ) async throws -> AuthResponse {
        try await api.register(
            RegisterRequest(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                platform: "ios",
                deviceId: deviceId
            )
        )
    }

    func uploadImage(_ data: Data, purpose: String) async throws -> MediaInfo {
        try await api.uploadMedia(purpose: purpose, data: data, mime: mimeType(for: data))
    }

    func deleteMedia(id: Int64) async throws {
        try await api.deleteMedia(id: id)
    }

    func uploadAvatar(_ data: Data) async throws -> MediaInfo {
        try await api.uploadAvatar(data: data, mime: mimeType(for: data))
    }

    private func mimeType(for data: Data) -> String {
        if data.starts(with: [UInt8]([0xFF, 0xD8, 0xFF])) { return "image/jpeg" }
        if data.starts(with: [UInt8]([0x89, 0x50, 0x4E, 0x47])) { return "image/png" }
        return "image/jpeg"
    }
}

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let auth: AuthStore
    let api: ApiService
    let repository: AppRepository
    let realtime: RealtimeClient
    let publisher: PublishCoordinator

    private init() {
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "image_cache"
        )
        let auth = AuthStore()
        let api = ApiService(auth: auth)
        self.auth = auth
        self.api = api
        let repository = AppRepository(api: api)
        self.repository = repository
        self.realtime = RealtimeClient(auth: auth)
        self.publisher = PublishCoordinator(api: api, repository: repository)
    }
}
