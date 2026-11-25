import Foundation
import Observation

@Observable
@MainActor
final class ProfileViewModel {
    private let authService: AuthService
    private let statsService: StatsService
    let updateChecker: AppUpdateChecker

    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var statsOverview: StatsOverview?
    var errorMessage: String?

    init(
        authService: AuthService,
        statsService: StatsService,
        updateChecker: AppUpdateChecker
    ) {
        self.authService = authService
        self.statsService = statsService
        self.updateChecker = updateChecker
    }

    func loadUser(into authSession: AuthSession) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await authService.getCurrentUser()
            authSession.restoreUser(user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshUser(into authSession: AuthSession) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let user = try await authService.getCurrentUser()
            authSession.restoreUser(user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadStats() async {
        do {
            statsOverview = try await statsService.fetchOverview().overview
        } catch {
            // Supplementary data keeps its last successful value on transient failure.
        }
    }

    func checkForUpdate() async {
        await updateChecker.checkForUpdate(userInitiated: false)
    }
}
