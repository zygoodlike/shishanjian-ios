import CryptoKit
import Foundation

/// GET 接口磁盘缓存：成功响应落盘，网络失败时回退到上一次结果。
/// 缓存按账号隔离，退出登录时清空。
///
/// 文件读写都不在主线程；每次请求只算一次 SHA256。
/// 写操作成功后清空当前账号缓存，避免重进页面时读到动作之前的旧数据。
enum ApiDiskCache {
    struct Entry: Sendable {
        let data: Data
        let age: TimeInterval
    }

    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("api_cache", isDirectory: true)
    }

    private static let lock = NSLock()
    private static var generation = 0

    /// 当前缓存代数。请求开始时取一次，写盘前比对；中间发生过清空就不再写，防止旧响应复活。
    static func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// 缓存文件位置，一次请求内复用，避免重复哈希。
    static func file(url: String, userId: Int64?) -> URL {
        let digest = SHA256.hash(data: Data(url.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return userRoot(userId).appendingPathComponent("\(digest).json")
    }

    /// 非隔离的 async 函数在全局执行器上运行，主线程 `await` 时不会被文件 IO 阻塞。
    static func read(_ file: URL) async -> Entry? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attrs?[.modificationDate] as? Date ?? .distantPast
        return Entry(data: data, age: Date().timeIntervalSince(modified))
    }

    static func write(_ data: Data, to file: URL, generation expected: Int) {
        Task.detached(priority: .utility) {
            lock.lock()
            defer { lock.unlock() }
            guard generation == expected else { return }
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: file, options: .atomic)
        }
    }

    /// 清空某个账号的接口缓存。代数先 +1，正在路上的旧响应就不会再落盘。
    static func clearUser(_ userId: Int64?) {
        lock.lock()
        generation += 1
        lock.unlock()
        let dir = userRoot(userId)
        Task.detached(priority: .utility) {
            lock.lock()
            defer { lock.unlock() }
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func clearAll() {
        lock.lock()
        generation += 1
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: root)
    }

    private static func userRoot(_ userId: Int64?) -> URL {
        let user = userId.map(String.init) ?? "guest"
        return root.appendingPathComponent(user, isDirectory: true)
    }
}
