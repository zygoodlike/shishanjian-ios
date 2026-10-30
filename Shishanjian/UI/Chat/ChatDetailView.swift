import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ChatDetailView: View {
    let convId: Int64
    let title: String?
    let cardTitle: String?
    let cardId: Int64?
    let otherUserId: Int64?
    let initialStatus: Int
    let currentUserId: Int64?
    let onBack: () -> Void
    let onOpenCard: (Int64) -> Void
    let onOpenUser: (Int64) -> Void

    @StateObject private var vm: ChatDetailViewModel
    @ObservedObject private var limits = AppLimits.shared
    @State private var text = ""
    @State private var reportOpen = false
    @State private var blockConfirm = false
    @State private var recallTarget: Message?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingImages: [PendingChatImage] = []
    @State private var replyTo: Message?
    @State private var uploadError: String?
    @State private var chatUploading = false
    @State private var previewImages: [String]?
    @State private var previewIndex = 0
    @State private var forwarding: Message?
    @State private var toastText: String?

    init(
        convId: Int64,
        title: String?,
        cardTitle: String?,
        cardId: Int64?,
        otherUserId: Int64?,
        initialStatus: Int,
        currentUserId: Int64?,
        onBack: @escaping () -> Void,
        onOpenCard: @escaping (Int64) -> Void,
        onOpenUser: @escaping (Int64) -> Void
    ) {
        self.convId = convId
        self.title = title
        self.cardTitle = cardTitle
        self.cardId = cardId
        self.otherUserId = otherUserId
        self.initialStatus = initialStatus
        self.currentUserId = currentUserId
        self.onBack = onBack
        self.onOpenCard = onOpenCard
        self.onOpenUser = onOpenUser
        _vm = StateObject(wrappedValue: ChatDetailViewModel(
            convId: convId,
            initialStatus: initialStatus,
            title: title,
            cardTitle: cardTitle,
            otherUserId: otherUserId
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(vm.title ?? (title?.isEmpty == false ? title! : "聊天"), onBack: onBack) {
                if let otherUserId {
                    Button { onOpenUser(otherUserId) } label: {
                        AvatarBlock(
                            userId: otherUserId,
                            name: vm.title,
                            imageURL: vm.otherAvatar,
                            size: 32
                        )
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    if otherUserId != nil {
                        Button("举报") { reportOpen = true }
                    }
                    Button("拉黑并结束会话", role: .destructive) { blockConfirm = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .frame(width: 44, height: 44)
                }
            }

            if let resolvedCardTitle = vm.cardTitle ?? cardTitle, !resolvedCardTitle.isEmpty {
                Button {
                    if let cardId { onOpenCard(cardId) }
                } label: {
                    Text("来自：\(resolvedCardTitle)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.bottom, 6)
                }
                .buttonStyle(.plain)
            }

            if vm.loading && vm.messages.isEmpty {
                // 本地缓存读完前留空，读完确认没有缓存才出骨架
                if vm.cacheChecked {
                    SkeletonChat()
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            safetyBanner
                            if let error = vm.error ?? uploadError {
                                StatusBanner(text: error, danger: true)
                                    .padding(.vertical, 8)
                            }
                            ForEach(Array(vm.messages.indices), id: \.self) { index in
                                let message = vm.messages[index]
                                if showTime(index) {
                                    Text(AppFormatters.clockTime(message.createdAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.tertiaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                messageRow(message)
                                    .id(message.id)
                            }
                            Spacer().frame(height: 8)
                        }
                        .padding(.horizontal, 16)
                    }
                    .onAppear {
                        // 首次进入直接定位到底部，不做长距离滚动动画；等一帧布局完成再定位
                        guard let last = vm.messages.last?.id else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.messages.last?.id) { oldValue, newValue in
                        guard let newValue else { return }
                        if oldValue == nil {
                            proxy.scrollTo(newValue, anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(newValue, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            if vm.conversationStatus != 0 {
                Text("会话已结束")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.surface)
            } else {
                inputBar
            }
        }
        .appBackground()
        .fullScreenCover(isPresented: Binding(
            get: { previewImages != nil },
            set: { if !$0 { previewImages = nil } }
        )) {
            ImageViewer(images: previewImages ?? [], initialIndex: previewIndex) {
                previewImages = nil
            }
        }
        .sheet(item: $forwarding) { message in
            ForwardPickerView(message: message, currentConvId: convId) {
                forwarding = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let toastText {
                Text(toastText)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(.bottom, 90)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            self.toastText = nil
                        }
                    }
            }
        }
        .task {
            await vm.open()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            let remaining = max(0, limits.config.chatImageMax - pendingImages.count)
            let batch = items.prefix(remaining)
            pickerItems = []
            uploadError = nil
            for item in batch {
                let pending = PendingChatImage()
                pendingImages.append(pending)
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        removePending(pending.id)
                        uploadError = "图片读取失败"
                        return
                    }
                    updatePending(pending.id) { image in
                        image.data = data
                        image.uploading = false
                    }
                }
            }
        }
        .sheet(isPresented: $reportOpen) {
            if let otherUserId {
                ReportSheet(targetType: "user", targetId: otherUserId)
            }
        }
        .confirmationDialog("拉黑对方？", isPresented: $blockConfirm, titleVisibility: .visible) {
            Button("确认拉黑", role: .destructive) {
                Task { _ = await vm.block() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("拉黑后会话立即结束，双方不能再发送消息。")
        }
        .alert("撤回消息？", isPresented: Binding(
            get: { recallTarget != nil },
            set: { if !$0 { recallTarget = nil } }
        )) {
            Button("取消", role: .cancel) { recallTarget = nil }
            Button("撤回", role: .destructive) {
                if let target = recallTarget {
                    Task { await vm.recall(messageId: target.id) }
                }
                recallTarget = nil
            }
        } message: {
            Text("撤回后双方都会显示“消息已撤回”。")
        }
    }

    private var safetyBanner: some View {
        Text("不要向陌生人转账，不要提供验证码，首次见面选公共场所。")
            .font(.system(size: 12))
            .foregroundColor(AppTheme.trustGreen)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.trustSurface))
            .padding(.vertical, 8)
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let replyTo {
                HStack(spacing: 8) {
                    Text("引用 \(quoteSenderName(replyTo))：\(quotePreview(replyTo))")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        self.replyTo = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.tertiaryText)
                            .frame(width: 44, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消引用")
                }
                .padding(.leading, 10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppTheme.soft)
                )
            }

            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingImages) { image in
                            pendingThumb(image)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, limits.config.chatImageMax - pendingImages.count),
                    matching: .images
                ) {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(AppTheme.ink)
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(pendingImages.count >= limits.config.chatImageMax || vm.sending)

                TextField("说点什么…", text: $text, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.soft))

                PrimaryButton(
                    title: chatUploading ? "上传中" : "发送",
                    loading: vm.sending || chatUploading,
                    enabled: canSend,
                    fillWidth: false
                ) {
                    Task {
                        chatUploading = true
                        var imageIds: [Int64] = []
                        do {
                            for image in pendingImages {
                                guard let data = image.data else { continue }
                                let media = try await AppServices.shared.repository.uploadImage(
                                    data,
                                    purpose: "chat"
                                )
                                imageIds.append(media.id)
                            }
                            if await vm.send(
                                content: text,
                                imageIds: imageIds,
                                replyToId: replyTo?.id
                            ) {
                                text = ""
                                pendingImages = []
                                replyTo = nil
                            } else {
                                for id in imageIds {
                                    try? await AppServices.shared.repository.deleteMedia(id: id)
                                }
                            }
                        } catch {
                            for id in imageIds {
                                try? await AppServices.shared.repository.deleteMedia(id: id)
                            }
                            uploadError = error.localizedDescription
                        }
                        chatUploading = false
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surface)
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = !pendingImages.isEmpty && pendingImages.allSatisfy { $0.data != nil }
        return !vm.sending && !chatUploading && (hasText || hasImage)
    }

    private func quoteSenderName(_ message: Message) -> String {
        if message.senderId == currentUserId { return "我" }
        let name = (vm.title ?? title) ?? ""
        return name.isEmpty ? "对方" : name
    }

    private func quotePreview(_ message: Message) -> String {
        if message.status == 1 { return "消息已撤回" }
        if message.status == 2 { return "该消息已屏蔽" }
        if message.type == 2 { return "[图片]" }
        let content = message.content ?? ""
        if message.type == 3 {
            return content.isEmpty ? "[图片]" : content + " [图片]"
        }
        return content.isEmpty ? "[消息]" : content
    }

    private func pendingThumb(_ image: PendingChatImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = image.data, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    AppTheme.soft
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if image.uploading {
                ProgressView()
                    .tint(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.black.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            RemoveBadge {
                removePending(image.id)
            }
        }
    }

    private func updatePending(_ id: UUID, _ change: (inout PendingChatImage) -> Void) {
        guard let index = pendingImages.firstIndex(where: { $0.id == id }) else { return }
        change(&pendingImages[index])
    }

    private func removePending(_ id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    private var ownAvatar: String? {
        AppServices.shared.auth.session?.avatarKey
    }

    private func messageRow(_ message: Message) -> some View {
        let own = message.senderId == currentUserId
        let urls = imageURLs(message)
        return HStack(alignment: .bottom, spacing: 8) {
            if !own {
                AvatarBlock(
                    userId: otherUserId ?? message.senderId,
                    name: vm.title,
                    imageURL: vm.otherAvatar,
                    size: 36
                )
            }
            Spacer(minLength: own ? 52 : 76)
            contentBubble(message, own: own)
                .contextMenu {
                    if message.status == 0 {
                        Button("引用回复") { replyTo = message }
                    }
                    if message.status == 0, let text = message.content, !text.isEmpty {
                        Button("复制") { UIPasteboard.general.string = text }
                    }
                    if message.status == 0 {
                        Button("转发") { forwarding = message }
                    }
                    if message.status == 0, !urls.isEmpty {
                        Button("保存图片") { saveImages(urls) }
                    }
                    if own && message.status == 0 {
                        Button("撤回", role: .destructive) { recallTarget = message }
                    }
                }
            if own {
                AvatarBlock(userId: currentUserId ?? 0, name: "我", imageURL: ownAvatar, size: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: own ? .trailing : .leading)
        .padding(.vertical, 4)
    }

    private func contentBubble(_ message: Message, own: Bool) -> some View {
        let urls = imageURLs(message)
        return Group {
            if message.status == 1 {
                Text("消息已撤回")
                    .font(.system(size: 13))
                    .foregroundColor(own ? .white.opacity(0.75) : AppTheme.tertiaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(bubbleBackground(own))
            } else if message.status == 2 {
                Text("该消息已屏蔽")
                    .font(.system(size: 13))
                    .foregroundColor(own ? .white.opacity(0.75) : AppTheme.tertiaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(bubbleBackground(own))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let reply = message.replyTo {
                        Text("\(reply.senderName ?? "对方")：\(reply.preview ?? "[消息]")")
                            .font(.system(size: 11))
                            .foregroundColor(own ? .white.opacity(0.86) : AppTheme.secondaryText)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(own ? Color.white.opacity(0.14) : AppTheme.soft)
                            )
                            .padding(.horizontal, urls.isEmpty ? 14 : 8)
                            .padding(.top, urls.isEmpty ? 9 : 6)
                            .padding(.bottom, 6)
                    }

                    if !urls.isEmpty {
                        chatImageGrid(urls) { index in
                            openImage(message, at: index)
                        }
                    }

                    if let content = message.content, !content.isEmpty {
                        Text(content)
                            .font(.system(size: 15.5))
                            .foregroundColor(own ? .white : AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(4)
                            .padding(.horizontal, urls.isEmpty ? 14 : 11)
                            .padding(.top, urls.isEmpty ? 11 : 7)
                            .padding(.bottom, urls.isEmpty ? 11 : 8)
                    }
                }
                .padding(urls.isEmpty ? 0 : 3)
                .background(bubbleBackground(own))
            }
        }
    }

    private func bubbleBackground(_ own: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(own ? AppTheme.accentDeep : AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(own ? Color.clear : AppTheme.line, lineWidth: 1)
            )
    }

    private func chatImageGrid(
        _ urls: [String],
        onTap: @escaping (Int) -> Void
    ) -> some View {
        let columns = urls.count == 1 ? 1 : (urls.count <= 4 ? 2 : 3)
        let side: CGFloat = columns == 1 ? 210 : (columns == 2 ? 106 : 70)
        let rows = (urls.count + columns - 1) / columns
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < urls.count {
                            CachedImage(url: ApiConfig.absolute(urls[index]), maxPoint: side) {
                                AppTheme.soft
                            }
                            .frame(width: side, height: columns == 1 ? 160 : side)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .onTapGesture { onTap(index) }
                        } else {
                            Color.clear.frame(width: side, height: side)
                        }
                    }
                }
            }
        }
    }

    private func imageURLs(_ message: Message) -> [String] {
        let list = (message.images ?? []).compactMap { $0.url }
        if !list.isEmpty { return list }
        return message.mediaUrl.map { [$0] } ?? []
    }

    private var allChatImages: [String] {
        vm.messages.filter { $0.status == 0 }.flatMap { imageURLs($0) }
    }

    private func openImage(_ message: Message, at index: Int) {
        var offset = 0
        for item in vm.messages {
            if item.id == message.id { break }
            if item.status == 0 { offset += imageURLs(item).count }
        }
        previewImages = allChatImages
        previewIndex = offset + index
    }

    private func saveImages(_ urls: [String]) {
        Task {
            do {
                for url in urls {
                    guard let absolute = ApiConfig.absolute(url) else { continue }
                    let (data, _) = try await URLSession.shared.data(from: absolute)
                    guard let image = UIImage(data: data) else { continue }
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }
                toastText = "已保存到相册"
            } catch {
                toastText = "保存失败"
            }
        }
    }

    private func showTime(_ index: Int) -> Bool {
        guard index > 0 else { return true }
        guard let previous = AppFormatters.parse(vm.messages[index - 1].createdAt),
              let current = AppFormatters.parse(vm.messages[index].createdAt) else { return false }
        return current.timeIntervalSince(previous) >= 300
    }
}

@MainActor
private struct ForwardPickerView: View {
    let message: Message
    let currentConvId: Int64
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [Conversation] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("转发到")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Button { dismiss(); onDone() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if loading {
                SkeletonList(rows: 3, rowHeight: 64, showAvatar: true)
                Spacer()
            } else if let error {
                Spacer()
                Text(error).font(.system(size: 13)).foregroundColor(AppTheme.danger)
                Spacer()
            } else if conversations.isEmpty {
                Spacer()
                Text("暂无可转发的会话").font(.system(size: 13)).foregroundColor(AppTheme.tertiaryText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(conversations) { conversation in
                            Button {
                                Task { await forward(to: conversation.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    AvatarBlock(
                                        userId: conversation.otherUserId ?? 0,
                                        name: conversation.otherNickname,
                                        imageURL: conversation.otherAvatar,
                                        size: 42
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(conversation.otherNickname ?? "")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppTheme.ink)
                                        Text(conversation.cardTitle ?? "")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.tertiaryText)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .cardSurface()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 12)
                }
            }
        }
        .appBackground()
        .task { await load() }
    }

    private func load() async {
        loading = true
        do {
            let list = try await AppServices.shared.api.conversations()
            conversations = list.filter { $0.id != currentConvId }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func forward(to convId: Int64) async {
        do {
            let imageIds = (message.images ?? []).map(\.id)
            _ = try await AppServices.shared.api.sendMessage(
                conversationId: convId,
                body: SendMessageRequest(
                    content: message.content?.isEmpty == false ? message.content : nil,
                    imageIds: imageIds.isEmpty ? nil : imageIds,
                    clientMsgId: UUID().uuidString
                )
            )
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PendingChatImage: Identifiable {
    let id = UUID()
    var data: Data? = nil
    var mediaId: Int64? = nil
    var uploading = true
}
