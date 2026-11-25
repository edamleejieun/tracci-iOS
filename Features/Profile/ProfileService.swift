import Foundation
import TracciNetworking

struct ProfileService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func getFeedbackOptions() async throws -> FeedbackOptionsResponse {
        try await apiClient.request(APIEndpoint(path: "feedbacks/options"))
    }

    func getAccountSecurityStatus() async throws -> AccountSecurityStatus {
        try await apiClient.request(APIEndpoint(path: "users/me/security"))
    }

    // MARK: - Email Bind

    func sendEmailBindCode(email: String) async throws -> SendVerificationCodeResponse {
        let body = SendVerificationCodeRequest(email: email)
        return try await apiClient.request(
            APIEndpoint(path: "auth/email/bind/send-code", method: .post, body: body)
        )
    }

    func confirmEmailBind(email: String, code: String, password: String) async throws {
        let body = EmailBindConfirmRequest(email: email, code: code, password: password)
        _ = try await apiClient.request(
            APIEndpoint(path: "auth/email/bind/confirm", method: .post, body: body),
            as: EmptyResponse.self
        )
    }

    func submitFeedback(
        type: String,
        title: String?,
        content: String,
        contactType: String?,
        contact: String?,
        imageIds: [String]?,
        appVersion: String?,
        systemInfo: FeedbackSystemInfo?
    ) async throws -> FeedbackSubmitResponse {
        let request = FeedbackSubmitRequest(
            type: type,
            title: title,
            content: content,
            contactType: contactType,
            contact: contact,
            imageIds: imageIds,
            platform: "IOS",
            appVersion: appVersion,
            systemInfo: systemInfo
        )
        return try await apiClient.request(
            APIEndpoint(path: "feedbacks", method: .post, body: request)
        )
    }

    // MARK: - Phone Bind / Unbind

    func sendPhoneBindCode(phone: String) async throws -> SendVerificationCodeResponse {
        let body = SendPhoneCodeRequest(phone: phone)
        return try await apiClient.request(
            APIEndpoint(path: "auth/phone/bind/send-code", method: .post, body: body)
        )
    }

    func confirmPhoneBind(phone: String, code: String) async throws {
        let body = VerifyPhoneCodeRequest(phone: phone, code: code)
        _ = try await apiClient.request(
            APIEndpoint(path: "auth/phone/bind/confirm", method: .post, body: body),
            as: EmptyResponse.self
        )
    }

    func unbindPhone() async throws {
        _ = try await apiClient.request(
            APIEndpoint(path: "auth/phone/unbind", method: .post),
            as: EmptyResponse.self
        )
    }
}
