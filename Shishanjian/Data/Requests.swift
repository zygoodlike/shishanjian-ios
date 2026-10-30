import Foundation

struct LoginRequest: Encodable {
    let username: String
    let password: String
    let platform: String
    let deviceId: String
}

struct RegisterRequest: Encodable {
    let username: String
    let password: String
    let email: String
    let code: String
    let nickname: String
    let platform: String
    let deviceId: String
}

struct EmailCodeRequest: Encodable {
    let email: String
    let purpose: String
    let ticket: String
}

struct CaptchaChallengeRequest: Encodable {
    let purpose: String
}

struct CaptchaVerifyRequest: Encodable {
    let challengeId: String
    let x: Int
    let track: [Int]?
}

struct CreateCardRequest: Encodable {
    let scene: String
    let title: String
    var description: String = ""
    var whenType: String = ""
    var whenText: String?
    var placeName: String = ""
    var headcount: Int = 2
    var tags: [String]?
    var identity: String = "nickname"
    var commentMode: String = "public"
    var reward: Int?
    var payNote: String?
    var imageIds: [Int64]?
}

struct UpdateProfileRequest: Encodable {
    var nickname: String?
    var bio: String?
}

struct ScenesRequest: Encodable {
    let scenes: [String]
}

struct CreateCommentRequest: Encodable {
    let content: String
    var parentId: Int64?
    var imageIds: [Int64]? = nil
}

struct ResetPasswordRequest: Encodable {
    let email: String
    let code: String
    let password: String
}

struct CommentModeRequest: Encodable {
    let mode: String
}

struct SendInterestRequest: Encodable {
    var note: String?
}

struct SendMessageRequest: Encodable {
    var content: String?
    var imageIds: [Int64]?
    var replyToId: Int64?
    let clientMsgId: String

    init(
        content: String? = nil,
        imageIds: [Int64]? = nil,
        replyToId: Int64? = nil,
        clientMsgId: String
    ) {
        self.content = content
        self.imageIds = imageIds
        self.replyToId = replyToId
        self.clientMsgId = clientMsgId
    }
}

struct SendImageMessageRequest: Encodable {
    let mediaId: Int64
    let clientMsgId: String
}

struct CreateReportRequest: Encodable {
    let targetType: String
    let targetId: Int64
    let reason: String
    var detail: String?
    var imageIds: [Int64]
}

struct CreateFeedbackRequest: Encodable {
    let content: String
    let imageIds: [Int64]
}

struct DeleteAccountRequest: Encodable {
    let password: String
}
