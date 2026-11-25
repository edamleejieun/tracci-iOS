import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

@MainActor
final class ItineraryNodeEditViewModelTests: XCTestCase {
    private var stub: HTTPStub!
    private var routeProvider: TripRouteProviderStub!
    private let locationJSON = #"{"name":"清水寺","provider":"APPLE"}"#

    override func setUp() {
        super.setUp()
        stub = HTTPStub()
        stub.install()
        routeProvider = TripRouteProviderStub()
    }

    override func tearDown() {
        stub.removeAllResponses()
        stub.resetRequestLog()
        stub.uninstall()
        stub = nil
        routeProvider = nil
        super.tearDown()
    }

    func testStartsFromCurrentNodeValuesWithoutSearching() async {
        let node = makeNode(title: "旧标题", note: "旧备注", startTime: "09:00", endTime: "10:00")
        let (model, _) = await makeModel(node: node)

        XCTAssertEqual(model.form.dayIndex, 1)
        XCTAssertEqual(model.form.title, "旧标题")
        XCTAssertEqual(model.form.note, "旧备注")
        XCTAssertEqual(model.form.startTime, "09:00")
        XCTAssertEqual(model.form.locationName, "清水寺")
        XCTAssertFalse(model.isNoteOnly)
        XCTAssertNil(model.activeMutation)
    }

    func testUpdateTitleSendsFullSnapshotAndAdoptsRefresh() async throws {
        let node = makeNode(title: "旧标题")
        let (model, itinerary) = await makeModel(node: node)
        stubSuccessfulUpdate(node: node, title: "新标题")

        let ok = await model.updateTitle("新标题")

        XCTAssertTrue(ok)
        XCTAssertEqual(model.form.title, "新标题")
        let body = try putBody()
        XCTAssertEqual(body["title"] as? String, "新标题")
        XCTAssertEqual(body["type"] as? String, "attraction")
        XCTAssertNotNil(body["location"])
        XCTAssertEqual(itinerary.selectedDayIndex, 1)
    }

    func testEmptyTitleStillSubmitsFallbackEmptyString() async throws {
        let node = makeNode(title: "旧标题")
        let (model, _) = await makeModel(node: node)
        stubSuccessfulUpdate(node: node, title: "")

        let ok = await model.updateTitle("   ")

        XCTAssertTrue(ok)
        let body = try putBody()
        XCTAssertEqual(body["title"] as? String, "")
    }

    func testUpdateDayMovesToNewDayEndpoint() async throws {
        let node = makeNode()
        let (model, itinerary) = await makeModel(node: node)
        stubSuccessfulUpdate(node: node, dayIndex: 2)

        let ok = await model.updateDay(2)

        XCTAssertTrue(ok)
        let put = try XCTUnwrap(stub.recordedRequests().first { $0.httpMethod == "PUT" })
        XCTAssertEqual(put.url?.path, "/api/v1/trips/trip-1/days/day-2/nodes/node-1")
        XCTAssertEqual(itinerary.selectedDayIndex, 2)
    }

    func testUpdateTypeToTransportClearsTitleAndSendsTransportDetails() async throws {
        let node = makeNode(title: "自定义标题")
        let (model, _) = await makeModel(node: node)
        stubSuccessfulUpdate(node: node, type: "transport", title: "")

        let ok = await model.updateType(.transport)

        XCTAssertTrue(ok)
        let body = try putBody()
        XCTAssertEqual(body["title"] as? String, "")
        XCTAssertEqual(body["type"] as? String, "transport")
        let details = try XCTUnwrap(body["details"] as? [String: Any])
        XCTAssertEqual(details["mode"] as? String, "flight")
    }

    func testClearTimeSendsEmptyEndTime() async throws {
        let node = makeNode(startTime: "09:00", endTime: "11:00")
        let (model, _) = await makeModel(node: node)
        stubSuccessfulUpdate(node: node, startTime: "09:00")

        let ok = await model.clearTime(.end)

        XCTAssertTrue(ok)
        let body = try putBody()
        XCTAssertEqual(body["startTime"] as? String, "09:00")
        XCTAssertNil(body["endTime"])
    }

    func testUpdateNoteClearsWithEmptyString() async throws {
        let node = makeNode(note: "旧备注")
        let (model, _) = await makeModel(node: node)
        stubSuccessfulUpdate(node: node, note: "")

        let ok = await model.updateNote("   ")

        XCTAssertTrue(ok)
        let body = try putBody()
        XCTAssertEqual(body["note"] as? String, "")
        XCTAssertEqual(body["type"] as? String, "attraction")
    }

    func testNoteOnlySendsNoteOnlyRequestAndBlocksStructuralEdits() async throws {
        let node = makeNode(note: "旧备注")
        let (model, _) = await makeModel(node: node, isNoteOnly: true)
        stubSuccessfulUpdate(node: node, note: "只改备注")

        XCTAssertTrue(model.isNoteOnly)
        let dayBlocked = await model.updateDay(2)
        let typeBlocked = await model.updateType(.hotel)
        XCTAssertFalse(dayBlocked)
        XCTAssertFalse(typeBlocked)
        XCTAssertEqual(model.form.dayIndex, 1)
        XCTAssertEqual(model.form.type, .attraction)
        XCTAssertTrue(stub.recordedRequests().filter { $0.httpMethod == "PUT" }.isEmpty)

        let ok = await model.updateNote("只改备注")
        XCTAssertTrue(ok)
        let body = try putBody()
        XCTAssertEqual(body["note"] as? String, "只改备注")
        XCTAssertNil(body["title"])
        XCTAssertNil(body["type"])
        XCTAssertNil(body["details"])
        XCTAssertNil(body["location"])
    }

    func testChangePlaceKeepsCurrentType() async throws {
        let node = makeNode(title: "午餐")
        let (model, _) = await makeModel(node: node)
        stubSuccessfulUpdate(node: node)
        let savedPlace = ItineraryFixtures.savedPlace(id: "saved-hotel", name: "溪畔酒店", category: .hotel)

        let ok = await model.updateSavedPlace(savedPlace)

        XCTAssertTrue(ok)
        let body = try putBody()
        let location = try XCTUnwrap(body["location"] as? [String: Any])
        XCTAssertEqual(location["name"] as? String, "溪畔酒店")
        XCTAssertEqual(body["type"] as? String, "attraction")
        XCTAssertEqual(body["title"] as? String, "午餐")
    }

    func testFailureRevertsDraftAndKeepsPreviousValues() async {
        let node = makeNode(title: "旧标题")
        let (model, _) = await makeModel(node: node)
        stub.stubAPIBusinessError(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/node-1",
            method: "PUT",
            code: 42236,
            message: "不能这样改"
        )

        let ok = await model.updateTitle("新标题")

        XCTAssertFalse(ok)
        XCTAssertEqual(model.form.title, "旧标题")
        XCTAssertNotNil(model.mutationError)
    }

    func testNoteLongerThan500IsRejectedLocally() async {
        let node = makeNode()
        let (model, _) = await makeModel(node: node)

        let ok = await model.updateNote(String(repeating: "啊", count: 501))

        XCTAssertFalse(ok)
        XCTAssertEqual(model.mutationError, "备注不能超过 500 字")
        XCTAssertTrue(stub.recordedRequests().filter { $0.httpMethod == "PUT" }.isEmpty)
    }

    // MARK: - Helpers

    private func makeNode(
        title: String = "测试节点",
        note: String? = nil,
        startTime: String? = "09:00",
        endTime: String? = "10:00",
        type: String = "attraction"
    ) -> ItineraryNodeItem {
        ItineraryFixtures.makeNodeItem(
            title: title,
            type: type,
            startTime: startTime,
            endTime: endTime,
            locationJSON: locationJSON,
            note: note
        )
    }

    private func makeModel(
        node: ItineraryNodeItem,
        isNoteOnly: Bool = false
    ) async -> (ItineraryNodeEditViewModel, ItineraryViewModel) {
        let trip = ItineraryFixtures.makeTrip(status: .planning, totalDays: 2)
        let itinerary = ItineraryViewModel(
            tripId: trip.id,
            trip: trip,
            itineraryService: ItineraryService(apiClient: stub.makeAPIClient()),
            savedPlaceService: nil,
            routeProvider: routeProvider
        )
        await load(itinerary, node: node)
        let model = ItineraryNodeEditViewModel(node: node, isNoteOnly: isNoteOnly, itinerary: itinerary)
        return (model, itinerary)
    }

    private func load(_ itinerary: ItineraryViewModel, node: ItineraryNodeItem) async {
        stub.stubAPISuccess(
            path: "/api/v1/trips/\(itinerary.tripId)/itinerary",
            dataJSON: ItineraryFixtures.twoDayResponseJSON(
                day1NodesJSON: [nodeJSON(from: node)]
            )
        )
        await itinerary.loadNodes()
    }

    private func stubSuccessfulUpdate(
        node: ItineraryNodeItem,
        dayIndex: Int = 1,
        type: String? = nil,
        title: String? = nil,
        note: String? = nil,
        startTime: String? = nil
    ) {
        let updatedType = type ?? node.type.rawValue
        let updatedTitle = title ?? node.title
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-\(dayIndex)/nodes/\(node.id)",
            method: "PUT",
            dataJSON: ItineraryFixtures.nodeDTOJSON(
                id: node.id,
                title: updatedTitle,
                type: updatedType,
                startTime: startTime ?? node.startTime,
                endTime: node.endTime,
                locationJSON: locationJSON,
                note: note ?? node.note
            )
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/itinerary",
            dataJSON: ItineraryFixtures.twoDayResponseJSON(
                day1NodesJSON: dayIndex == 1 ? [nodeJSON(from: node, title: updatedTitle, type: updatedType, note: note)] : [],
                day2NodesJSON: dayIndex == 2 ? [nodeJSON(from: node, title: updatedTitle, type: updatedType, note: note)] : []
            )
        )
    }

    private func nodeJSON(
        from node: ItineraryNodeItem,
        title: String? = nil,
        type: String? = nil,
        note: String? = nil
    ) -> String {
        ItineraryFixtures.nodeDTOJSON(
            id: node.id,
            title: title ?? node.title,
            type: type ?? node.type.rawValue,
            startTime: node.startTime,
            endTime: node.endTime,
            locationJSON: locationJSON,
            note: note ?? node.note
        )
    }

    private func putBody() throws -> [String: Any] {
        let put = try XCTUnwrap(stub.recordedRequests().first { $0.httpMethod == "PUT" })
        let data = try XCTUnwrap(put.httpBodyData)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
