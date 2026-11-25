import Foundation
import CoreGraphics
import SwiftUI

/// Expanded vs scroll-collapsed chrome on root tabs (home / memory / profile).
enum AppNavigationChromeMode: Equatable {
    case expanded
    case compact
}

/// Hysteresis policy for the root-tab chrome. Kept pure so the scroll-to-mode
/// transition is testable independently from SwiftUI scroll observation.
enum AppNavigationChromePolicy {
    static func resolvedMode(
        current: AppNavigationChromeMode,
        scrollOffset: CGFloat,
        allowsCompaction: Bool
    ) -> AppNavigationChromeMode {
        guard allowsCompaction else { return .expanded }

        switch current {
        case .expanded:
            return scrollOffset > AppNavigationMetrics.compactScrollThreshold
                ? .compact
                : .expanded
        case .compact:
            return scrollOffset < AppNavigationMetrics.expandScrollThreshold
                ? .expanded
                : .compact
        }
    }
}

/// Shared geometry for the three-destination navigation chrome and detached create action.
enum AppNavigationMetrics {
    // MARK: - Expanded layout

    static let horizontalInset: CGFloat = AppSpacing.cardSmall
    /// Navigation and creation remain visually related without reading as one fused control.
    static let destinationCreateMinimumSeparation: CGFloat = 36
    static let expandedDestinationIslandMaxWidth: CGFloat = 282
    /// Optical grouping distance for the destination and create glass islands on iOS 26+.
    static let glassContainerSpacing: CGFloat = AppSpacing.sm
    /// Shared morphing distance for the create island and its expanded action cluster.
    static let createMenuGlassSpacing: CGFloat = AppSpacing.tight

    static let destinationMinimumHeight: CGFloat = 44
    static let destinationIconSize: CGFloat = 17
    static let destinationIconHeight: CGFloat = 18
    /// Optical lift so the glyph sits above the faded-in label in expanded chrome.
    static let destinationIconExpandedOffsetY: CGFloat = -7
    static let destinationLabelBottomPadding: CGFloat = 5
    static let destinationLensHorizontalInset: CGFloat = 2
    static let expandedDestinationLensHeight: CGFloat = 40
    static let compactDestinationLensHeight: CGFloat = 36

    // MARK: - Creek Dock selection emphasis

    /// Unselected destinations rest quieter; selection is carried by lens + fill + color
    /// (no scale on icons — scale made the previous tab appear to “wiggle” on switch).
    static let unselectedIconOpacity: Double = 0.64
    /// A neutral wash keeps regular Glass legible over both paper and media without adding
    /// another material or restoring the custom outer stroke removed in LG2.
    static let navigationGlassTintOpacity: Double = 0.08
    static let increasedContrastNavigationGlassTintOpacity: Double = 0.14
    /// Thin tint and highlight drawn over native Glass for the moving selection lens.
    static let selectionLensTintOpacity: Double = 0.16
    static let selectionLensHighlightOpacity: Double = 0.34
    static let increasedContrastSelectionLensTintOpacity: Double = 0.24
    static let increasedContrastSelectionLensHighlightOpacity: Double = 0.46
    /// Create-menu cards share the same legibility policy while retaining semantic tint.
    static let createMenuNeutralGlassTintOpacity: Double = 0.12
    static let increasedContrastCreateMenuNeutralGlassTintOpacity: Double = 0.18
    static let createMenuSuccessGlassTintOpacity: Double = 0.16
    static let increasedContrastCreateMenuSuccessGlassTintOpacity: Double = 0.22

    static let createActionSize: CGFloat = 52
    static let createActionBorderWidth: CGFloat = 1.0
    static let createActionGlowRadius: CGFloat = 12
    static let createActionGlowY: CGFloat = 4
    static let createActionGlowOpacity: Double = 0.24

    /// Space between chrome and last content row (expanded).
    static let contentClearance: CGFloat = 16
    /// Large controls and multi-line state cards need one additional row of scroll clearance.
    static let accessibilityContentClearance: CGFloat = 48
    /// Capsule body height when fully expanded.
    static let chromeHeight: CGFloat = 50
    static let chromeCornerRadius: CGFloat = 25
    /// Pull chrome into the home-indicator zone (larger = lower on screen).
    static let bottomInsetAdjustment: CGFloat = 10
    /// Keeps floating controls clear of the physical screen edge on devices without a home indicator.
    static let minimumChromeBottomPadding: CGFloat = AppSpacing.xxs
    /// The expanded menu sits above the collapsed create island to make the unfolding direction legible.
    static let createMenuBottomLift: CGFloat = 18
    static let createMenuMinimumBottomPadding: CGFloat = 28

    // MARK: - Compact (scroll-collapsed) layout

    static let compactChromeHeight: CGFloat = 44
    static let compactCreateActionSize: CGFloat = 46
    static let compactIconSize: CGFloat = 16
    static let compactContentClearance: CGFloat = 12
    static let compactCornerRadius: CGFloat = 22
    static let compactBottomInsetAdjustment: CGFloat = 12
    /// Scroll past this offset → compact; return near top → expanded.
    static let compactScrollThreshold: CGFloat = 36
    static let expandScrollThreshold: CGFloat = 10

    // MARK: - Helpers

    static func chromeHeight(for mode: AppNavigationChromeMode) -> CGFloat {
        mode == .compact ? compactChromeHeight : chromeHeight
    }

    static func createActionSize(for mode: AppNavigationChromeMode) -> CGFloat {
        mode == .compact ? compactCreateActionSize : createActionSize
    }

    static func destinationLensHeight(for mode: AppNavigationChromeMode) -> CGFloat {
        mode == .compact ? compactDestinationLensHeight : expandedDestinationLensHeight
    }

    static func destinationLensVerticalInset(for mode: AppNavigationChromeMode) -> CGFloat {
        max((chromeHeight(for: mode) - destinationLensHeight(for: mode)) / 2, 0)
    }

    static func bottomInsetAdjustment(for mode: AppNavigationChromeMode) -> CGFloat {
        mode == .compact ? compactBottomInsetAdjustment : bottomInsetAdjustment
    }

    static func navigationGlassTintOpacity(forIncreasedContrast increased: Bool) -> Double {
        increased ? increasedContrastNavigationGlassTintOpacity : navigationGlassTintOpacity
    }

    static func selectionLensTintOpacity(forIncreasedContrast increased: Bool) -> Double {
        increased ? increasedContrastSelectionLensTintOpacity : selectionLensTintOpacity
    }

    static func selectionLensHighlightOpacity(forIncreasedContrast increased: Bool) -> Double {
        increased ? increasedContrastSelectionLensHighlightOpacity : selectionLensHighlightOpacity
    }

    static func createMenuNeutralGlassTintOpacity(forIncreasedContrast increased: Bool) -> Double {
        increased ? increasedContrastCreateMenuNeutralGlassTintOpacity : createMenuNeutralGlassTintOpacity
    }

    static func createMenuSuccessGlassTintOpacity(forIncreasedContrast increased: Bool) -> Double {
        increased ? increasedContrastCreateMenuSuccessGlassTintOpacity : createMenuSuccessGlassTintOpacity
    }

    /// Actual distance between the screen edge and floating chrome after optical downshift.
    static func chromeBottomPadding(
        for bottomInset: CGFloat,
        mode: AppNavigationChromeMode
    ) -> CGFloat {
        max(
            max(bottomInset, 0) - bottomInsetAdjustment(for: mode),
            minimumChromeBottomPadding
        )
    }

    static func createMenuBottomPadding(for bottomInset: CGFloat) -> CGFloat {
        max(
            max(bottomInset, 0) + createMenuBottomLift,
            createMenuMinimumBottomPadding
        )
    }

    /// Distance from the physical screen edge to the clearance line above expanded chrome.
    /// Use for root overlays whose alignment space extends to the screen edge (for example, toasts).
    static func overlayBottomPadding(for bottomInset: CGFloat) -> CGFloat {
        chromeBottomPadding(for: bottomInset, mode: .expanded)
            + max(chromeHeight, createActionSize)
            + contentClearance
    }

    /// Extra safe-area inset for scroll content. `safeAreaInset(edge: .bottom)` already starts
    /// above the device safe area, so subtract it once instead of reserving it twice.
    /// Expanded geometry keeps the last row stable when chrome switches to compact mode.
    static func contentInset(for bottomInset: CGFloat) -> CGFloat {
        max(overlayBottomPadding(for: bottomInset) - max(bottomInset, 0), contentClearance)
    }

    static func contentInset(for bottomInset: CGFloat, mode: AppNavigationChromeMode) -> CGFloat {
        // Keep stable list padding; visual chrome may shrink inside the reserved band.
        _ = mode
        return contentInset(for: bottomInset)
    }

    static func contentInset(for bottomInset: CGFloat, accessibilityLayout: Bool) -> CGFloat {
        contentInset(for: bottomInset)
            + (accessibilityLayout ? accessibilityContentClearance : 0)
    }
}

enum AppControlMetrics {
    static let minimumTapTarget: CGFloat = 44
}

/// iOS 18+ reports root-tab scrolling from ScrollGeometry. Earlier systems keep
/// the existing preference-key fallback supplied by each root ScrollView.
struct RootScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RootScrollOffsetReportingModifier: ViewModifier {
    let onOffsetChange: (CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    onOffsetChange(offset)
                }
        } else {
            content
                .onPreferenceChange(RootScrollOffsetKey.self) { offset in
                    onOffsetChange(max(0, offset))
                }
        }
    }
}

extension View {
    func tracciRootScrollOffset(
        onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        modifier(RootScrollOffsetReportingModifier(onOffsetChange: onChange))
    }
}
