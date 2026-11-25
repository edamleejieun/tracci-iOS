import SwiftUI

/// Renders the global navigation/create chrome independently from feature content.
struct MainTabChromeView: View {
    @Bindable var coordinator: MainTabCoordinator
    let bottomInset: CGFloat
    let glassNamespace: Namespace.ID
    let onCreate: () -> Void
    let onManualTripCreate: () -> Void
    let onJoinTrip: () -> Void
    let onDismissCreateOptions: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            GlassEffectContainer(spacing: AppNavigationMetrics.createMenuGlassSpacing) {
                chromeContent(sharesNativeGlassContainer: true)
            }
        } else {
            chromeContent(sharesNativeGlassContainer: false)
        }
        #else
        chromeContent(sharesNativeGlassContainer: false)
        #endif
    }

    private func chromeContent(sharesNativeGlassContainer: Bool) -> some View {
        ZStack(alignment: .bottom) {
            if coordinator.shouldShowTabBar {
                GlobalNavigationBar(
                    selectedTab: binding(\.selectedTab),
                    tabs: coordinator.visibleTabs,
                    chromeMode: coordinator.navigationChromeMode,
                    bottomInset: bottomInset,
                    glassNamespace: glassNamespace,
                    isHostedInGlassContainer: sharesNativeGlassContainer,
                    onCreate: onCreate
                )
                // Fade + small on-screen offset (system-tab-bar style), not a full
                // bottom-edge slide: on pop-back, a `.move` entrance finishes its
                // travel hidden under the still-departing detail page (longer still
                // with the iOS 18 zoom transition), which reads as the dock
                // "appearing late". A fade is already in place as the page reveals.
                .transition(dockTransition)
                .zIndex(5)
            }

            if coordinator.showingCreateOptions {
                CreateOptionsOverlay(
                    bottomInset: bottomInset,
                    glassNamespace: glassNamespace,
                    isHostedInGlassContainer: sharesNativeGlassContainer,
                    onManualTripCreate: onManualTripCreate,
                    onJoinTrip: onJoinTrip,
                    onDismiss: onDismissCreateOptions
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

    private var dockTransition: AnyTransition {
        let base = AnyTransition.opacity
        guard !reduceMotion else { return base }
        return base.combined(with: .offset(y: AppMotion.fadeSlideOffset))
    }

    private func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<MainTabCoordinator, Value>
    ) -> Binding<Value> {
        Binding(
            get: { coordinator[keyPath: keyPath] },
            set: { coordinator[keyPath: keyPath] = $0 }
        )
    }
}
