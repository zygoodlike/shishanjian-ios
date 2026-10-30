import Foundation

struct User: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var username: String?
    var nickname: String?
    var bio: String?
    var avatarKey: String?
    var avatarStatus: Int = 0
    var status: Int = 0
    var createdAt: String?
}

struct AuthResponse: Codable {
    var token: String?
    var expiresIn: Int64 = 0
    var sessionId: String?
    var user: User?
}

struct EmailCodeResponse: Codable {
    var sent: Bool = false
    var expiresIn: Int64 = 0
    var devCode: String?
}

struct CaptchaChallenge: Codable {
    var challengeId: String = ""
    var type: String?
    var background: String?
    var piece: String?
    var y: Int = 0
    var width: Int = 320
}

struct CaptchaVerifyResult: Codable {
    var ticket: String?
    var expiresIn: Int64 = 0
}

struct Card: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var scene: String?
    var title: String?
    var description: String?
    var whenType: String?
    var whenText: String?
    var placeName: String?
    var headcount: Int = 1
    var reward: Int?
    var payNote: String?
    var tags: [String]?
    var identity: String?
    var commentMode: String?
    var status: Int = 1
    var statusLabel: String?
    var authorName: String?
    var authorId: Int64?
    var authorAvatar: String?
    var mine: Bool = false
    var acceptedCount: Int = 0
    var commentCount: Int = 0
    var interestExpressed: Bool = false
    var interestStatus: Int?
    var interestConversationId: Int64?
    var images: [String]?
    var createdAt: String?
    var updatedAt: String?
}

struct CardPage: Codable {
    var items: [Card]?
    var page: Int = 1
    var size: Int = 20
    var hasMore: Bool = false
}

struct Comment: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var cardId: Int64 = 0
    var userId: Int64 = 0
    var nickname: String?
    var avatar: String?
    var parentId: Int64?
    var replyToUserId: Int64?
    var replyToNickname: String?
    var content: String?
    var visibility: Int = 1
    var status: Int = 0
    var depth: Int = 1
    var deleted: Bool = false
    var createdAt: String?
    var images: [MessageImage]?
    var children: [Comment]?
}

struct Interest: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var cardId: Int64 = 0
    var cardTitle: String?
    var cardStatus: Int = 0
    var userId: Int64 = 0
    var nickname: String?
    var avatar: String?
    var note: String?
    var status: Int = 0
    var createdAt: String?
    var conversationId: Int64?
}

struct ReceivedComment: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var cardId: Int64 = 0
    var cardTitle: String?
    var userId: Int64 = 0
    var nickname: String?
    var avatar: String?
    var content: String?
    var parentId: Int64?
    var replyToNickname: String?
    var createdAt: String?
}

struct AcceptResponse: Codable {
    var conversationId: Int64?
}

struct Conversation: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var cardId: Int64?
    var cardTitle: String?
    var otherUserId: Int64?
    var otherNickname: String?
    var otherAvatar: String?
    var lastMessage: String?
    var lastMsgId: Int64?
    var lastMsgAt: String?
    var unread: Int = 0
    var status: Int = 0
}

struct MessageImage: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var url: String?
}

struct MessageReply: Codable, Hashable {
    var id: Int64 = 0
    var senderId: Int64 = 0
    var senderName: String?
    var type: Int = 1
    var preview: String?
    var status: Int = 0
}

struct Message: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var convId: Int64 = 0
    var senderId: Int64 = 0
    var type: Int = 1
    var content: String?
    var mediaId: Int64?
    var mediaUrl: String?
    var images: [MessageImage]?
    var replyTo: MessageReply?
    var status: Int = 0
    var createdAt: String?
}

struct MessagePage: Codable {
    var items: [Message]?
    var hasMore: Bool = false
    var nextBeforeId: Int64?
}

extension Message {
    var previewText: String {
        if status == 1 { return "消息已撤回" }
        if type == 2 { return "[图片]" }
        if type == 3 {
            let text = content ?? ""
            return text.isEmpty ? "[图片]" : text + " [图片]"
        }
        let text = content ?? ""
        return text.isEmpty ? "新消息" : text
    }
}

struct Profile: Codable {
    var user: User?
    var scenes: [String]?
}

struct DeviceSession: Codable, Identifiable, Hashable {
    var sid: String = ""
    var platform: String?
    var deviceId: String?
    var current: Bool = false
    var createdAt: String?
    var lastActiveAt: String?
    var expiresAt: String?

    var id: String { sid }
}

struct MediaInfo: Codable {
    var id: Int64 = 0
    var url: String?
    var mime: String?
    var size: Int64 = 0
    var width: Int?
    var height: Int?
    var status: Int = 1
}

struct Feedback: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var userId: Int64 = 0
    var nickname: String?
    var content: String?
    var status: Int = 0
    var adminReply: String?
    var images: [String]?
    var createdAt: String?
    var handledAt: String?
}

struct UserProfile: Codable {
    var user: User?
    var works: [Card]?
    var mine: Bool = false
    var canChat: Bool = false
    var conversationId: Int64?
}

struct ReportInfo: Codable, Identifiable {
    var id: Int64 = 0
    var reporterId: Int64 = 0
    var targetType: String?
    var targetId: Int64 = 0
    var reason: String?
    var detail: String?
    var snapshot: String?
    var status: Int = 0
    var handledBy: Int64?
    var handledAt: String?
    var createdAt: String?
}

struct ApiErrorBody: Codable {
    var code: String?
    var message: String?
    var details: ApiErrorDetails?
}

struct ApiErrorDetails: Codable {
    var signals: [String]?
}
