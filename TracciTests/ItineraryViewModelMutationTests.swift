import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Phase 0 表征：`ItineraryViewModel` 四种写操作（create / update / updateNote / delete）+
/// 酒店置底 reorder + demo 模式只读守卫。
///
/// VM 依赖具体 `ItineraryService` + `any TripRouteProviding`，故沿用 HTTPStub 范式
/// （真实 Service + `TripRouteProviderStub`），不新造协议 stub。
@MainActor
final class ItineraryViewModelMutationTests: XCTestCase {
    private var stub: HTTPStub!
    private var routeProvider: TripRouteProviderStub!

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

    // MARK: - Helpers

    private func makeService() -> ItineraryService {
        ItineraryService(apiClient: stub.makeAPIClient())
    }

    private func makeVM(trip: Trip) -> ItineraryViewModel {
        ItineraryViewModel(
            tripId: trip.id,
            trip: trip,
            itineraryService: makeService(),
            savedPlaceService: nil,
            routeProvider: routeProvider
        )
    }

    /// 构造通过校验的有效表单：有效地点 + 合法时间段。
    private func makeValidForm(dayIndex: Int = 1, type: ItineraryNodeType = .attraction) -> ItineraryNodeFormState {
        var form = ItineraryNodeFormState.create(defaultDayIndex: dayIndex)
        form.type = type
        form.locationName = "清水寺"
        form.startTime = "09:00"
        form.endTime = "10:00"
        return form
    }

    private func twoDayResponse(tripId: String = "trip-1") -> String {
        ItineraryFixtures.itineraryResponseJSON(
            tripId: tripId,
            daysJSON: [
                ItineraryFixtures.dayJSON(id: "day-1", dayIndex: 1, nodesJSON: []),
                ItineraryFixtures.dayJSON(id: "day-2", dayIndex: 2, nodesJSON: []),
            ]
        )
    }

    /// 桩两天行程并载入，使 `dayId(for:)` 可解析出 day-1 / day-2。
    private func loadTwoDays(_ vm: ItineraryViewModel) async {
        stub.stubAPISuccess(
            path: "/api/v1/trips/\(vm.tripId)/itinerary",
            dataJSON: twoDayResponse(tripId: vm.tripId)
        )
        await vm.loadNodes()
    }

    private func itineraryRefreshCount(tripId: String = "trip-1") -> Int {
        stub.recordedRequests().filter {
            $0.httpMethod == "GET" && $0.url?.path == "/api/v1/trips/\(tripId)/itinerary"
        }.count
    }

    // MARK: - createNode

    func testCreateNode_POSTsToDayId_refreshes_clearsCache_syncsSelectedDay() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)
        let refreshCountBeforeCreate = itineraryRefreshCount()

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes",
            method: "POST",
            dataJSON: ItineraryFixtures.nodeDTOJSON(id: "new-node", title: "新节点", type: "attraction")
        )

        let result = await vm.createNode(form: makeValidForm(dayIndex: 1))

        XCTAssertEqual(result, "new-node")

        let post = try XCTUnwrap(stub.recordedRequests().first { $0.httpMethod == "POST" })
        XCTAssertEqual(post.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes")

        // 创建后 refresh（GET）+ 清缓存 + 同步 selectedDay。
        XCTAssertEqual(
            itineraryRefreshCount(),
            refreshCountBeforeCreate + 1,
            "创建成功后应额外刷新一次 itinerary"
        )
        let cacheCount = await routeProvider.clearCacheCount
        XCTAssertGreaterThanOrEqual(cacheCount, 1)
        XCTAssertEqual(vm.selectedDayIndex, 1)
    }

    private var hasWriteRequest: Bool {
        stub.recordedRequests().contains { ["POST", "PUT", "DELETE"].contains($0.httpMethod ?? "") }
    }

    func testCreateNode_validationFailure_sendsNoRequest() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)

        var form = makeValidForm(dayIndex: 1)
        form.locationName = "" // 地点为空 → 校验失败

        let result = await vm.createNode(form: form)

        XCTAssertNil(result)
        XCTAssertFalse(hasWriteRequest, "校验失败不应发出写请求")
    }

    func testCreateNode_unknownDayIndex_reportsError() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)

        let result = await vm.createNode(form: makeValidForm(dayIndex: 99))

        XCTAssertNil(result)
        // dayIndex 超出 tripDays → validate 失败（设置 validationErrors，不设置 errorMessage）。
        XCTAssertNotNil(vm.validationMessage(for: .dayIndex))
        XCTAssertFalse(hasWriteRequest, "未知天不应发出写请求")
    }

    func testCreateNode_failureSetsErrorMessage() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)

        stub.stubAPIBusinessError(
            path: "/api/v1/trips/trip-1/days/day-1/nodes",
            method: "POST",
            code: 42236,
            message: "Node note-only"
        )

        let result = await vm.createNode(form: makeValidForm(dayIndex: 1))

        XCTAssertNil(result)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - 酒店置底 reorder

    func testCreateNode_nonHotelOnDayWithHotel_triggersReorder() async throws {
        // day-1 已有酒店（sortOrder 0）+ 景点（sortOrder 1）→ 新建非酒店节点后触发置底 reorder。
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)

        let day1 = ItineraryFixtures.dayJSON(id: "day-1", dayIndex: 1, nodesJSON: [
            ItineraryFixtures.nodeDTOJSON(id: "hotel-1", title: "酒店", type: "hotel", sortOrder: 0),
            ItineraryFixtures.nodeDTOJSON(id: "node-1", title: "景点", type: "attraction", sortOrder: 1),
        ])
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/itinerary",
            dataJSON: ItineraryFixtures.itineraryResponseJSON(tripId: "trip-1", daysJSON: [
                day1,
                ItineraryFixtures.dayJSON(id: "day-2", dayIndex: 2, nodesJSON: []),
            ])
        )
        await vm.loadNodes()

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes",
            method: "POST",
            dataJSON: ItineraryFixtures.nodeDTOJSON(id: "new-node", title: "新景点", type: "attraction")
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/reorder",
            method: "PUT",
            dataJSON: "null"
        )

        let result = await vm.createNode(form: makeValidForm(dayIndex: 1, type: .attraction))
        XCTAssertNotNil(result)

        let reorder = try XCTUnwrap(stub.recordedRequests().first { $0.url?.path == "/api/v1/trips/trip-1/days/day-1/nodes/reorder" })
        let body = try XCTUnwrap(reorder.httpBodyData.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("node-1"))
        XCTAssertTrue(body.contains("hotel-1"))
    }

    // MARK: - updateNode

    func testUpdateNode_sameDayPUTsOriginalDayId() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)
        let refreshCountBeforeUpdate = itineraryRefreshCount()

        let node = ItineraryFixtures.makeNodeItem(id: "node-1", tripId: "trip-1", dayId: "day-1", dayIndex: 1, type: "attraction")

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/node-1",
            method: "PUT",
            dataJSON: ItineraryFixtures.nodeDTOJSON(id: "node-1", title: "更新后", type: "attraction")
        )

        let ok = await vm.updateNode(node, form: makeValidForm(dayIndex: 1))

        XCTAssertTrue(ok)
        let put = try XCTUnwrap(stub.recordedRequests().first { $0.httpMethod == "PUT" })
        XCTAssertEqual(put.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes/node-1")
        XCTAssertEqual(vm.selectedDayIndex, 1)
        XCTAssertEqual(
            itineraryRefreshCount(),
            refreshCountBeforeUpdate + 1,
            "更新成功后应额外刷新一次 itinerary"
        )
    }

    func testUpdateNode_crossDayPUTsNewDayIdAndSwitchesSelectedDay() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)
        let refreshCountBeforeMove = itineraryRefreshCount()

        let node = ItineraryFixtures.makeNodeItem(id: "node-1", tripId: "trip-1", dayId: "day-1", dayIndex: 1, type: "attraction")

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-2/nodes/node-1",
            method: "PUT",
            dataJSON: ItineraryFixtures.nodeDTOJSON(id: "node-1", title: "更新后", type: "attraction")
        )

        let ok = await vm.updateNode(node, form: makeValidForm(dayIndex: 2))

        XCTAssertTrue(ok)
        let put = try XCTUnwrap(stub.recordedRequests().first { $0.httpMethod == "PUT" })
        XCTAssertEqual(put.url?.path, "/api/v1/trips/trip-1/days/day-2/nodes/node-1", "跨天应 PUT 到新天")
        XCTAssertEqual(vm.selectedDayIndex, 2, "跨天应切换 selectedDay")
        XCTAssertEqual(
            itineraryRefreshCount(),
            refreshCountBeforeMove + 1,
            "跨天更新成功后应额外刷新一次 itinerary"
        )
    }

    func testUpdateNode_failureReturnsFalseAndSetsErrorMessage() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)

        let node = ItineraryFixtures.makeNodeItem(id: "node-1", tripId: "trip-1", dayId: "day-1", dayIndex: 1, type: "attraction")

        stub.stubAPIBusinessError(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/node-1",
            method: "PUT",
            code: 42236,
            message: "Node note-only"
        )

        let ok = await vm.updateNode(node, form: makeValidForm(dayIndex: 1))

        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - updateNodeNote

    func testUpdateNodeNote_PUTsNoteOnlyPath() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)
        let refreshCountBeforeNoteUpdate = itineraryRefreshCount()

        let node = ItineraryFixtures.makeNodeItem(id: "node-1", tripId: "trip-1", dayId: "day-1", dayIndex: 1, type: "attraction")

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/node-1",
            method: "PUT",
            dataJSON: ItineraryFixtures.nodeDTOJSON(id: "node-1", title: "", type: "attraction", note: "新备注")
        )

        let ok = await vm.updateNodeNote(node, note: "新备注")

        XCTAssertTrue(ok)
        let put = try XCTUnwrap(stub.recordedRequests().first { $0.httpMethod == "PUT" })
        XCTAssertEqual(put.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes/node-1")
        let body = try XCTUnwrap(put.httpBodyData.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("\"note\""))
        XCTAssertEqual(
            itineraryRefreshCount(),
            refreshCountBeforeNoteUpdate + 1,
            "备注更新成功后应额外刷新一次 itinerary"
        )
    }

    // MARK: - deleteNode

    func testDeleteNode_sendsDELETEAndRefreshes() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        await loadTwoDays(vm)
        let refreshCountBeforeDelete = itineraryRefreshCount()

        let node = ItineraryFixtures.makeNodeItem(id: "node-1", tripId: "trip-1", dayId: "day-1", dayIndex: 1, type: "attraction")

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1/days/day-1/nodes/node-1",
            method: "DELETE",
            dataJSON: "null"
        )

        let ok = await vm.deleteNode(node)

        XCTAssertTrue(ok)
        let del = try XCTUnwrap(stub.recordedRequests().first { $0.httpMethod == "DELETE" })
        XCTAssertEqual(del.url?.path, "/api/v1/trips/trip-1/days/day-1/nodes/node-1")
        XCTAssertEqual(
            itineraryRefreshCount(),
            refreshCountBeforeDelete + 1,
            "删除成功后应额外刷新一次 itinerary"
        )
    }

    // MARK: - demo 模式只读守卫

    func testDemoMode_rejectsAllFourWrites_withToastAndNoRequests() async throws {
        let trip = ItineraryFixtures.makeTrip(id: "trip-1", title: "旅程", status: .planning, totalDays: 2)
        let vm = makeVM(trip: trip)
        vm.isDemoMode = true // 置先于 loadTwoDays，避免 demo 下 loadNodes 发 GET
        await loadTwoDays(vm)

        let node = ItineraryFixtures.makeNodeItem(id: "node-1", tripId: "trip-1", dayId: "day-1", dayIndex: 1, type: "attraction")

        let createResult = await vm.createNode(form: makeValidForm(dayIndex: 1))
        let updateResult = await vm.updateNode(node, form: makeValidForm(dayIndex: 1))
        let noteResult = await vm.updateNodeNote(node, note: "备注")
        let deleteResult = await vm.deleteNode(node)

        XCTAssertNil(createResult)
        XCTAssertFalse(updateResult)
        XCTAssertFalse(noteResult)
        XCTAssertFalse(deleteResult)
        XCTAssertEqual(vm.errorMessage, DemoReadOnlyCopy.toast)
        XCTAssertTrue(stub.recordedRequests().isEmpty, "demo 模式不应发出任何写请求")
    }
}
