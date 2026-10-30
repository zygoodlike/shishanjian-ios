import Combine
import Foundation

enum RealtimeEvent {
    case connected(Int64)
    case newMessage(convId: Int64, message: Message, senderName: String?, cardTitle: String?)
    case read(convId: Int64, userId: Int64)
    case profileChanged(userId: Int64, nickname: String?, avatar: String?)
    case newComment(comment: Comment, cardTitle: String?)
    case newInterest(interest: Interest)
    case recalled(convId: Int64, message: Message, senderName: String?, cardTitle: String?)
    case cardStatusChanged(cardId: Int64, title: String?, status: Int, statusLabel: String?)
    case disconnected
}

/// 全局唯一的聊天长连接。App 在前台时连接，退到后台后由系统挂起。
///
/// iOS 没有应用商店之外的常驻后台通道，杀进程后的通知需要 APNs。
@MainActor
final class RealtimeClient: ObservableObject {
    private let auth: AuthStore
    private let subject = PassthroughSubject<RealtimeEvent, Never>()
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var attempt = 0
    private var active = false
    private let decoder = JSONDecoder()

    /// 收到服务端 connected 后为 true，断开即 false；用于判断回到页面是否需要补拉。
    private(set) var isConnected = false

    var events: AnyPublisher<RealtimeEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    init(auth: AuthStore) {
        self.auth = auth
    }

    func setActive(_ value: Bool) {
        active = value
        if value {
            connect()
        } else {
            disconnect()
        }
    }

    func sendRead(convId: Int64) {
        let payload = "{\"type\":\"read\",\"convId\":\(convId)}"
        task?.send(.string(payload)) { _ in }
    }

    private func connect() {
        guard active, task == nil, let token = auth.token, !token.isEmpty else { return }
        let base = ApiConfig.baseURL.absoluteString
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/ws/chat") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        task = socket
        socket.resume()
        receiveLoop(socket)
        startPing(socket)
    }

    private func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        let wasOpen = task != nil
        task = nil
        attempt = 0
        isConnected = false
        if wasOpen { subject.send(.disconnected) }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard let self else { return }
                    if case .string(let text) = message {
                        self.handle(text)
                    }
                } catch {
                    guard let self else { return }
                    self.handleFailure(socket)
                    return
                }
            }
        }
    }

    private func startPing(_ socket: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                if Task.isCancelled { return }
                socket.sendPing { error in
                    if error != nil {
                        Task { @MainActor in self?.handleFailure(socket) }
                    }
                }
            }
        }
    }

    private func handleFailure(_ socket: URLSessionWebSocketTask) {
        guard task === socket else { return }
        task = nil
        isConnected = false
        pingTask?.cancel()
        subject.send(.disconnected)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard active else { return }
        reconnectTask?.cancel()
        let wait = min(30, 2 << min(attempt, 4))
        attempt = min(attempt + 1, 5)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func handle(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = root["type"] as? String
        else { return }
        switch type {
        case "connected":
            attempt = 0
            isConnected = true
            subject.send(.connected((root["userId"] as? NSNumber)?.int64Value ?? 0))
        case "message", "recall":
            guard
                let convId = (root["convId"] as? NSNumber)?.int64Value,
                let payload = root["data"],
                let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                let message = try? decoder.decode(Message.self, from: payloadData)
            else { return }
            let sender = root["senderName"] as? String
            let cardTitle = root["cardTitle"] as? String
            if type == "message" {
                subject.send(.newMessage(
                    convId: convId,
                    message: message,
                    senderName: sender,
                    cardTitle: cardTitle
                ))
            } else {
                subject.send(.recalled(
                    convId: convId,
                    message: message,
                    senderName: sender,
                    cardTitle: cardTitle
                ))
            }
        case "read":
            guard let convId = (root["convId"] as? NSNumber)?.int64Value else { return }
            let userId = ((root["data"] as? [String: Any])?["userId"] as? NSNumber)?.int64Value ?? 0
            subject.send(.read(convId: convId, userId: userId))
        case "profile":
            guard let data = root["data"] as? [String: Any],
                  let userId = (data["userId"] as? NSNumber)?.int64Value else { return }
            let nickname = data["nickname"] as? String
            let avatar = data["avatar"] as? String
            ProfileCache.shared.update(userId: userId, nickname: nickname, avatar: avatar)
            subject.send(.profileChanged(userId: userId, nickname: nickname, avatar: avatar))
        case "comment":
            guard let payload = root["data"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let comment = try? decoder.decode(Comment.self, from: payloadData) else { return }
            let cardTitle = (payload as? [String: Any])?["cardTitle"] as? String
            subject.send(.newComment(comment: comment, cardTitle: cardTitle))
        case "interest":
            guard let payload = root["data"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let interest = try? decoder.decode(Interest.self, from: payloadData) else { return }
            subject.send(.newInterest(interest: interest))
        case "card":
            guard let data = root["data"] as? [String: Any],
                  let cardId = (data["id"] as? NSNumber)?.int64Value else { return }
            subject.send(.cardStatusChanged(
                cardId: cardId,
                title: data["title"] as? String,
                status: (data["status"] as? NSNumber)?.intValue ?? 0,
                statusLabel: data["statusLabel"] as? String
            ))
        default:
            break
        }
    }
}
