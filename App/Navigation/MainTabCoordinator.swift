import Observation
import SwiftUI

enum AppTab: CaseIterable {
    case home
    case explore
    case export
    case profile

    /// 底栏占位（决策 2026-09-18）：底栏在任何构建下都是这 4 格的单一形态。
    static let dockTabs: [AppTab] = [.home, .explore, .export, .profile]

    var title: String {
        switch self {
        case .home: "旅程"
        case .explore: "探索"
        case .export: "回忆"
        case .profile: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "map"
        case .explore: "safari"
        // Prefer a simple fill pair for tab chrome. `book.pages` is multi-layer and
        // flashes mid-morph under selection spring; 页头同样引用这里（决策 2026-09-18）。
        case .export: "book.closed"
        case .profile: "person"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .home: "home"
        case .explore: "explore"
        case .export: "memory"
        case .profile: "profile"
        }
    }
}

enum MainCreateFlow {
    case manual
    case join
}

/// Owns Main Scene navigation and presentation state only.
/// Business requests remain outside the coordinator.
@MainActor
@Observable
final class MainTabCoordinator {
    var selectedTab: AppTab = .home
    var showingCreateTrip = false
    var showingJoinTrip = false
    var showingCreateOptions = false
    var isCreateFlowTransitioning = false
    /// 探索城市页「用这里创建旅程」带来的只读目的地（规格 §7.3）；`nil` 是普通创建入口。
    var createTripSeed: TripCreateSeed?
    var tripDetailNavigationRequest: TripDetailNavigationRequest?
    var memoryNavigationRequest: MemoryNavigationRequest?
    var isContentImmersive = false
    var isMemoryRoot = true
    var homeNavigationPath = NavigationPath()
    var exploreNavigationPath = NavigationPath()
    var profileNavigationPath = NavigationPath()
    var homeRootOverlayHidesTabBar = false
    var navigationChromeMode: AppNavigationChromeMode = .expanded

    /// 底栏实际占位的四格。单一形态。
    var visibleTabs: [AppTab] { AppTab.dockTabs }

    var hidesTabBarForGlobalOverlay: Bool {
        TracciMainTabBarVisibilityPolicy.hidesForGlobalOverlay(
            showingCreateOptions: showingCreateOptions,
            isCreateFlowTransitioning: isCreateFlowTransitioning,
            showingCreateTrip: showingCreateTrip,
            showingJoinTrip: showingJoinTrip
        )
    }

    var hidesTabBarForSelectedTabImmersive: Bool {
        switch selectedTab {
        case .export:
            !isMemoryRoot || isContentImmersive
        default:
            false
        }
    }

    var hidesTabBarForSelectedTabNavigation: Bool {
        switch selectedTab {
        case .home:
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(
                pathDepth: homeNavigationPath.count,
                rootOverlayHidden: homeRootOverlayHidesTabBar
            )
        case .explore:
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(
                pathDepth: exploreNavigationPath.count,
                rootOverlayHidden: false
            )
        case .profile:
            TracciNavigationPathTabBarPolicy.shouldHideTabBar(
                pathDepth: profileNavigationPath.count,
                rootOverlayHidden: false
            )
        // 回忆没有自己的 NavigationStack。
        case .export:
            false
        }
    }

    var selectedTabNavigationDepth: Int {
        switch selectedTab {
        case .home:
            homeNavigationPath.count
        case .explore:
            exploreNavigationPath.count
        case .profile:
            profileNavigationPath.count
        case .export:
            0
        }
    }

    var shouldShowTabBar: Bool {
        TracciMainTabBarVisibilityPolicy.shouldShowTabBar(
            globalOverlayHidden: hidesTabBarForGlobalOverlay,
            immersiveHidden: hidesTabBarForSelectedTabImmersive,
            navigationHidden: hidesTabBarForSelectedTabNavigation
        )
    }

    var isSelectedTabAtRoot: Bool {
        switch selectedTab {
        case .home:
            homeNavigationPath.isEmpty && !homeRootOverlayHidesTabBar
        case .explore:
            exploreNavigationPath.isEmpty
        case .export:
            isMemoryRoot && !isContentImmersive
        case .profile:
            profileNavigationPath.isEmpty
        }
    }

    func handleSelectedTabChange() {
        isContentImmersive = false
        navigationChromeMode = .expanded
    }

    func handleTabBarVisibilityChange(isVisible: Bool) {
        if !isVisible {
            navigationChromeMode = .expanded
        }
    }

    func handleCreateOptionsChange(isShowing: Bool) {
        if isShowing {
            navigationChromeMode = .expanded
        }
    }

    func handleCreateTripPresentationChange(isShowing: Bool) {
        if isShowing {
            // 从探索发起时不切 Tab：放弃创建要回到刚才那座城市，而不是被留在首页。
            if createTripSeed == nil {
                selectedTab = .home
            }
        } else {
            createTripSeed = nil
        }
    }

    @discardableResult
    func presentCreateOptions() -> Bool {
        guard canPresentCreateOptions else { return false }
        showingCreateOptions = true
        return true
    }

    func dismissCreateOptions() {
        showingCreateOptions = false
    }

    /// 创建 / 加入共用同一个全屏 cover，同一时间只能有一个。
    var hasGlobalOverlay: Bool {
        showingCreateTrip || showingJoinTrip
    }

    var canPresentCreateOptions: Bool { !hasGlobalOverlay }

    /// 两种创建流的第一步完全一样：收起创建菜单、标记过渡中。具体开哪张表由
    /// `completeCreateFlowTransition` 决定。
    @discardableResult
    func beginCreateFlow() -> Bool {
        isCreateFlowTransitioning = true
        showingCreateOptions = false
        return true
    }

    func completeCreateFlowTransition(_ flow: MainCreateFlow) {
        switch flow {
        case .manual:
            showingCreateTrip = true
        case .join:
            showingJoinTrip = true
        }
        isCreateFlowTransitioning = false
    }

    func openMemory(tripId: String) {
        memoryNavigationRequest = MemoryNavigationRequest(tripId: tripId)
        selectedTab = .export
    }

    func openTripDetail(tripId: String, initialTab: TripDetailTab) {
        tripDetailNavigationRequest = TripDetailNavigationRequest(
            tripId: tripId,
            initialTab: initialTab
        )
        selectedTab = .home
    }

    func handleRootScrollOffset(_ offset: CGFloat) {
        let next = AppNavigationChromePolicy.resolvedMode(
            current: navigationChromeMode,
            scrollOffset: offset,
            allowsCompaction: shouldShowTabBar && isSelectedTabAtRoot
        )
        guard next != navigationChromeMode else { return }
        navigationChromeMode = next
    }
}
