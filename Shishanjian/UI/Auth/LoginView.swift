import SwiftUI
import UIKit

@MainActor
struct LoginView: View {
    let onGoRegister: () -> Void
    let onGoReset: () -> Void
    var onLoggedIn: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AuthViewModel()
    @State private var username = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var savedAccounts: [SavedAccount] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 56)
                LogoView(size: 92)
                Text("狮山见")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(AppTheme.ink)
                    .padding(.top, 18)
                Text("校内连接，从一条需求开始")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
                    .padding(.top, 8)
                Spacer().frame(height: 34)

                VStack(alignment: .leading, spacing: 0) {
                    if !savedAccounts.isEmpty {
                        Text("快捷登录")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.ink)
                        VStack(spacing: 6) {
                            ForEach(savedAccounts) { account in
                                savedAccountRow(account)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                    }
                    FieldLabel(text: "用户名")
                    AuthField(
                        text: $username,
                        placeholder: "请输入用户名",
                        keyboard: .default,
                        contentType: .username
                    )
                    .padding(.top, 8)
                    FieldLabel(text: "密码")
                        .padding(.top, 16)
                    AuthField(
                        text: $password,
                        placeholder: "请输入密码",
                        secure: true,
                        visible: $passwordVisible,
                        contentType: .password
                    )
                    .padding(.top, 8)
                    if let error = vm.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.danger)
                            .padding(.top, 12)
                    }
                    PrimaryButton(title: "登录", loading: vm.loading) {
                        Task {
                            if await vm.login(username: username, password: password) {
                                onLoggedIn()
                                dismiss()
                            }
                        }
                    }
                    .padding(.top, 22)
                    HStack(spacing: 0) {
                        Button(action: onGoReset) {
                            Text("忘记密码？")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.tertiaryText)
                                .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        Button(action: onGoRegister) {
                            Text("还没有账号？注册")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.accentDeep)
                                .frame(height: 44)
                                .padding(.leading, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AppTheme.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.line, lineWidth: 1)
                )
                .padding(.horizontal, 24)

                Text("仅限 @webmail.hzau.edu.cn 校内邮箱注册")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.tertiaryText)
                    .padding(.top, 20)
                Spacer().frame(height: 32)
            }
        }
        .appBackground()
        .onAppear {
            savedAccounts = AppServices.shared.auth.savedAccounts()
        }
    }

    private func savedAccountRow(_ account: SavedAccount) -> some View {
        HStack(spacing: 10) {
            Button {
                username = account.username
                password = account.password
                Task {
                    if await vm.login(username: account.username, password: account.password) {
                        onLoggedIn()
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    AvatarBlock(
                        userId: 0,
                        name: account.nickname ?? account.username,
                        imageURL: account.avatar,
                        size: 34
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.nickname?.isEmpty == false ? account.nickname! : account.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.ink)
                        Text("@\(account.username)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                AppServices.shared.auth.removeSavedAccount(username: account.username)
                savedAccounts = AppServices.shared.auth.savedAccounts()
            } label: {
                Text("移除")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.tertiaryText)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
struct AuthField: View {
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false
    var visible: Binding<Bool>? = nil
    var contentType: UITextContentType? = nil
    var suffix: String? = nil
    var disabled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if secure && !(visible?.wrappedValue ?? false) {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(.system(size: 15))
            .foregroundColor(AppTheme.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(contentType)
            .disabled(disabled)

            if let suffix {
                Text(suffix)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            if secure, let visible {
                Button {
                    visible.wrappedValue.toggle()
                } label: {
                    Image(systemName: visible.wrappedValue ? "eye.slash" : "eye")
                        .foregroundColor(AppTheme.tertiaryText)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.soft))
    }
}
