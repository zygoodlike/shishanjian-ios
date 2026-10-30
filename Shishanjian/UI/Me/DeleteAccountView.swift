import SwiftUI

@MainActor
struct DeleteAccountView: View {
    let onBack: () -> Void

    @StateObject private var vm = DevicesViewModel()
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var confirmText = ""

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("注销账号", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("注销后：")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                    ForEach(["所有需求立即下架", "所有会话立即关闭", "15 天后删除个人信息", "30 天内不能重新注册"], id: \.self) { line in
                        Text("· \(line)")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding(.vertical, 4)
                    }
                    .padding(.top, 10)

                    FieldLabel(text: "输入「注销」确认", required: true)
                        .padding(.top, 24)
                    AuthField(text: $confirmText, placeholder: "注销")
                        .padding(.top, 8)
                        .onChange(of: confirmText) { _, value in
                            if value.count > 2 { confirmText = String(value.prefix(2)) }
                        }
                    FieldLabel(text: "当前密码", required: true)
                        .padding(.top, 16)
                    AuthField(text: $password, placeholder: "请输入密码", secure: true, visible: $passwordVisible)
                        .padding(.top, 8)
                    if let error = vm.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.danger)
                            .padding(.top, 10)
                    }
                    PrimaryButton(
                        title: "注销账号",
                        enabled: confirmText == "注销" && !password.isEmpty
                    ) {
                        Task { _ = await vm.deleteAccount(password: password) }
                    }
                    .padding(.top, 24)
                    Text("注销后无法恢复，请确认已备份需要保留的信息。")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.tertiaryText)
                        .padding(.top, 10)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .appBackground()
    }
}
