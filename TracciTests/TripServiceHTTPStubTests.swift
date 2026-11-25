import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Characterizes `TripService` URL/path/query/method/body/error mapping via `HTTPStub`.
final class TripServiceHTTPStubTests: XCTestCase {
    private var stub: HTTPStub!
    private var tripService: TripService!

    override func setUp() {
        super.setUp()
        stub = HTTPStub()
        stub.install()
        let client = stub.makeAPIClient()
        tripService = TripService(
            apiClient: client,
            fileUploadService: FileUploadService(apiClient: client)
        )
    }

    override func tearDown() {
        stub.removeAllResponses()
        stub.resetRequestLog()
        stub.uninstall()
        stub = nil
        tripService = nil
        super.tearDown()
    }

    // MARK: - listTrips

    func testListTrips_buildsCorrectURLAndDecodesPage() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips?page=1&pageSize=20",
            dataJSON: TripServiceFixtures.tripPageJSON(ids: ["1"])
        )

        let result = try await tripService.listTrips()
        XCTAssertEqual(result.list.count, 1)
        XCTAssertEqual(result.list.first?.id, "1")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/trips")
        XCTAssertTrue(request.url?.query?.contains("page=1") == true)
        XCTAssertTrue(request.url?.query?.contains("pageSize=20") == true)
    }

    func testListTrips_includesKeywordQueryParam() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips?page=1&pageSize=20&keyword=Tokyo",
            dataJSON: #"{"list":[],"total":0,"page":1,"pageSize":20}"#
        )

        _ = try await tripService.listTrips(keyword: "Tokyo")
        let query = try XCTUnwrap(stub.recordedRequests().first?.url?.query)
        XCTAssertTrue(query.contains("keyword=Tokyo"))
    }

    func testListTrips_includesStatusQueryParamWithRawValue() async throws {
        // TripStatus.rawValue is lowercase (e.g. "ongoing"), matching list query construction.
        stub.stubAPISuccess(
            path: "/api/v1/trips?page=1&pageSize=20&status=ongoing",
            dataJSON: #"{"list":[],"total":0,"page":1,"pageSize":20}"#
        )

        _ = try await tripService.listTrips(status: .ongoing)
        let query = try XCTUnwrap(stub.recordedRequests().first?.url?.query)
        XCTAssertTrue(query.contains("status=ongoing"))
    }

    // MARK: - tripDetail

    func testTripDetail_buildsCorrectURL() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-42",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-42", title: "Test Trip")
        )

        let result = try await tripService.tripDetail(id: "trip-42")
        XCTAssertEqual(result.id, "trip-42")
        XCTAssertEqual(result.title, "Test Trip")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-42")
    }

    // MARK: - createTrip

    func testCreateTrip_sendsPOSTWithTitleInBody() async throws {
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
        let requestBody = CreateTripRequest(from: formState, baseCurrency: "CNY")
        let result = try await tripService.createTrip(requestBody)
        XCTAssertEqual(result.id, "new-trip")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/trips")

        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"title\":\"From API\""))
        XCTAssertTrue(body.contains("\"baseCurrency\":\"CNY\""))
    }

    // MARK: - updateTrip

    func testUpdateTrip_sendsPUTWithStatusChangeConfirmedInBody() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "PUT",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-1", title: "Updated")
        )

        let formState = TripFormState(
            title: "Updated",
            destinationName: "Osaka",
            selectedDestination: nil,
            startDate: nil,
            endDate: nil,
            coverFileId: nil,
            coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
        let requestBody = UpdateTripRequest(from: formState, baseCurrency: "CNY", statusChangeConfirmed: true)
        let result = try await tripService.updateTrip(id: "trip-1", requestBody)
        XCTAssertEqual(result.id, "trip-1")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-1")

        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"statusChangeConfirmed\":true"))
    }

    // MARK: - deleteTrip

    func testDeleteTrip_sendsDELETEAndAcceptsEmptyDataEnvelope() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "DELETE",
            dataJSON: "null"
        )

        try await tripService.deleteTrip(id: "trip-1")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-1")
    }

    // MARK: - stageOverview

    func testStageOverview_includesClientPlatformAndTimeZone() async throws {
        let overviewJSON = """
        {"generatedDate":"2026-08-07","timeZone":"Asia/Shanghai","timeZoneFallbackApplied":false,"phase":"NO_TRIP","focusTrip":null,"permissions":null,"selection":{"mode":"NONE","reason":"NO_TRIP","candidateCount":0},"planning":null,"ongoing":null,"memory":null,"completed":null,"actions":[]}
        """
        // Path-only match: query order is stable but timeZone comes from TracciDateContext.
        stub.stubAPISuccess(
            path: "/api/v1/trips/stage-overview",
            dataJSON: overviewJSON,
            allowPathOnlyMatch: true
        )

        _ = try await tripService.stageOverview(tripId: "trip-1")
        let request = try XCTUnwrap(stub.recordedRequests().first)
        let query = try XCTUnwrap(request.url?.query)
        XCTAssertTrue(query.contains("clientPlatform=IOS"))
        XCTAssertTrue(query.contains("timeZone="))
        XCTAssertTrue(query.contains("tripId=trip-1"))
    }

    // MARK: - Error handling

    func testTripDetail_propagatesBusinessErrorFromEnvelope() async throws {
        stub.stubAPIBusinessError(
            path: "/api/v1/trips/missing",
            code: 40401,
            message: "Not Found"
        )

        do {
            _ = try await tripService.tripDetail(id: "missing")
            XCTFail("Expected business error")
        } catch let error as APIError {
            guard case let .business(code, message) = error else {
                return XCTFail("Expected business error, got \(error)")
            }
            XCTAssertEqual(code, 40401)
            XCTAssertEqual(message, "Not Found")
        }
    }

    func testTripDetail_propagatesBusinessErrorFromHTTPStatusEnvelope() async throws {
        stub.stubHTTPError(
            path: "/api/v1/trips/missing",
            statusCode: 404,
            code: 404,
            message: "Not Found"
        )

        do {
            _ = try await tripService.tripDetail(id: "missing")
            XCTFail("Expected error")
        } catch let error as APIError {
            guard case let .business(code, _) = error else {
                return XCTFail("Expected business error from HTTP body, got \(error)")
            }
            XCTAssertEqual(code, 404)
        }
    }
}
