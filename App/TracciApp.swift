import SwiftUI

@main
struct TracciApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authSession: AuthSession

    private let dependencies: AppDependencies

    init() {
        let dependencies = LiveDependencies.make()
        self.dependencies = dependencies
        _authSession = State(initialValue: dependencies.authSession)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(dependencies: dependencies)
            .environment(authSession)
            // v1 App Store: light-only. Pairs with Info.plist UIUserInterfaceStyle = Light.
            // Dark Mode is deferred until a full semantic color-token pass.
            .preferredColorScheme(.light)
        }
    }
}
