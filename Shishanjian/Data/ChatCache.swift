import Foundation

/// 聊天记录本地缓存：按账号和会话保存 JSON，最多 500 条。
///
/// 读写都不在主线程：读在后台解码后再交回界面；写入按会话防抖 500ms，
/// 同一批增量只编码、写盘一次。
enum ChatCache {
    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_cache", isDirectory: true)
    }

    @MainActor private static var pending: [String: Task<Void, Never>] = [:]

    /// 非隔离的 async 函数在全局执行器上读盘解码，不占主线程。
    static func load(userId: Int64?, convId: Int64) async -> [Message] {
        guard let userId else { return [] }
        let url = file(userId: userId, convId: convId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    /// 防抖保存：500ms 内的多次调用只写最后一次。
    @MainActor
    static func save(userId: Int64?, convId: Int64, messages: [Message]) {
        guard let userId else { return }
        let key = "\(userId)/\(convId)"
        let url = file(userId: userId, convId: convId)
        let snapshot = Array(messages.suffix(500))
        pending[key]?.cancel()
        pending[key] = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    @MainActor
    static func clearAll() {
        pending.values.forEach { $0.cancel() }
        pending = [:]
        try? FileManager.default.removeItem(at: root)
    }

    private static func file(userId: Int64, convId: Int64) -> URL {
        root.appendingPathComponent("\(userId)", isDirectory: true)
            .appendingPathComponent("\(convId).json")
    }
}
