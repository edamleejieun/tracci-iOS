import SwiftUI
import UIKit

enum SafeAreaMetrics {
    /// Top safe area inset from the key window.
    /// Use when an ancestor applies `ignoresSafeArea(edges: .top)` and GeometryReader reports 0.
    static var top: CGFloat {
        resolveTopInset(geometryInset: 0)
    }

    /// Bottom safe area inset from the key window.
    /// Use for custom floating controls that are overlaid outside a child view.
    static var bottom: CGFloat {
        resolveBottomInset(geometryInset: 0)
    }

    /// Top padding for custom chrome on pushed / immersive pages.
    static func chromeTopPadding(using inset: CGFloat? = nil) -> CGFloat {
        max(16, (inset ?? top) + 8)
    }

    /// Top padding for sheet-hosted form chrome (sheet owns the status-bar region).
    static let sheetChromeTopPadding: CGFloat = 16

    /// Picks the best available top inset during navigation / sheet transitions.
    ///
    /// Immersive full-screen surfaces (`ignoresSafeArea`) often get `GeometryReader` insets of 0;
    /// fall back across all windows and the scene status-bar frame so chrome stays below the clock.
    static func resolveTopInset(geometryInset: CGFloat) -> CGFloat {
        var best = geometryInset
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden && window.alpha > 0 {
                best = max(best, window.safeAreaInsets.top)
            }
            let statusHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0
            if statusHeight > 0 {
                best = max(best, statusHeight)
            }
        }
        return best
    }

    /// Picks the best available bottom inset during root-tab and overlay transitions.
    /// Geometry can briefly report zero while a sheet or navigation host is changing.
    static func resolveBottomInset(geometryInset: CGFloat) -> CGFloat {
        var best = geometryInset
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden && window.alpha > 0 {
                best = max(best, window.safeAreaInsets.bottom)
            }
        }
        return best
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static var foregroundWindow: UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            if let key = windowScene.windows.first(where: \.isKeyWindow) {
                return key
            }
            if let visible = windowScene.windows.first(where: { !$0.isHidden && $0.alpha > 0 }) {
                return visible
            }
        }
        return nil
    }
}

// MARK: - Chrome Presentation

/// Controls how custom top chrome accounts for the status-bar safe area.
///
/// - `sheet`: System sheet provides top inset — use modest fixed padding only.
/// - `pushed`: Navigation child after an immersive parent may lose safe area — pair with
///   `tracciFormChromePage(presentation:)` and `FormSheetTopBar(presentation: .pushed)`.
enum FormChromePresentation {
    case sheet
    case pushed
}

// MARK: - Layout Modifiers

extension View {
    /// Pushed form pages that hide the navigation bar and draw custom top chrome.
    func tracciPushedChromePage() -> some View {
        ignoresSafeArea(edges: .top)
    }

    /// Immersive hero scroll surfaces (e.g. trip detail) that extend under the status bar.
    /// Always position chrome with `SafeAreaMetrics.top`, never negative top padding alone.
    func tracciImmersiveHeroScroll() -> some View {
        ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    func tracciFormChromePage(presentation: FormChromePresentation) -> some View {
        switch presentation {
        case .sheet:
            self
        case .pushed:
            tracciPushedChromePage()
        }
    }

    /// Inline-title pages pushed from stacks whose root hides the navigation bar
    /// (Home, Profile, Trip detail, etc.). Restores the system bar and offsets scroll
    /// content so it does not sit under the inline title. Safe to apply when layout is
    /// already correct — compensation resolves to zero.
    func tracciNavigationSubpage(background: Color = AppColors.backgroundGrouped) -> some View {
        modifier(NavigationSubpageModifier(background: background))
    }

    /// Keeps a binding in sync with the container's top safe-area inset.
    /// Pair with `SafeAreaMetrics.top` on immersive pages that ignore the top safe area.
    func tracciReadsSafeAreaTop(_ topInset: Binding<CGFloat>) -> some View {
        background {
            SafeAreaTopInsetReader(topInset: topInset)
        }
    }
}

// MARK: - Navigation Subpage

/// Restores the system navigation bar on pages pushed from a hidden-bar root
/// (Home / Profile / Memory, etc.).
///
/// Do **not** add manual top padding here. NavigationStack already lays content below
/// the inline bar. A GeometryReader behind `background.ignoresSafeArea()` often reports
/// `minY == 0` even when layout is correct, which used to inject a permanent ~safeArea+44
/// blank band under the title (visible on 全部旅程 and other subpages).
private struct NavigationSubpageModifier: ViewModifier {
    let background: Color

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                background.ignoresSafeArea()
            }
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Safe Area Reader

/// Reads top safe-area from the SwiftUI container and refreshes after navigation transitions.
private struct SafeAreaTopInsetReader: View {
    @Binding var topInset: CGFloat

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.top
            } action: { geometryInset in
                applyResolvedInset(geometryInset)
            }
            .onAppear {
                applyResolvedInset(0)
                scheduleTransitionRetries()
            }
    }

    private func applyResolvedInset(_ geometryInset: CGFloat) {
        let resolved = SafeAreaMetrics.resolveTopInset(geometryInset: geometryInset)
        guard resolved > 0 else { return }
        if abs(topInset - resolved) > 0.5 {
            topInset = resolved
        }
    }

    private func scheduleTransitionRetries() {
        for delay in [0.05, 0.15, 0.35] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let resolved = SafeAreaMetrics.top
                guard resolved > 0 else { return }
                if abs(topInset - resolved) > 0.5 {
                    topInset = resolved
                }
            }
        }
    }
}
