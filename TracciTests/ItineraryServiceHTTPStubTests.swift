import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Characterizes `ItineraryService` URL/path/query/method/body/error mapping via `HTTPStub`.
final class ItineraryServiceHTTPStubTests: XCTestCase {
    private var stub: HTTPStub!
    private var service: ItineraryService!

    override func setUp() {
        super.setUp()
        stub = HTTPStub()
        stub.install()
        service = ItineraryService(apiClient: stub.makeAPIClient())
    }

    override func tearDown() {
        stub.removeAllResponses()
        stub.resetRequestLog()
        stub.uninstall()
        stub = nil
        service = nil
        super.tearDown()
    }

    // MARK: - fetchItinerary

    func testFetchItinerary_buildsCorrectURLAndDecodesDays() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/itinerary",
            dataJSON: ItineraryFixtures.twoDayResponseJSON(day1NodesJSON: [
                ItineraryFixtures.nodeDTOJSON(id: "node-1", title: "清水寺", type: "attraction", startTime: "09:00"),
            ])
        )

        let result = try await service.fetchItinerary(tripId: "trip-1")
        XCTAssertEqual(result.tripId, "trip-1")
        XCTAssertEqual(result.days.count, 2)
        XCTAssertEqual(result.days.first?.nodes.first?.title, "清水寺")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-1/itinerary")
    }

    func testFetchItinerary_decodesDetailsAndFlexibleSortOrder() async throws {
        let nodeJSON = ItineraryFixtures.nodeDTOJSON(
            id: "node-1",
            title: "航班",
            type: "transport",
            detailsJSON: #"{"mode":"flight","flightNo":"JL001"}"#,
            sortOrder: 2
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/itinerary",
            dataJSON: ItineraryFixtures.itineraryResponseJSON(
                tripId: "trip-1",
                daysJSON: [ItineraryFixtures.dayJSON(id: "day-1", dayIndex: 1, nodesJSON: [nodeJSON])]
            )
        )

        let node = try await service.fetchItinerary(tripId: "trip-1").days.first?.nodes.first
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.details?.transportMode, .flight)
        XCTAssertEqual(node?.details?.flightNo, "JL001")
        XCTAssertEqual(node?.sortOrder, 2)
    }

    // MARK: - createNode

    func testCreateNode_sendsPOSTWithBodyAndReturnsDTO() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes",
            method: "POST",
            dataJSON: ItineraryFixtures.nodeDTOJSON(id: "new-node", title: "新节点", type: "attraction")
        )

        let form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        let created = try await service.createNode(
            tripId: "trip-1",
            dayId: "day-1",
            request: CreateItineraryNodeRequest(from: form)
        )
        XCTAssertEqual(created.id, "new-node")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes")
        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"title\""))
    }

    // MARK: - updateNode

    func testUpdateNode_sendsPUTWithBody() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/node-1",
            method: "PUT",
            dataJSON: ItineraryFixtures.nodeDTOJSON(id: "node-1", title: "更新后", type: "attraction")
        )

        let form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        let updated = try await service.updateNode(
            tripId: "trip-1",
            dayId: "day-1",
            nodeId: "node-1",
            request: UpdateItineraryNodeRequest(from: form)
        )
        XCTAssertEqual(updated.title, "更新后")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes/node-1")
    }

    // MARK: - deleteNode

    func testDeleteNode_sendsDELETEAndAcceptsNullDataEnvelope() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/node-1",
            method: "DELETE",
            dataJSON: "null"
        )

        try await service.deleteNode(tripId: "trip-1", dayId: "day-1", nodeId: "node-1")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes/node-1")
    }

    // MARK: - reorderNodes

    func testReorderNodes_sendsPUTWithNodeIdsBody() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/reorder",
            method: "PUT",
            dataJSON: "null"
        )

        try await service.reorderNodes(tripId: "trip-1", dayId: "day-1", nodeIds: ["node-2", "node-1"])

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes/reorder")
        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"nodeIds\""))
        XCTAssertTrue(body.contains("node-2"))
        XCTAssertTrue(body.contains("node-1"))
    }

    // MARK: - Error handling

    func testCreateNode_propagatesBusinessErrorFromEnvelope() async throws {
        stub.stubAPIBusinessError(
            path: "/api/v1/trips/trip-1/days/day-1/nodes",
            method: "POST",
            code: 42236,
            message: "Node note-only"
        )

        let form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        do {
            _ = try await service.createNode(tripId: "trip-1", dayId: "day-1",
                                            request: CreateItineraryNodeRequest(from: form))
            XCTFail("Expected business error")
        } catch let error as APIError {
            guard case let .business(code, message) = error else {
                return XCTFail("Expected business error, got \(error)")
            }
            XCTAssertEqual(code, 42236)
            XCTAssertEqual(message, "Node note-only")
        }
    }

    func testFetchItinerary_propagatesBusinessErrorFromHTTPStatusEnvelope() async throws {
        stub.stubHTTPError(
            path: "/api/v1/trips/trip-1/itinerary",
            statusCode: 403,
            code: 403,
            message: "Forbidden"
        )

        do {
            _ = try await service.fetchItinerary(tripId: "trip-1")
            XCTFail("Expected error")
        } catch let error as APIError {
            guard case let .business(code, _) = error else {
                return XCTFail("Expected business error from HTTP body, got \(error)")
            }
            XCTAssertEqual(code, 403)
        }
    }
}
