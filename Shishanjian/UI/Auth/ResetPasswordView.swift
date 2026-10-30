import SwiftUI

@MainActor
struct ResetPasswordView: View {
    let onBack: () -> Void
    let onReset: () -> Void

    @StateObject private var vm = AuthViewModel()
    @State private var emailPrefix = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var captchaOpen = false

    private var fullEmail: String {
        let prefix = emailPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? "" : "\(prefix)@webmail.hzau.edu.cn"
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("重置密码", onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("用注册时的学校邮箱验证身份")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.tertiaryText)
                        .padding(.top, 10)

                    FieldLabel(text: "学校邮箱前缀", required: true)
                        .padding(.top, 22)
                    AuthField(
                        text: $emailPrefix,
                        placeholder: "例如 zygoodlike",
                        keyboard: .default,
                        contentType: .username
                    )
                    .padding(.top, 8)
                    Text("@webmail.hzau.edu.cn")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.tertiaryText)
                        .padding(.top, 5)
                    if !fullEmail.isEmpty {
                        Text("将验证：\(fullEmail)")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accentDeep)
                            .padding(.top, 6)
                    }
                    SecondaryButton(
                        title: vm.countdown > 0 ? "\(vm.countdown)s 后重发" : "发送验证码",
                        enabled: vm.countdown == 0 && !vm.loading && !fullEmail.isEmpty
                    ) {
                        captchaOpen = true
                    }
                    .padding(.top, 12)

                    FieldLabel(text: "验证码", required: true)
                        .padding(.top, 18)
                    AuthField(
                        text: $code,
                        placeholder: "6 位验证码",
                        keyboard: .numberPad,
                        contentType: .oneTimeCode
                    )
                    .padding(.top, 8)
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                    }

                    FieldLabel(text: "新密码", required: true)
                        .padding(.top, 18)
                    AuthField(
                        text: $password,
                        placeholder: "8–32 位，包含字母和数字",
                        secure: true,
                        contentType: .newPassword
                    )
                    .padding(.top, 8)

                    FieldLabel(text: "确认新密码", required: true)
                        .padding(.top, 18)
                    AuthField(
                        text: $confirm,
                        placeholder: "再次输入新密码",
                        secure: true,
                        contentType: .newPassword
                    )
                    .padding(.top, 8)

                    if let devCode = vm.devCode {
                        Text("开发环境验证码：\(devCode)")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.tertiaryText)
                            .padding(.top, 10)
                    }
                    if let error = vm.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.danger)
                            .padding(.top, 12)
                    }

                    PrimaryButton(
                        title: "重置密码",
                        loading: vm.loading,
                        enabled: !fullEmail.isEmpty && code.count == 6 && !password.isEmpty
                    ) {
                        Task {
                            if await vm.resetPassword(
                                email: fullEmail,
                                code: code,
                                password: password,
                                confirm: confirm
                            ) {
                                onReset()
                            }
                        }
                    }
                    .padding(.top, 28)
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .appBackground()
        .sheet(isPresented: $captchaOpen) {
            CaptchaSheet(purpose: "reset_password") { ticket in
                captchaOpen = false
                vm.sendResetCode(email: fullEmail, ticket: ticket)
            }
        }
    }
}
