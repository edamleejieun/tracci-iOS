import SwiftUI
import UIKit

enum TripDetailTab: String, CaseIterable, Identifiable {
    /// Workspace surfaces: overview is selected from the primary scope rail;
    /// these three modes are secondary to a selected Day.
    case overview
    case itinerary
    case expense
    case journal

    var id: String { rawValue }

    static let dayDisplayOrder: [TripDetailTab] = [.itinerary, .journal, .expense]

    var title: String {
        switch self {
        case .overview: "总览"
        case .itinerary: "行程"
        case .expense: "开支"
        case .journal: "日志"
        }
    }

    /// SF Symbol for the secondary day-mode tab.
    /// Prefer simple, similar-mass outline glyphs so optical size matches Chinese labels;
    /// avoid dense multi-part symbols and map glyphs (Hero owns cover/map).
    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .itinerary: "list.bullet"
        case .journal: "book"
        case .expense: "yensign"
        }
    }

    /// Stage-aware default when opening trip detail from home (not deep links).
    /// Completed trips with journals open on the story surface; otherwise itinerary.
    static func preferred(for trip: Trip) -> TripDetailTab {
        if trip.effectiveStatus == .completed, (trip.journalCount ?? 0) > 0 {
            return .journal
        }
        return .itinerary
    }
}

struct TripDetailNavigationRequest: Equatable {
    let tripId: String
    let initialTab: TripDetailTab
}

/// Secondary view switcher for a selected Day.
///
/// Interaction borrows X’s “icon by default, icon + label when selected” pattern
/// without changing Day Rail / overview scope selection.
/// Selected state stays light (ink + short accent) so it does not compete with
/// Day Rail’s filled selection chips above.
struct TripDetailTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: TripDetailTab
    var isCompact: Bool = false
    @Namespace private var selectionNamespace

    private var forcesExpandedLabels: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            // Glass lens container: the selected indicator is a small Liquid Glass
            // capsule that morphs between tabs (G5.2), same language as the dock
            // selection lens. Falls back to the flat brand underline otherwise.
            GlassEffectContainer {
                tabBarContent
            }
        } else {
            tabBarContent
        }
        #else
        tabBarContent
        #endif
    }

    private var tabBarContent: some View {
        HStack(spacing: 0) {
            ForEach(TripDetailTab.dayDisplayOrder) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, TripDetailLayout.pageInset)
        .padding(.vertical, 4)
        .frame(minHeight: isCompact ? TripDetailLayout.tabBarCompactHeight : TripDetailLayout.tabBarHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当日内容：行程、日志、开支")
    }

    private func tabButton(_ tab: TripDetailTab) -> some View {
        let isSelected = selectedTab == tab
        let showsLabel = isSelected || forcesExpandedLabels

        return Button {
            guard !isSelected else { return }
            AppHaptics.selection()
            withAnimation(tabSwitchAnimation) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                HStack(alignment: .center, spacing: 5) {
                    // Fixed optical box: keeps mixed SF Symbols aligned with Chinese labels
                    // and prevents layout jump when selection weight changes.
                    Image(systemName: tab.systemImage)
                        .font(isSelected ? TripDetailTypography.tabIconSelected : TripDetailTypography.tabIcon)
                        .symbolRenderingMode(.monochrome)
                        .frame(
                            width: TripDetailLayout.tabIconOpticalSize,
                            height: TripDetailLayout.tabIconOpticalSize,
                            alignment: .center
                        )

                    if showsLabel {
                        Text(tab.title)
                            .font(isSelected ? TripDetailTypography.modeOptionSelected : TripDetailTypography.modeOption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: true, vertical: false)
                            .transition(labelTransition)
                    }
                }
                // Stable row height so icon-only ↔ icon+label does not reflow vertically.
                .frame(height: TripDetailLayout.tabIconOpticalSize + 2, alignment: .center)

                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .frame(height: 2.5)

                    if isSelected {
                        selectionIndicator(showsLabel: showsLabel)
                    }
                }
            }
            .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppControlMetrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle(scale: AppMotion.pressScale, opacity: AppMotion.pressOpacity))
        .accessibilityLabel(tab.title)
        .accessibilityHint(isSelected ? "当前正在查看\(tab.title)" : "切换到\(tab.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tabSwitchAnimation: Animation? {
        AppMotion.animation(.easeInOut(duration: 0.24), reduceMotion: reduceMotion)
    }

    /// Selected indicator: a small Liquid Glass lens morphing across tabs on
    /// iOS 26 (G5.2); the flat brand underline everywhere else. Both stay light
    /// so the Day Rail's filled selection chips keep the primary weight.
    @ViewBuilder
    private func selectionIndicator(showsLabel: Bool) -> some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            Capsule()
                .fill(AppColors.brandPrimary.opacity(0.9))
                .frame(width: showsLabel ? 30 : 16, height: 5)
                .glassEffect(.regular.tint(AppColors.brandPrimary.opacity(0.30)), in: Capsule())
                .glassEffectID("day-view-lens", in: selectionNamespace)
        } else {
            legacyUnderline(showsLabel: showsLabel)
        }
        #else
        legacyUnderline(showsLabel: showsLabel)
        #endif
    }

    private func legacyUnderline(showsLabel: Bool) -> some View {
        Capsule()
            .fill(AppColors.brandPrimary)
            .frame(width: showsLabel ? 28 : 14, height: 2.5)
            .matchedGeometryEffect(id: "selected-day-view-accent", in: selectionNamespace)
    }

    /// Label appears from the icon’s trailing edge; exit is slightly faster via easeInOut pair.
    private var labelTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .leading)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
        )
    }
}
