import SwiftUI

enum AppTheme {
    static let background = Color(hex: 0xF3F5FA)
    static let surface = Color.white
    static let soft = Color(hex: 0xF0F3F8)
    static let ink = Color(hex: 0x141824)
    static let secondaryText = Color(hex: 0x64708A)
    static let tertiaryText = Color(hex: 0x98A2B3)
    static let accent = Color(hex: 0x4C8DFF)
    static let accentDeep = Color(hex: 0x2F6BFF)
    static let accentSoft = Color(hex: 0xEAF1FF)
    static let trustGreen = Color(hex: 0x12B76A)
    static let trustSurface = Color(hex: 0xEAF5EF)
    static let danger = Color(hex: 0xF04438)
    static let dangerSurface = Color(hex: 0xFDECEC)
    static let line = Color(hex: 0xE8ECF3)
    static let warningSurface = Color(hex: 0xFFF8E6)

    static let pagePadding: CGFloat = 18
    static let cardRadius: CGFloat = 20
    static let fieldRadius: CGFloat = 14
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension View {
    func appBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }

    func cardSurface() -> some View {
        background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.line.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}
