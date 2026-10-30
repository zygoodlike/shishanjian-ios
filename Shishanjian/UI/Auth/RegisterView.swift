import SwiftUI
import UIKit

@MainActor
struct RegisterView: View {
    let onGoLogin: () -> Void
    let onRegistered: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AuthViewModel()
    @State private var step = 1
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordVisible = false
    @State private var confirmVisible = false
    @State private var emailPrefix = ""
    @State private var code = ""
    @State private var captchaOpen = false
    @State private var localError: String?

    private var fullEmail: String {
        emailPrefix.isEmpty ? "" : "\(emailPrefix.trimmingCharacters(in: .whitespaces))@webmail.hzau.edu.cn"
    }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar("注册", onBack: {
                if step == 2 { step = 1 } else { dismiss() }
            })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(step)/2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.accentDeep)
                    Text(step == 1 ? "设置账号" : "绑定学校邮箱")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(AppTheme.ink)
                        .padding(.top, 8)
                    Spacer().frame(height: 24)

                    if step == 1 {
                        accountStep
                    } else {
                        emailStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .appBackground()
        .sheet(isPresented: $captchaOpen) {
            CaptchaSheet(purpose: "register") { ticket in
                captchaOpen = false
                vm.sendCode(email: fullEmail, ticket: ticket)
            }
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(text: "用户名", required: true)
            AuthField(text: $username, placeholder: "4–20 位字母、数字或下划线")
                .padding(.top, 8)
            FieldLabel(text: "密码", required: true)
                .padding(.top, 18)
            AuthField(
                text: $password,
                placeholder: "8–32 位，字母加数字",
                secure: true,
                visible: $passwordVisible,
                contentType: .newPassword
            )
            .padding(.top, 8)
            FieldLabel(text: "确认密码", required: true)
                .padding(.top, 18)
            AuthField(
                text: $confirmPassword,
                placeholder: "再次输入密码",
                secure: true,
                visible: $confirmVisible,
                contentType: .newPassword
            )
            .padding(.top, 8)
            if let localError {
                Text(localError)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.danger)
                    .padding(.top, 12)
            }
            PrimaryButton(title: "下一步", action: nextStep)
                .padding(.top, 28)
            Button(action: onGoLogin) {
                Text("已有账号？登录")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accentDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(text: "学校邮箱前缀", required: true)
            AuthField(
                text: Binding(
                    get: { emailPrefix },
                    set: { value in
                        emailPrefix = String(value.filter { $0.isLetter || $0.isNumber || "._-".contains($0) }.prefix(64))
                        localError = nil
                    }
                ),
                placeholder: "例如 zygoodlike",
                suffix: "@webmail.hzau.edu.cn"
            )
            .padding(.top, 8)
            if !fullEmail.isEmpty {
                Text("将绑定：\(fullEmail)")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accentDeep)
                    .padding(.top, 6)
            }
            Link(destination: URL(string: "https://webmail.hzau.edu.cn/")!) {
                Text("还没有学校邮箱？先到 webmail.hzau.edu.cn 注册，验证码会发到这个邮箱。")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accentDeep)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
            }
            SecondaryButton(
                title: vm.countdown > 0 ? "\(vm.countdown)s 后重发" : "发送验证码",
                enabled: vm.countdown == 0 && !vm.loading && !fullEmail.isEmpty,
                fillWidth: true
            ) {
                captchaOpen = true
            }
            .padding(.top, 10)

            FieldLabel(text: "验证码", required: true)
                .padding(.top, 18)
            AuthField(
                text: Binding(
                    get: { code },
                    set: { code = String($0.filter { $0.isNumber }.prefix(6)) }
                ),
                placeholder: "6 位验证码",
                keyboard: .numberPad
            )
            .padding(.top, 8)
            if let devCode = vm.devCode {
                Text("开发环境验证码：\(devCode)")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.tertiaryText)
                    .padding(.top, 8)
            }
            if let error = localError ?? vm.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.danger)
                    .padding(.top, 12)
            }
            PrimaryButton(
                title: "完成注册",
                loading: vm.loading,
                enabled: !fullEmail.isEmpty && code.count == 6,
                action: register
            )
            .padding(.top, 28)
            Text("仅支持 @webmail.hzau.edu.cn")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.tertiaryText)
                .padding(.top, 12)
        }
    }

    private func nextStep() {
        let nameValid = username.range(of: "^[A-Za-z0-9_]{4,20}$", options: .regularExpression) != nil
        let passwordValid = password.range(of: "^(?=.*[A-Za-z])(?=.*\\d).{8,32}$", options: .regularExpression) != nil
        if !nameValid {
            localError = "用户名为 4–20 位字母、数字或下划线"
            return
        }
        if !passwordValid {
            localError = "密码需为 8–32 位，且包含字母和数字"
            return
        }
        if password != confirmPassword {
            localError = "两次输入的密码不一致"
            return
        }
        localError = nil
        step = 2
    }

    private func register() {
        Task {
            let success = await vm.register(
                username: username,
                password: password,
                email: fullEmail,
                code: code,
                nickname: username
            )
            if success { onRegistered() }
        }
    }
}
