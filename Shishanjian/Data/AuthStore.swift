import Foundation

struct AuthSession: Equatable {
    let token: String
    let userId: Int64?
    let username: String?
    let nickname: String?
    let avatarKey: String?
    let justRegistered: Bool
}

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: AuthSession?

    private let defaults = UserDefaults.standard
    private let savedAccountsStore = SavedAccountsStore()
    private(set) var justLoggedOut = false
    private let tokenKey = "token"
    private let userIdKey = "user_id"
    private let usernameKey = "username"
    private let nicknameKey = "nickname"
    private let avatarKey = "avatar"
    private let justRegisteredKey = "just_registered"

    init() {
        session = read()
    }

    var token: String? { session?.token }
    var userId: Int64? { session?.userId }
    var isLoggedIn: Bool { !(token ?? "").isEmpty }

    func save(
        _ response: AuthResponse,
        justRegistered: Bool = false,
        username: String? = nil,
        password: String? = nil
    ) {
        guard let token = response.token, !token.isEmpty else { return }
        defaults.set(token, forKey: tokenKey)
        defaults.set(response.user?.id ?? 0, forKey: userIdKey)
        defaults.set(response.user?.username ?? username, forKey: usernameKey)
        defaults.set(response.user?.nickname, forKey: nicknameKey)
        defaults.set(response.user?.avatarKey, forKey: avatarKey)
        defaults.set(justRegistered, forKey: justRegisteredKey)
        if let username, let password, !username.isEmpty, !password.isEmpty {
            savedAccountsStore.save(
                username: username,
                password: password,
                nickname: response.user?.nickname,
                avatar: response.user?.avatarKey
            )
        }
        session = read()
    }

    func savedAccounts() -> [SavedAccount] {
        savedAccountsStore.list()
    }

    func removeSavedAccount(username: String) {
        savedAccountsStore.remove(username: username)
    }

    func consumeJustLoggedOut() -> Bool {
        let value = justLoggedOut
        justLoggedOut = false
        return value
    }

    func updateToken(_ token: String) {
        defaults.set(token, forKey: tokenKey)
        session = read()
    }

    func updateNickname(_ nickname: String?) {
        guard defaults.string(forKey: nicknameKey) != nickname else { return }
        defaults.set(nickname, forKey: nicknameKey)
        session = read()
    }

    func updateUsername(_ username: String?) {
        guard let username, !username.isEmpty,
              defaults.string(forKey: usernameKey) != username else { return }
        defaults.set(username, forKey: usernameKey)
        session = read()
    }

    func updateAvatar(_ key: String?) {
        guard defaults.string(forKey: avatarKey) != key else { return }
        defaults.set(key, forKey: avatarKey)
        session = read()
    }

    func consumeJustRegistered() {
        defaults.set(false, forKey: justRegisteredKey)
        session = read()
    }

    func clear() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: nicknameKey)
        defaults.removeObject(forKey: avatarKey)
        defaults.removeObject(forKey: justRegisteredKey)
        justLoggedOut = true
        session = nil
    }

    private func read() -> AuthSession? {
        guard let token = defaults.string(forKey: tokenKey), !token.isEmpty else { return nil }
        let id = defaults.integer(forKey: userIdKey)
        return AuthSession(
            token: token,
            userId: id > 0 ? Int64(id) : nil,
            username: defaults.string(forKey: usernameKey),
            nickname: defaults.string(forKey: nicknameKey),
            avatarKey: defaults.string(forKey: avatarKey),
            justRegistered: defaults.bool(forKey: justRegisteredKey)
        )
    }
}
