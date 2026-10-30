import ImageIO
import SwiftUI
import UIKit

/// 图片下载 + 按显示尺寸解码 + 内存缓存。
///
/// 下载走 URLSession.shared，`/media/**` 的长缓存头让 URLCache 直接命中磁盘；
/// 解码用 ImageIO 缩略图，头像和列表缩略图不会按原图分辨率占内存。
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cached(_ url: URL, maxPixel: Int) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    func load(_ url: URL, maxPixel: Int) async -> UIImage? {
        let cacheKey = key(url, maxPixel)
        if let hit = cache.object(forKey: cacheKey) { return hit }
        // 非隔离的 async 方法在全局并发执行器上运行，下载完成后的解码不在主线程
        guard let result = try? await URLSession.shared.data(from: url) else { return nil }
        let image = ImageLoader.downsample(result.0, maxPixel: maxPixel)
        if let image {
            let pixels = (image.cgImage?.width ?? 0) * (image.cgImage?.height ?? 0)
            cache.setObject(image, forKey: cacheKey, cost: pixels * 4)
        }
        return image
    }

    private func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(maxPixel)|\(url.absoluteString)" as NSString
    }

    private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// 替代 AsyncImage：按 `maxPoint` × 屏幕倍率解码。
@MainActor
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    let maxPoint: CGFloat
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(
        url: URL?,
        maxPoint: CGFloat = 200,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPoint = maxPoint
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    private var maxPixel: Int { Int((maxPoint * max(displayScale, 1)).rounded(.up)) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = ImageLoader.shared.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            let loaded = await ImageLoader.shared.load(url, maxPixel: maxPixel)
            if !Task.isCancelled { image = loaded }
        }
    }
}

extension CachedImage where Placeholder == Color {
    init(url: URL?, maxPoint: CGFloat = 200, contentMode: ContentMode = .fill) {
        self.init(url: url, maxPoint: maxPoint, contentMode: contentMode) {
            Color(hex: 0xE8ECF3)
        }
    }
}

/// 静态骨架块：浅灰圆角，不做循环闪光动画。
@MainActor
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = 6

    var body: some View {
        if let width {
            shape.frame(width: width, height: height)
        } else {
            shape.frame(maxWidth: .infinity).frame(height: height)
        }
    }

    private var shape: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(hex: 0xEEF1F6))
    }
}

/// 列表骨架：与真实条目同尺寸的白卡片 + 灰条。
@MainActor
struct SkeletonList: View {
    var rows: Int = 3
    var rowHeight: CGFloat = 96
    var showAvatar: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    if showAvatar {
                        Circle()
                            .fill(Color(hex: 0xEEF1F6))
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(width: 120, height: 14)
                        SkeletonBlock(height: 12)
                        SkeletonBlock(width: 180, height: 12)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .topLeading)
                .cardSurface()
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 需求详情骨架：标题条 + 两行正文 + 发布者行。
@MainActor
struct SkeletonDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: 64, height: 22, radius: 11)
            SkeletonBlock(width: 220, height: 22)
            SkeletonBlock(height: 13)
            SkeletonBlock(width: 240, height: 13)
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xEEF1F6)).frame(width: 28, height: 28)
                SkeletonBlock(width: 90, height: 13)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 私聊骨架：左右交错的气泡占位。
@MainActor
struct SkeletonChat: View {
    var body: some View {
        VStack(spacing: 14) {
            bubble(leading: true, width: 180)
            bubble(leading: false, width: 140)
            bubble(leading: true, width: 220)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 16)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bubble(leading: Bool, width: CGFloat) -> some View {
        HStack {
            if !leading { Spacer() }
            SkeletonBlock(width: width, height: 40, radius: 18)
            if leading { Spacer() }
        }
    }
}
