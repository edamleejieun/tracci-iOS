import Foundation
import TracciNetworking

struct AuthService: @unchecked Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func register(email: String, password: String, nickname: String?) async throws -> AuthResult {
        let body = RegisterRequest(email: email, password: password, nickname: nickname)
        return try await apiClient.request(
            APIEndpoint(path: "auth/register", method: .post, body: body, requiresAuth: false)
        )
    }

    func login(email: String, password: String) async throws -> AuthResult {
        let body = LoginRequest(email: email, password: password)
        return try await apiClient.request(
            APIEndpoint(path: "auth/login", method: .post, body: body, requiresAuth: false)
        )
    }

    func loginWithWeChatApp(code: String) async throws -> AuthResult {
        let body = WeChatAppLoginRequest(code: code, channel: "IOS")
        return try await apiClient.request(
            APIEndpoint(path: "auth/wechat-app/login", method: .post, body: body, requiresAuth: false)
        )
    }

    func refresh(refreshToken: String) async throws -> RefreshTokenResult {
        let body = RefreshTokenRequest(refreshToken: refreshToken)
        return try await apiClient.request(
            APIEndpoint(path: "auth/refresh", method: .post, body: body, requiresAuth: false)
        )
    }

    func logout() async throws {
        _ = try await apiClient.request(
            APIEndpoint(path: "auth/logout", method: .post),
            as: EmptyResponse.self
        )
    }

    func getCurrentUser() async throws -> User {
        try await apiClient.request(APIEndpoint(path: "users/me"))
    }

    func updateProfile(
        nickname: String?,
        avatarFileId: String?,
        signature: String? = nil,
        gender: String? = nil,
        birthDate: String? = nil
    ) async throws -> User {
        let body = UpdateProfileRequest(
            nickname: nickname,
            avatarFileId: avatarFileId,
            signature: signature,
            gender: gender,
            birthDate: birthDate
        )
        return try await apiClient.request(
            APIEndpoint(path: "users/me", method: .put, body: body)
        )
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        let body = ChangePasswordRequest(oldPassword: oldPassword, newPassword: newPassword)
        _ = try await apiClient.request(
            APIEndpoint(path: "auth/password/change", method: .post, body: body),
            as: EmptyResponse.self
        )
    }

    func deleteAccount(confirmText: String, reason: String?, password: String?) async throws {
        let body = DeleteAccountRequest(confirmText: confirmText, reason: reason, password: password)
        _ = try await apiClient.request(
            APIEndpoint(path: "users/me/delete-account", method: .post, body: body),
            as: EmptyResponse.self
        )
    }

    func loginWithPhoneOneTap(accessToken: String) async throws -> AuthResult {
        let body = PhoneOneTapLoginRequest(accessToken: accessToken)
        #if DEBUG
        print("[AuthService] Requesting auth/phone/one-tap-login with accessToken length: \(accessToken.count)")
        #endif
        return try await apiClient.request(
            APIEndpoint(path: "auth/phone/one-tap-login", method: .post, body: body, requiresAuth: false)
        )
    }

    // MARK: - Password Reset (Email)

    func sendPasswordResetEmailCode(email: String) async throws -> SendVerificationCodeResponse {
        let body = SendVerificationCodeRequest(email: email)
        return try await apiClient.request(
            APIEndpoint(path: "auth/password/reset/email-code", method: .post, body: body, requiresAuth: false)
        )
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        let body = PasswordResetConfirmRequest(email: email, code: code, newPassword: newPassword)
        _ = try await apiClient.request(
            APIEndpoint(path: "auth/password/reset", method: .post, body: body, requiresAuth: false),
            as: EmptyResponse.self
        )
    }
}

private struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let nickname: String?
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
}

private struct WeChatAppLoginRequest: Encodable {
    let code: String
    let channel: String
}

private struct PhoneOneTapLoginRequest: Encodable {
    let accessToken: String
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String
}
