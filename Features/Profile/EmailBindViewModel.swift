import Foundation
import Observation

@Observable
@MainActor
final class EmailBindViewModel {
    private let profileService: ProfileService

    var email = ""
    var code = ""
    var password = ""
    var confirmPassword = ""

    private(set) var isCodeSent = false
    private(set) var countdown = 0
    private let verificationTimer = VerificationCodeTimer()
    private(set) var isSendingCode = false
    private(set) var isBinding = false
    private(set) var bindSuccess = false
    var errorMessage: String?

    init(profileService: ProfileService) {
        self.profileService = profileService
    }

    var isStepOneEnabled: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingCode
    }

    var isStepTwoEnabled: Bool {
        code.count == 6
            && !password.isEmpty
            && !confirmPassword.isEmpty
            && passwordValidationError == nil
            && confirmValidationError == nil
            && !isBinding
    }

    var canResendCode: Bool {
        countdown == 0 && !isSendingCode
    }

    var passwordValidationError: String? {
        AccountValidation.passwordValidationError(for: password)
    }

    var confirmValidationError: String? {
        AccountValidation.confirmPasswordError(password: password, confirm: confirmPassword)
    }

    func backToEmailEntry() {
        code = ""
        password = ""
        confirmPassword = ""
        isCodeSent = false
        errorMessage = nil
        invalidateTimer()
    }

    func sendCode() async {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AccountValidation.isValidEmail(trimmedEmail) else {
            errorMessage = "请输入正确的邮箱地址"
            return
        }
        guard !isSendingCode else { return }
        isSendingCode = true
        defer { isSendingCode = false }

        do {
            let response = try await profileService.sendEmailBindCode(email: trimmedEmail)
            email = trimmedEmail
            isCodeSent = true
            AppHaptics.lightImpact()
            startCountdown(seconds: response.retryAfterSeconds)
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
        }
    }

    func confirmBind() async {
        errorMessage = nil
        guard passwordValidationError == nil else {
            errorMessage = "请检查密码格式"
            return
        }
        guard confirmValidationError == nil else {
            errorMessage = "两次输入的密码不一致"
            return
        }
        guard !isBinding else { return }
        isBinding = true
        defer { isBinding = false }

        do {
            try await profileService.confirmEmailBind(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                code: code,
                password: password
            )
            bindSuccess = true
            AppHaptics.success()
        } catch {
            errorMessage = "绑定失败：\(error.localizedDescription)"
        }
    }

    func invalidateTimer() {
        verificationTimer.invalidate()
        countdown = 0
    }

    func sanitizeCode(_ value: String) {
        code = String(value.filter(\.isNumber).prefix(6))
    }

    /*
     FUTURE（待产品确认）：邮箱换绑状态与动作。
     原有 beginReplace / replace success 分支暂不作为可执行代码恢复；
     待明确原邮箱或当前密码校验、会话撤销及独立 API 后再接入。
     */

    private func startCountdown(seconds: Int) {
        verificationTimer.start(seconds: seconds) { [weak self] value in
            self?.countdown = value
        }
    }
}
