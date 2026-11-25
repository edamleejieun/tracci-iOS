import SwiftUI
import UIKit

// MARK: - Trip Detail Typography Scale
//
// Five content levels + chrome utilities. Avoid ad-hoc .system(size:) on this page.
// Weights: semibold (emphasis) · medium (labels) · regular (body)

/// Trip detail type scale. All tokens scale with Dynamic Type (default-category sizes preserved).
enum TripDetailTypography {
    // L1 — Hero
    static var heroTitle: Font { AppFont.scaled(size: 24, weight: .semibold, relativeTo: .title2) }
    static var heroMeta: Font { AppFont.scaled(size: 13, weight: .regular, relativeTo: .footnote) }
    static var heroChip: Font { AppFont.scaled(size: 11, weight: .medium, relativeTo: .caption2) }

    // L2 — Metrics
    static var statValue: Font { AppFont.scaled(size: 18, weight: .semibold, relativeTo: .headline) }
    static var statLabel: Font { AppFont.scaled(size: 11, weight: .medium, relativeTo: .caption2) }

    // Mode switcher — icon and label share the same design size so Chinese text
    // and SF Symbols read as one optical line (select only changes weight/color).
    static var modeCaption: Font { AppFont.scaled(size: 12, weight: .regular, relativeTo: .caption) }
    static var modeOption: Font { AppFont.scaled(size: 14, weight: .medium, relativeTo: .subheadline) }
    static var modeOptionSelected: Font { AppFont.scaled(size: 14, weight: .semibold, relativeTo: .subheadline) }
    /// Same design size as `modeOption` so icon + 文案 baseline-align; weight only for selection.
    static var tabIcon: Font { AppFont.scaled(size: 14, weight: .medium, relativeTo: .subheadline) }
    static var tabIconSelected: Font { AppFont.scaled(size: 14, weight: .semibold, relativeTo: .subheadline) }
    // Day navigation
    static var railEyebrow: Font { AppFont.scaled(size: 11, weight: .medium, relativeTo: .caption2) }
    static var dayDate: Font { AppFont.scaled(size: 14, weight: .medium, relativeTo: .subheadline) }
    static var dayDateSelected: Font { AppFont.scaled(size: 14, weight: .semibold, relativeTo: .subheadline) }
    static var dayWeekday: Font { AppFont.scaled(size: 11, weight: .regular, relativeTo: .caption2) }
    static var dayWeekdaySelected: Font { AppFont.scaled(size: 11, weight: .medium, relativeTo: .caption2) }
    static var dayBadge: Font { AppFont.scaled(size: 10, weight: .semibold, relativeTo: .caption2) }
    static var compactDate: Font { AppFont.scaled(size: 14, weight: .semibold, relativeTo: .subheadline) }
    static var compactWeekday: Font { AppFont.scaled(size: 12, weight: .regular, relativeTo: .caption) }

    // L3–L5 — Content
    static var sectionEyebrow: Font { AppFont.scaled(size: 12, weight: .medium, relativeTo: .caption) }
    static var contentTitle: Font { AppFont.scaled(size: 15, weight: .medium, relativeTo: .callout) }
    static var body: Font { AppFont.scaled(size: 13, weight: .regular, relativeTo: .footnote) }
    static var bodyMedium: Font { AppFont.scaled(size: 13, weight: .medium, relativeTo: .footnote) }
    static var caption: Font { AppFont.scaled(size: 12, weight: .regular, relativeTo: .caption) }
    static var captionMedium: Font { AppFont.scaled(size: 12, weight: .medium, relativeTo: .caption) }

    // Timeline nodes
    static var nodeTitle: Font { AppFont.scaled(size: 15, weight: .medium, relativeTo: .callout) }
    static var nodeMeta: Font { AppFont.scaled(size: 12, weight: .regular, relativeTo: .caption) }
    static var nodeMetaMedium: Font { AppFont.scaled(size: 12, weight: .medium, relativeTo: .caption) }
    static var nodeTag: Font { AppFont.scaled(size: 10, weight: .medium, relativeTo: .caption2) }
    static var timelineSequence: Font { AppFont.scaled(size: 10, weight: .semibold, relativeTo: .caption2) }

    // Chrome — collapsed nav, toast, header actions
    static var chromeTitle: Font { AppFont.scaled(size: 15, weight: .semibold, relativeTo: .callout) }
    static var chromeIcon: Font { AppFont.scaled(size: 15, weight: .semibold, relativeTo: .callout) }
    static var toast: Font { AppFont.scaled(size: 13, weight: .medium, relativeTo: .footnote) }

    // FAB menu
    static var fabGlyph: Font { AppFont.scaled(size: 18, weight: .medium, relativeTo: .headline) }
    static var fabMenuPrimary: Font { AppFont.scaled(size: 15, weight: .semibold, relativeTo: .callout) }
    static var fabMenuSecondary: Font { AppFont.scaled(size: 15, weight: .medium, relativeTo: .callout) }
    static var fabMenuCaption: Font { AppFont.scaled(size: 12, weight: .regular, relativeTo: .caption) }
    static var fabMenuIcon: Font { AppFont.scaled(size: 16, weight: .semibold, relativeTo: .callout) }

    // Micro utilities
    static var emptyStateIcon: Font { AppFont.scaled(size: 28, weight: .light, relativeTo: .title3) }
    static var microChevron: Font { AppFont.scaled(size: 10, weight: .semibold, relativeTo: .caption2) }
    static var inlineIcon: Font { AppFont.scaled(size: 12, weight: .medium, relativeTo: .caption) }
}

// MARK: - Trip Detail Layout Rhythm

enum TripDetailLayout {
    static let pageInset: CGFloat = AppSpacing.pageX

    static let timelineGutter: CGFloat = 22
    static let timelineSequenceDotSize: CGFloat = 16
    static let timelineHollowDotSize: CGFloat = 7
    static let timelineDotSpacing: CGFloat = 6
    static var timelineContentLeading: CGFloat { timelineGutter + timelineDotSpacing }

    /// Leading inset inside the feed column when the day route timeline rail is active.
    static func feedContentLeading(usesTimelineRail: Bool) -> CGFloat {
        usesTimelineRail ? timelineContentLeading : 0
    }

    /// Spacing between peer modules in the day feed (map, nodes, lists).
    static let moduleSpacing: CGFloat = 14
    /// Spacing between major narrative blocks (execution ↔ stream).
    static let sectionSpacing: CGFloat = 18
    static let railTrackRadius: CGFloat = 14
    static let routeMapTopRadius: CGFloat = 10
    static let routeMapToTimelineSpacing: CGFloat = 14

    // MARK: Timeline depth layering (P3 — soft depth for node states)
    /// Leading accent bar width on timeline node cards.
    static let timelineAccentBarWidth: CGFloat = 3
    /// Completed nodes recede visually — lowered opacity signals "already flowed past".
    static let timelineCompletedOpacity: Double = 0.82
    /// Corner radius for timeline node cards.
    static let timelineNodeRadius: CGFloat = AppRadius.small
    /// Secondary day-mode tab strip — visual height; hit targets remain ≥44 via tab buttons.
    static let tabBarHeight: CGFloat = 42
    static let tabBarCompactHeight: CGFloat = 40
    static let tabCardSpacing: CGFloat = 0
    /// Fixed optical box for day-mode tab glyphs so mixed SF Symbols share width/height.
    static let tabIconOpticalSize: CGFloat = 18

    /// Space between pinned Day workspace header and the feed body.
    /// Hero sits directly above the workspace; trip metrics live in 洞察 Sheet.
    static let feedTopPadding: CGFloat = AppSpacing.md

    static let chromeIconSize: CGFloat = 36
    static let fabSize: CGFloat = 48
    static let fabIdleOpacityEmpty: Double = 1
    static let fabIdleOpacityWithContent: Double = 0.94
    static let fabScrollingOpacity: Double = 0.50
    static let fabScrollingPeekOffset: CGFloat = 10
    static let fabScrollIdleDelay: Duration = .milliseconds(500)
    static let fabBorderOpacity: CGFloat = 0.10
    static let fabMenuWidth: CGFloat = 252
    static let fabMenuPrimaryHeight: CGFloat = 72
    static let fabMenuSecondaryHeight: CGFloat = 64

    // Ongoing-day execution focus — slightly shorter map band so the card doesn't dominate
    static let executionMapHeight: CGFloat = 96
    static let executionMapDecorationSize: CGFloat = 48

    static let emptyStateMinHeightFloor: CGFloat = 280
    static let controlBandHeight: CGFloat = 132
    static let collapsedNavBodyHeight: CGFloat = 54

    /// Day count at or below this uses equal-width rail cells instead of horizontal scroll.
    static let dayRailCompactMaxDays = 5

    /// Top chrome when the control band is pinned: status bar + collapsed overlay nav.
    static func emptyStatePinnedTopClearance(topSafeInset: CGFloat) -> CGFloat {
        topSafeInset + collapsedNavBodyHeight
    }

    /// Minimum height so a full-day empty state still fills the remaining viewport
    /// below pinned chrome and above the FAB. Content itself is top-aligned; do not
    /// vertically center, or shorter completed / journal cards will sit lower.
    static func emptyStateMinHeight(topSafeInset: CGFloat, bottomSafeInset: CGFloat) -> CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        let fabClearance = fabSize + 32 + bottomSafeInset
        let topChrome = emptyStatePinnedTopClearance(topSafeInset: topSafeInset) + controlBandHeight
        let available = screenHeight - topChrome - fabClearance
        let balancedTarget = available * 0.62 + 24
        return max(emptyStateMinHeightFloor, min(available, balancedTarget))
    }
}
