import Foundation
import TracciNetworking

protocol SavedPlaceServicing {
    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace
    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace>
    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace
    func delete(savedPlaceId: String) async throws
    func placeDetail(placeId: String) async throws -> PlaceDetail
    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace>
}

struct SavedPlaceService: SavedPlaceServicing {
    private let apiClient: APIClient
    init(apiClient: APIClient) { self.apiClient = apiClient }
    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace { try await apiClient.request(APIEndpoint(path: "saved-places", method: .post, body: request), as: SavedPlace.self) }
    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> { try await apiClient.request(APIEndpoint(path: "saved-places", queryItems: query.queryItems), as: PageResponse<SavedPlace>.self) }
    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace {
        struct Body: Encodable { let note: String? }
        return try await apiClient.request(APIEndpoint(path: "saved-places/\(savedPlaceId)", method: .put, body: Body(note: note)), as: SavedPlace.self)
    }
    func delete(savedPlaceId: String) async throws { _ = try await apiClient.request(APIEndpoint(path: "saved-places/\(savedPlaceId)", method: .delete), as: EmptyResponse.self) }
    func placeDetail(placeId: String) async throws -> PlaceDetail { try await apiClient.request(APIEndpoint(path: "places/\(placeId)"), as: PlaceDetail.self) }
    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> { try await apiClient.request(APIEndpoint(path: "places", queryItems: query.queryItems), as: PageResponse<PublishedPlace>.self) }
}
