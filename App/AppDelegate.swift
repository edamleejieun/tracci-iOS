import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Pending invite code from deep link, consumed by AppRootView after auth.
    nonisolated(unsafe) static var pendingInviteCode: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // v1 App Store: light-only for UIKit windows (phone-auth SDK, etc.).
        // Complements Info.plist UIUserInterfaceStyle=Light and SwiftUI preferredColorScheme.
        forceLightInterfaceStyleIfNeeded(on: application)

        // Brand-tint the system pull-to-refresh spinner (backs every `.refreshable`).
        UIRefreshControl.appearance().tintColor = UIColor(AppColors.brandPrimary)

        PhoneAuthManager.shared.configure()

        // Handle deep link from launch options (cold start)
        if let url = launchOptions?[.url] as? URL {
            _ = handleDeepLink(url)
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Windows may not exist yet in didFinishLaunching under SwiftUI lifecycle.
        forceLightInterfaceStyleIfNeeded(on: application)
    }

    /// Locks connected scene windows to light so UIKit-presented flows stay consistent with SwiftUI.
    private func forceLightInterfaceStyleIfNeeded(on application: UIApplication) {
        for scene in application.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != .light {
                window.overrideUserInterfaceStyle = .light
            }
        }
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return handleDeepLink(url)
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if let url = userActivity.webpageURL {
            return handleDeepLink(url)
        }
        return false
    }

    // MARK: - Deep Link Handling

    /// Handles collaboration invite deep links:
    /// `tracci://join-trip?code=8K3M` and `tracci://co-editor?id={tripId}&code=8K3M`.
    private func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme == "tracci",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return false
        }

        let code: String?
        switch url.host {
        case "join-trip", "co-editor":
            code = components.queryItems?.first(where: { $0.name == "code" })?.value
        default:
            return false
        }

        guard let code, !code.isEmpty else {
            return false
        }

        Self.pendingInviteCode = TripInviteCode.normalize(code)
        NotificationCenter.default.post(name: .tracciDeepLinkJoinTrip, object: code)
        return true
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let tracciDeepLinkJoinTrip = Notification.Name("tracciDeepLinkJoinTrip")
}
