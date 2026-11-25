import Foundation

#if TRACCI_ENABLE_WECHAT && canImport(WechatOpenSDK)
import UIKit
import WechatOpenSDK

final class WeChatLoginManager: NSObject, WXApiDelegate, @unchecked Sendable {
    static let shared = WeChatLoginManager()

    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState: String?
    private var isRegistered = false

    private override init() {}

    var isConfigured: Bool {
        !Self.appID.isEmpty &&
            !Self.appID.contains("$(") &&
            !Self.universalLink.isEmpty &&
            !Self.universalLink.contains("$(")
    }

    var isAppInstalled: Bool {
        WXApi.isWXAppInstalled()
    }

    @discardableResult
    func register() -> Bool {
        guard isConfigured else { return false }

        let success = WXApi.registerApp(Self.appID, universalLink: Self.universalLink)
        isRegistered = success
        return success
    }

    func requestAuthCode() async throws -> String {
        guard isConfigured else {
            throw WeChatLoginError.notConfigured
        }

        if !isRegistered {
            register()
        }

        guard WXApi.isWXAppInstalled() else {
            throw WeChatLoginError.appNotInstalled
        }

        guard WXApi.isWXAppSupport() else {
            throw WeChatLoginError.unsupported
        }

        guard continuation == nil else {
            throw WeChatLoginError.requestInProgress
        }

        let state = "tracci_ios_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        expectedState = state

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = SendAuthReq()
            request.scope = "snsapi_userinfo"
            request.state = state

            WXApi.send(request) { [weak self] success in
                guard success else {
                    self?.resume(throwing: WeChatLoginError.unableToOpenWeChat)
                    return
                }
            }
        }
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        WXApi.handleOpen(url, delegate: self)
    }

    @discardableResult
    func handleUniversalLink(_ userActivity: NSUserActivity) -> Bool {
        WXApi.handleOpenUniversalLink(userActivity, delegate: self)
    }

    func onResp(_ resp: BaseResp) {
        guard let authResponse = resp as? SendAuthResp else { return }

        guard authResponse.state == expectedState else {
            resume(throwing: WeChatLoginError.invalidState)
            return
        }

        switch authResponse.errCode {
        case WXSuccess.rawValue:
            guard let code = authResponse.code, !code.isEmpty else {
                resume(throwing: WeChatLoginError.missingCode)
                return
            }
            resume(returning: code)
        case WXErrCodeUserCancel.rawValue:
            resume(throwing: WeChatLoginError.cancelled)
        case WXErrCodeAuthDeny.rawValue:
            resume(throwing: WeChatLoginError.denied)
        default:
            resume(throwing: WeChatLoginError.sdkError(authResponse.errStr))
        }
    }

    func onReq(_ req: BaseReq) {}

    private func resume(returning code: String) {
        continuation?.resume(returning: code)
        cleanupPendingRequest()
    }

    private func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        cleanupPendingRequest()
    }

    private func cleanupPendingRequest() {
        continuation = nil
        expectedState = nil
    }

    private static var appID: String {
        (Bundle.main.object(forInfoDictionaryKey: "WECHAT_APP_ID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var universalLink: String {
        (Bundle.main.object(forInfoDictionaryKey: "WECHAT_UNIVERSAL_LINK") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
#else
final class WeChatLoginManager: @unchecked Sendable {
    static let shared = WeChatLoginManager()

    var isConfigured: Bool { false }
    var isAppInstalled: Bool { false }

    private init() {}

    @discardableResult
    func register() -> Bool { false }

    func requestAuthCode() async throws -> String {
        throw WeChatLoginError.officialSDKMissing
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool { false }

    @discardableResult
    func handleUniversalLink(_ userActivity: NSUserActivity) -> Bool { false }
}
#endif

enum WeChatLoginError: LocalizedError, Equatable {
    case officialSDKMissing
    case notConfigured
    case appNotInstalled
    case unsupported
    case requestInProgress
    case unableToOpenWeChat
    case invalidState
    case missingCode
    case cancelled
    case denied
    case sdkError(String?)

    var errorDescription: String? {
        switch self {
        case .officialSDKMissing:
            return "请先按官方文档集成 WechatOpenSDK"
        case .notConfigured:
            return "微信登录尚未配置 AppID 或 Universal Link"
        case .appNotInstalled:
            return "请先安装微信后再登录"
        case .unsupported:
            return "当前微信版本不支持授权登录"
        case .requestInProgress:
            return "微信登录正在进行中"
        case .unableToOpenWeChat:
            return "无法拉起微信，请稍后重试"
        case .invalidState:
            return "微信登录状态校验失败，请重试"
        case .missingCode:
            return "微信未返回授权 code，请重试"
        case .cancelled:
            return "已取消微信登录"
        case .denied:
            return "微信授权失败"
        case let .sdkError(message):
            return message?.isEmpty == false ? message : "微信登录失败，请重试"
        }
    }
}
