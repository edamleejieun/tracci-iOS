import SwiftUI

struct CreateOptionsOverlay: View {
    let bottomInset: CGFloat
    var glassNamespace: Namespace.ID?
    var isHostedInGlassContainer = false
    let onManualTripCreate: () -> Void
    let onJoinTrip: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var localGlassNamespace
    @State private var appeared = false

    private var resolvedGlassNamespace: Namespace.ID {
        glassNamespace ?? localGlassNamespace
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onDismiss) {
                overlayBackground
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭新建菜单")

            glassAwareMenu
                .padding(.trailing, AppSpacing.pageX)
                .padding(.bottom, AppNavigationMetrics.createMenuBottomPadding(for: bottomInset))
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(AppMotion.animation(AppMotion.morphOpen, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var glassAwareMenu: some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency, !isHostedInGlassContainer {
            GlassEffectContainer(spacing: AppNavigationMetrics.createMenuGlassSpacing) {
                menuContent
            }
        } else {
            menuContent
        }
        #else
        menuContent
        #endif
    }

    private var menuContent: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.tight) {
            CreateOptionCard(
                title: "手动新建旅程",
                subtitle: "从目的地和日期开始",
                systemImage: "square.and.pencil",
                style: .standard,
                glassEffectID: CreateMenuGlassID.manual,
                glassNamespace: resolvedGlassNamespace,
                action: onManualTripCreate
            )
            .createOptionMotion(isAppeared: appeared, index: 0, reduceMotion: reduceMotion)

            CreateOptionCard(
                title: "输入邀请码加入",
                subtitle: "和朋友一起规划旅行",
                systemImage: "person.badge.plus",
                style: .success,
                glassEffectID: CreateMenuGlassID.join,
                glassNamespace: resolvedGlassNamespace,
                action: onJoinTrip
            )
            .createOptionMotion(isAppeared: appeared, index: 1, reduceMotion: reduceMotion)

            GlobalCreateAction(
                state: .expanded,
                glassEffectID: GlobalNavigationGlassID.create,
                glassNamespace: resolvedGlassNamespace,
                action: onDismiss
            )
        }
    }

    @ViewBuilder
    private var overlayBackground: some View {
        ZStack {
            if reduceTransparency {
                Rectangle().fill(AppColors.backgroundGrouped.opacity(0.96))
            } else {
                Rectangle().fill(.regularMaterial)
            }

            Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12)
        }
    }
}

private struct CreateOptionCard: View {
    enum Style {
        case standard
        case success
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let style: Style
    /// 同 style 的卡出现多张时用它区分；缺省按 style 给。
    var accessibilityID: String?
    var glassEffectID: String?
    var glassNamespace: Namespace.ID?
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var usesNativeLiquidGlass: Bool {
        #if compiler(>=26)
        if #available(iOS 26, *) {
            return !reduceTransparency
        }
        #endif
        return false
    }

    var body: some View {
        Button(action: action) {
            cardSurface
        }
        .buttonStyle(PressableCardStyle(scale: 0.975, opacity: 0.94))
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var cardSurface: some View {
        if usesNativeLiquidGlass {
            nativeGlassCard
        } else {
            AppGlassSurface(radius: AppRadius.hero, padding: 0) {
                cardContent
            }
        }
    }

    @ViewBuilder
    private var nativeGlassCard: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)

        #if compiler(>=26)
        if #available(iOS 26, *) {
            cardContent
                .background {
                    let surface = shape
                        .glassEffect(.regular.tint(nativeGlassTint).interactive(), in: shape)

                    if let glassEffectID, let glassNamespace {
                        surface
                            .glassEffectID(glassEffectID, in: glassNamespace)
                            .glassEffectTransition(.materialize)
                    } else {
                        surface
                            .glassEffectTransition(.materialize)
                    }
                }
                .clipShape(shape)
        }
        #endif
    }

    private var nativeGlassTint: Color {
        switch style {
        case .standard:
            Color.white.opacity(
                AppNavigationMetrics.createMenuNeutralGlassTintOpacity(
                    forIncreasedContrast: colorSchemeContrast == .increased
                )
            )
        case .success:
            AppColors.success.opacity(
                AppNavigationMetrics.createMenuSuccessGlassTintOpacity(
                    forIncreasedContrast: colorSchemeContrast == .increased
                )
            )
        }
    }

    private var cardContent: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppFont.system(16, weight: .bold, design: .rounded))
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(AppTypography.label)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: systemImage)
                .font(AppFont.system(18, weight: .bold, design: .rounded))
                .foregroundStyle(iconColor)
                .frame(width: 38, height: 38)
                .background(iconBackground)
                .clipShape(Circle())
        }
        .padding(.leading, AppSpacing.card)
        .padding(.trailing, AppSpacing.cardSmall)
        .padding(.vertical, AppSpacing.xxs)
        .frame(width: 272)
        .frame(minHeight: 76)
    }

    private var titleColor: Color {
        AppColors.textPrimary
    }

    private var subtitleColor: Color {
        AppColors.textSecondary
    }

    private var iconColor: Color {
        switch style {
        case .standard:
            return AppColors.brandPrimary
        case .success:
            return AppColors.successForeground
        }
    }

    private var iconBackground: Color {
        switch style {
        case .standard:
            return AppColors.brandPrimaryBackground
        case .success:
            return AppColors.success.opacity(0.12)
        }
    }

    private var accessibilityIdentifier: String {
        if let accessibilityID { return accessibilityID }
        switch style {
        case .standard: return "global-create-option-manual"
        case .success: return "global-create-option-join"
        }
    }

}

private enum CreateMenuGlassID {
    static let manual = "global-create-menu-manual"
    static let join = "global-create-menu-join"
}

private struct CreateOptionMotionModifier: ViewModifier {
    let isAppeared: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isAppeared ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isAppeared ? 0 : AppMotion.milestoneOffset))
            .scaleEffect(isAppeared || reduceMotion ? 1 : AppMotion.modalOpenScale, anchor: .bottomTrailing)
            .animation(
                AppMotion.animation(
                    AppMotion.milestoneSpring.delay(reduceMotion ? 0 : Double(index) * AppMotion.listStaggerDelay),
                    reduceMotion: reduceMotion
                ),
                value: isAppeared
            )
    }
}

private extension View {
    func createOptionMotion(isAppeared: Bool, index: Int, reduceMotion: Bool) -> some View {
        modifier(CreateOptionMotionModifier(isAppeared: isAppeared, index: index, reduceMotion: reduceMotion))
    }
}

private struct CreateOptionsOverlayPreview: View {
    var body: some View {
        CreateOptionsOverlay(
            bottomInset: 34,
            onManualTripCreate: {},
            onJoinTrip: {},
            onDismiss: {}
        )
    }
}

#Preview("Create Options · Native Glass") {
    CreateOptionsOverlayPreview()
}

