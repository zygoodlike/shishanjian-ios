import SwiftUI

@MainActor
struct GuestGateView: View {
    let title: String
    let subtitle: String
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 120)
            Image(systemName: "lock")
                .font(.system(size: 24))
                .foregroundColor(AppTheme.tertiaryText)
                .frame(width: 64, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.line))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppTheme.ink)
                .padding(.top, 18)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            PrimaryButton(title: "登录 / 注册", fillWidth: false, action: onLogin)
                .frame(width: 190)
                .padding(.top, 22)
            Text("先逛逛大厅也可以")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }
}
