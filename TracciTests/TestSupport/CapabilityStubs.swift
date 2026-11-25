import CoreLocation
import Foundation
import MapKit
import UIKit
@testable import Tracci
import TracciNetworking
import TracciTestSupport

// MARK: - SavedPlaceServicing

/// Configurable `SavedPlaceServicing` stub/spy for Feature-level ViewModel tests.
@MainActor
final class SavedPlaceServicingStub: SavedPlaceServicing {
    enum Method: String {
        case create
        case list
        case updateNote
        case delete
        case placeDetail
        case publishedPlaces
    }

    let recorder = CallRecorder<Method, String>()

    var listHandler: ((SavedPlaceListQuery) async throws -> PageResponse<SavedPlace>)?
    var createHandler: ((CreateSavedPlaceRequest) async throws -> SavedPlace)?
    var updateNoteHandler: ((String, String?) async throws -> SavedPlace)?
    var deleteHandler: ((String) async throws -> Void)?
    var placeDetailHandler: ((String) async throws -> PlaceDetail)?
    var publishedPlacesHandler: ((PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace>)?

    /// Default page payload used when handlers are nil.
    var defaultList: PageResponse<SavedPlace> = PageResponse(list: [], total: 0, page: 1, pageSize: 20)
    var defaultPublishedPlaces: PageResponse<PublishedPlace> = PageResponse(list: [], total: 0, page: 1, pageSize: 50)
    var defaultPlace: SavedPlace = SavedPlaceFixtures.sample
    var defaultDetail: PlaceDetail = SavedPlaceFixtures.sampleDetail

    private(set) var queries: [SavedPlaceListQuery] = []
    private(set) var publishedPlaceQueries: [PublishedPlacesQuery] = []
    private(set) var createdRequests: [CreateSavedPlaceRequest] = []

    func resetRecordedCalls() {
        queries.removeAll()
        publishedPlaceQueries.removeAll()
        createdRequests.removeAll()
        recorder.reset()
    }

    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace {
        recorder.record(method: .create, arguments: [request.placeId ?? "location"])
        createdRequests.append(request)
        if let createHandler {
            return try await createHandler(request)
        }
        return defaultPlace
    }

    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> {
        recorder.record(method: .list, arguments: ["page=\(query.page)", query.keyword ?? ""])
        queries.append(query)
        if let listHandler {
            return try await listHandler(query)
        }
        return defaultList
    }

    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace {
        recorder.record(method: .updateNote, arguments: [savedPlaceId, note ?? ""])
        if let updateNoteHandler {
            return try await updateNoteHandler(savedPlaceId, note)
        }
        return defaultPlace
    }

    func delete(savedPlaceId: String) async throws {
        recorder.record(method: .delete, arguments: [savedPlaceId])
        if let deleteHandler {
            try await deleteHandler(savedPlaceId)
        }
    }

    func placeDetail(placeId: String) async throws -> PlaceDetail {
        recorder.record(method: .placeDetail, arguments: [placeId])
        if let placeDetailHandler {
            return try await placeDetailHandler(placeId)
        }
        return defaultDetail
    }

    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> {
        recorder.record(method: .publishedPlaces, arguments: [
            query.placeScope?.rawValue ?? "",
            query.cityName ?? "",
            "page=\(query.page)",
        ])
        publishedPlaceQueries.append(query)
        if let publishedPlacesHandler {
            return try await publishedPlacesHandler(query)
        }
        return defaultPublishedPlaces
    }
}

enum SavedPlaceFixtures {
    static let samplePlace = PlaceSummary(
        name: "清水寺",
        placeScope: .poi,
        category: .attraction,
        address: "京都府京都市",
        cityName: "京都",
        country: "日本",
        latitude: 34.9949,
        longitude: 135.7850,
        supportedUsages: [.itineraryNode, .tripDestination]
    )

    static let sample = SavedPlace(
        id: "saved-1",
        placeId: "place-1",
        place: samplePlace,
        note: nil,
        usageSummary: nil,
        createdAt: "2026-08-02T10:00:00Z",
        updatedAt: nil
    )

    static let sample2 = SavedPlace(
        id: "saved-2",
        placeId: "place-2",
        place: samplePlace,
        note: "二页",
        usageSummary: nil,
        createdAt: "2026-08-02T11:00:00Z",
        updatedAt: nil
    )

    static let sampleDetail = PlaceDetail(
        id: "place-1",
        name: "清水寺",
        placeScope: .poi,
        category: .attraction,
        address: "京都府京都市",
        cityName: "京都",
        country: "日本",
        latitude: 34.9949,
        longitude: 135.7850,
        supportedUsages: [.itineraryNode],
        userContext: PlaceUserContext(
            isSaved: true,
            savedPlaceId: "saved-1",
            note: nil,
            usageSummary: nil
        ),
        editorialContent: nil,
        contentMeta: nil,
        media: nil
    )
}

// MARK: - TripRouteProviding

actor TripRouteProviderStub: TripRouteProviding {
    private(set) var routeCallCount = 0
    private(set) var clearCacheCount = 0
    var coordinates: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0),
        CLLocationCoordinate2D(latitude: 35.01, longitude: 135.01)
    ]
    var error: Error?

    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType
    ) async throws -> [CLLocationCoordinate2D] {
        routeCallCount += 1
        if let error { throw error }
        return coordinates
    }

    func clearCache() async {
        clearCacheCount += 1
    }
}

// MARK: - PhoneAuthProviding

@MainActor
final class PhoneAuthProviderStub: PhoneAuthProviding {
    var isConfigured = true
    var environmentAvailable = true
    var token = "test-token"
    var requestError: Error?
    private(set) var requestCount = 0
    private(set) var prepareCount = 0
    private(set) var dismissCount = 0

    func prepareForOneTapPresentation() async {
        prepareCount += 1
    }

    func checkEnvironmentAvailable() async throws -> Bool {
        environmentAvailable
    }

    func requestOneTapLogin(from controller: UIViewController) async throws -> String {
        requestCount += 1
        if let requestError { throw requestError }
        return token
    }

    func dismissLoginPage() {
        dismissCount += 1
    }
}

// MARK: - Service fixture JSON (for HTTP stub tests)

enum TripServiceFixtures {
    /// Minimal Trip JSON that `Trip` can decode.
    static func tripJSON(
        id: String = "trip-1",
        title: String = "测试旅程",
        status: String = "PLANNING"
    ) -> String {
        """
        {"id":"\(id)","title":"\(title)","startDate":"2026-08-01","endDate":"2026-08-05","status":"\(status)","totalDays":5,"destination":{"name":"Tokyo"},"baseCurrency":"CNY","nodeCount":3,"journalCount":2,"expenseCount":1,"access":{"role":"owner"},"createdAt":"2026-07-01T00:00:00Z","updatedAt":"2026-07-15T00:00:00Z"}
        """
    }

    static func tripPageJSON(ids: [String] = ["trip-1"]) -> String {
        let items = ids.map { tripJSON(id: $0) }.joined(separator: ",")
        return """
        {"list":[\(items)],"total":\(ids.count),"page":1,"pageSize":20}
        """
    }
}
