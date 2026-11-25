import SwiftUI
import XCTest
@testable import Tracci

@MainActor
final class MainTabCoordinatorTests: XCTestCase {
    func testInitialStateShowsHomeRootTabBar() {
        let coordinator = MainTabCoordinator()

        XCTAssertEqual(coordinator.selectedTab, .home)
        XCTAssertTrue(coordinator.homeNavigationPath.isEmpty)
        XCTAssertTrue(coordinator.profileNavigationPath.isEmpty)
        XCTAssertTrue(coordinator.shouldShowTabBar)
        XCTAssertEqual(coordinator.navigationChromeMode, .expanded)
    }

    func testSelectedTabChangeClearsImmersiveStateAndExpandsChrome() {
        let coordinator = MainTabCoordinator()
        coordinator.selectedTab = .export
        coordinator.isContentImmersive = true
        coordinator.navigationChromeMode = .compact

        coordinator.handleSelectedTabChange()

        XCTAssertFalse(coordinator.isContentImmersive)
        XCTAssertEqual(coordinator.navigationChromeMode, .expanded)
    }

    func testNavigationAndRootOverlayDriveTabBarVisibility() {
        let coordinator = MainTabCoordinator()

        coordinator.homeNavigationPath.append("trip-detail")
        XCTAssertTrue(coordinator.hidesTabBarForSelectedTabNavigation)
        XCTAssertFalse(coordinator.shouldShowTabBar)

        coordinator.homeNavigationPath = NavigationPath()
        coordinator.homeRootOverlayHidesTabBar = true
        XCTAssertTrue(coordinator.hidesTabBarForSelectedTabNavigation)
    }

    /// 底栏单一形态（决策 2026-09-18）：「我的」恒占第四格。
    func testProfileTabNavigationDepthOnlyAppliesWhenProfileIsDocked() {
        let coordinator = MainTabCoordinator()

        XCTAssertEqual(coordinator.visibleTabs, [.home, .explore, .export, .profile])
        coordinator.selectedTab = .profile
        coordinator.profileNavigationPath.append("version")

        XCTAssertTrue(coordinator.hidesTabBarForSelectedTabNavigation)
        XCTAssertFalse(coordinator.isSelectedTabAtRoot)
        XCTAssertEqual(coordinator.selectedTabNavigationDepth, 1)
    }

    func testMemoryImmersiveAndNestedStatesHideTabBar() {
        let coordinator = MainTabCoordinator()
        coordinator.selectedTab = .export

        coordinator.isMemoryRoot = false
        XCTAssertTrue(coordinator.hidesTabBarForSelectedTabImmersive)

        coordinator.isMemoryRoot = true
        coordinator.isContentImmersive = true
        XCTAssertTrue(coordinator.hidesTabBarForSelectedTabImmersive)

        coordinator.isContentImmersive = false
        XCTAssertTrue(coordinator.shouldShowTabBar)
    }

    /// 底栏在任何构建下都是同一组 4 格（决策 2026-09-18）。
    func testDockOrderFollowsProductSpec() {
        XCTAssertEqual(AppTab.dockTabs, [.home, .explore, .export, .profile])
        XCTAssertEqual(AppTab.dockTabs.count, 4)
    }

    func testCoordinatorExposesSingleDockForm() {
        XCTAssertEqual(MainTabCoordinator().visibleTabs, AppTab.dockTabs)
    }

    func testExploreCityPageHidesTabBarAndReportsDepth() {
        let coordinator = MainTabCoordinator()
        coordinator.selectedTab = .explore

        XCTAssertTrue(coordinator.isSelectedTabAtRoot)
        XCTAssertTrue(coordinator.shouldShowTabBar)
        XCTAssertEqual(coordinator.selectedTabNavigationDepth, 0)

        coordinator.exploreNavigationPath.append("kyoto")
        XCTAssertFalse(coordinator.hidesTabBarForSelectedTabImmersive)
        XCTAssertTrue(coordinator.hidesTabBarForSelectedTabNavigation)
        XCTAssertFalse(coordinator.shouldShowTabBar)
        XCTAssertFalse(coordinator.isSelectedTabAtRoot)
        XCTAssertEqual(coordinator.selectedTabNavigationDepth, 1)

        coordinator.exploreNavigationPath = NavigationPath()
        XCTAssertTrue(coordinator.shouldShowTabBar)
    }

    func testExploreNavigationDepthIsIndependentOfOtherTabs() {
        let coordinator = MainTabCoordinator()
        coordinator.homeNavigationPath.append("trip-detail")
        coordinator.selectedTab = .explore

        XCTAssertEqual(coordinator.selectedTabNavigationDepth, 0)
        XCTAssertTrue(coordinator.shouldShowTabBar)
    }

    func testExploreRootScrollCompactsChromeOnlyAtRoot() {
        let coordinator = MainTabCoordinator()
        coordinator.selectedTab = .explore
        let compactOffset = AppNavigationMetrics.compactScrollThreshold + 1

        coordinator.handleRootScrollOffset(compactOffset)
        XCTAssertEqual(coordinator.navigationChromeMode, .compact)

        coordinator.navigationChromeMode = .expanded
        coordinator.exploreNavigationPath.append("kyoto")
        coordinator.handleRootScrollOffset(compactOffset)
        XCTAssertEqual(coordinator.navigationChromeMode, .expanded)
    }

    func testCrossTabRoutesPreserveRequestPayloads() throws {
        let coordinator = MainTabCoordinator()

        coordinator.openMemory(tripId: "trip-memory")
        XCTAssertEqual(coordinator.selectedTab, .export)
        XCTAssertEqual(coordinator.memoryNavigationRequest?.tripId, "trip-memory")

        coordinator.openTripDetail(tripId: "trip-detail", initialTab: .journal)
        XCTAssertEqual(coordinator.selectedTab, .home)
        XCTAssertEqual(
            coordinator.tripDetailNavigationRequest,
            TripDetailNavigationRequest(tripId: "trip-detail", initialTab: .journal)
        )
    }

    func testCreateFlowTransitionKeepsTabBarHiddenUntilDestinationAppears() {
        let coordinator = MainTabCoordinator()
        XCTAssertTrue(coordinator.presentCreateOptions())
        XCTAssertFalse(coordinator.shouldShowTabBar)

        XCTAssertTrue(coordinator.beginCreateFlow())
        XCTAssertFalse(coordinator.showingCreateOptions)
        XCTAssertTrue(coordinator.isCreateFlowTransitioning)
        XCTAssertFalse(coordinator.shouldShowTabBar)

        coordinator.completeCreateFlowTransition(.manual)
        XCTAssertFalse(coordinator.isCreateFlowTransitioning)
        XCTAssertTrue(coordinator.showingCreateTrip)
        XCTAssertFalse(coordinator.shouldShowTabBar)
    }

    func testCreateFlowTransitionCanLandOnJoinSheet() {
        let coordinator = MainTabCoordinator()
        XCTAssertTrue(coordinator.presentCreateOptions())

        XCTAssertTrue(coordinator.beginCreateFlow())
        coordinator.completeCreateFlowTransition(.join)

        XCTAssertFalse(coordinator.isCreateFlowTransitioning)
        XCTAssertFalse(coordinator.showingCreateTrip)
        XCTAssertTrue(coordinator.showingJoinTrip)
        XCTAssertFalse(coordinator.shouldShowTabBar)
    }

    func testCreateOptionsCannotOpenOverExistingPresentation() {
        let coordinator = MainTabCoordinator()
        coordinator.showingJoinTrip = true

        XCTAssertFalse(coordinator.presentCreateOptions())
        XCTAssertFalse(coordinator.showingCreateOptions)
    }

    func testRootScrollCompactsOnlyWhenSelectedTabIsAtRootAndVisible() {
        let coordinator = MainTabCoordinator()
        let compactOffset = AppNavigationMetrics.compactScrollThreshold + 1

        coordinator.handleRootScrollOffset(compactOffset)
        XCTAssertEqual(coordinator.navigationChromeMode, .compact)

        coordinator.navigationChromeMode = .expanded
        coordinator.homeNavigationPath.append("trip-detail")
        coordinator.handleRootScrollOffset(compactOffset)
        XCTAssertEqual(coordinator.navigationChromeMode, .expanded)
    }

    // MARK: - 探索发起的创建旅程（规格 §7.3）

    /// 切到首页是为了让旅程列表垫在创建表单后面；从探索发起时这么做会把用户
    /// 在放弃创建后留在首页，回不到刚才那座城市。
    func testSeededCreateTripKeepsExploreTabAndClearsSeedOnDismiss() {
        let coordinator = MainTabCoordinator()
        coordinator.selectedTab = .explore
        coordinator.createTripSeed = TripCreateSeed(
            destinationSavedPlaceId: "saved-9",
            destinationName: "杭州"
        )

        coordinator.handleCreateTripPresentationChange(isShowing: true)
        XCTAssertEqual(coordinator.selectedTab, .explore)

        coordinator.handleCreateTripPresentationChange(isShowing: false)
        XCTAssertNil(coordinator.createTripSeed, "关掉后清种子，下次创建是干净的")
    }

    func testUnseededCreateTripStillSwitchesToHomeTab() {
        let coordinator = MainTabCoordinator()
        coordinator.selectedTab = .explore

        coordinator.handleCreateTripPresentationChange(isShowing: true)

        XCTAssertEqual(coordinator.selectedTab, .home)
    }
}
