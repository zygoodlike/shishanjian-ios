import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct CardDetailView: View {
    let cardId: Int64
    let currentUserId: Int64?
    let loggedIn: Bool
    let onRequireLogin: () -> Void
    let onBack: () -> Void
    let onOpenCard: (Int64) -> Void
    let onOpenChat: (Int64?, String?, String?, Int64?) -> Void
    let onOpenUser: (Int64) -> Void
    let onOpenFeedback: () -> Void

    @StateObject private var vm: CardDetailViewModel
    @ObservedObject private var limits = AppLimits.shared
    @State private var manageOpen = false
    @State private var pendingAction: CardAction?
    @State private var reportOpen = false
    @State private var replyTo: Comment?
    @State private var commentText = ""
    @State private var commentPickerItems: [PhotosPickerItem] = []
    @State private var commentImages: [CommentPendingImage] = []
    @State private var commentUploading = false
    @State private var reported = false
    @State private var viewerImages: [String]?
    @State private var viewerIndex = 0
    @State private var commentToDelete: Comment?
    @State private var pendingCommentMode: String?

    init(
        cardId: Int64,
        currentUserId: Int64?,
        loggedIn: Bool,
        onRequireLogin: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onOpenCard: @escaping (Int64) -> Void,
        onOpenChat: @escaping (Int64?, String?, String?, Int64?) -> Void,
        onOpenUser: @escaping (Int64) -> Void,
        onOpenFeedback: @escaping () -> Void
    ) {
        self.cardId = cardId
        self.currentUserId = currentUserId
        self.loggedIn = loggedIn
        self.onRequireLogin = onRequireLogin
        self.onBack = onBack
        self.onOpenCard = onOpenCard
        self.onOpenChat = onOpenChat
        self.onOpenUser = onOpenUser
        self.onOpenFeedback = onOpenFeedback
        _vm = StateObject(wrappedValue: CardDetailViewModel(cardId: cardId))
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("", onBack: onBack) {
                if !loggedIn {
                    Button(action: onRequireLogin) {
                        Text("登录")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accentDeep)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        if vm.card?.mine == true {
                            Button("管理这条需求") { manageOpen = true }
                        } else {
                            Button("举报") { reportOpen = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 44, height: 44)
                    }
                }
            }

            if vm.loading && vm.card == nil {
                SkeletonDetail()
                Spacer()
            } else if vm.card == nil {
                Spacer()
                ErrorStateView(message: vm.error ?? "出了点问题") {
                    Task { await vm.load() }
                }
                Spacer()
            } else if let card = vm.card {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        cardHeader(card)
                        if vm.error != nil || vm.notice != nil {
                            StatusBanner(text: vm.error ?? vm.notice ?? "", danger: vm.error != nil)
                                .padding(.top, 12)
                            if vm.rejected {
                                Button("去反馈", action: onOpenFeedback)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.accentDeep)
                                    .buttonStyle(.plain)
                                    .padding(.top, 6)
                            }
                        }
                        if reported {
                            StatusBanner(text: "已收到，会在 24 小时内处理")
                                .padding(.top, 12)
                        }
                        if card.status == 2 {
                            StatusBanner(text: card.mine ? "已隐藏，其他人看不到这条需求" : "作者已隐藏")
                                .padding(.top, 12)
                        }
                        if card.status == 0 || card.status == 4 {
                            StatusBanner(text: card.status == 0 ? "内容正在审核，通常几分钟内完成" : "内容需要人工复核，24 小时内处理")
                                .padding(.top, 12)
                        }
                        if card.status == 5 {
                            StatusBanner(text: "内容不符合社区规范，可以修改后重试", danger: true)
                                .padding(.top, 12)
                        }
                        actionButton(card)
                            .padding(.top, 18)

                        if card.mine {
                            interestsSection(card)
                        }
                        commentsSection(card)
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)

                commentInput(card)
            }
        }
        .appBackground()
        .fullScreenCover(isPresented: Binding(
            get: { viewerImages != nil },
            set: { if !$0 { viewerImages = nil } }
        )) {
            ImageViewer(images: viewerImages ?? [], initialIndex: viewerIndex) {
                viewerImages = nil
            }
        }
        .task { await vm.loadIfStale() }
        .onChange(of: commentPickerItems) { _, items in
            guard !items.isEmpty else { return }
            let remaining = max(0, limits.config.commentImageMax - commentImages.count)
            let batch = items.prefix(remaining)
            commentPickerItems = []
            for item in batch {
                let pending = CommentPendingImage()
                commentImages.append(pending)
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        commentImages.removeAll { $0.id == pending.id }
                        AppNoticeCenter.shared.error("图片读取失败")
                        return
                    }
                    updateCommentImage(pending.id) {
                        $0.data = data
                        $0.uploading = false
                    }
                }
            }
        }
        .onChange(of: loggedIn) { _, value in
            if value { Task { await vm.load() } }
        }
        .sheet(isPresented: $manageOpen) {
            if let card = vm.card {
                ManageCardSheet(
                    card: card,
                    loading: vm.actionLoading,
                    onAction: { action in
                        manageOpen = false
                        pendingAction = action
                    },
                    onSaveMode: { mode in
                        manageOpen = false
                        pendingCommentMode = mode
                    }
                )
            }
        }
        .sheet(isPresented: $reportOpen) {
            if let card = vm.card {
                ReportSheet(targetType: "card", targetId: card.id) {
                    reported = true
                }
            }
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmLabel, role: action.destructive ? .destructive : nil) {
                perform(action)
            }
            Button("取消", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .confirmationDialog(
            "删除这条评论？",
            isPresented: Binding(
                get: { commentToDelete != nil },
                set: { if !$0 { commentToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: commentToDelete
        ) { comment in
            Button("删除", role: .destructive) {
                commentToDelete = nil
                Task { await vm.deleteComment(id: comment.id) }
            }
            Button("取消", role: .cancel) { commentToDelete = nil }
        } message: { _ in
            Text("删除后不可恢复。作者可以删除自己需求下的任意评论。")
        }
        .confirmationDialog(
            "保存评论区设置？",
            isPresented: Binding(
                get: { pendingCommentMode != nil },
                set: { if !$0 { pendingCommentMode = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingCommentMode
        ) { mode in
            Button("保存") {
                pendingCommentMode = nil
                Task { await vm.setCommentMode(mode) }
            }
            Button("取消", role: .cancel) { pendingCommentMode = nil }
        } message: { mode in
            Text("保存后评论区将切换为「\(mode == "hidden" ? "不公开" : mode == "closed" ? "关闭" : "公开")」，只影响之后的新评论。")
        }
    }

    private func perform(_ action: CardAction) {
        pendingAction = nil
        Task {
            switch action {
            case .hide:
                await vm.pause()
            case .resume:
                await vm.resume()
            case .close:
                await vm.close()
            case .delete:
                if await vm.deleteCard() { onBack() }
            }
        }
    }

    private func cardHeader(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SceneChip(scene: card.scene)
                Text(AppFormatters.cardStatusLabel(card.status, fallback: card.statusLabel))
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                if card.status == 1 && card.acceptedCount >= card.headcount {
                    Text("已满员")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accentDeep)
                }
            }
            Text(card.title ?? "")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.ink)
                .padding(.top, 12)

            let timeText = (card.whenText ?? "").isEmpty ? AppFormatters.whenLabel(card.whenType) : (card.whenText ?? "")
            if !timeText.isEmpty {
                metaRow("clock", timeText)
                    .padding(.top, 14)
            }
            if let place = card.placeName, !place.isEmpty {
                metaRow("mappin.and.ellipse", place)
                    .padding(.top, 8)
            }
            metaRow("person.2", "需要 \(card.headcount) 人 · 已有 \(card.acceptedCount) 人同意")
                .padding(.top, 8)

            if let description = card.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.ink)
                    .lineSpacing(6)
                    .padding(.top, 16)
            }
            let images = card.images ?? []
            if !images.isEmpty {
                ImageGrid(images: images) { index in
                    viewerIndex = index
                    viewerImages = images
                }
                .padding(.top, 14)
            }
            if let tags = card.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { TagChip(text: $0) }
                }
                .padding(.top, 14)
            }
            if let reward = card.reward {
                let payText = "报酬 ¥\(reward)" + (card.payNote.map { " · \($0)" } ?? "")
                Text(payText)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.accentDeep)
                    .padding(.top, 12)
            }
            HStack(spacing: 8) {
                if card.identity == "anonymous" {
                    AvatarBlock(userId: 0, name: "匿名", size: 32, anonymous: true)
                    Text("匿名")
                } else {
                    AvatarBlock(
                        userId: card.authorId ?? card.id,
                        name: card.authorName,
                        imageURL: card.authorAvatar,
                        size: 32
                    )
                    Text(card.authorName ?? "")
                }
                Text(card.mine ? "发布者 · 我" : "发布者")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.tertiaryText)
                Spacer()
                Text(AppFormatters.relativeTime(card.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.tertiaryText)
            }
            .font(.system(size: 14))
            .padding(.top, 18)
            .contentShape(Rectangle())
            .onTapGesture {
                if let id = card.authorId { onOpenUser(id) }
            }
        }
    }

    private func metaRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    private func actionButton(_ card: Card) -> some View {
        Group {
            if !loggedIn {
                PrimaryButton(title: "登录后加入", action: onRequireLogin)
            } else if card.mine {
                SecondaryButton(title: "管理这条需求", fillWidth: true) {
                    manageOpen = true
                }
            } else if card.interestStatus == 1 {
                PrimaryButton(title: "已同意，去聊天") {
                    onOpenChat(card.interestConversationId, card.authorName, card.title, card.id)
                }
            } else {
                let label: String
                let enabled: Bool
                if card.interestStatus == 0 {
                    label = "已发送，等待回应"
                    enabled = false
                } else if card.interestStatus == 2 {
                    label = "对方已处理"
                    enabled = false
                } else if card.interestStatus == 4 {
                    label = "意向已失效"
                    enabled = false
                } else if card.status != 1 {
                    label = "已结束"
                    enabled = false
                } else if card.acceptedCount >= card.headcount {
                    label = "已满员"
                    enabled = false
                } else {
                    label = "我想加入"
                    enabled = true
                }
                PrimaryButton(title: label, loading: vm.actionLoading, enabled: enabled) {
                    Task { await vm.join() }
                }
            }
        }
    }

    private func interestsSection(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("收到的意向")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                Text("\(vm.interests.filter { $0.status == 0 }.count)")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.tertiaryText)
            }
            .padding(.top, 24)

            if vm.interests.isEmpty {
                Text("还没有人表达意向，把需求转发出去试试")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.tertiaryText)
                    .padding(.vertical, 14)
            } else {
                ForEach(vm.interests) { interest in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            AvatarBlock(userId: interest.userId, name: interest.nickname, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(interest.nickname ?? "")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.ink)
                                Text(AppFormatters.relativeTime(interest.createdAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.tertiaryText)
                            }
                            Spacer()
                            Text(AppFormatters.interestStatusLabel(interest.status))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.tertiaryText)
                        }
                        if let note = interest.note, !note.isEmpty {
                            Text("「\(note)」")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.secondaryText)
                                .lineLimit(2)
                                .padding(.leading, 46)
                        }
                        if interest.status == 0 {
                            HStack {
                                Spacer()
                                SecondaryButton(title: "忽略", enabled: !vm.actionLoading) {
                                    Task { await vm.ignoreInterest(id: interest.id) }
                                }
                                PrimaryButton(title: "同意", enabled: !vm.actionLoading, fillWidth: false) {
                                    Task {
                                        if let conversationId = await vm.acceptInterest(id: interest.id) {
                                            onOpenChat(conversationId, interest.nickname, card.title, card.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func commentsSection(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("评论 \(card.commentCount) 条")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.ink)
                Text("· \(commentModeLabel(card.commentMode))")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.tertiaryText)
            }
            .padding(.top, 24)

            if card.commentMode == "hidden" {
                StatusBanner(text: "评论区不公开，大家大胆评论")
                    .padding(.top, 8)
            }

            if vm.comments.isEmpty {
                Text("还没有评论，来说第一句")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.tertiaryText)
                    .padding(.vertical, 18)
            } else {
                ForEach(vm.flatComments) { item in
                    commentRow(item.comment, depth: item.depth, card: card)
                }
            }
        }
    }

    private func commentRow(_ comment: Comment, depth: Int, card: Card) -> some View {
        let deleted = comment.deleted || comment.status == 3
        let canDelete = loggedIn && (comment.userId == currentUserId || card.mine)
        return HStack(alignment: .top, spacing: 9) {
            AvatarBlock(userId: comment.userId, name: comment.nickname, imageURL: comment.avatar, size: 30)
                .onTapGesture { onOpenUser(comment.userId) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(comment.nickname ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .onTapGesture { onOpenUser(comment.userId) }
                    if let replyName = comment.replyToNickname, !replyName.isEmpty {
                        Text("回复 @\(replyName)")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accentDeep)
                    }
                    Spacer()
                    Text(AppFormatters.relativeTime(comment.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                if deleted {
                    Text("该评论已删除")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.tertiaryText)
                        .lineSpacing(4)
                } else {
                    if let content = comment.content, !content.isEmpty {
                        Text(content)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.ink)
                            .lineSpacing(4)
                    }
                    let urls = (comment.images ?? []).compactMap { $0.url }
                    if !urls.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                CachedImage(url: ApiConfig.absolute(url), maxPoint: 76) {
                                    AppTheme.soft
                                }
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onTapGesture {
                                    viewerIndex = index
                                    viewerImages = urls
                                }
                            }
                        }
                        .padding(.top, 3)
                    }
                }
                if !deleted {
                    HStack(spacing: 14) {
                        Button("回复") {
                            if loggedIn { replyTo = comment } else { onRequireLogin() }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                        if canDelete {
                            Button("删除") {
                                commentToDelete = comment
                            }
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.danger)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.leading, CGFloat(max(0, depth - 1)) * 18)
        .padding(.top, 12)
    }

    private func commentInput(_ card: Card) -> some View {
        Group {
            if card.commentMode == "closed" {
                Text("作者已关闭评论区")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.surface)
            } else if !loggedIn {
                Button(action: onRequireLogin) {
                    Text("登录后参与评论")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.accentDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppTheme.surface)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let replyTo {
                        HStack(spacing: 8) {
                            Text("回复 @\(replyTo.nickname ?? "")")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accentDeep)
                            Button("取消") { self.replyTo = nil }
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                    if !commentImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(commentImages) { image in
                                    commentThumb(image)
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        PhotosPicker(
                            selection: $commentPickerItems,
                            maxSelectionCount: max(1, limits.config.commentImageMax - commentImages.count),
                            matching: .images
                        ) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(AppTheme.ink)
                                .frame(width: 38, height: 42)
                        }
                        .buttonStyle(.plain)
                        .disabled(commentImages.count >= limits.config.commentImageMax || vm.actionLoading)

                        TextField("说点什么…", text: $commentText)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(Capsule().fill(AppTheme.soft))
                        PrimaryButton(
                            title: "发送",
                            loading: vm.actionLoading || commentUploading,
                            enabled: canSubmitComment,
                            fillWidth: false
                        ) {
                            Task {
                                commentUploading = true
                                var imageIds: [Int64] = []
                                do {
                                    for image in commentImages {
                                        guard let data = image.data else { continue }
                                        let media = try await AppServices.shared.repository.uploadImage(
                                            data,
                                            purpose: "comment"
                                        )
                                        if media.status == 2 {
                                            throw ApiException(
                                                code: "IMAGE_REJECTED",
                                                message: "有图片未通过审核，请更换后重试"
                                            )
                                        }
                                        imageIds.append(media.id)
                                    }
                                    if await vm.submitComment(
                                        commentText,
                                        replyTo: replyTo,
                                        imageIds: imageIds
                                    ) {
                                        commentText = ""
                                        self.replyTo = nil
                                        commentImages = []
                                    } else {
                                        for id in imageIds {
                                            try? await AppServices.shared.repository.deleteMedia(id: id)
                                        }
                                    }
                                } catch {
                                    for id in imageIds {
                                        try? await AppServices.shared.repository.deleteMedia(id: id)
                                    }
                                    AppNoticeCenter.shared.error(error.localizedDescription)
                                }
                                commentUploading = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
            }
        }
    }

    private var canSubmitComment: Bool {
        let hasText = !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = !commentImages.isEmpty && commentImages.allSatisfy { $0.data != nil }
        return !vm.actionLoading && !commentUploading && (hasText || hasImage)
    }

    private func commentThumb(_ image: CommentPendingImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = image.data, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    AppTheme.soft
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            if image.uploading {
                ProgressView()
                    .tint(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            RemoveBadge {
                commentImages.removeAll { $0.id == image.id }
            }
        }
    }

    private func updateCommentImage(_ id: UUID, _ change: (inout CommentPendingImage) -> Void) {
        guard let index = commentImages.firstIndex(where: { $0.id == id }) else { return }
        change(&commentImages[index])
    }

    private func commentModeLabel(_ mode: String?) -> String {
        switch mode {
        case "hidden": return "不公开"
        case "closed": return "关闭"
        default: return "公开"
        }
    }

}

private enum CardAction: String, Identifiable {
    case hide
    case resume
    case close
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hide: return "隐藏这条需求？"
        case .resume: return "重新公开这条需求？"
        case .close: return "结束这条需求？"
        case .delete: return "删除这条需求？"
        }
    }

    var message: String {
        switch self {
        case .hide: return "隐藏后其他人看不到，随时可以重新公开。"
        case .resume: return "重新公开后，这条需求会再次出现在大厅。"
        case .close: return "结束后不再接收新的意向，已建立的会话不受影响。"
        case .delete: return "删除后不可恢复，未处理的意向会失效。"
        }
    }

    var confirmLabel: String {
        switch self {
        case .hide: return "隐藏"
        case .resume: return "重新公开"
        case .close: return "结束"
        case .delete: return "删除"
        }
    }

    var destructive: Bool {
        self == .close || self == .delete
    }
}

@MainActor
private struct ManageCardSheet: View {
    let card: Card
    let loading: Bool
    let onAction: (CardAction) -> Void
    let onSaveMode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: String

    init(card: Card, loading: Bool, onAction: @escaping (CardAction) -> Void, onSaveMode: @escaping (String) -> Void) {
        self.card = card
        self.loading = loading
        self.onAction = onAction
        self.onSaveMode = onSaveMode
        _selectedMode = State(initialValue: card.commentMode ?? "public")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("管理这条需求")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.ink)
                .padding(.bottom, 14)

            if card.status == 1 {
                manageRow("隐藏这条需求", "从大厅移除，随时可以重新公开") {
                    onAction(.hide)
                    dismiss()
                }
            }
            if card.status == 2 {
                manageRow("重新公开", "重新出现在大厅") {
                    onAction(.resume)
                    dismiss()
                }
            }
            if card.status == 1 || card.status == 2 {
                manageRow("结束这条需求", "结束后不再接受新的意向") {
                    onAction(.close)
                    dismiss()
                }
            }

            Text("评论区模式")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.ink)
                .padding(.top, 12)
            HStack(spacing: 8) {
                ForEach([
                    SegmentOption(key: "public", label: "公开"),
                    SegmentOption(key: "hidden", label: "不公开"),
                    SegmentOption(key: "closed", label: "关闭"),
                ]) { option in
                    let active = selectedMode == option.key
                    Button {
                        selectedMode = option.key
                    } label: {
                        Text(option.label)
                            .font(.system(size: 13))
                            .foregroundColor(active ? .white : AppTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Capsule().fill(active ? AppTheme.ink : AppTheme.soft))
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                }
            }
            .padding(.top, 8)

            PrimaryButton(
                title: "保存评论区设置",
                loading: loading,
                enabled: selectedMode != (card.commentMode ?? "public"),
                fillWidth: true
            ) {
                onSaveMode(selectedMode)
                dismiss()
            }
            .padding(.top, 10)

            Button("删除需求") {
                onAction(.delete)
                dismiss()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AppTheme.danger)
            .frame(height: 48)
            .padding(.top, 14)
            .disabled(loading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 28)
        .presentationDetents([.large])
    }

    private func manageRow(_ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CommentPendingImage: Identifiable {
    let id = UUID()
    var data: Data? = nil
    var mediaId: Int64? = nil
    var uploading = true
}
