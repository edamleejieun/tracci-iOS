import Foundation
import TracciNetworking

/// Root dependency graph. This type stays at the App/Root assembly boundary.
struct AppDependencies {
    let authSession: AuthSession
    let phoneAuthProvider: any PhoneAuthProviding
    let mainScene: MainSceneDependencies
}

/// Dependencies required to assemble the authenticated main scene.
/// Leaf views and view models continue to receive only their direct dependencies.
struct MainSceneDependencies {
    let authService: AuthService
    let tripService: TripService
    let itineraryService: ItineraryService
    let journalService: JournalService
    let expenseService: ExpenseService
    let statsService: StatsService
    let exportService: ExportService
    let profileService: ProfileService
    let fileUploadService: FileUploadService
    let collaborationService: CollaborationService
    let demoJourneyService: DemoJourneyService
    let savedPlaceService: SavedPlaceService
    let appUpdateChecker: AppUpdateChecker
    let routeProvider: any TripRouteProviding
}
