import Foundation
import TracciNetworking

actor TokenRefreshCoordinator {
    private var refreshTask: Task<RefreshTokenResult, Error>?

    func refreshIfNeeded(
        refreshToken: String?,
        refresh: @escaping @Sendable (String) async throws -> RefreshTokenResult
    ) async throws -> RefreshTokenResult {
        if let refreshTask {
            return try await refreshTask.value
        }

        guard let refreshToken, !refreshToken.isEmpty else {
            throw APIError.unauthorized
        }

        let task = Task {
            try await refresh(refreshToken)
        }
        refreshTask = task

        do {
            let result = try await task.value
            refreshTask = nil
            return result
        } catch {
            refreshTask = nil
            throw error
        }
    }
}
