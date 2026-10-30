import Photos
import SwiftUI
import UIKit

/// 图片九宫格：1 张单列，2–4 张两列，5–9 张三列。
@MainActor
struct ImageGrid: View {
    let images: [String]
    var compact = false
    var onTap: (Int) -> Void = { _ in }

    private var visible: [String] {
        Array(images.prefix(compact ? 3 : 9))
    }

    var body: some View {
        if !images.isEmpty {
            if compact {
                HStack(spacing: 4) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, url in
                        ZStack {
                            CachedImage(url: ApiConfig.absolute(url), maxPoint: 140)
                            if index == visible.count - 1, images.count > visible.count {
                                Color.black.opacity(0.45)
                                Text("+\(images.count - visible.count)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 104)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(index) }
                    }
                }
            } else if visible.count == 1 {
                CachedImage(url: ApiConfig.absolute(visible[0]), maxPoint: 420)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { onTap(0) }
            } else {
                let columns = visible.count == 2 ? 2 : 3
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, url in
                        ZStack(alignment: .center) {
                            Color(hex: 0xE8ECF3)
                            CachedImage(url: ApiConfig.absolute(url), maxPoint: 180)
                            if compact, index == visible.count - 1, images.count > visible.count {
                                Color.black.opacity(0.45)
                                Text("+\(images.count - visible.count)")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(index) }
                    }
                }
            }
        }
    }
}

/// 全屏图片预览，支持左右滑动、保存到相册。
@MainActor
struct ImageViewer: View {
    let images: [String]
    let initialIndex: Int
    let onClose: () -> Void

    @State private var index: Int
    @State private var message: String?
    @State private var showSaveConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(images: [String], initialIndex: Int, onClose: @escaping () -> Void) {
        self.images = images
        self.initialIndex = initialIndex
        self.onClose = onClose
        _index = State(initialValue: min(max(initialIndex, 0), max(images.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color(hex: 0x08090D).ignoresSafeArea().onTapGesture { showSaveConfirm = false }
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { item in
                    CachedImage(
                        url: ApiConfig.absolute(item.element),
                        maxPoint: 1400,
                        contentMode: .fit
                    ) {
                        ProgressView().tint(.white)
                    }
                    .onLongPressGesture { showSaveConfirm = true }
                    .tag(item.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: index) { _, _ in showSaveConfirm = false }

            VStack {
                HStack {
                    Button {
                        onClose()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(index + 1) / \(images.count)")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 12)
                Spacer()
            }

            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 90)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .confirmationDialog(
            "保存这张图片？",
            isPresented: $showSaveConfirm,
            titleVisibility: .visible
        ) {
            Button("保存到相册") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("保存后可能需要在系统相册中查看。")
        }
    }

    private func save() {
        guard images.indices.contains(index),
              let url = ApiConfig.absolute(images[index]) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { throw NSError(domain: "image", code: 0) }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                message = "已保存到相册"
            } catch {
                message = "保存失败"
            }
        }
    }
}
