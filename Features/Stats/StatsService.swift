import Foundation
import TracciNetworking

struct StatsService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchOverview(tripId: String? = nil) async throws -> StatsOverviewResponse {
        try await apiClient.request(
            APIEndpoint(
                path: "stats/overview",
                queryItems: queryItems(tripId: tripId)
            ),
            as: StatsOverviewResponse.self
        )
    }

    private func queryItems(tripId: String?) -> [URLQueryItem] {
        // Align with TracciDateContext / stage-overview business day (Asia/Shanghai).
        var items = [URLQueryItem(name: "timeZone", value: TracciDateContext.timeZone.identifier)]
        if let tripId, !tripId.isEmpty {
            items.append(URLQueryItem(name: "tripId", value: tripId))
        }
        return items
    }
}
