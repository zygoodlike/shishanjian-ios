import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct CreateCardView: View {
    let onBack: () -> Void
    let onPublishing: () -> Void

    @ObservedObject private var limits = AppLimits.shared
    @State private var scene = ""
    @State private var title = ""
    @State private var description = ""
    @State private var whenType = ""
    @State private var place = ""
    @State private var headcount = 2
    @State private var selectedTags = Set<String>()
    @State private var identity = "nickname"
    @State private var commentMode = "public"
    @State private var reward = ""
    @State private var payNote = ""
    @State private var localError: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploads: [PendingImage] = []

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("发布需求", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FieldLabel(text: "选一个场景", required: true)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                        spacing: 10
                    ) {
                        ForEach(appScenes) { item in
                            sceneOption(item)
                        }
                    }
                    .padding(.top, 12)

                    FieldLabel(text: "标题", required: true)
                        .padding(.top, 24)
                    SoftTextField(text: $title, placeholder: "一句话说清楚要做什么")
                        .padding(.top, 8)
                        .onChange(of: title) { _, value in
                            if value.count > 20 { title = String(value.prefix(20)) }
                        }
                    Text("\(title.count)/20")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)

                    FieldLabel(text: "补充说明（选填）")
                        .padding(.top, 18)
                    TextEditor(text: $description)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.ink)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(height: 110)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.soft))
                        .overlay(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("集合方式、希望找什么样的人…")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.tertiaryText)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.top, 8)
                        .onChange(of: description) { _, value in
                            if value.count > 200 { description = String(value.prefix(200)) }
                        }
                    Text("\(description.count)/200")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)

                    FieldLabel(text: "图片（选填，最多 \(limits.config.cardImageMax) 张）")
                        .padding(.top, 18)
                    uploadGrid
                        .padding(.top, 8)
                    Text("图片会经过内容审核，通过后自动展示")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.tertiaryText)
                        .padding(.top, 6)

                    FieldLabel(text: "时间（选填）")
                        .padding(.top, 18)
                    FlowLayout(spacing: 8) {
                        ForEach(whenOptions) { option in
                            FilterPill(title: option.label, selected: whenType == option.key) {
                                whenType = option.key
                            }
                        }
                    }
                    .padding(.top, 8)

                    FieldLabel(text: "地点（选填）")
                        .padding(.top, 18)
                    SoftTextField(text: $place, placeholder: "如：图书馆四楼")
                        .padding(.top, 8)
                        .onChange(of: place) { _, value in
                            if value.count > 50 { place = String(value.prefix(50)) }
                        }

                    FieldLabel(text: "人数（选填）")
                        .padding(.top, 18)
                    HStack(spacing: 0) {
                        stepperButton("minus", enabled: headcount > 1) { headcount -= 1 }
                        Text("\(headcount) 人")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 84)
                        stepperButton("plus", enabled: headcount < 5) { headcount += 1 }
                    }
                    .padding(.top, 8)

                    if scene == "errand" || scene == "car" {
                        FieldLabel(text: "费用/报酬（元）")
                            .padding(.top, 18)
                        SoftTextField(text: $reward, placeholder: "0", keyboard: .numberPad)
                            .padding(.top, 8)
                            .onChange(of: reward) { _, value in
                                reward = String(value.filter { $0.isNumber }.prefix(4))
                            }
                        FieldLabel(text: "结算说明")
                            .padding(.top, 12)
                        SoftTextField(text: $payNote, placeholder: "如：完成后微信转账")
                            .padding(.top, 8)
                            .onChange(of: payNote) { _, value in
                                if value.count > 30 { payNote = String(value.prefix(30)) }
                            }
                        Text("报酬私下结算，平台不收款")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accentDeep)
                            .padding(.top, 8)
                    }

                    FieldLabel(text: "标签（选填，最多 3 个）")
                        .padding(.top, 18)
                    FlowLayout(spacing: 8) {
                        ForEach(appTagOptions, id: \.self) { tag in
                            let active = selectedTags.contains(tag)
                            let full = selectedTags.count >= 3 && !active
                            Button {
                                if active {
                                    selectedTags.remove(tag)
                                } else if selectedTags.count < 3 {
                                    selectedTags.insert(tag)
                                }
                            } label: {
                                Text(tag)
                                    .font(.system(size: 13))
                                    .foregroundColor(active ? .white : (full ? AppTheme.tertiaryText : AppTheme.secondaryText))
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(Capsule().fill(active ? AppTheme.ink : (full ? AppTheme.soft.opacity(0.5) : Color.white)))
                                    .overlay(Capsule().stroke(active ? AppTheme.ink : AppTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(full)
                        }
                    }
                    .padding(.top, 8)

                    FieldLabel(text: "展示方式")
                        .padding(.top, 18)
                    SegmentedPicker(
                        options: [
                            SegmentOption(key: "nickname", label: "显示昵称"),
                            SegmentOption(key: "anonymous", label: "匿名"),
                        ],
                        selected: identity,
                        onSelect: { identity = $0 }
                    )
                    .padding(.top, 8)

                    FieldLabel(text: "评论区")
                        .padding(.top, 18)
                    SegmentedPicker(
                        options: [
                            SegmentOption(key: "public", label: "公开"),
                            SegmentOption(key: "hidden", label: "不公开"),
                            SegmentOption(key: "closed", label: "关闭"),
                        ],
                        selected: commentMode,
                        onSelect: { commentMode = $0 }
                    )
                    .padding(.top, 8)
                    if commentMode == "hidden" {
                        Text("只有你和评论者能看到评论")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding(.top, 8)
                    }

                    if let message = localError {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.danger)
                            .padding(.top, 14)
                    }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
            VStack(alignment: .leading, spacing: 8) {
                let canPublish = !scene.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !canPublish {
                    Text(scene.isEmpty ? "选择场景后即可发布" : "请输入标题")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.tertiaryText)
                }
                PrimaryButton(
                    title: "发布",
                    enabled: canPublish,
                    action: publish
                )
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 12)
            .background(AppTheme.background)
        }
        .appBackground()
    }

    private var whenOptions: [SegmentOption] {
        [
            SegmentOption(key: "", label: "不限"),
            SegmentOption(key: "now", label: "现在"),
            SegmentOption(key: "today", label: "今天"),
            SegmentOption(key: "week", label: "本周"),
            SegmentOption(key: "long", label: "长期"),
        ]
    }

    private func sceneOption(_ item: SceneMeta) -> some View {
        let active = scene == item.key
        return Button {
            scene = item.key
            localError = nil
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 21))
                    .foregroundColor(active ? AppTheme.accentDeep : AppTheme.secondaryText)
                Text(item.label)
                    .font(.system(size: 12))
                    .foregroundColor(active ? AppTheme.ink : AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? Color(hex: 0xFFF6DF) : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(active ? AppTheme.accent : AppTheme.line, lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func stepperButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(enabled ? AppTheme.ink : AppTheme.tertiaryText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppTheme.soft))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
                            // 视觉 20，点击区域 44；圆点仍贴在右上角内 5pt
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 7, y: -7)
                    .accessibilityLabel("移除")

                }
            }
            if uploads.count < limits.config.cardImageMax {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, limits.config.cardImageMax - uploads.count),
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
                    guard uploads.count < limits.config.cardImageMax else { break }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { continue }
                    uploads.append(PendingImage(image: image))
                }
                pickerItems = []
            }
        }
    }

    private func publish() {
        localError = nil
        guard !scene.isEmpty else {
            localError = "请选择一个场景"
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localError = "请输入标题"
            return
        }
        let request = CreateCardRequest(
            scene: scene,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            whenType: whenType,
            whenText: nil,
            placeName: place.trimmingCharacters(in: .whitespacesAndNewlines),
            headcount: headcount,
            tags: selectedTags.isEmpty ? nil : Array(selectedTags),
            identity: identity,
            commentMode: commentMode,
            reward: (scene == "errand" || scene == "car") ? Int(reward) : nil,
            payNote: (scene == "errand" || scene == "car") && !payNote.isEmpty ? payNote : nil,
            imageIds: nil
        )
        AppServices.shared.publisher.publish(
            request: request,
            images: uploads.map(\.image)
        )
        uploads = []
        onPublishing()
    }
}

@MainActor
struct SoftTextField: View {
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 15))
            .foregroundColor(AppTheme.ink)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.soft))
    }
}

@MainActor
private struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
    var mediaId: Int64?
    var status = 0
    var uploading = true
}
