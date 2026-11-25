import Foundation
import TracciNetworking

struct TripService {
    private let apiClient: APIClient
    private let fileUploadService: FileUploadService

    init(apiClient: APIClient, fileUploadService: FileUploadService) {
        self.apiClient = apiClient
        self.fileUploadService = fileUploadService
    }

    func listTrips(
        page: Int = 1,
        pageSize: Int = 20,
        status: TripStatus? = nil,
        keyword: String? = nil
    ) async throws -> PageResponse<Trip> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]

        if let status, status != .unknown {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }

        if let keyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
            queryItems.append(URLQueryItem(name: "keyword", value: keyword))
        }

        return try await apiClient.request(
            APIEndpoint(
                path: "trips",
                queryItems: queryItems
            ),
            as: PageResponse<Trip>.self
        )
    }

    func tripDetail(id: String) async throws -> Trip {
        try await apiClient.request(
            APIEndpoint(path: "trips/\(id)"),
            as: Trip.self
        )
    }

    func tripWeather(id: String) async throws -> TripWeatherResponse {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(id)/weather",
                queryItems: [
                    URLQueryItem(name: "clientPlatform", value: "IOS")
                ]
            ),
            as: TripWeatherResponse.self
        )
    }

    func stageOverview(tripId: String? = nil) async throws -> TripStageOverview {
        var queryItems = [
            URLQueryItem(name: "clientPlatform", value: "IOS"),
            // Align with TracciDateContext / trip-detail business day (Asia/Shanghai).
            URLQueryItem(name: "timeZone", value: TracciDateContext.timeZone.identifier)
        ]
        if let tripId, !tripId.isEmpty {
            queryItems.append(URLQueryItem(name: "tripId", value: tripId))
        }

        return try await apiClient.request(
            APIEndpoint(path: "trips/stage-overview", queryItems: queryItems),
            as: TripStageOverview.self
        )
    }

    func createTrip(_ request: CreateTripRequest) async throws -> Trip {
        try await apiClient.request(
            APIEndpoint(
                path: "trips",
                method: .post,
                body: request
            ),
            as: Trip.self
        )
    }

    func updateTrip(id: String, _ request: UpdateTripRequest) async throws -> Trip {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(id)",
                method: .put,
                body: request
            ),
            as: Trip.self
        )
    }

    func deleteTrip(id: String) async throws {
        _ = try await apiClient.request(
            APIEndpoint(
                path: "trips/\(id)",
                method: .delete
            ),
            as: EmptyResponse.self
        )
    }

    // MARK: - Trip Cover Upload

    func uploadCoverImage(
        tripId: String?,
        imageData: Data,
        fileName: String,
        contentType: String,
        width: Int?,
        height: Int?
    ) async throws -> FileConfirmResponse {
        try await fileUploadService.uploadImage(
            businessType: "TRIP_COVER",
            businessId: tripId,
            imageData: imageData,
            fileName: fileName,
            contentType: contentType,
            width: width,
            height: height
        )
    }
}
