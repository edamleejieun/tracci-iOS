import Foundation
import Observation
import TracciNetworking

@Observable
final class AuthSession: AccessTokenProviding {
    private let tokenStore: any AuthTokenStoring
    private let refreshCoordinator: TokenRefreshCoordinator
    private var authService: AuthService?

    private(set) var token: AuthToken?
    private(set) var currentUser: User?
    private(set) var isLoading = false
    private(set) var hasCompletedInitialRestore = false
    var errorMessage: String?

    var accessToken: String? {
        token?.accessToken
    }

    var isAuthenticated: Bool {
        token?.accessToken.isEmpty == false
    }

    var isLoggedIn: Bool {
        isAuthenticated
    }

    init(
        tokenStore: any AuthTokenStoring,
        refreshCoordinator: TokenRefreshCoordinator = TokenRefreshCoordinator()
    ) {
        self.tokenStore = tokenStore
        self.refreshCoordinator = refreshCoordinator
        token = try? tokenStore.loadToken()
    }

    func configure(authService: AuthService) {
        self.authService = authService
    }

    @MainActor
    func restoreSession() async {
        guard !hasCompletedInitialRestore else { return }

        guard isAuthenticated else {
            hasCompletedInitialRestore = true
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasCompletedInitialRestore = true
        }

        do {
            currentUser = try await requireAuthService().getCurrentUser()
        } catch {
            guard shouldAttemptRefresh(after: error), await refreshSessionIfNeeded() else {
                if shouldClearSession(after: error) {
                    clear()
                } else {
                    errorMessage = error.localizedDescription
                }
                return
            }

            do {
                currentUser = try await requireAuthService().getCurrentUser()
            } catch {
                clear()
            }
        }
    }

    @MainActor
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await requireAuthService().login(email: email, password: password)
            saveLogin(result: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loginWithWeChatApp(code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await requireAuthService().loginWithWeChatApp(code: code)
            saveLogin(result: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loginWithPhoneOneTap(accessToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            #if DEBUG
            print("[AuthSession] Calling authService.loginWithPhoneOneTap...")
            #endif
            let result = try await requireAuthService().loginWithPhoneOneTap(accessToken: accessToken)
            #if DEBUG
            print("[AuthSession] Backend login success, saving session...")
            #endif
            saveLogin(result: result)
        } catch {
            #if DEBUG
            print("[AuthSession] loginWithPhoneOneTap error: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func register(email: String, password: String, nickname: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await requireAuthService().register(
                email: email,
                password: password,
                nickname: nickname
            )
            saveLogin(result: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func logout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await requireAuthService().logout()
        } catch {
            // Local logout must always be possible, even if the backend is unreachable.
        }

        clear()
    }

    @MainActor
    @discardableResult
    func refreshSessionIfNeeded() async -> Bool {
        guard let refreshToken = token?.refreshToken, !refreshToken.isEmpty else {
            clear()
            return false
        }

        do {
            let result = try await refreshCoordinator.refreshIfNeeded(refreshToken: refreshToken) { [authService] token in
                guard let authService else { throw APIError.unauthorized }
                return try await authService.refresh(refreshToken: token)
            }
            updateAccessToken(result.accessToken, expiresAt: result.accessTokenExpiresAt)
            return true
        } catch {
            clear()
            return false
        }
    }

    @MainActor
    func saveLogin(result: AuthResult) {
        currentUser = result.user
        token = result.token
        try? tokenStore.save(token: result.token)
    }

    @MainActor
    func updateAccessToken(_ accessToken: String, expiresAt: String?) {
        guard var existingToken = token else { return }
        existingToken.accessToken = accessToken
        existingToken.accessTokenExpiresAt = expiresAt
        token = existingToken
        try? tokenStore.save(token: existingToken)
    }

    @MainActor
    func restoreUser(_ user: User) {
        currentUser = user
    }

    @MainActor
    func clear() {
        currentUser = nil
        token = nil
        errorMessage = nil
        try? tokenStore.clear()
    }

    private func requireAuthService() throws -> AuthService {
        guard let authService else {
            throw APIError.underlying("认证服务尚未初始化")
        }
        return authService
    }

    private func shouldAttemptRefresh(after error: Error) -> Bool {
        if case APIError.unauthorized = error {
            return true
        }

        if case let APIError.business(code, _) = error, code == 40101 || code == 40102 {
            return true
        }

        return false
    }

    private func shouldClearSession(after error: Error) -> Bool {
        if case APIError.unauthorized = error {
            return true
        }

        if case let APIError.business(code, _) = error, code == 40101 || code == 40102 || code == 40302 {
            return true
        }

        return false
    }
}

#if DEBUG
extension AuthSession {
    /// 预览专用：内存 token store，不碰 Keychain、不发任何网络请求。
    /// 默认未登录（占位头像）；需要带头像的预览可在外部直接给 `currentUser` 赋值。
    static func preview() -> AuthSession {
        AuthSession(tokenStore: InMemoryTokenStore())
    }
}
#endif
