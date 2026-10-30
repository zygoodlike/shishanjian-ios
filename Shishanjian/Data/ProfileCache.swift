import Combine
import Foundation

/// 全局用户资料缓存：头像和昵称只有一个源头。
///
/// 服务端推送 profile 事件、聊天/评论/需求接口返回资料时都写入这里；
/// 所有 AvatarBlock 优先读这里，一处更新全页面生效。
struct CachedProfile: Codable, Equatable {
    let nickname: String?
    let avatar: String?
}

private struct ProfileRecord: Codable {
    let userId: Int64
    let nickname: String?
    let avatar: String?
}

struct ProfileUpdate {
    let userId: Int64?
    let nickname: String?
    let avatar: String?
}

final class ProfileCache: ObservableObject {
    static let shared = ProfileCache()

    @Published private(set) var profiles: [Int64: CachedProfile] = [:]

    /// 每次变更只发出变化了的用户 ID，头像组件按 ID 过滤，别人改资料不触发重绘。
    let changes = PassthroughSubject<Set<Int64>, Never>()

    private let key = "shishanjian_profile_cache_v1"
    private let persistQueue = DispatchQueue(label: "shishanjian.profile-cache", qos: .utility)
    private var persistWork: DispatchWorkItem?

    private init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([ProfileRecord].self, from: data) else {
            return
        }
        profiles = Dictionary(records.map {
            ($0.userId, CachedProfile(nickname: $0.nickname, avatar: $0.avatar))
        }, uniquingKeysWith: { _, last in last })
    }

    func update(userId: Int64?, nickname: String?, avatar: String?) {
        updateMany([ProfileUpdate(userId: userId, nickname: nickname, avatar: avatar)])
    }

    /// 批量写入：一次只发一次变更、写一次盘。
    func updateMany(_ updates: [ProfileUpdate]) {
        let valid = updates.filter { ($0.userId ?? 0) > 0 }
        guard !valid.isEmpty else { return }
        if Thread.isMainThread {
            apply(valid)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(valid)
            }
        }
    }

    func clear() {
        if Thread.isMainThread {
            reset()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reset()
            }
        }
    }

    private func reset() {
        let ids = Set(profiles.keys)
        profiles = [:]
        persistWork?.cancel()
        let key = self.key
        persistQueue.async {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if !ids.isEmpty { changes.send(ids) }
    }

    private func apply(_ updates: [ProfileUpdate]) {
        var next = profiles
        var changed = Set<Int64>()
        for update in updates {
            guard let userId = update.userId else { continue }
            let value = CachedProfile(nickname: update.nickname, avatar: update.avatar)
            if next[userId] != value {
                next[userId] = value
                changed.insert(userId)
            }
        }
        guard !changed.isEmpty else { return }
        profiles = next
        changes.send(changed)
        schedulePersist(next)
    }

    /// 合并 300ms 内的多次写入，编码和写盘都在后台队列。
    private func schedulePersist(_ snapshot: [Int64: CachedProfile]) {
        persistWork?.cancel()
        let key = self.key
        let work = DispatchWorkItem {
            let records = snapshot.map {
                ProfileRecord(userId: $0.key, nickname: $0.value.nickname, avatar: $0.value.avatar)
            }
            guard let data = try? JSONEncoder().encode(records) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }
        persistWork = work
        persistQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

/// 单个用户的资料订阅：只在该用户资料变化时刷新。
final class ProfileObserver: ObservableObject {
    @Published private(set) var profile: CachedProfile?

    private var userId: Int64
    private var cancellable: AnyCancellable?

    init(userId: Int64) {
        self.userId = userId
        self.profile = ProfileCache.shared.profiles[userId]
        cancellable = ProfileCache.shared.changes.sink { [weak self] ids in
            guard let self, ids.contains(self.userId) else { return }
            self.profile = ProfileCache.shared.profiles[self.userId]
        }
    }

    func rebind(_ userId: Int64) {
        guard userId != self.userId else { return }
        self.userId = userId
        profile = ProfileCache.shared.profiles[userId]
    }
}
