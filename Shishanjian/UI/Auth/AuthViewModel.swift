import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var loading = false
    @Published var error: String?
    @Published var devCode: String?
    @Published var countdown = 0

    private let repository = AppServices.shared.repository
    private let auth = AppServices.shared.auth
    private var countdownTask: Task<Void, Never>?

    func login(username: String, password: String) async -> Bool {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            error = "请输入用户名和密码"
            return false
        }
        loading = true
        error = nil
        do {
            let response = try await repository.login(username: username, password: password)
            auth.save(response, justRegistered: false, username: username, password: password)
            loading = false
            return true
        } catch {
            loading = false
            self.error = error.localizedDescription
            return false
        }
    }

    func sendCode(email: String, ticket: String) {
        sendCode(email: email, ticket: ticket, purpose: "register")
    }

    func sendResetCode(email: String, ticket: String) {
        sendCode(email: email, ticket: ticket, purpose: "reset_password")
    }

    private func sendCode(email: String, ticket: String, purpose: String) {
        guard !email.isEmpty else {
            error = "请输入学校邮箱"
            return
        }
        loading = true
        error = nil
        Task {
            do {
                let response = try await AppServices.shared.api.emailCode(
                    EmailCodeRequest(email: email, purpose: purpose, ticket: ticket)
                )
                loading = false
                devCode = response.devCode
                startCountdown()
            } catch {
                loading = false
                self.error = error.localizedDescription
            }
        }
    }

    func resetPassword(email: String, code: String, password: String, confirm: String) async -> Bool {
        let text = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { error = "请输入学校邮箱"; return false }
        if code.range(of: "^\\d{6}$", options: .regularExpression) == nil {
            error = "验证码为 6 位数字"
            return false
        }
        if password.range(of: "^(?=.*[A-Za-z])(?=.*\\d).{8,32}$", options: .regularExpression) == nil {
            error = "密码需为 8–32 位，且包含字母和数字"
            return false
        }
        if password != confirm {
            error = "两次输入的密码不一致"
            return false
        }
        loading = true
        error = nil
        do {
            try await AppServices.shared.api.resetPassword(
                ResetPasswordRequest(email: text, code: code, password: password)
            )
            loading = false
            return true
        } catch {
            loading = false
            self.error = error.localizedDescription
            return false
        }
    }

    func register(
        username: String,
        password: String,
        email: String,
        code: String,
        nickname: String
    ) async -> Bool {
        guard !username.isEmpty, !password.isEmpty, !email.isEmpty, !code.isEmpty else {
            error = "请完整填写注册信息"
            return false
        }
        loading = true
        error = nil
        do {
            let response = try await repository.register(
                username: username,
                password: password,
                email: email,
                code: code,
                nickname: nickname.isEmpty ? username : nickname
            )
            auth.save(
                response,
                justRegistered: true,
                username: username,
                password: password
            )
            loading = false
            return true
        } catch {
            loading = false
            self.error = error.localizedDescription
            return false
        }
    }

    func clearError() {
        error = nil
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task {
            while !Task.isCancelled && countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }
}
