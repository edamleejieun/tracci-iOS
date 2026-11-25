import Foundation
import Observation
import TracciNetworking

@Observable
@MainActor
final class AccountSecurityViewModel {
    let authService: AuthService
    let profileService: ProfileService

    private(set) var securityStatus: AccountSecurityStatus?
    private(set) var isLoadingSecurity = false
    var securityError: String?

    // Delete account state
    var deleteStep: DeleteAccountStep = .confirm
    var deletePassword = ""
    var deleteReason: DeleteReason?
    var customDeleteReason = ""
    var deleteConfirmText = ""
    var deleteFinalAgreed = false
    private(set) var isDeletingAccount = false
    var deleteError: String?
    var deleteSuccess = false

    init(authService: AuthService, profileService: ProfileService) {
        self.authService = authService
        self.profileService = profileService
    }

    var hasPassword: Bool {
        securityStatus?.hasPassword ?? true
    }

    var isDeleteEnabled: Bool {
        deleteConfirmText == "DELETE"
            && deleteFinalAgreed
            && !isDeletingAccount
            && (!hasPassword || !deletePassword.isEmpty)
    }

    var isDeleteReasonSelected: Bool {
        deleteReason != nil
    }

    func reloadStatus() async {
        await loadSecurityStatus()
    }

    func loadSecurityStatus() async {
        guard !isLoadingSecurity else { return }
        isLoadingSecurity = true
        securityError = nil
        defer { isLoadingSecurity = false }

        do {
            securityStatus = try await profileService.getAccountSecurityStatus()
        } catch {
            securityError = error.localizedDescription
        }
    }

    func deleteAccount() async {
        guard deleteConfirmText == "DELETE" else {
            deleteError = "请输入 DELETE 确认注销"
            return
        }
        guard deleteFinalAgreed else {
            deleteError = "请先确认已了解注销后果"
            return
        }
        guard !hasPassword || !deletePassword.isEmpty else {
            deleteError = "请输入登录密码"
            return
        }

        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteError = nil
        defer { isDeletingAccount = false }

        let password: String? = hasPassword ? deletePassword : nil
        let reason = resolvedDeleteReason

        do {
            try await authService.deleteAccount(
                confirmText: "DELETE",
                reason: reason?.isEmpty == false ? reason : nil,
                password: password
            )
            deleteSuccess = true
        } catch let APIError.business(code, _) where code == 42240 {
            deleteError = "你仍是共同旅程的创建者，请先到对应旅程的成员管理中转让所有权"
        } catch {
            deleteError = "注销失败：\(error.localizedDescription)"
        }
    }

    func resetDeleteFlow() {
        deleteStep = .confirm
        deletePassword = ""
        deleteReason = nil
        customDeleteReason = ""
        deleteConfirmText = ""
        deleteFinalAgreed = false
        deleteError = nil
        deleteSuccess = false
        isDeletingAccount = false
    }

    private var resolvedDeleteReason: String? {
        guard let deleteReason else { return nil }
        if deleteReason == .other {
            let trimmed = customDeleteReason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? deleteReason.title : trimmed
        }
        return deleteReason.title
    }
}

enum DeleteAccountStep: CaseIterable {
    case confirm
    case reason
    case verify
    case final
}

enum DeleteReason: String, CaseIterable, Identifiable {
    case noNeed
    case privacy
    case anotherAccount
    case hardToUse
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noNeed:
            return "不再需要这个应用"
        case .privacy:
            return "担心隐私安全"
        case .anotherAccount:
            return "想换一个账号"
        case .hardToUse:
            return "使用体验不好"
        case .other:
            return "其他原因"
        }
    }
}
