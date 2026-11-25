import Foundation
import Observation
import UIKit

enum PhoneLoginPhase: Equatable {
    case idle
    case checkingEnvironment
    case requestingAuthorization
    case gettingMobileToken
    case loggingInWithBackend
    case userCancelled
    case providerError(String)
    case backendError(String)
    case networkError(String)

    var isLoading: Bool {
        switch self {
        case .checkingEnvironment, .requestingAuthorization, .gettingMobileToken, .loggingInWithBackend: true
        default: false
        }
    }

    var buttonTitle: String {
        switch self {
        case .checkingEnvironment: "正在检查本机环境"
        case .requestingAuthorization: "正在打开运营商授权"
        case .gettingMobileToken: "正在获取本机号码凭证"
        case .loggingInWithBackend: "正在安全登录"
        default: "本机号码一键登录"
        }
    }

    var statusMessage: String? {
        switch self {
        case .checkingEnvironment: "将通过运营商安全确认本机号码，不会展示完整手机号。"
        case .requestingAuthorization: "请在授权页阅读协议后继续，取消不会影响邮箱登录。"
        case .gettingMobileToken: "正在从号码认证服务获取一次性凭证。"
        case .loggingInWithBackend: "凭证已获取，正在完成趣溪账号登录。"
        case .userCancelled: "已取消本机号码登录，可继续使用邮箱登录。"
        case let .providerError(message), let .backendError(message), let .networkError(message): message
        case .idle: nil
        }
    }
}

enum PhoneLoginUIEvent: Equatable {
    case none
    case showToast(String)
    case expandEmail
    case success
}

@MainActor
@Observable
final class AuthViewModel {
    private let phoneAuthProvider: any PhoneAuthProviding
    var email = ""
    var password = ""
    var confirmPassword = ""
    var nickname = ""
    var agreedToTerms = false
    var isLoading = false
    var errorMessage: String?
    private(set) var phoneLoginPhase: PhoneLoginPhase = .idle

    init(phoneAuthProvider: any PhoneAuthProviding) {
        self.phoneAuthProvider = phoneAuthProvider
    }

    convenience init() {
        self.init(phoneAuthProvider: UnavailablePhoneAuthProvider())
    }

    func preparePhoneLogin() async {
        await phoneAuthProvider.prepareForOneTapPresentation()
    }

    func resetPhoneLogin() {
        phoneLoginPhase = .idle
    }

    func presenterUnavailable() -> PhoneLoginUIEvent {
        phoneLoginPhase = .providerError("无法打开授权页，请稍后重试或使用邮箱登录。")
        return .showToast("无法获取当前页面，请稍后重试")
    }

    func phoneOneTapLogin(
        authSession: AuthSession,
        presenting controller: UIViewController
    ) async -> PhoneLoginUIEvent {
        guard phoneAuthProvider.isConfigured else {
            phoneLoginPhase = .providerError("号码认证服务暂不可用，请使用邮箱登录。")
            return .showToast("号码认证服务暂不可用，请使用邮箱登录")
        }

        phoneLoginPhase = .requestingAuthorization
        do {
            guard try await phoneAuthProvider.checkEnvironmentAvailable() else {
                phoneLoginPhase = .providerError("本机号码登录需要 SIM 卡和蜂窝网络支持，请使用邮箱登录。")
                return .showToast("本机号码登录需要 SIM 卡和蜂窝网络支持")
            }
        } catch {
            if let phoneError = error as? PhoneAuthError,
               let message = phoneError.errorDescription {
                phoneLoginPhase = .providerError("\(message)，请使用邮箱登录。")
                return .showToast(message)
            }
            return .none
        }

        let accessToken: String
        do {
            accessToken = try await phoneAuthProvider.requestOneTapLogin(from: controller)
        } catch {
            phoneAuthProvider.dismissLoginPage()
            Task { await phoneAuthProvider.prepareForOneTapPresentation() }
            if let phoneError = error as? PhoneAuthError {
                switch phoneError {
                case .userCancelled:
                    phoneLoginPhase = .userCancelled
                case .userSwitchedMethod:
                    phoneLoginPhase = .idle
                    return .expandEmail
                default:
                    if let message = phoneError.errorDescription {
                        phoneLoginPhase = .providerError("\(message)，请使用邮箱登录。")
                        return .showToast(message)
                    }
                }
            }
            return .none
        }

        phoneLoginPhase = .loggingInWithBackend
        await authSession.loginWithPhoneOneTap(accessToken: accessToken)
        phoneAuthProvider.dismissLoginPage()

        if let errorMessage = authSession.errorMessage {
            let message = friendlyPhoneBackendMessage(errorMessage)
            phoneLoginPhase = isNetworkLikeError(errorMessage)
                ? .networkError(message)
                : .backendError(message)
            Task { await phoneAuthProvider.prepareForOneTapPresentation() }
            return .showToast(message)
        }

        phoneLoginPhase = .idle
        return .success
    }

    var canLogin: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && agreedToTerms
    }

    var canRegister: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && password == confirmPassword
            && agreedToTerms
    }

    func login(authSession: AuthSession) async {
        guard validateLoginForm() else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await authSession.login(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        errorMessage = authSession.errorMessage.map(friendlyLoginError)
    }

#if DEBUG
    func fillAdminDebugAccount() {
        email = "admin"
        password = "admin123456"
        agreedToTerms = true
        errorMessage = nil
    }
#endif

    func register(authSession: AuthSession) async {
        guard validateRegisterForm() else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        await authSession.register(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            nickname: trimmedNickname.isEmpty ? nil : trimmedNickname
        )
        errorMessage = authSession.errorMessage.map(friendlyRegisterError)
    }

    private func validateLoginForm() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "请输入邮箱和密码"
            return false
        }

        guard agreedToTerms else {
            errorMessage = "请先阅读并同意用户协议和隐私政策"
            return false
        }
        return true
    }

    private func validateRegisterForm() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "请输入合法邮箱地址"
            return false
        }

        guard isValidPassword(password) else {
            errorMessage = "密码需为 8-30 位，并同时包含字母和数字"
            return false
        }

        guard password == confirmPassword else {
            errorMessage = "两次输入的密码不一致"
            return false
        }

        guard trimmedNickname.count <= 50 else {
            errorMessage = "昵称最多 50 个字符"
            return false
        }

        guard agreedToTerms else {
            errorMessage = "请先阅读并同意用户协议和隐私政策"
            return false
        }

        return true
    }

    private func isValidEmail(_ value: String) -> Bool {
        guard value.count <= 255 else { return false }
        return value.range(
            of: #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#,
            options: .regularExpression
        ) != nil
    }

    private func isValidPassword(_ value: String) -> Bool {
        guard (8...30).contains(value.count) else { return false }
        let hasLetter = value.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        let hasNumber = value.range(of: #"\d"#, options: .regularExpression) != nil
        return hasLetter && hasNumber
    }

    private func friendlyLoginError(_ message: String) -> String {
        if message.contains("邮箱或密码") || message.contains("40003") {
            return "邮箱或密码不正确，请检查后再试"
        }
        if message.contains("锁定") {
            return "尝试次数较多，请稍后再登录"
        }
        if message.contains("网络") || message.contains("连接") || message.contains("超时") {
            return "网络连接不稳定，请稍后重试"
        }
        return message.isEmpty ? "登录失败，请稍后重试" : message
    }

    private func friendlyRegisterError(_ message: String) -> String {
        if message.contains("已被注册") || message.contains("40004") {
            return "这个邮箱已经注册，可以直接登录"
        }
        if message.contains("格式") || message.contains("40002") {
            return "邮箱或密码格式不正确，请检查后再试"
        }
        if message.contains("网络") || message.contains("连接") || message.contains("超时") {
            return "网络连接不稳定，请稍后重试"
        }
        return message.isEmpty ? "注册失败，请稍后重试" : message
    }

    private func friendlyPhoneBackendMessage(_ message: String) -> String {
        if isNetworkLikeError(message) {
            return "网络连接不稳定，请稍后重试或使用邮箱登录。"
        }
        return message.isEmpty ? "本机号码登录失败，请使用邮箱登录。" : "\(message)，也可以使用邮箱登录。"
    }

    private func isNetworkLikeError(_ message: String) -> Bool {
        message.contains("网络") || message.contains("连接") || message.contains("超时")
    }
}
