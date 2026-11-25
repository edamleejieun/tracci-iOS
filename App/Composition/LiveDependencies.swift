import Foundation
import TracciNetworking

@MainActor
enum LiveDependencies {
    static func make() -> AppDependencies {
        let tokenStore = KeychainTokenStore()
        let authSession = AuthSession(tokenStore: tokenStore)

        #if DEBUG
        let networkConfig: NetworkConfig = .development
        #else
        let networkConfig: NetworkConfig = .production
        #endif

        let apiClient = APIClient(config: networkConfig, tokenProvider: authSession)
        let fileUploadService = FileUploadService(apiClient: apiClient)
        let authService = AuthService(apiClient: apiClient)

        authSession.configure(authService: authService)
        apiClient.unauthorizedRetryHandler = { [weak authSession] in
            guard let authSession else {
                return false
            }
            return await authSession.refreshSessionIfNeeded()
        }
        apiClient.accountDeletedHandler = { [weak authSession] in
            await MainActor.run {
                authSession?.clear()
            }
        }

        return AppDependencies(
            authSession: authSession,
            phoneAuthProvider: LivePhoneAuthAdapter(),
            mainScene: MainSceneDependencies(
                authService: authService,
                tripService: TripService(
                    apiClient: apiClient,
                    fileUploadService: fileUploadService
                ),
                itineraryService: ItineraryService(apiClient: apiClient),
                journalService: JournalService(
                    apiClient: apiClient,
                    fileUploadService: fileUploadService
                ),
                expenseService: ExpenseService(apiClient: apiClient),
                statsService: StatsService(apiClient: apiClient),
                exportService: ExportService(apiClient: apiClient),
                profileService: ProfileService(apiClient: apiClient),
                fileUploadService: fileUploadService,
                collaborationService: CollaborationService(apiClient: apiClient),
                demoJourneyService: DemoJourneyService(apiClient: apiClient),
                savedPlaceService: SavedPlaceService(apiClient: apiClient),
                appUpdateChecker: AppUpdateChecker(),
                routeProvider: RouteCacheService()
            )
        )
    }
}
