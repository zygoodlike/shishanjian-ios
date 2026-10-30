import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ReportSheet: View {
    let targetType: String
    let targetId: Int64
    var onSubmitted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var limits = AppLimits.shared
    @State private var selected: String?
    @State private var detail = ""
    @State private var loading = false
    @State private var error: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploads: [ReportPendingImage] = []

    private let reasons = [
        "骚扰 / 言语冒犯",
        "广告推广 / 拉群",
        "虚假信息 / 疑似诈骗",
        "索要钱财 / 诱导转账",
        "跑腿报酬纠纷",
        "色情低俗",
        "人身安全威胁",
        "其他",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("举报")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                    Text("请选择举报原因")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            selected = reason
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .stroke(selected == reason ? AppTheme.accent : AppTheme.line, lineWidth: 1)
                                    .background(Circle().fill(selected == reason ? AppTheme.accent : Color.clear))
                                    .frame(width: 18, height: 18)
                                Text(reason)
                                    .font(.system(size: 15))
                                    .foregroundColor(AppTheme.ink)
                                Spacer()
                            }
                            .frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("上传凭证（必填，\(limits.config.reportImageMin)–\(limits.config.reportImageMax) 张）")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.top, 8)
                    reportUploadGrid
                        .padding(.top, 8)

                    TextEditor(text: $detail)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.ink)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 88)
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.soft))
                        .overlay(alignment: .topLeading) {
                            if detail.isEmpty {
                                Text("补充说明（选填，100 字）")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.tertiaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: detail) { _, value in
                            if value.count > 100 { detail = String(value.prefix(100)) }
                        }
                        .padding(.top, 8)

                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.danger)
                            .padding(.top, 10)
                    }

                    PrimaryButton(
                        title: "提交举报",
                        loading: loading,
                        enabled: selected != nil
                            && uploads.count >= limits.config.reportImageMin,
                        action: submit
                    )
                    .padding(.top, 16)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .presentationDetents([.medium, .large])
    }

    private var reportUploadGrid: some View {
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
            if uploads.count < limits.config.reportImageMax {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, limits.config.reportImageMax - uploads.count),
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
                    guard uploads.count < limits.config.reportImageMax else { break }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { continue }
                    uploads.append(ReportPendingImage(image: image, data: data))
                }
                pickerItems = []
            }
        }
    }

    private func submit() {
        guard let reason = selected else { return }
        guard uploads.count >= limits.config.reportImageMin else {
            error = "请上传举报凭证"
            return
        }
        loading = true
        error = nil
        Task {
            var imageIds: [Int64] = []
            do {
                for upload in uploads {
                    let media = try await AppServices.shared.repository.uploadImage(
                        upload.data,
                        purpose: "report"
                    )
                    imageIds.append(media.id)
                }
                _ = try await AppServices.shared.api.report(
                    CreateReportRequest(
                        targetType: targetType,
                        targetId: targetId,
                        reason: reason,
                        detail: detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail,
                        imageIds: imageIds
                    )
                )
                loading = false
                onSubmitted()
                dismiss()
            } catch {
                for id in imageIds {
                    try? await AppServices.shared.repository.deleteMedia(id: id)
                }
                loading = false
                self.error = error.localizedDescription
            }
        }
    }
}

@MainActor
private struct ReportPendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
}
