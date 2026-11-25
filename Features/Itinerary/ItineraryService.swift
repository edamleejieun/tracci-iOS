import Foundation
import TracciNetworking

struct ItineraryService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchItinerary(tripId: String) async throws -> ItineraryResponse {
        try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/itinerary"),
            as: ItineraryResponse.self
        )
    }

    func createNode(
        tripId: String,
        dayId: String,
        request: CreateItineraryNodeRequest
    ) async throws -> ItineraryNodeDTO {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/days/\(dayId)/nodes",
                method: .post,
                body: request
            ),
            as: ItineraryNodeDTO.self
        )
    }

    func updateNode(
        tripId: String,
        dayId: String,
        nodeId: String,
        request: UpdateItineraryNodeRequest
    ) async throws -> ItineraryNodeDTO {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/days/\(dayId)/nodes/\(nodeId)",
                method: .put,
                body: request
            ),
            as: ItineraryNodeDTO.self
        )
    }

    func deleteNode(tripId: String, dayId: String, nodeId: String) async throws {
        _ = try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/days/\(dayId)/nodes/\(nodeId)",
                method: .delete
            ),
            as: EmptyResponse.self
        )
    }

    /// Reorder all nodes for a day. `nodeIds` must include every node of that day in the new order.
    func reorderNodes(tripId: String, dayId: String, nodeIds: [String]) async throws {
        _ = try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/days/\(dayId)/nodes/reorder",
                method: .put,
                body: ReorderItineraryNodesRequest(nodeIds: nodeIds)
            ),
            as: EmptyResponse.self
        )
    }
}
