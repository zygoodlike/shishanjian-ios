import PhotosUI
import SwiftUI

@MainActor
final class MyFeedbackViewModel: ObservableObject {
    @Published var items: [Feedback] = []
    @Published var loading = true
    @Published var error: String?

    private let api = AppServices.shared.api
    private let throttle = RefreshThrottle()
    private var lastLoadedAt: Date?

    /// 刚提交过反馈时下次进入列表强制走网络，不读 60 秒缓存。
    static var needsBypass = false

    func loadIfStale() async {
        if let last = lastLoadedAt, Date().timeIntervalSince(last) < 60 { return }
        await load()
    }

    func load(manual: Bool = false) async {
        if manual && !throttle.tryAcquire() { return }
        loading = !manual && items.isEmpty
        error = nil
        let bypass = manual || Self.needsBypass
        do {
            items = try await api.myFeedback(bypassCache: bypass)
            Self.needsBypass = false
            lastLoadedAt = Date()
            loading = false
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }
}

@MainActor
struct FeedbackView: View {
    let onBack: () -> Void
    let onOpenMyFeedback: () -> Void

    @ObservedObject private var limits = AppLimits.shared
    @State private var content = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploads: [FeedbackUpload] = []
    @State private var submitting = false
    @State private var submitted = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("意见反馈", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if submitted {
                        Text("已提交，管理员会人工查看")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.accentDeep)
                            .padding(.top, 20)
                        PrimaryButton(title: "查看我的反馈", action: onOpenMyFeedback)
                            .padding(.top, 16)
                    } else {
                        Text("如果正常需求、评论或头像被误拦截，请说明情况并上传截图。反馈图片不会再经过机器审核，会直接给管理员看。")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                            .lineSpacing(4)

                        TextEditor(text: $content)
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(height: 150)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topLeading) {
                                if content.isEmpty {
                                    Text("说明被拦截的内容和原因…")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppTheme.tertiaryText)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 18)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.top, 14)
                            .onChange(of: content) { _, value in
                                if value.count > 500 { content = String(value.prefix(500)) }
                            }
                        Text("\(content.count)/500")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Text("凭证图片（选填，最多 \(limits.config.feedbackImageMax) 张）")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.ink)
                            .padding(.top, 14)
                        uploadGrid
                            .padding(.top, 8)

                        if let error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.danger)
                                .padding(.top, 12)
                        }

                        PrimaryButton(
                            title: "提交反馈",
                            loading: submitting,
                            enabled: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            submit()
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 30)
            }
        }
        .appBackground()
    }

    private var uploadGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach($uploads) { $item in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button {
                        uploads.removeAll { $0.id == item.id }
                    } label: {
                        Text("×")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.black.opacity(0.6), in: Circle())
                            // 视觉 20，点击区域 44
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // 圆点仍贴在右上角内 5pt（44 框中心偏移 = 22 - 10 - 5）
                    .offset(x: 7, y: -7)
                    .accessibilityLabel("移除")
                }
            }
            if uploads.count < limits.config.feedbackImageMax {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, limits.config.feedbackImageMax - uploads.count),
                    matching: .images
                ) {
                    Text("＋")
                        .font(.system(size: 26))
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(AppTheme.soft, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    guard uploads.count < limits.config.feedbackImageMax else { break }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { continue }
                    uploads.append(FeedbackUpload(image: image, data: data))
                }
                pickerItems = []
            }
        }
    }

    private func submit() {
        submitting = true
        error = nil
        Task {
            var imageIds: [Int64] = []
            do {
                for upload in uploads {
                    let media = try await AppServices.shared.repository.uploadImage(
                        upload.data,
                        purpose: "feedback"
                    )
                    imageIds.append(media.id)
                }
                _ = try await AppServices.shared.api.submitFeedback(
                    CreateFeedbackRequest(
                        content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                        imageIds: imageIds
                    )
                )
                MyFeedbackViewModel.needsBypass = true
                submitting = false
                submitted = true
            } catch {
                for id in imageIds {
                    try? await AppServices.shared.repository.deleteMedia(id: id)
                }
                submitting = false
                self.error = error.localizedDescription
            }
        }
    }
}

@MainActor
struct MyFeedbackView: View {
    let onBack: () -> Void
    let onNewFeedback: () -> Void

    @StateObject private var vm = MyFeedbackViewModel()
    @State private var viewerImages: [String]?
    @State private var viewerIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("我的反馈", onBack: onBack)
            if vm.loading && vm.items.isEmpty {
                SkeletonList(rows: 3, rowHeight: 110)
                Spacer()
            } else if let error = vm.error, vm.items.isEmpty {
                Spacer()
                ErrorStateView(message: error) { Task { await vm.load() } }
                Spacer()
            } else if vm.items.isEmpty {
                EmptyStateView(
                    title: "还没有提交过反馈",
                    subtitle: "被误拦截时可以告诉管理员",
                    actionTitle: "去反馈",
                    action: onNewFeedback
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.items) { item in
                            feedbackCard(item)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 8)
                }
                .refreshable { await vm.load(manual: true) }
            }
        }
        .appBackground()
        .task { await vm.loadIfStale() }
        .fullScreenCover(isPresented: Binding(
            get: { viewerImages != nil },
            set: { if !$0 { viewerImages = nil } }
        )) {
            ImageViewer(images: viewerImages ?? [], initialIndex: viewerIndex) {
                viewerImages = nil
            }
        }
    }

    private func feedbackCard(_ item: Feedback) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.status == 0 ? "待处理" : "已处理")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(item.status == 0 ? AppTheme.accentDeep : AppTheme.secondaryText)
                Spacer()
                Text(AppFormatters.relativeTime(item.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.tertiaryText)
            }
            Text(item.content ?? "")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.ink)
                .lineSpacing(4)
            if let images = item.images, !images.isEmpty {
                ImageGrid(images: images, compact: true) { index in
                    viewerIndex = index
                    viewerImages = images
                }
            }
            if let reply = item.adminReply, !reply.isEmpty {
                Text("管理员回复：\(reply)")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.accentDeep)
            }
        }
        .padding(16)
        .cardSurface()
    }
}

@MainActor
private struct FeedbackUpload: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
}
