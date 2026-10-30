import Combine
import Foundation

struct PublicConfig: Codable {
    var cardImageMax: Int = 3
    var commentImageMax: Int = 3
    var chatImageMax: Int = 9
    var feedbackImageMax: Int = 9
    var reportImageMin: Int = 1
    var reportImageMax: Int = 9
    var imageMaxMb: Int = 5
}

/// 服务端下发的公开数量限制，避免把图片上限写死在客户端。
///
/// 启动先用上次保存的值；`/config/public` 有 24 小时磁盘缓存，过期才真正请求。
@MainActor
final class AppLimits: ObservableObject {
    static let shared = AppLimits()

    @Published private(set) var config: PublicConfig

    private let key = "shishanjian_public_config_v1"
    private var refreshed = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(PublicConfig.self, from: data) {
            config = saved
        } else {
            config = PublicConfig()
        }
    }

    /// 每次进程只刷新一次。
    func refresh(api: ApiService) async {
        guard !refreshed else { return }
        refreshed = true
        guard let value = try? await api.publicConfigs() else {
            refreshed = false
            return
        }
        config = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
