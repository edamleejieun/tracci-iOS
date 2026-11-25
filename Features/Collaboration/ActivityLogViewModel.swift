import Foundation
import Observation

/// ViewModel for journey history (§16.7).
@MainActor
@Observable
final class ActivityLogViewModel: DemoModeProviding {
    let tripId: String
    private let collaborationService: CollaborationService

    private(set) var logs: [ActivityLogResp] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Demo Journey read-only guard.
    var isDemoMode = false

    private let recentLimit = 10

    init(tripId: String, collaborationService: CollaborationService) {
        self.tripId = tripId
        self.collaborationService = collaborationService
    }

    func loadLogs() async {
        guard !isDemoMode else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await collaborationService.listActivityLogs(
                tripId: tripId,
                page: 1,
                pageSize: recentLimit
            )
            logs = Array(response.list.filter(\.isContentHistoryVisible).prefix(recentLimit))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isDemoMode else { return }
        await loadLogs()
    }

    /// Demo Journey: hydrate activity list from Bundle without network.
    func applyDemoLogs(_ logs: [ActivityLogResp]) {
        isDemoMode = true
        self.logs = Array(logs.filter(\.isContentHistoryVisible).prefix(recentLimit))
        isLoading = false
        errorMessage = nil
    }
}
