import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Cross-service path/method mapping tests through `HTTPStub`.
/// Focus: URL construction and envelope decode — not full domain coverage.
final class ServiceMappingHTTPStubTests: XCTestCase {
    private var stub: HTTPStub!
    private var apiClient: APIClient!

    override func setUp() {
        super.setUp()
        stub = HTTPStub()
        stub.install()
        apiClient = stub.makeAPIClient()
    }

    override func tearDown() {
        stub.removeAllResponses()
        stub.resetRequestLog()
        stub.uninstall()
        stub = nil
        apiClient = nil
        super.tearDown()
    }

    // MARK: - TripService

    func testTripService_tripDetail_mapsPath() async throws {
        let service = TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-123",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-123", title: "API Path Test")
        )

        let result = try await service.tripDetail(id: "trip-123")
        XCTAssertEqual(result.id, "trip-123")
        XCTAssertEqual(result.title, "API Path Test")
        XCTAssertEqual(stub.recordedRequests().first?.httpMethod, "GET")
        XCTAssertEqual(stub.recordedRequests().first?.url?.path, "/api/v1/trips/trip-123")
    }

    func testTripService_createTrip_sendsPOST() async throws {
        let service = TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips",
            method: "POST",
            dataJSON: TripServiceFixtures.tripJSON(id: "new-trip", title: "From API")
        )

        let formState = TripFormState(
            title: "From API",
            destinationName: "Osaka",
            selectedDestination: nil,
            startDate: nil,
            endDate: nil,
            coverFileId: nil,
            coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
        let result = try await service.createTrip(CreateTripRequest(from: formState, baseCurrency: "CNY"))
        XCTAssertEqual(result.id, "new-trip")
        XCTAssertEqual(stub.recordedRequests().first?.httpMethod, "POST")
    }

    func testTripService_deleteTrip_sendsDELETE() async throws {
        let service = TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "DELETE",
            dataJSON: "null"
        )

        try await service.deleteTrip(id: "trip-1")
        XCTAssertEqual(stub.recordedRequests().first?.httpMethod, "DELETE")
    }

    // MARK: - ItineraryService

    func testItineraryService_fetch_mapsPath() async throws {
        let service = ItineraryService(apiClient: apiClient)
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/itinerary",
            dataJSON: #"{"tripId":"trip-1","days":[{"id":"day-1","dayIndex":1,"date":"2026-08-01","nodes":[]}]}"#
        )

        let result = try await service.fetchItinerary(tripId: "trip-1")
        XCTAssertEqual(result.tripId, "trip-1")
        XCTAssertEqual(result.days.count, 1)
        XCTAssertEqual(stub.recordedRequests().first?.httpMethod, "GET")
        XCTAssertEqual(stub.recordedRequests().first?.url?.path, "/api/v1/trips/trip-1/itinerary")
    }

    // MARK: - JournalService

    func testJournalService_listEntries_mapsPath() async throws {
        let service = JournalService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/journal?page=1&pageSize=20",
            dataJSON: #"{"list":[{"id":"j1","tripId":"trip-1","content":"Entry 1","photos":[]}],"total":1,"page":1,"pageSize":20}"#
        )

        let result = try await service.listEntries(tripId: "trip-1")
        XCTAssertEqual(result.list.count, 1)
        XCTAssertEqual(result.list.first?.id, "j1")
        XCTAssertEqual(stub.recordedRequests().first?.httpMethod, "GET")
        XCTAssertTrue(stub.recordedRequests().first?.url?.pathAndQuery.contains("journal") == true)
    }

    // MARK: - ExpenseService

    func testExpenseService_fetchSummary_mapsPath() async throws {
        let service = ExpenseService(apiClient: apiClient)
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/expenses/summary",
            dataJSON: #"{"totalCny":"150.00","perDayCny":"50.00","expenseCount":3,"breakdown":[{"category":"food","amountCny":"100.00","count":2,"ratio":0.67}]}"#
        )

        let result = try await service.fetchSummary(tripId: "trip-1")
        XCTAssertEqual(result.totalCny, "150.00")
        XCTAssertEqual(result.breakdown.first?.category, .food)
        XCTAssertEqual(stub.recordedRequests().first?.url?.path, "/api/v1/trips/trip-1/expenses/summary")
    }

    // MARK: - CollaborationService

    func testCollaborationService_listMembers_mapsPath() async throws {
        let service = CollaborationService(apiClient: apiClient)
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/members",
            dataJSON: #"[{"id":"m1","tripId":"trip-1","userId":"u1","nickname":"Test User","role":"owner","status":"ACTIVE"}]"#
        )

        let result = try await service.listMembers(tripId: "trip-1")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.role, .owner)
        XCTAssertEqual(stub.recordedRequests().first?.url?.path, "/api/v1/trips/trip-1/members")
    }

    // MARK: - SavedPlaceService

    func testSavedPlaceService_list_mapsPathAndQuery() async throws {
        let service = SavedPlaceService(apiClient: apiClient)
        stub.stubAPISuccess(
            path: "/api/v1/saved-places",
            dataJSON: #"{"list":[],"total":0,"page":1,"pageSize":20}"#,
            allowPathOnlyMatch: true
        )

        let query = SavedPlaceListQuery(usage: .itineraryNode, page: 1, pageSize: 20)
        let result = try await service.list(query)
        XCTAssertEqual(result.total, 0)

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.url?.path, "/api/v1/saved-places")
        XCTAssertTrue(request.url?.query?.contains("usage=ITINERARY_NODE") == true)
        XCTAssertTrue(request.url?.query?.contains("page=1") == true)
    }

    // MARK: - Error mapping

    func testServiceErrorMapping_businessCodeFromEnvelope() async throws {
        let service = TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
        stub.stubAPIBusinessError(
            path: "/api/v1/trips/missing",
            code: 404,
            message: "Not Found"
        )

        do {
            _ = try await service.tripDetail(id: "missing")
            XCTFail("Expected error")
        } catch let error as APIError {
            guard case let .business(code, message) = error else {
                return XCTFail("Expected business error, got \(error)")
            }
            XCTAssertEqual(code, 404)
            XCTAssertEqual(message, "Not Found")
        }
    }
}
