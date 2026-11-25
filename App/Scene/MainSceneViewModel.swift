import Foundation
import Observation

/// Owns authenticated Main Scene data flow and cross-tab synchronization.
/// Navigation and presentation state remain in `MainTabCoordinator`.
@MainActor
@Observable
final class MainSceneViewModel {
    let homeViewModel: HomeViewModel
    let memoryPageViewModel: MemoryPageViewModel
    let profileViewModel: ProfileViewModel
    let exploreHomeViewModel: ExploreHomeViewModel
    let tripListActions: TripListActions

    private(set) var tripDataRevision = 0
    private(set) var lastDeletedTripId: String?

    @ObservationIgnored private let coordinator: MainTabCoordinator

    init(
        coordinator: MainTabCoordinator,
        homeViewModel: HomeViewModel,
        memoryPageViewModel: MemoryPageViewModel,
        profileViewModel: ProfileViewModel,
        exploreHomeViewModel: ExploreHomeViewModel,
        tripListActions: TripListActions
    ) {
        self.coordinator = coordinator
        self.homeViewModel = homeViewModel
        self.memoryPageViewModel = memoryPageViewModel
        self.profileViewModel = profileViewModel
        self.exploreHomeViewModel = exploreHomeViewModel
        self.tripListActions = tripListActions
    }

    func updateCurrentUser(id: String?) {
        homeViewModel.currentUserId = id
    }

    func handleTripCreated(_ trip: Trip) {
        // Milestone moment (G3.2): success haptic as the create sheet confirms,
        // then the new home card plays its entrance as the sheet lifts.
        AppHaptics.success()
        homeViewModel.upsertTrip(trip)
        homeViewModel.markNewlyCreated(tripId: trip.id)
        Task { [weak self] in
            await self?.homeViewModel.refreshTrips()
        }
    }

    func handleTripJoined(tripId: String? = nil) {
        Task { [weak self] in
            guard let self else { return }
            await self.homeViewModel.refreshTrips()
            if let tripId {
                self.homeViewModel.markNewlyCreated(tripId: tripId)
            }
        }
    }

    func openTripDetailFromExternalTab(tripId: String, initialTab: TripDetailTab) {
        coordinator.openTripDetail(tripId: tripId, initialTab: initialTab)
        Task { [weak self] in
            await self?.homeViewModel.loadTripsIfNeeded()
        }
    }

    func handleTripDeleted(_ tripId: String) {
        lastDeletedTripId = tripId
        tripDataRevision += 1
        memoryPageViewModel.removeTrip(id: tripId)
        Task { [weak self] in
            await self?.memoryPageViewModel.refreshTrips()
        }
    }

    /// Bumps shared revision so trip-scoped surfaces and Memory refresh after detail mutations.
    func handleTripContentChanged() {
        lastDeletedTripId = nil
        tripDataRevision += 1
    }
}
