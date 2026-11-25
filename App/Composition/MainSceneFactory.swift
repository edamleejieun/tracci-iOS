import Foundation

struct MainScene {
    let coordinator: MainTabCoordinator
    let viewModel: MainSceneViewModel
    /// 「加入行程」能力，组合根构造一次后由各 Tab 共享。
    let savedPlaceTripProvider: SavedPlaceTripProvider
}

/// Constructs stable Main Scene state objects at the Composition Root boundary.
@MainActor
struct MainSceneFactory {
    let dependencies: MainSceneDependencies

    func make() -> MainScene {
        let coordinator = MainTabCoordinator()
        let homeViewModel = HomeViewModel(
            tripService: dependencies.tripService,
            demoJourneyService: dependencies.demoJourneyService
        )
        let memoryPageViewModel = MemoryPageViewModel(
            tripService: dependencies.tripService,
            exportService: dependencies.exportService,
            journalService: dependencies.journalService
        )
        let profileViewModel = ProfileViewModel(
            authService: dependencies.authService,
            statsService: dependencies.statsService,
            updateChecker: dependencies.appUpdateChecker
        )
        let exploreHomeViewModel = ExploreHomeViewModel(
            service: dependencies.savedPlaceService
        )
        let tripListActions = TripListActions(
            tripService: dependencies.tripService,
            collaborationService: dependencies.collaborationService
        )
        let savedPlaceTripProvider = SavedPlaceTripProvider(
            tripService: dependencies.tripService,
            itineraryService: dependencies.itineraryService
        )
        let viewModel = MainSceneViewModel(
            coordinator: coordinator,
            homeViewModel: homeViewModel,
            memoryPageViewModel: memoryPageViewModel,
            profileViewModel: profileViewModel,
            exploreHomeViewModel: exploreHomeViewModel,
            tripListActions: tripListActions
        )

        return MainScene(
            coordinator: coordinator,
            viewModel: viewModel,
            savedPlaceTripProvider: savedPlaceTripProvider
        )
    }
}
