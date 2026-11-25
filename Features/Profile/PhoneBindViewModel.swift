import Foundation
import Observation

enum AccountBindSuccessKind: Equatable {
    case bound
    case replaced
    case unbound
}

@Observable
@MainActor
final class PhoneBindViewModel {
    private let profileService: ProfileService

    /// 国内 11 位手机号，不含区号。
    var nationalNumber = ""
    var code = ""

    private(set) var isCodeSent = false
    private(set) var isReplacing = false
    private(set) var countdown = 0
    private let verificationTimer = VerificationCodeTimer()

    private(set) var isSendingCode = false
    private(set) var isBinding = false

    var errorMessage: String?
    private(set) var successKind: AccountBindSuccessKind?

    let boundPhone: String?

    var hasExistingPhone: Bool {
        boundPhone != nil && !(boundPhone?.isEmpty ?? true)
    }

    var showsManagement: Bool {
        hasExistingPhone && !isReplacing && !isCodeSent && successKind == nil
    }

    var bindSuccess: Bool {
        successKind != nil
    }

    var fullPhone: String {
        AccountValidation.fullChinaPhone(nationalNumber: nationalNumber)
    }

    var successTitle: String {
        switch successKind {
        case .bound: "手机号绑定成功"
        case .replaced: "手机号已更换"
        case .unbound: "手机号已解绑"
        case .none: ""
        }
    }

    var successSubtitle: String {
        switch successKind {
        case .bound: "可用于登录验证和账号安全保护"
        case .replaced: "新手机号已生效"
        case .unbound: "该手机号已不再关联此账号"
        case .none: ""
        }
    }

    init(profileService: ProfileService, boundPhone: String? = nil) {
        self.profileService = profileService
        self.boundPhone = boundPhone
        if let boundPhone, !boundPhone.isEmpty {
            nationalNumber = AccountValidation.chinaNationalNumber(from: boundPhone)
        }
    }

    var isStepOneEnabled: Bool {
        AccountValidation.isValidChinaMobileNumber(nationalNumber) && !isSendingCode
    }

    var isStepTwoEnabled: Bool {
        code.filter(\.isNumber).count >= 4 && !isBinding
    }

    var canResendCode: Bool {
        countdown == 0 && !isSendingCode
    }

    func beginReplace() {
        isReplacing = true
        nationalNumber = ""
        code = ""
        isCodeSent = false
        errorMessage = nil
        successKind = nil
        invalidateTimer()
    }

    func cancelReplaceOrBackToEnter() {
        if isCodeSent {
            code = ""
            isCodeSent = false
            errorMessage = nil
            invalidateTimer()
            return
        }
        if isReplacing {
            isReplacing = false
            nationalNumber = AccountValidation.chinaNationalNumber(from: boundPhone ?? "")
            code = ""
            isCodeSent = false
            errorMessage = nil
            invalidateTimer()
        }
    }

    func sendCode() async {
        errorMessage = nil

        guard AccountValidation.isValidChinaMobileNumber(nationalNumber) else {
            errorMessage = "请输入 11 位手机号"
            return
        }

        guard !isSendingCode else { return }
        isSendingCode = true
        defer { isSendingCode = false }

        do {
            let response = try await profileService.sendPhoneBindCode(phone: fullPhone)
            isCodeSent = true
            AppHaptics.lightImpact()
            startCountdown(seconds: response.retryAfterSeconds)
        } catch {
            errorMessage = "发送失败：\(error.localizedDescription)"
        }
    }

    func confirmBind() async {
        errorMessage = nil

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "请输入验证码"
            return
        }

        guard !isBinding else { return }
        isBinding = true
        defer { isBinding = false }

        do {
            try await profileService.confirmPhoneBind(
                phone: fullPhone,
                code: trimmedCode
            )
            successKind = (hasExistingPhone || isReplacing) ? .replaced : .bound
            AppHaptics.success()
        } catch {
            errorMessage = "绑定失败：\(error.localizedDescription)"
        }
    }

    func unbind() async {
        errorMessage = nil
        guard !isBinding else { return }
        isBinding = true
        defer { isBinding = false }

        do {
            try await profileService.unbindPhone()
            successKind = .unbound
            AppHaptics.success()
        } catch {
            errorMessage = "解绑失败：\(error.localizedDescription)"
        }
    }

    func resetForm() {
        isReplacing = false
        nationalNumber = AccountValidation.chinaNationalNumber(from: boundPhone ?? "")
        code = ""
        isCodeSent = false
        errorMessage = nil
        successKind = nil
        invalidateTimer()
    }

    func invalidateTimer() {
        verificationTimer.invalidate()
        countdown = 0
    }

    func sanitizeNationalNumber(_ value: String) {
        let digits = value.filter(\.isNumber)
        nationalNumber = String(digits.prefix(11))
    }

    func sanitizeCode(_ value: String) {
        let digits = value.filter(\.isNumber)
        code = String(digits.prefix(6))
    }

    // MARK: - Private

    private func startCountdown(seconds: Int) {
        verificationTimer.start(seconds: seconds) { [weak self] value in
            self?.countdown = value
        }
    }
}
