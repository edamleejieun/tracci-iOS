import XCTest
@testable import Tracci
import TracciNetworking

@MainActor
final class MainSceneViewModelTests: XCTestCase {
    func testHandleTripCreatedUpsertsAndRefreshesHome() async {
        let trip = Trip(
            id: "manual-created",
            title: "京都 3 日游",
            startDate: "2026-08-12",
            endDate: "2026-08-14",
            status: .planning
        )
        let refreshStarted = expectation(description: "refresh trips after manual creation")
        let subject = makeSubject(
            tripPageLoader: { _, _ in
                refreshStarted.fulfill()
                return PageResponse(list: [trip], total: 1, page: 1, pageSize: 20)
            }
        )

        subject.viewModel.handleTripCreated(trip)

        XCTAssertEqual(subject.viewModel.homeViewModel.trips, [trip])
        await fulfillment(of: [refreshStarted], timeout: 1)
        XCTAssertEqual(subject.viewModel.homeViewModel.trips, [trip])
    }

    func testTripContentChangesPublishMemoryRevisionAndDeletion() {
        let subject = makeSubject()

        subject.viewModel.handleTripContentChanged()
        XCTAssertEqual(subject.viewModel.tripDataRevision, 1)
        XCTAssertNil(subject.viewModel.lastDeletedTripId)

        subject.viewModel.handleTripDeleted("deleted-trip")
        XCTAssertEqual(subject.viewModel.tripDataRevision, 2)
        XCTAssertEqual(subject.viewModel.lastDeletedTripId, "deleted-trip")
    }

    private func makeSubject(
        tripPageLoader: @escaping (Int, Int) async throws -> PageResponse<Trip> = { _, _ in
            PageResponse(list: [], total: 0, page: 1, pageSize: 20)
        }
    ) -> (coordinator: MainTabCoordinator, viewModel: MainSceneViewModel) {
        let apiClient = APIClient(config: .simulator)
        let uploadService = FileUploadService(apiClient: apiClient)
        let tripService = TripService(apiClient: apiClient, fileUploadService: uploadService)
        let journalService = JournalService(apiClient: apiClient, fileUploadService: uploadService)
        let coordinator = MainTabCoordinator()
        let homeViewModel = HomeViewModel(
            tripService: tripService,
            tripPageLoader: tripPageLoader
        )
        let memoryPageViewModel = MemoryPageViewModel(
            tripService: tripService,
            exportService: ExportService(apiClient: apiClient),
            journalService: journalService
        )
        let profileViewModel = ProfileViewModel(
            authService: AuthService(apiClient: apiClient),
            statsService: StatsService(apiClient: apiClient),
            updateChecker: AppUpdateChecker(session: .shared, lookupURL: nil)
        )
        let exploreHomeViewModel = ExploreHomeViewModel(
            service: SavedPlaceService(apiClient: apiClient)
        )
        let tripListActions = TripListActions(
            operations: TripListActionOperations(
                deleteTrip: { _ in },
                createInvitation: { _, _ in throw TestError.unavailable },
                listMembers: { _ in [] }
            )
        )
        let viewModel = MainSceneViewModel(
            coordinator: coordinator,
            homeViewModel: homeViewModel,
            memoryPageViewModel: memoryPageViewModel,
            profileViewModel: profileViewModel,
            exploreHomeViewModel: exploreHomeViewModel,
            tripListActions: tripListActions
        )
        return (coordinator, viewModel)
    }
}

private enum TestError: Error {
    case unavailable
}
