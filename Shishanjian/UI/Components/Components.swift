import SwiftUI

@MainActor
struct LogoView: View {
    var size: CGFloat = 92

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

struct AppTopBar<Trailing: View>: View {
    let title: String
    let onBack: (() -> Void)?
    let trailing: Trailing

    init(_ title: String, onBack: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 12)
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
    }
}

extension AppTopBar where Trailing == EmptyView {
    init(_ title: String, onBack: (() -> Void)? = nil) {
        self.init(title, onBack: onBack) { EmptyView() }
    }
}

@MainActor
struct PrimaryButton: View {
    let title: String
    var loading: Bool = false
    var enabled: Bool = true
    var fillWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(.white)
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .frame(height: 48)
            .padding(.horizontal, fillWidth ? 0 : 20)
            .background(Capsule().fill(AppTheme.accentDeep.opacity(enabled && !loading ? 1 : 0.35)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || loading)
    }
}

@MainActor
struct SecondaryButton: View {
    let title: String
    var enabled: Bool = true
    var fillWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(enabled ? AppTheme.accentDeep : AppTheme.tertiaryText)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .frame(height: 40)
                .padding(.horizontal, fillWidth ? 0 : 16)
                .background(Capsule().fill(AppTheme.accentSoft.opacity(enabled ? 1 : 0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

@MainActor
struct SceneChip: View {
    let scene: String?

    var body: some View {
        let meta = sceneMeta(scene)
        Text(meta.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(hex: meta.color))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(hex: meta.light)))
    }
}

@MainActor
struct FilterPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : AppTheme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(selected ? AppTheme.accentDeep : AppTheme.surface))
                .overlay(Capsule().stroke(selected ? AppTheme.accentDeep : AppTheme.line, lineWidth: 1))
                // 视觉高 32，点击区域上下扩到 44
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(AppTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(AppTheme.soft))
    }
}

@MainActor
struct AvatarBlock: View {
    let userId: Int64
    let name: String?
    var imageURL: String? = nil
    var size: CGFloat = 40
    var anonymous: Bool = false

    @StateObject private var observer: ProfileObserver

    init(
        userId: Int64,
        name: String?,
        imageURL: String? = nil,
        size: CGFloat = 40,
        anonymous: Bool = false
    ) {
        self.userId = userId
        self.name = name
        self.imageURL = imageURL
        self.size = size
        self.anonymous = anonymous
        _observer = StateObject(wrappedValue: ProfileObserver(userId: userId))
    }

    private var cached: CachedProfile? { observer.profile }
    private var effectiveName: String? { cached != nil ? cached?.nickname : name }
    private var effectiveImage: String? { cached != nil ? cached?.avatar : imageURL }

    private var palette: [Color] {
        [
            Color(hex: 0xDCE8F7), Color(hex: 0xDFEFE2), Color(hex: 0xF8E8D5),
            Color(hex: 0xE7E0F5), Color(hex: 0xF3E2E2), Color(hex: 0xE2EEEC),
        ]
    }

    private var backgroundColor: Color {
        if anonymous { return AppTheme.soft }
        let index = Int(abs(userId)) % palette.count
        return palette[index]
    }

    private var displayName: String {
        let value = (effectiveName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "友" : String(value.prefix(1))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            if let effectiveImage, let url = ApiConfig.absolute(effectiveImage) {
                CachedImage(url: url, maxPoint: size) {
                    avatarText
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                avatarText
            }
        }
        .frame(width: size, height: size)
        .onChange(of: userId) { _, value in
            observer.rebind(value)
        }
    }

    private var avatarText: some View {
        Text(anonymous ? "匿" : displayName)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundColor(anonymous ? AppTheme.tertiaryText : AppTheme.ink)
    }
}

@MainActor
struct NeedCardView: View {
    let card: Card
    let onTap: () -> Void
    var onOpenUser: (Int64) -> Void = { _ in }

    private var timeText: String {
        let text = (card.whenText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? AppFormatters.whenLabel(card.whenType) : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SceneChip(scene: card.scene)
                if !timeText.isEmpty {
                    Text(timeText).font(.system(size: 13)).foregroundColor(AppTheme.secondaryText)
                }
                Spacer()
                if card.status != 1 {
                    Text(AppFormatters.cardStatusLabel(card.status, fallback: card.statusLabel))
                        .font(.system(size: 12))
                        .foregroundColor(card.status == 5 ? AppTheme.danger : AppTheme.accentDeep)
                }
            }
            Text(card.title ?? "")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.ink)
                .lineLimit(1)
                .padding(.top, 6)
            Text(metaText)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .lineLimit(1)
                .padding(.top, 4)
            if let images = card.images, !images.isEmpty {
                ImageGrid(images: images, compact: true)
                    .padding(.top, 8)
            }
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    if card.identity != "anonymous" {
                        AvatarBlock(
                            userId: card.authorId ?? card.id,
                            name: card.authorName,
                            imageURL: card.authorAvatar,
                            size: 24
                        )
                    }
                    Text(card.identity == "anonymous" ? "匿名" : (card.authorName ?? ""))
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    if card.identity != "anonymous", let id = card.authorId { onOpenUser(id) }
                }
                if let tags = card.tags, !tags.isEmpty {
                    let tagText = tags.prefix(2).map { "#\($0)" }.joined(separator: " ")
                    Text(tagText)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text("评论 \(card.commentCount)")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.tertiaryText)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .cardSurface()
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private var metaText: String {
        var parts: [String] = []
        if let place = card.placeName, !place.isEmpty { parts.append(place) }
        parts.append("\(card.acceptedCount)/\(card.headcount) 人")
        let relative = AppFormatters.relativeTime(card.createdAt)
        if !relative.isEmpty { parts.append(relative) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
struct FieldLabel: View {
    let text: String
    var required: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.ink)
            if required {
                Text("*").font(.system(size: 13)).foregroundColor(AppTheme.danger)
            }
        }
    }
}

@MainActor
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(AppTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct EmptyStateView: View {
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "ellipsis")
                .font(.system(size: 24))
                .foregroundColor(AppTheme.tertiaryText)
                .frame(width: 64, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.line))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, fillWidth: false, action: action)
                    .frame(width: 160)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 48)
    }
}

@MainActor
struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            SecondaryButton(title: "重试", action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.pagePadding)
    }
}

@MainActor
struct StatusBanner: View {
    let text: String
    var danger: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(danger ? AppTheme.danger : AppTheme.accentDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(danger ? AppTheme.dangerSurface : AppTheme.warningSurface)
            )
    }
}

struct SegmentOption: Identifiable, Hashable {
    let key: String
    let label: String
    var id: String { key }
}

@MainActor
struct SegmentedPicker: View {
    let options: [SegmentOption]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let active = option.key == selected
                Button {
                    onSelect(option.key)
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: active ? .semibold : .regular))
                        .foregroundColor(active ? AppTheme.ink : AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(active ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.soft))
    }
}

/// 只订阅单个用户资料的昵称文本，别人改资料不触发重绘。
@MainActor
struct ProfileNameText: View {
    let userId: Int64
    let fallback: String

    @StateObject private var observer: ProfileObserver

    init(userId: Int64, fallback: String) {
        self.userId = userId
        self.fallback = fallback
        _observer = StateObject(wrappedValue: ProfileObserver(userId: userId))
    }

    var body: some View {
        Text(observer.profile?.nickname ?? fallback)
            .font(.system(size: 22, weight: .heavy))
            .foregroundColor(AppTheme.ink)
            .onChange(of: userId) { _, value in
                observer.rebind(value)
            }
    }
}

/// 缩略图右上角的删除按钮：视觉是小圆点，点击区域 44×44。
///
/// 放在 `ZStack(alignment: .topTrailing)` 里，圆点中心落在缩略图右上角外 4pt 处。
@MainActor
struct RemoveBadge: View {
    var dotSize: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: dotSize * 0.45, weight: .bold))
                .foregroundColor(.white)
                .frame(width: dotSize, height: dotSize)
                .background(Color.black.opacity(0.65), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 22 - dotSize / 2 + 4, y: -(22 - dotSize / 2 + 4))
        .accessibilityLabel("移除")
    }
}

@MainActor
struct RefreshButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 17))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}
