import XCTest
@testable import Tracci

// MARK: - MainTabView gate policy

final class TracciMainTabBarVisibilityPolicyTests: XCTestCase {
    func testCreateTripSheetHidesTabBarViaGlobalOverlay() {
        XCTAssertTrue(
            TracciMainTabBarVisibilityPolicy.hidesForGlobalOverlay(
                showingCreateOptions: false,
                isCreateFlowTransitioning: false,
                showingCreateTrip: true,
                showingJoinTrip: false
            )
        )
        XCTAssertFalse(
            TracciMainTabBarVisibilityPolicy.shouldShowTabBar(
                globalOverlayHidden: true,
                immersiveHidden: false,
                navigationHidden: false
            )
        )
    }

    func testCreateFlowTransitionKeepsTabBarHiddenBetweenOverlayAndSheet() {
        XCTAssertTrue(
            TracciMainTabBarVisibilityPolicy.hidesForGlobalOverlay(
                showingCreateOptions: false,
                isCreateFlowTransitioning: true,
                showingCreateTrip: false,
                showingJoinTrip: false
            ),
            "The tab bar must stay hidden while the create overlay hands off to its destination"
        )
    }

    func testHomeSubpageHiddenAfterSheetDismissBecausePathIsStillDeep() {
        let navigationHidden = TracciNavigationPathTabBarPolicy.shouldHideTabBar(
            pathDepth: 1,
            rootOverlayHidden: false
        )

        XCTAssertFalse(
            TracciMainTabBarVisibilityPolicy.shouldShowTabBar(
                globalOverlayHidden: false,
                immersiveHidden: false,
                navigationHidden: navigationHidden
            ),
            "A dismissed sheet must not force-show the tab bar while Home path is still on a subpage"
        )
    }
}

// MARK: - NavigationPath policy

final class TracciNavigationPathTabBarPolicyTests: XCTestCase {
    func testRootWithoutOverlayShowsTabBar() {
        XCTAssertFalse(
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(pathDepth: 0, rootOverlayHidden: false)
        )
    }

    func testRootOverlayHidesTabBar() {
        XCTAssertTrue(
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(pathDepth: 0, rootOverlayHidden: true)
        )
    }

    func testPushedSubpageHidesTabBar() {
        XCTAssertTrue(
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(pathDepth: 1, rootOverlayHidden: false)
        )
    }

    func testDeepSubpageHidesTabBar() {
        XCTAssertTrue(
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(pathDepth: 3, rootOverlayHidden: false)
        )
    }

    func testInteractivePopCancelKeepsSubpageHiddenWhenPathRemainsDeep() {
        XCTAssertTrue(
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(pathDepth: 1, rootOverlayHidden: false)
        )
    }

    func testInteractivePopCompleteShowsTabBarWhenPathReturnsToRoot() {
        XCTAssertFalse(
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(pathDepth: 0, rootOverlayHidden: false)
        )
    }
}

// MARK: - Global navigation geometry

final class AppNavigationMetricsTests: XCTestCase {
    func testChromePolicyCompactsPastThresholdAndUsesHysteresis() {
        XCTAssertEqual(
            AppNavigationChromePolicy.resolvedMode(
                current: .expanded,
                scrollOffset: AppNavigationMetrics.compactScrollThreshold + 1,
                allowsCompaction: true
            ),
            .compact
        )
        XCTAssertEqual(
            AppNavigationChromePolicy.resolvedMode(
                current: .compact,
                scrollOffset: AppNavigationMetrics.expandScrollThreshold + 1,
                allowsCompaction: true
            ),
            .compact
        )
        XCTAssertEqual(
            AppNavigationChromePolicy.resolvedMode(
                current: .compact,
                scrollOffset: AppNavigationMetrics.expandScrollThreshold - 1,
                allowsCompaction: true
            ),
            .expanded
        )
    }

    func testChromePolicyForcesExpandedWhenCompactionIsNotAllowed() {
        XCTAssertEqual(
            AppNavigationChromePolicy.resolvedMode(
                current: .compact,
                scrollOffset: AppNavigationMetrics.compactScrollThreshold + 100,
                allowsCompaction: false
            ),
            .expanded
        )
    }

    func testHomeIndicatorLayoutUsesActualChromeTopEdgeForContentClearance() {
        XCTAssertEqual(
            AppNavigationMetrics.chromeBottomPadding(for: 34, mode: .expanded),
            24
        )
        XCTAssertEqual(AppNavigationMetrics.overlayBottomPadding(for: 34), 92)
        XCTAssertEqual(AppNavigationMetrics.contentInset(for: 34), 58)
    }

    func testFlatBottomDeviceRetainsPhysicalEdgeClearance() {
        XCTAssertEqual(
            AppNavigationMetrics.chromeBottomPadding(for: 0, mode: .expanded),
            AppSpacing.xxs
        )
        XCTAssertEqual(AppNavigationMetrics.overlayBottomPadding(for: 0), 72)
        XCTAssertEqual(AppNavigationMetrics.contentInset(for: 0), 72)
    }

    func testCompactChromeMovesWithoutChangingReservedContentInset() {
        XCTAssertEqual(
            AppNavigationMetrics.chromeBottomPadding(for: 34, mode: .compact),
            22
        )
        XCTAssertEqual(
            AppNavigationMetrics.contentInset(for: 34, mode: .compact),
            AppNavigationMetrics.contentInset(for: 34)
        )
    }

    func testCreateMenuBottomPaddingHandlesBothDeviceFamilies() {
        XCTAssertEqual(AppNavigationMetrics.createMenuBottomPadding(for: 34), 52)
        XCTAssertEqual(AppNavigationMetrics.createMenuBottomPadding(for: 0), 28)
    }

    func testIncreasedContrastStrengthensGlassWithoutChangingGeometry() {
        XCTAssertGreaterThan(
            AppNavigationMetrics.navigationGlassTintOpacity(forIncreasedContrast: true),
            AppNavigationMetrics.navigationGlassTintOpacity(forIncreasedContrast: false)
        )
        XCTAssertGreaterThan(
            AppNavigationMetrics.selectionLensTintOpacity(forIncreasedContrast: true),
            AppNavigationMetrics.selectionLensTintOpacity(forIncreasedContrast: false)
        )
        XCTAssertGreaterThan(
            AppNavigationMetrics.selectionLensHighlightOpacity(forIncreasedContrast: true),
            AppNavigationMetrics.selectionLensHighlightOpacity(forIncreasedContrast: false)
        )
        XCTAssertEqual(AppNavigationMetrics.contentInset(for: 34), 58)
    }

    func testCreateMenuSemanticTintsRespondToIncreasedContrast() {
        XCTAssertGreaterThan(
            AppNavigationMetrics.createMenuNeutralGlassTintOpacity(forIncreasedContrast: true),
            AppNavigationMetrics.createMenuNeutralGlassTintOpacity(forIncreasedContrast: false)
        )
        XCTAssertGreaterThan(
            AppNavigationMetrics.createMenuSuccessGlassTintOpacity(forIncreasedContrast: true),
            AppNavigationMetrics.createMenuSuccessGlassTintOpacity(forIncreasedContrast: false)
        )
    }

    func testAccessibilityLayoutAddsScrollableControlClearance() {
        XCTAssertEqual(
            AppNavigationMetrics.contentInset(for: 34, accessibilityLayout: false),
            58
        )
        XCTAssertEqual(
            AppNavigationMetrics.contentInset(for: 34, accessibilityLayout: true),
            58 + AppNavigationMetrics.accessibilityContentClearance
        )
    }

    func testSelectionLensIsConcentricAndContainedInBothChromeModes() {
        XCTAssertEqual(AppNavigationMetrics.expandedDestinationIslandMaxWidth, 282)
        XCTAssertEqual(AppNavigationMetrics.destinationCreateMinimumSeparation, 36)
        XCTAssertEqual(AppNavigationMetrics.createActionSize, 52)
        XCTAssertEqual(AppNavigationMetrics.destinationLensHeight(for: .expanded), 40)
        XCTAssertEqual(AppNavigationMetrics.destinationLensVerticalInset(for: .expanded), 5)
        XCTAssertEqual(AppNavigationMetrics.destinationLensHeight(for: .compact), 36)
        XCTAssertEqual(AppNavigationMetrics.destinationLensVerticalInset(for: .compact), 4)
        XCTAssertLessThan(
            AppNavigationMetrics.destinationLensHeight(for: .expanded),
            AppNavigationMetrics.chromeHeight(for: .expanded)
        )
        XCTAssertLessThan(
            AppNavigationMetrics.destinationLensHeight(for: .compact),
            AppNavigationMetrics.chromeHeight(for: .compact)
        )
    }
}
