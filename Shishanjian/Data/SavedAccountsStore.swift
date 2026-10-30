import Foundation
import Security

struct SavedAccount: Codable, Identifiable, Hashable {
    var id: String { username }
    let username: String
    let password: String
    let nickname: String?
    let avatar: String?
    let lastLoginAt: TimeInterval
}

/// 已登录账号快捷登录记录，密码只写入 iOS Keychain。
@MainActor
final class SavedAccountsStore {
    private let service = "com.shishanjian.savedAccounts"
    private let account = "accounts"
    private let maxAccounts = 5

    func list() -> [SavedAccount] {
        guard let data = readData() else { return [] }
        return (try? JSONDecoder().decode([SavedAccount].self, from: data)) ?? []
    }

    func save(username: String, password: String, nickname: String?, avatar: String?) {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else { return }
        let existing = list().filter { $0.username.lowercased() != name.lowercased() }
        let updated = Array(([
            SavedAccount(
                username: name,
                password: password,
                nickname: nickname,
                avatar: avatar,
                lastLoginAt: Date().timeIntervalSince1970
            )
        ] + existing).prefix(maxAccounts))
        guard let data = try? JSONEncoder().encode(updated) else { return }
        writeData(data)
    }

    func remove(username: String) {
        let updated = list().filter { $0.username.lowercased() != username.lowercased() }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        writeData(data)
    }

    private func readData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func writeData(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
