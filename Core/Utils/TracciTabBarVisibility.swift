import SwiftUI
import UIKit

// MARK: - Navigation Path Tab Bar Policy

enum TracciNavigationPathTabBarPolicy {
    static func shouldHideTabBar(pathDepth: Int, rootOverlayHidden: Bool) -> Bool {
        pathDepth > 0 || rootOverlayHidden
    }
}

enum TracciMainTabBarVisibilityPolicy {
    static func hidesForGlobalOverlay(
        showingCreateOptions: Bool,
        isCreateFlowTransitioning: Bool,
        showingCreateTrip: Bool,
        showingJoinTrip: Bool
    ) -> Bool {
        showingCreateOptions
            || isCreateFlowTransitioning
            || showingCreateTrip
            || showingJoinTrip
    }

    static func shouldShowTabBar(
        globalOverlayHidden: Bool,
        immersiveHidden: Bool,
        navigationHidden: Bool
    ) -> Bool {
        !globalOverlayHidden && !immersiveHidden && !navigationHidden
    }
}

// MARK: - Tab Bar Visibility Contract

extension View {
    @ViewBuilder
    func tracciTabBarVisibility(_ visibility: Visibility) -> some View {
        if #available(iOS 18, *) {
            toolbar(visibility, for: .tabBar)
                .toolbarVisibility(visibility, for: .tabBar)
        } else {
            toolbar(visibility, for: .tabBar)
        }
    }

    /// G5.4 — condense the system navigation bar into its glass capsule while the
    /// page scrolls (iOS 26 only; no-op below so pushed sub-pages are unchanged).
    @ViewBuilder
    func tracciNavigationBarMinimizeOnScroll() -> some View {
        #if compiler(>=26)
        if #available(iOS 26, *) {
            navigationBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    #if DEBUG
    func tracciTabBarDebugTrace(
        _ label: String,
        selectedTab: String,
        customShouldShow: Bool,
        nativeShouldShow: Bool,
        globalHidden: Bool,
        immersiveHidden: Bool,
        navigationHidden: Bool,
        syncRevision: Int
    ) -> some View {
        background(
            TracciTabBarDebugTrace(
                label: label,
                selectedTab: selectedTab,
                customShouldShow: customShouldShow,
                nativeShouldShow: nativeShouldShow,
                globalHidden: globalHidden,
                immersiveHidden: immersiveHidden,
                navigationHidden: navigationHidden,
                syncRevision: syncRevision
            )
        )
    }
    #endif

    func tracciNavigationPathUIKitPopSync(path: Binding<NavigationPath>) -> some View {
        background(TracciNavigationPathUIKitPopSync(path: path))
    }
}

private struct TracciNavigationPathUIKitPopSync: UIViewControllerRepresentable {
    @Binding var path: NavigationPath

    func makeCoordinator() -> Coordinator {
        Coordinator(path: $path)
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.path = $path
        controller.onResolveNavigationController = { navigationController in
            context.coordinator.attach(to: navigationController)
        }
        controller.resolveNavigationController()
    }

    final class Controller: UIViewController {
        var onResolveNavigationController: ((UINavigationController) -> Void)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            resolveNavigationController()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            resolveNavigationController()
        }

        func resolveNavigationController() {
            guard let navigationController = resolvedNavigationController() else { return }
            onResolveNavigationController?(navigationController)
        }

        private func resolvedNavigationController() -> UINavigationController? {
            if let navigationController { return navigationController }
            var current: UIViewController? = self
            while let viewController = current {
                if let navigationController = viewController as? UINavigationController {
                    return navigationController
                }
                if let navigationController = viewController.navigationController {
                    return navigationController
                }
                current = viewController.parent
            }
            return nil
        }
    }

    final class Coordinator: NSObject {
        var path: Binding<NavigationPath>
        private weak var navigationController: UINavigationController?
        private var observation: NSKeyValueObservation?

        init(path: Binding<NavigationPath>) {
            self.path = path
        }

        func attach(to navigationController: UINavigationController) {
            guard self.navigationController !== navigationController else { return }

            observation = nil
            self.navigationController = navigationController
            observation = navigationController.observe(\.viewControllers, options: [.new]) { [weak self] navigationController, _ in
                self?.sync(to: navigationController)
            }
        }

        private func sync(to navigationController: UINavigationController) {
            if let coordinator = navigationController.transitionCoordinator, coordinator.isInteractive {
                // Interactive swipe-back is handled by TracciInteractivePopGesture
                // with route-specific target depths. UIKit may report transient
                // stack depths during the animation, so do not mirror it here.
                return
            }

            let targetDepth = max(navigationController.viewControllers.count - 1, 0)
            let currentDepth = path.wrappedValue.count
            guard currentDepth > targetDepth else { return }
            path.wrappedValue.removeLast(currentDepth - targetDepth)
            #if DEBUG
            print("[TabBarPath:UIKitSync] navigationPath.count \(currentDepth) -> \(targetDepth)")
            #endif
        }
    }
}

#if DEBUG
private struct TracciTabBarDebugTrace: UIViewControllerRepresentable {
    let label: String
    let selectedTab: String
    let customShouldShow: Bool
    let nativeShouldShow: Bool
    let globalHidden: Bool
    let immersiveHidden: Bool
    let navigationHidden: Bool
    let syncRevision: Int

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.trace(
            label: label,
            selectedTab: selectedTab,
            customShouldShow: customShouldShow,
            nativeShouldShow: nativeShouldShow,
            globalHidden: globalHidden,
            immersiveHidden: immersiveHidden,
            navigationHidden: navigationHidden,
            syncRevision: syncRevision
        )
    }

    final class Controller: UIViewController {
        private var lastMessage = ""
        private var traceSequence = 0

        func trace(
            label: String,
            selectedTab: String,
            customShouldShow: Bool,
            nativeShouldShow: Bool,
            globalHidden: Bool,
            immersiveHidden: Bool,
            navigationHidden: Bool,
            syncRevision: Int
        ) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let tabBar = self.tabBarController?.tabBar ?? Self.findTabBarController()?.tabBar
                self.traceSequence += 1
                let message = "[TabBarTrace:\(label)] #\(self.traceSequence) selected=\(selectedTab) customVisible=\(customShouldShow) nativeVisible=\(nativeShouldShow) gates(global=\(globalHidden), immersive=\(immersiveHidden), nav=\(navigationHidden)) depth=\(syncRevision) nativeActual(isHidden=\(tabBar?.isHidden.description ?? "nil"), alpha=\(tabBar.map { String(format: "%.2f", $0.alpha) } ?? "nil"), frame=\(tabBar.map { NSCoder.string(for: $0.frame) } ?? "nil"))"
                guard message != self.lastMessage else { return }
                self.lastMessage = message
                print(message)
            }
        }

        private static func findTabBarController() -> UITabBarController? {
            guard let root = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
            else {
                return nil
            }
            return findTabBarController(in: root)
        }

        private static func findTabBarController(in viewController: UIViewController) -> UITabBarController? {
            if let tabBarController = viewController as? UITabBarController {
                return tabBarController
            }
            if let tabBarController = viewController.tabBarController {
                return tabBarController
            }
            for child in viewController.children {
                if let tabBarController = findTabBarController(in: child) {
                    return tabBarController
                }
            }
            if let presented = viewController.presentedViewController,
               let tabBarController = findTabBarController(in: presented) {
                return tabBarController
            }
            return nil
        }
    }
}
#endif
