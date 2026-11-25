import Foundation
import Observation

@Observable
@MainActor
final class ChangePasswordViewModel {
    let authService: AuthService

    var oldPassword = ""
    var newPassword = ""
    var confirmPassword = ""
    private(set) var isChangingPassword = false
    var errorMessage: String?
    var changeSuccess = false
    var validationError: String?

    let hasPassword: Bool

    init(authService: AuthService, hasPassword: Bool) {
        self.authService = authService
        self.hasPassword = hasPassword
    }

    var isChangePasswordEnabled: Bool {
        !oldPassword.isEmpty
            && !newPassword.isEmpty
            && !confirmPassword.isEmpty
            && !isChangingPassword
    }

    func changePassword() async {
        validationError = nil
        errorMessage = nil

        if let passwordError = AccountValidation.passwordValidationError(for: newPassword) {
            validationError = passwordError
            return
        }

        if let confirmError = AccountValidation.confirmPasswordError(
            password: newPassword,
            confirm: confirmPassword,
            mismatchMessage: "两次输入的新密码不一致"
        ) {
            validationError = confirmError
            return
        }

        guard newPassword != oldPassword else {
            validationError = "新密码不能与原密码相同"
            return
        }

        guard !isChangingPassword else { return }
        isChangingPassword = true
        defer { isChangingPassword = false }

        do {
            try await authService.changePassword(oldPassword: oldPassword, newPassword: newPassword)
            changeSuccess = true
        } catch {
            errorMessage = "修改密码失败：\(error.localizedDescription)"
        }
    }
}
