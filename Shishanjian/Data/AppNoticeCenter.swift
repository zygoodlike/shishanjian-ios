import Combine
import Foundation

enum AppNoticeKind: Equatable {
    case error
    case info
    case message
}

struct AppNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String?
    let message: String
    let kind: AppNoticeKind
}

/// 全局应用内提示：接口异常和前台新消息都走这里。
@MainActor
final class AppNoticeCenter: ObservableObject {
    static let shared = AppNoticeCenter()

    @Published private(set) var notice: AppNotice?

    private var dismissTask: Task<Void, Never>?
    private var lastMessage = ""
    private var lastAt = Date.distantPast

    func show(title: String?, message: String, kind: AppNoticeKind = .info) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let now = Date()
        if text == lastMessage, now.timeIntervalSince(lastAt) < 1.2 {
            return
        }
        lastMessage = text
        lastAt = now
        notice = AppNotice(title: title, message: text, kind: kind)
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }

    func error(_ message: String) {
        show(title: "提示", message: message, kind: .error)
    }

    func message(title: String?, message: String) {
        show(title: title, message: message, kind: .message)
    }

    func dismiss() {
        dismissTask?.cancel()
        notice = nil
    }
}
