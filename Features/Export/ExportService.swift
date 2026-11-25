import Foundation
import TracciNetworking

struct ExportService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchExportAssets(
        tripId: String,
        template: ExportTemplate,
        format: ExportFormat
    ) async throws -> ExportAssetsResponse {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/export-assets",
                queryItems: [
                    URLQueryItem(name: "template", value: template.rawValue),
                    URLQueryItem(name: "format", value: format.rawValue)
                ]
            ),
            as: ExportAssetsResponse.self
        )
    }

    func fetchItineraryExportAssets(
        tripId: String,
        selectedDates: [String]? = nil
    ) async throws -> ItineraryExportAssetsResponse {
        var queryItems: [URLQueryItem] = []
        if let selectedDates, !selectedDates.isEmpty {
            queryItems.append(
                URLQueryItem(name: "dates", value: selectedDates.joined(separator: ","))
            )
        }

        return try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/itinerary-export-assets",
                queryItems: queryItems
            ),
            as: ItineraryExportAssetsResponse.self
        )
    }

    func fetchTripSummary(tripId: String) async throws -> TripSummaryResponse {
        try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/summary"),
            as: TripSummaryResponse.self
        )
    }
}
