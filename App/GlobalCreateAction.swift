import SwiftUI

/// Shared visual shell for the global create entry.
struct GlobalCreateAction: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum State {
        case idle
        case expanded
    }

    let state: State
    var chromeMode: AppNavigationChromeMode = .expanded
    var glassEffectID: String?
    var glassNamespace: Namespace.ID?
    let action: () -> Void

    /// Real size for each chrome mode — avoid scaleEffect on glass (leaves a translucent halo).
    private var size: CGFloat {
        AppNavigationMetrics.createActionSize(for: chromeMode)
    }

    private var usesNativeLiquidGlass: Bool {
        #if compiler(>=26)
        if #available(iOS 26, *) {
            return !reduceTransparency
        }
        #endif
        return false
    }

    var body: some View {
        Button {
            AppHaptics.lightImpact()
            action()
        } label: {
            Image(systemName: "plus")
                .font(AppFont.system(chromeMode == .compact ? 18 : 20, weight: .semibold, design: .rounded))
                .foregroundStyle(foregroundColor)
                .frame(width: size, height: size)
                .background { createSurface }
                .overlay {
                    if !usesNativeLiquidGlass {
                        Circle()
                            .stroke(borderColor, lineWidth: AppNavigationMetrics.createActionBorderWidth)
                    }
                }
                .contentShape(Circle())
                .rotationEffect(.degrees(state == .expanded && !reduceMotion ? 45 : 0))
        }
        .buttonStyle(PressableCardStyle(scale: 0.93, opacity: 0.9))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(state == .idle ? "global-create-action" : "global-create-close")
        .modifier(
            GlobalCreateActionDepthModifier(
                usesNativeLiquidGlass: usesNativeLiquidGlass,
                state: state,
                glowColor: idleGlowColor
            )
        )
        .animation(
            AppMotion.animation(
                state == .expanded ? AppMotion.morphOpen : AppMotion.morphClose,
                reduceMotion: reduceMotion
            ),
            value: state
        )
        .animation(AppMotion.animation(AppMotion.chromeMode, reduceMotion: reduceMotion), value: chromeMode)
    }

    @ViewBuilder
    private var createSurface: some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            if let glassEffectID, let glassNamespace, !reduceMotion {
                Circle()
                    .glassEffect(.regular.tint(backgroundColor).interactive(), in: Circle())
                    .glassEffectID(glassEffectID, in: glassNamespace)
            } else {
                Circle()
                    .glassEffect(.regular.tint(backgroundColor).interactive(), in: Circle())
                    .glassEffectTransition(reduceMotion ? .identity : .materialize)
            }
        } else {
            Circle().fill(backgroundColor)
        }
        #else
        Circle().fill(backgroundColor)
        #endif
    }

    private var foregroundColor: Color {
        switch state {
        case .idle: AppColors.textPrimaryInverse
        case .expanded: AppColors.brandPrimary
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .idle: AppColors.brandPrimary
        case .expanded: AppColors.brandPrimaryBackground.opacity(0.96)
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle: Color.white.opacity(0.78)
        case .expanded: AppColors.brandPrimary.opacity(0.18)
        }
    }

    private var idleGlowColor: Color {
        switch state {
        case .idle: AppColors.brandPrimary.opacity(AppNavigationMetrics.createActionGlowOpacity)
        case .expanded: Color.clear
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "新建旅程"
        case .expanded: "关闭新建菜单"
        }
    }
}

/// Avoids stacking custom glow/elevation over the depth already rendered by native Glass.
/// Earlier systems and Reduce Transparency retain the established solid-button treatment.
private struct GlobalCreateActionDepthModifier: ViewModifier {
    let usesNativeLiquidGlass: Bool
    let state: GlobalCreateAction.State
    let glowColor: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesNativeLiquidGlass {
            content
        } else {
            content
                .shadow(
                    color: glowColor,
                    radius: AppNavigationMetrics.createActionGlowRadius,
                    x: 0,
                    y: AppNavigationMetrics.createActionGlowY
                )
                .tracciElevation(state == .expanded ? .l1 : .l2)
        }
    }
}

#Preview("Global Create Action") {
    HStack(spacing: AppSpacing.lg) {
        GlobalCreateAction(state: .idle, chromeMode: .expanded, action: {})
        GlobalCreateAction(state: .idle, chromeMode: .compact, action: {})
        GlobalCreateAction(state: .expanded, action: {})
    }
    .padding(AppSpacing.xl)
    .background(AppColors.creekMistBottom)
}
