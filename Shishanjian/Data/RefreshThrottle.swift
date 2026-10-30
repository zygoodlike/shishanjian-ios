import Foundation

/// 手动下拉刷新节流：3 秒内只允许发一次请求。
@MainActor
final class RefreshThrottle {
    private let interval: TimeInterval
    private var lastAt = Date.distantPast

    init(interval: TimeInterval = 3) {
        self.interval = interval
    }

    func tryAcquire() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastAt) < interval { return false }
        lastAt = now
        return true
    }
}
