import Foundation
import Observation

@Observable
@MainActor
final class PasswordResetViewModel {
    private let authService: AuthService

    // Input
    var email = ""
    var code = ""
    var newPassword = ""
    var confirmPassword = ""

    // Flow state
    private(set) var isCodeSent = false
    private(set) var countdown = 0
    private let verificationTimer = VerificationCodeTimer()

    // Loading
    private(set) var isSendingCode = false
    private(set) var isResetting = false

    // Outcome
    var errorMessage: String?
    var successMessage: String?
    var resetSuccess = false

    init(authService: AuthService) {
        self.authService = authService
    }

    var isStepOneEnabled: Bool {
        !self.email.isEmpty && !self.isSendingCode
    }

    var isStepTwoEnabled: Bool {
        !self.code.isEmpty
            && !self.newPassword.isEmpty
            && !self.confirmPassword.isEmpty
            && !self.isResetting
    }

    var canResendCode: Bool {
        self.countdown == 0 && !self.isSendingCode
    }

    var maskedEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return trimmed }

        let name = String(parts[0])
        let domain = String(parts[1])
        if name.count <= 2 {
            return "\(name.prefix(1))***@\(domain)"
        }
        return "\(name.prefix(2))***@\(domain)"
    }

    var passwordValidationError: String? {
        AccountValidation.passwordValidationError(for: newPassword)
    }

    var confirmValidationError: String? {
        AccountValidation.confirmPasswordError(password: newPassword, confirm: confirmPassword)
    }

    func sendCode() async {
        self.errorMessage = nil
        self.successMessage = nil

        let trimmedEmail = self.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AccountValidation.isValidEmail(trimmedEmail) else {
            self.errorMessage = "请输入正确的邮箱地址"
            return
        }

        guard !self.isSendingCode else { return }
        self.isSendingCode = true
        defer { self.isSendingCode = false }

        do {
            let response = try await authService.sendPasswordResetEmailCode(email: trimmedEmail)
            self.isCodeSent = true
            self.email = trimmedEmail
            self.successMessage = "验证码已发送，请在 5 分钟内完成重置。"
            startCountdown(seconds: response.retryAfterSeconds)
        } catch {
            self.errorMessage = friendlySendCodeError(error.localizedDescription)
        }
    }

    func resetPassword() async {
        self.errorMessage = nil
        self.successMessage = nil

        guard self.passwordValidationError == nil else {
            self.errorMessage = "请检查新密码格式"
            return
        }
        guard self.confirmPassword == self.newPassword else {
            self.errorMessage = "两次输入的密码不一致"
            return
        }

        guard !self.isResetting else { return }
        self.isResetting = true
        defer { self.isResetting = false }

        let trimmedEmail = self.email.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await authService.resetPassword(
                email: trimmedEmail,
                code: self.code.trimmingCharacters(in: .whitespacesAndNewlines),
                newPassword: self.newPassword
            )
            self.resetSuccess = true
            self.successMessage = "密码已重置，请使用新密码登录。"
        } catch {
            self.errorMessage = friendlyResetError(error.localizedDescription)
        }
    }

    func resetForm() {
        self.email = ""
        self.code = ""
        self.newPassword = ""
        self.confirmPassword = ""
        self.isCodeSent = false
        self.errorMessage = nil
        self.successMessage = nil
        self.resetSuccess = false
        self.invalidateTimer()
    }

    func invalidateTimer() {
        verificationTimer.invalidate()
        countdown = 0
    }

    // MARK: - Private

    private func startCountdown(seconds: Int) {
        verificationTimer.start(seconds: seconds) { [weak self] value in
            self?.countdown = value
        }
    }

    private func friendlySendCodeError(_ message: String) -> String {
        if message.contains("频繁") || message.contains("429") {
            return "发送过于频繁，请稍后再试。"
        }
        if message.contains("网络") || message.contains("连接") || message.contains("超时") {
            return "网络连接不稳定，请稍后重试。"
        }
        return message.isEmpty ? "验证码发送失败，请稍后重试。" : "验证码发送失败，请稍后重试。"
    }

    private func friendlyResetError(_ message: String) -> String {
        if message.contains("验证码") || message.contains("40001") {
            return "验证码错误或已过期，请重新确认后再试。"
        }
        if message.contains("格式") || message.contains("40002") {
            return "邮箱、验证码或新密码格式不正确，请检查后再试。"
        }
        if message.contains("网络") || message.contains("连接") || message.contains("超时") {
            return "网络连接不稳定，请稍后重试。"
        }
        return message.isEmpty ? "重置失败，请稍后重试。" : "重置失败，请稍后重试。"
    }
}
