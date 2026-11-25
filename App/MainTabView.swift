import SwiftUI
import TracciNetworking

private extension View {
    @ViewBuilder
    func mainTabBarDebugTrace(
        selectedTab: AppTab,
        customShouldShow: Bool,
        nativeShouldShow: Bool,
        globalHidden: Bool,
        immersiveHidden: Bool,
        navigationHidden: Bool,
        syncRevision: Int
    ) -> some View {
        #if DEBUG
        tracciTabBarDebugTrace(
            "Main",
            selectedTab: selectedTab.title,
            customShouldShow: customShouldShow,
            nativeShouldShow: nativeShouldShow,
            globalHidden: globalHidden,
            immersiveHidden: immersiveHidden,
            navigationHidden: navigationHidden,
            syncRevision: syncRevision
        )
        #else
        self
        #endif
    }
}
struct MainTabView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var globalChromeGlassNamespace
    @State private var coordinator: MainTabCoordinator
    @State private var sceneViewModel: MainSceneViewModel
    @State private var savedPlaceTripProvider: SavedPlaceTripProvider

    let dependencies: MainSceneDependencies

    init(dependencies: MainSceneDependencies) {
        self.dependencies = dependencies
        let scene = MainSceneFactory(dependencies: dependencies).make()
        _coordinator = State(initialValue: scene.coordinator)
        _sceneViewModel = State(initialValue: scene.viewModel)
        _savedPlaceTripProvider = State(initialValue: scene.savedPlaceTripProvider)
    }

    private var authService: AuthService { dependencies.authService }
    private var tripService: TripService { dependencies.tripService }
    private var itineraryService: ItineraryService { dependencies.itineraryService }
    private var journalService: JournalService { dependencies.journalService }
    private var expenseService: ExpenseService { dependencies.expenseService }
    private var exportService: ExportService { dependencies.exportService }
    private var profileService: ProfileService { dependencies.profileService }
    private var fileUploadService: FileUploadService { dependencies.fileUploadService }
    private var collaborationService: CollaborationService { dependencies.collaborationService }
    private var savedPlaceService: SavedPlaceService { dependencies.savedPlaceService }

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = SafeAreaMetrics.resolveBottomInset(
                geometryInset: geometry.safeAreaInsets.bottom
            )

            ZStack(alignment: .bottom) {
                MainTabRouterView(
                    selectedTab: coordinatorBinding(\.selectedTab),
                    tabs: coordinator.visibleTabs,
                    content: { tab in
                        tabContent(for: tab, bottomInset: bottomInset)
                    }
                )

                MainTabChromeView(
                    coordinator: coordinator,
                    bottomInset: bottomInset,
                    glassNamespace: globalChromeGlassNamespace,
                    onCreate: presentCreateOptions,
                    onManualTripCreate: { presentCreateFlow(.manual) },
                    onJoinTrip: { presentCreateFlow(.join) },
                    onDismissCreateOptions: dismissCreateOptions
                )
            }
        }
        .mainTabBarDebugTrace(
            selectedTab: coordinator.selectedTab,
            customShouldShow: coordinator.shouldShowTabBar,
            nativeShouldShow: false,
            globalHidden: coordinator.hidesTabBarForGlobalOverlay,
            immersiveHidden: coordinator.hidesTabBarForSelectedTabImmersive,
            navigationHidden: coordinator.hidesTabBarForSelectedTabNavigation,
            syncRevision: coordinator.selectedTabNavigationDepth
        )
        .tracciActionSheetHost()
        .tracciChoiceSheetHost()
        .animation(
            AppMotion.animation(.easeInOut(duration: 0.22), reduceMotion: reduceMotion),
            value: coordinator.isContentImmersive
        )
        // Dock show/hide fades overlap the navigation pop window (`normal`, not
        // `quick`) so the dock feels present as the departing page reveals it.
        .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: coordinator.shouldShowTabBar)
        .animation(AppMotion.animation(AppMotion.morphOpen, reduceMotion: reduceMotion), value: coordinator.showingCreateOptions)
        .animation(AppMotion.animation(AppMotion.chromeMode, reduceMotion: reduceMotion), value: coordinator.navigationChromeMode)
        .modifier(
            MainScenePresentationModifier(
                coordinator: coordinator,
                sceneViewModel: sceneViewModel,
                dependencies: dependencies,
                savedPlaceTripProvider: savedPlaceTripProvider
            )
        )
    }

    private func coordinatorBinding<Value>(
        _ keyPath: ReferenceWritableKeyPath<MainTabCoordinator, Value>
    ) -> Binding<Value> {
        Binding(
            get: { coordinator[keyPath: keyPath] },
            set: { coordinator[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab, bottomInset: CGFloat) -> some View {
        switch tab {
        case .home:
            HomeView(
                viewModel: sceneViewModel.homeViewModel,
                tripListActions: sceneViewModel.tripListActions,
                tripService: tripService,
                itineraryService: itineraryService,
                journalService: journalService,
                expenseService: expenseService,
                exportService: exportService,
                collaborationService: collaborationService,
                savedPlaceService: savedPlaceService,
                routeProvider: dependencies.routeProvider,
                bottomTabBarContentInset: rootTabContentInset(for: bottomInset),
                tripDetailNavigationRequest: coordinatorBinding(\.tripDetailNavigationRequest),
                navigationPath: coordinatorBinding(\.homeNavigationPath),
                rootOverlayHidesTabBar: coordinatorBinding(\.homeRootOverlayHidesTabBar),
                onRootScrollOffsetChange: handleRootScrollOffset,
                onTripDeleted: { tripId in
                    sceneViewModel.handleTripDeleted(tripId)
                },
                onTripContentChanged: {
                    sceneViewModel.handleTripContentChanged()
                },
                onOpenMemory: { tripId in
                    coordinator.openMemory(tripId: tripId)
                },
                onCreateTripFromDemo: {
                    // Demo detail already pops home route; present the same create menu as + .
                    presentCreateOptions()
                }
            )
        case .explore:
            ExploreRootView(
                viewModel: sceneViewModel.exploreHomeViewModel,
                service: savedPlaceService,
                navigationPath: coordinatorBinding(\.exploreNavigationPath),
                bottomTabBarContentInset: rootTabContentInset(for: bottomInset),
                onRootScrollOffsetChange: handleRootScrollOffset,
                onCreateTrip: { seed in
                    // 种子要先落到 Coordinator：`showingCreateTrip` 翻起来时创建表单才读得到。
                    coordinator.createTripSeed = seed
                    presentCreateFlow(.manual)
                },
                onCreateTripFromPlace: {
                    // 规格 §8.3：半层这条**不**预填目的地，就是普通的手动创建入口。
                    coordinator.createTripSeed = nil
                    presentCreateFlow(.manual)
                },
                tripProvider: savedPlaceTripProvider
            )
        case .export:
            MemoryView(
                pageViewModel: sceneViewModel.memoryPageViewModel,
                userId: authSession.currentUser?.id,
                isContentImmersive: coordinatorBinding(\.isContentImmersive),
                memoryNavigationRequest: coordinatorBinding(\.memoryNavigationRequest),
                demoBundle: sceneViewModel.homeViewModel.displayableEmptyStateDemoBundle,
                tripDataRevision: sceneViewModel.tripDataRevision,
                deletedTripId: sceneViewModel.lastDeletedTripId,
                isTabSelected: coordinator.selectedTab == .export,
                bottomTabBarContentInset: rootTabContentInset(for: bottomInset),
                onCreateTrip: {
                    coordinator.showingCreateTrip = true
                },
                onOpenTripRecord: { tripId, tab in
                    sceneViewModel.openTripDetailFromExternalTab(tripId: tripId, initialTab: tab)
                },
                onRootStateChange: { isRoot in
                    coordinator.isMemoryRoot = isRoot
                },
                onRootScrollOffsetChange: handleRootScrollOffset
            )
            .ignoresSafeArea(
                .container,
                edges: coordinator.selectedTab == .export && coordinator.isContentImmersive ? .all : []
            )
        case .profile:
            ProfileView(
                viewModel: sceneViewModel.profileViewModel,
                authService: authService,
                profileService: profileService,
                fileUploadService: fileUploadService,
                savedPlaceService: savedPlaceService,
                tripProvider: savedPlaceTripProvider,
                navigationPath: coordinatorBinding(\.profileNavigationPath),
                bottomTabBarContentInset: rootTabContentInset(for: bottomInset),
                onRootScrollOffsetChange: handleRootScrollOffset
            )
        }
    }

    private func rootTabContentInset(for bottomInset: CGFloat) -> CGFloat {
        AppNavigationMetrics.contentInset(
            for: bottomInset,
            accessibilityLayout: dynamicTypeSize.isAccessibilitySize
        )
    }

    private func handleRootScrollOffset(_ offset: CGFloat) {
        // Single driver: parent `.animation(AppMotion.chromeMode, value:)` already springs
        // this binding. Do not wrap in a second `withAnimation` (double spring = jitter).
        coordinator.handleRootScrollOffset(offset)
    }

    private func presentCreateOptions() {
        guard coordinator.canPresentCreateOptions else { return }
        AppHaptics.mediumImpact()
        _ = withAnimation(AppMotion.animation(AppMotion.morphOpen, reduceMotion: reduceMotion)) {
            coordinator.presentCreateOptions()
        }
    }

    private func dismissCreateOptions() {
        AppHaptics.lightImpact()
        withAnimation(AppMotion.animation(AppMotion.morphClose, reduceMotion: reduceMotion)) {
            coordinator.dismissCreateOptions()
        }
    }

    private func presentCreateFlow(_ flow: MainCreateFlow) {
        AppHaptics.lightImpact()
        _ = withAnimation(AppMotion.animation(AppMotion.morphClose, reduceMotion: reduceMotion)) {
            coordinator.beginCreateFlow()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + AppMotion.morphCloseDuration + 0.04) {
            coordinator.completeCreateFlowTransition(flow)
        }
    }
}
