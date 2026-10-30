import SwiftUI

@MainActor
struct AppNoticeBanner: View {
    @ObservedObject private var center = AppNoticeCenter.shared

    var body: some View {
        Group {
            if let notice = center.notice {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent(notice.kind))
                        .frame(width: 4, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        if let title = notice.title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.72))
                        }
                        Text(notice.message)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .lineSpacing(3)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Text("×")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(background(notice.kind), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .contentShape(Rectangle())
                .onTapGesture { center.dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.notice)
    }

    private func accent(_ kind: AppNoticeKind) -> Color {
        switch kind {
        case .error: return Color(hex: 0xFF6B6B)
        case .message: return Color(hex: 0x69B7FF)
        case .info: return Color(hex: 0xE0B84C)
        }
    }

    private func background(_ kind: AppNoticeKind) -> Color {
        switch kind {
        case .error: return Color(hex: 0x351C21)
        case .message: return Color(hex: 0x16202B)
        case .info: return Color(hex: 0x20232B)
        }
    }
}
