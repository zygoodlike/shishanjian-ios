import Foundation
import UIKit

enum PublishPhase {
    case idle
    case uploading
    case submitting
    case published
    case pendingReview
    case failed
}

struct PublishTask {
    var phase: PublishPhase = .idle
    var cardId: Int64?
    var message: String?
    var uploaded = 0
    var total = 0
    var rejected = false

    var running: Bool { phase == .uploading || phase == .submitting }
}

/// 发布任务挂在 AppServices 上，不随发布页销毁；
/// 用户点发布后先跳到结果页，再切到其他页面也会继续跑完。
@MainActor
final class PublishCoordinator: ObservableObject {
    @Published private(set) var task = PublishTask()

    private let api: ApiService
    private let repository: AppRepository
    private var job: Task<Void, Never>?

    init(api: ApiService, repository: AppRepository) {
        self.api = api
        self.repository = repository
    }

    func publish(request: CreateCardRequest, images: [UIImage]) {
        job?.cancel()
        task = PublishTask(phase: .uploading, total: images.count)
        job = Task { [weak self] in
            guard let self else { return }
            var uploadedIds: [Int64] = []
            do {
                for (index, image) in images.enumerated() {
                    guard !Task.isCancelled else { return }
                    self.task = PublishTask(
                        phase: .uploading,
                        uploaded: index,
                        total: images.count
                    )
                    guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
                    let media = try await repository.uploadImage(data, purpose: "card")
                    if media.status == 2 {
                        throw ApiException(
                            code: "IMAGE_REJECTED",
                            message: "有图片未通过审核，请更换后重试"
                        )
                    }
                    uploadedIds.append(media.id)
                }
                guard !Task.isCancelled else { return }
                self.task = PublishTask(
                    phase: .submitting,
                    uploaded: images.count,
                    total: images.count
                )
                var withImages = request
                withImages.imageIds = uploadedIds.isEmpty ? nil : uploadedIds
                let card = try await api.createCard(withImages)
                // 大厅和我的需求都有短 TTL 缓存，发布成功后清掉，返回列表能立刻看到新帖。
                ApiDiskCache.clearAll()
                if card.status == 4 {
                    AppNoticeCenter.shared.message(
                        title: "已提交",
                        message: "内容正在等待人工复核"
                    )
                    self.task = PublishTask(
                        phase: .pendingReview,
                        cardId: card.id,
                        message: "内容已提交，正在等待人工复核。通过后会出现在大厅和你的需求列表里。"
                    )
                } else {
                    AppNoticeCenter.shared.message(
                        title: "发布成功",
                        message: "你的需求已经出现在大厅"
                    )
                    self.task = PublishTask(phase: .published, cardId: card.id)
                }
            } catch {
                if Task.isCancelled { return }
                for id in uploadedIds {
                    try? await repository.deleteMedia(id: id)
                }
                let apiError = error as? ApiException
                self.task = PublishTask(
                    phase: .failed,
                    message: error.localizedDescription,
                    rejected: apiError?.code == "CONTENT_REJECTED"
                        || apiError?.code == "IMAGE_REJECTED"
                        || apiError?.code == "AVATAR_REJECTED"
                )
            }
        }
    }
}
