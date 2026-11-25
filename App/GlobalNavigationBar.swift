import SwiftUI

/// Four-slot app navigation with a detached global create action.
///
/// **Creek Dock** — floating glass island + create FAB:
/// - Expanded: icons + labels, sliding selection lens
/// - Compact (scroll): real geometry spring (height/padding) — never `scaleEffect` on glass
/// - Selection: spring lens + hierarchical fill morph + one-shot bounce
///
/// Note: `scaleEffect` on Liquid Glass leaves a full-size translucent halo (layout bounds
/// stay large while content shrinks). Compact mode must resize the glass container itself.
struct GlobalNavigationBar: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var localGlassNamespace
    @Namespace private var selectionNamespace

    @Binding var selectedTab: AppTab
    /// 底栏实际占位的四格，由调用方传入。
    let tabs: [AppTab]
    var chromeMode: AppNavigationChromeMode = .expanded
    let bottomInset: CGFloat
    var glassNamespace: Namespace.ID?
    var isHostedInGlassContainer = false
    let onCreate: () -> Void

    private var resolvedGlassNamespace: Namespace.ID {
        glassNamespace ?? localGlassNamespace
    }

    private var isCompact: Bool {
        chromeMode == .compact && !dynamicTypeSize.isAccessibilitySize
    }

    private var chromeModeForLayout: AppNavigationChromeMode {
        isCompact ? .compact : .expanded
    }

    private var capsuleHeight: CGFloat {
        AppNavigationMetrics.chromeHeight(for: chromeModeForLayout)
    }

    private var cornerRadius: CGFloat {
        isCompact ? AppNavigationMetrics.compactCornerRadius : AppNavigationMetrics.chromeCornerRadius
    }

    private var usesNativeLiquidGlass: Bool {
        #if compiler(>=26)
        if #available(iOS 26, *) {
            return !reduceTransparency
        }
        #endif
        return false
    }

    private var chromeSpring: Animation? {
        AppMotion.animation(AppMotion.chromeMode, reduceMotion: reduceMotion)
    }

    private var selectionSpring: Animation? {
        AppMotion.animation(AppMotion.tabSelection, reduceMotion: reduceMotion)
    }

    var body: some View {
        glassAwareChrome
            .padding(.horizontal, AppNavigationMetrics.horizontalInset)
            .padding(
                .bottom,
                AppNavigationMetrics.chromeBottomPadding(
                    for: bottomInset,
                    mode: chromeModeForLayout
                )
            )
            // Parent is safe-area constrained; push chrome into the home-indicator band.
            .offset(y: max(bottomInset, 0))
            .sensoryFeedback(.selection, trigger: selectedTab)
    }

    @ViewBuilder
    private var glassAwareChrome: some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency, !isHostedInGlassContainer {
            GlassEffectContainer(spacing: AppNavigationMetrics.glassContainerSpacing) {
                chromeContent
            }
        } else {
            chromeContent
        }
        #else
        chromeContent
        #endif
    }

    private var chromeContent: some View {
        HStack(alignment: .center, spacing: 0) {
            destinationCapsule
            Spacer(minLength: AppNavigationMetrics.destinationCreateMinimumSeparation)
                .frame(width: AppNavigationMetrics.destinationCreateMinimumSeparation)
            GlobalCreateAction(
                state: .idle,
                chromeMode: chromeModeForLayout,
                glassEffectID: GlobalNavigationGlassID.create,
                glassNamespace: resolvedGlassNamespace,
                action: onCreate
            )
            .accessibilityHint("打开创建和加入旅程选项")
        }
        .frame(maxWidth: .infinity)
    }

    private var destinationCapsule: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, isCompact ? AppSpacing.xxs : AppSpacing.xs)
        .frame(height: capsuleHeight)
        .frame(maxWidth: isCompact ? nil : AppNavigationMetrics.expandedDestinationIslandMaxWidth)
        .background {
            // Clip glass only. Do not scale the glass host — Liquid Glass + scaleEffect
            // leaves a translucent full-size halo outside the shrunk visuals.
            destinationGlassSurface
                .clipShape(Capsule())
        }
        .contentShape(Capsule())
        .modifier(
            GlobalNavigationDepthModifier(
                usesNativeLiquidGlass: usesNativeLiquidGlass,
                cornerRadius: cornerRadius,
                isHighContrast: colorSchemeContrast == .increased
            )
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var destinationGlassSurface: some View {
        let shape = Capsule()

        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            // glassEffectID morphs material across geometry; identity transition avoids
            // rematerialize flashes on continuous compact↔expanded springs.
            shape
                .glassEffect(
                    .regular
                        .tint(
                            Color.white.opacity(
                                AppNavigationMetrics.navigationGlassTintOpacity(
                                    forIncreasedContrast: colorSchemeContrast == .increased
                                )
                            )
                        )
                        .interactive(),
                    in: shape
                )
                .glassEffectID(GlobalNavigationGlassID.destinations, in: resolvedGlassNamespace)
                .glassEffectTransition(.identity)
        } else {
            fallbackDestinationSurface
        }
        #else
        fallbackDestinationSurface
        #endif
    }

    private var fallbackDestinationSurface: some View {
        FloatingGlassBackground(
            cornerRadius: cornerRadius,
            reduceTransparency: reduceTransparency,
            isHighContrast: colorSchemeContrast == .increased,
            style: .navigationChrome
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        let showsLabel = !isCompact && !dynamicTypeSize.isAccessibilitySize
        let iconSize = AppNavigationMetrics.destinationIconSize

        return Button {
            guard selectedTab != tab else { return }
            AppHaptics.selection()
            withAnimation(selectionSpring) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                // Glyph geometry snaps (no spring). `book.pages` multi-layer fill morph +
                // bounce under animation produced an empty frame — read as a flash.
                // Motion stays on the selection lens + tint only.
                tabIcon(for: tab, isSelected: isSelected, iconSize: iconSize)
                    .opacity(isSelected ? 1 : AppNavigationMetrics.unselectedIconOpacity)
                    .offset(y: showsLabel ? AppNavigationMetrics.destinationIconExpandedOffsetY : 0)
                    .transaction { transaction in
                        transaction.animation = nil
                    }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(tab.title)
                        .font(isSelected ? AppTypography.chipSemibold : AppTypography.chip)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(showsLabel ? 1 : 0)
                        .offset(y: showsLabel ? 0 : 4)
                        .padding(.bottom, AppNavigationMetrics.destinationLabelBottomPadding)
                        .accessibilityHidden(!showsLabel)
                }
            }
            .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textSecondary)
            .frame(width: isCompact ? 44 : nil, height: capsuleHeight)
            .frame(maxWidth: isCompact ? nil : .infinity)
            .background {
                if isSelected {
                    selectionIndicator
                        .matchedGeometryEffect(id: "global-navigation-selection-lens", in: selectionNamespace)
                        .padding(
                            .vertical,
                            AppNavigationMetrics.destinationLensVerticalInset(for: chromeModeForLayout)
                        )
                        .padding(.horizontal, AppNavigationMetrics.destinationLensHorizontalInset)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle(scale: 0.96, opacity: 0.88))
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("global-navigation-\(tab.accessibilityIdentifier)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "当前页面" : "切换到\(tab.title)")
    }

    /// Outline + fill via `symbolVariant`, but never animated: multi-layer symbols
    /// (especially `book.pages`) can drop a blank raster mid-morph under spring.
    private func tabIcon(for tab: AppTab, isSelected: Bool, iconSize: CGFloat) -> some View {
        Image(systemName: tab.systemImage)
            .symbolVariant(isSelected ? .fill : .none)
            .font(AppFont.system(iconSize, weight: isSelected ? .semibold : .regular))
            .symbolRenderingMode(.monochrome)
            .contentTransition(.identity)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        let shape = Capsule()

        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            let lens = shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(
                                AppNavigationMetrics.selectionLensHighlightOpacity(
                                    forIncreasedContrast: colorSchemeContrast == .increased
                                )
                            ),
                            AppColors.brandPrimary.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .glassEffect(
                    .clear
                        .tint(
                            AppColors.brandPrimary.opacity(
                                AppNavigationMetrics.selectionLensTintOpacity(
                                    forIncreasedContrast: colorSchemeContrast == .increased
                                )
                            )
                        )
                        .interactive(),
                    in: shape
                )

            if reduceMotion {
                lens
            } else {
                lens.glassEffectID(GlobalNavigationGlassID.selection, in: resolvedGlassNamespace)
            }
        } else {
            fallbackSelectionIndicator(shape: shape)
        }
        #else
        fallbackSelectionIndicator(shape: shape)
        #endif
    }

    private func fallbackSelectionIndicator(shape: Capsule) -> some View {
        shape
            .fill(AppColors.brandPrimaryBackground.opacity(reduceTransparency ? 1 : 0.94))
            .overlay {
                shape.stroke(AppColors.brandPrimary.opacity(0.14), lineWidth: 0.6)
            }
    }
}

enum GlobalNavigationGlassID {
    static let destinations = "global-navigation-destinations"
    static let selection = "global-navigation-selection"
    static let create = "global-navigation-create"
}

/// Native Liquid Glass supplies its own edge lighting and depth. The custom highlight and
/// elevation remain only for material/solid fallbacks where the system does not render them.
private struct GlobalNavigationDepthModifier: ViewModifier {
    let usesNativeLiquidGlass: Bool
    let cornerRadius: CGFloat
    let isHighContrast: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesNativeLiquidGlass {
            content
        } else {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            Color.white.opacity(isHighContrast ? 0.82 : 0.55),
                            lineWidth: isHighContrast ? 1.0 : 0.65
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
                .tracciElevation(.l2)
        }
    }
}

#Preview("Global Navigation · Creek Dock") {
    @Previewable @State var selectedTab: AppTab = .home
    @Previewable @State var chromeMode: AppNavigationChromeMode = .expanded

    VStack(spacing: 28) {
        Spacer()
        Text("Expanded")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        GlobalNavigationBar(
            selectedTab: $selectedTab,
            tabs: AppTab.dockTabs,
            chromeMode: .expanded,
            bottomInset: 34,
            onCreate: {}
        )
        Text("Compact")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
        GlobalNavigationBar(
            selectedTab: $selectedTab,
            tabs: AppTab.dockTabs,
            chromeMode: .compact,
            bottomInset: 34,
            onCreate: {}
        )
        Button(chromeMode == .expanded ? "预览收起" : "预览展开") {
            withAnimation(AppMotion.chromeMode) {
                chromeMode = chromeMode == .expanded ? .compact : .expanded
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.brandPrimary)
        GlobalNavigationBar(
            selectedTab: $selectedTab,
            tabs: AppTab.dockTabs,
            chromeMode: chromeMode,
            bottomInset: 34,
            onCreate: {}
        )
    }
    .background(AppColors.creekMistBottom)
}

#Preview("Global Navigation · Rich Background") {
    @Previewable @State var selectedTab: AppTab = .export

    ZStack(alignment: .bottom) {
        LinearGradient(
            colors: [
                Color(hex: 0x17233A),
                AppColors.stagePlanning,
                AppColors.dawnGold.opacity(0.78),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        GlobalNavigationBar(
            selectedTab: $selectedTab,
            tabs: AppTab.dockTabs,
            chromeMode: .expanded,
            bottomInset: 34,
            onCreate: {}
        )
    }
}

#Preview("Global Navigation · Accessibility") {
    @Previewable @State var selectedTab: AppTab = .profile

    GlobalNavigationBar(
        selectedTab: $selectedTab,
        tabs: AppTab.dockTabs,
        chromeMode: .compact,
        bottomInset: 0,
        onCreate: {}
    )
    .padding(.top, 180)
    .background(AppColors.creekMistBottom)
    .environment(\.dynamicTypeSize, .accessibility5)
}
