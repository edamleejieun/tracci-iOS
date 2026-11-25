import UIKit

@MainActor
protocol PhoneAuthProviding: AnyObject {
    var isConfigured: Bool { get }
    func prepareForOneTapPresentation() async
    func checkEnvironmentAvailable() async throws -> Bool
    func requestOneTapLogin(from controller: UIViewController) async throws -> String
    func dismissLoginPage()
}

/// Narrow adapter around the vendor SDK manager. The SDK keeps its required
/// single-instance lifecycle while Features depend on an injectable capability.
@MainActor
final class LivePhoneAuthAdapter: PhoneAuthProviding {
    private let manager: PhoneAuthManager

    init(manager: PhoneAuthManager = .shared) {
        self.manager = manager
    }

    var isConfigured: Bool { manager.isConfigured }

    func prepareForOneTapPresentation() async {
        await manager.prepareForOneTapPresentation()
    }

    func checkEnvironmentAvailable() async throws -> Bool {
        try await manager.checkEnvAvailable()
    }

    func requestOneTapLogin(from controller: UIViewController) async throws -> String {
        try await manager.requestOneTapLogin(from: controller)
    }

    func dismissLoginPage() {
        manager.hideLoginLoading()
        manager.cancelLogin(animated: true)
    }
}

@MainActor
final class UnavailablePhoneAuthProvider: PhoneAuthProviding {
    var isConfigured: Bool { false }
    func prepareForOneTapPresentation() async {}
    func checkEnvironmentAvailable() async throws -> Bool { false }
    func requestOneTapLogin(from controller: UIViewController) async throws -> String {
        throw PhoneAuthError.notConfigured
    }
    func dismissLoginPage() {}
}
