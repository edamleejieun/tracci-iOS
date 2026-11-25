import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Phase 3 编辑旅程的字段写入、确认重试、快照一致性与权限门禁。
@MainActor
final class TripEditViewModelTests: XCTestCase {
    private var stub: HTTPStub!

    override func setUp() {
        super.setUp()
        stub = HTTPStub()
        stub.install()
    }

    override func tearDown() {
        stub.removeAllResponses()
        stub.resetRequestLog()
        stub.uninstall()
        stub = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService() -> TripService {
        TripService(
            apiClient: stub.makeAPIClient(),
            fileUploadService: FileUploadService(apiClient: stub.makeAPIClient())
        )
    }

    private func makeTrip(
        id: String = "trip-1",
        title: String = "旧名",
        status: TripStatus = .planning
    ) -> Trip {
        let dates: (start: String, end: String)
        switch status {
        case .completed:
            dates = ("2000-08-01", "2000-08-05")
        case .ongoing:
            let today = TripDateFormatting.apiString(from: Date())
            dates = (today, today)
        case .planning, .unknown:
            dates = ("2099-08-01", "2099-08-05")
        }
        return Trip(
            id: id,
            title: title,
            startDate: dates.start,
            endDate: dates.end,
            status: status,
            totalDays: 5,
            destination: TripDestination(name: "Tokyo", provider: "APPLE"),
            coverPhoto: nil,
            baseCurrency: "CNY",
            totalCny: nil,
            nodeCount: nil,
            journalCount: nil,
            expenseCount: nil,
            access: TripAccessContext(role: .owner, permissions: [.updateTrip, .deleteTrip, .editContent]),
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-15T00:00:00Z"
        )
    }

    private func makeVM(
        trip: Trip? = nil,
        access: TripAccessContext? = nil,
        coverUploader: TripEditViewModel.CoverUploader? = nil
    ) -> TripEditViewModel {
        TripEditViewModel(
            trip: trip ?? makeTrip(),
            tripService: makeService(),
            initialAccess: access,
            coverUploader: coverUploader
        )
    }

    private func stubSuccessfulUpdate(title: String = "旧名", status: String = "PLANNING") {
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "PUT",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-1", title: title, status: status)
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "GET",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-1", title: title, status: status)
        )
    }

    private func requestBody(method: String = "PUT", at index: Int = 0) throws -> [String: Any] {
        let matching = stub.recordedRequests().filter { $0.httpMethod == method }
        let request = try XCTUnwrap(matching[safe: index])
        let data = try XCTUnwrap(request.httpBodyData)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - 权限与显示

    func testPermissions_followResolvedAccess() {
        let noDelete = TripAccessContext(role: .editor, permissions: [.updateTrip])
        let vm = makeVM(access: noDelete)

        XCTAssertTrue(vm.canUpdateTrip)
        XCTAssertFalse(vm.canDeleteTrip)
        XCTAssertEqual(vm.destinationDisplayValue, "Tokyo")
        XCTAssertEqual(vm.dateRangeDisplayValue, "2099.08.01 — 2099.08.05 · 5 天")
    }

    func testApplyAccess_overridesResolvedAccess() {
        let vm = makeVM()
        vm.applyAccess(TripAccessContext(role: .viewer, permissions: [.read]))

        XCTAssertFalse(vm.canUpdateTrip)
        XCTAssertFalse(vm.canDeleteTrip)
    }

    // MARK: - 标题

    func testUpdateTitle_success_updatesBodyAndCanonicalSnapshot() async throws {
        let vm = makeVM()
        stubSuccessfulUpdate(title: "新名")

        let ok = await vm.updateTitle("  新名  ")

        XCTAssertTrue(ok)
        XCTAssertEqual(vm.trip.title, "新名")
        XCTAssertEqual(try requestBody()["title"] as? String, "新名")
        XCTAssertNil(vm.mutationError)
        XCTAssertNil(vm.activeMutation)
    }

    func testUpdateTitle_validationFailsWithoutNetwork() async {
        let vm = makeVM()

        let emptyResult = await vm.updateTitle("   ")
        XCTAssertFalse(emptyResult)
        XCTAssertEqual(vm.mutationError, "请输入旅程名称")
        XCTAssertTrue(stub.recordedRequests().isEmpty)

        vm.clearMutationError()
        let longResult = await vm.updateTitle(String(repeating: "旅", count: 51))
        XCTAssertFalse(longResult)
        XCTAssertEqual(vm.mutationError, "旅程名称不能超过 50 字")
        XCTAssertTrue(stub.recordedRequests().isEmpty)
    }

    func testUpdateTitle_networkError_keepsEditorErrorAndReleasesToken() async {
        let vm = makeVM()
        stub.stubHTTPError(
            path: "/api/v1/trips/trip-1",
            method: "PUT",
            statusCode: 500,
            code: 50000,
            message: "server boom"
        )

        let result = await vm.updateTitle("新名")
        XCTAssertFalse(result)
        XCTAssertNotNil(vm.mutationError)
        XCTAssertNil(vm.activeMutation)
    }

    // MARK: - 目的地

    func testUpdateDestination_structuredDestination_replacesBody() async throws {
        let vm = makeVM()
        stubSuccessfulUpdate()
        let destination = TripDestination(
            name: "Kyoto",
            provider: "APPLE",
            providerPlaceId: "kyoto-1",
            country: "日本"
        )

        let result = await vm.updateDestination(destination, manualName: nil)
        XCTAssertTrue(result)

        let body = try requestBody()
        let encoded = try XCTUnwrap(body["destination"] as? [String: Any])
        XCTAssertEqual(encoded["name"] as? String, "Kyoto")
        XCTAssertEqual(encoded["provider"] as? String, "APPLE")
        XCTAssertEqual(encoded["providerPlaceId"] as? String, "kyoto-1")
    }

    func testUpdateDestination_manualName_clearsOldStructuredDestination() async throws {
        let vm = makeVM()
        stubSuccessfulUpdate()

        let result = await vm.updateDestination(nil, manualName: "  自定义地点  ")
        XCTAssertTrue(result)

        let body = try requestBody()
        let encoded = try XCTUnwrap(body["destination"] as? [String: Any])
        XCTAssertEqual(encoded["name"] as? String, "自定义地点")
        XCTAssertEqual(encoded["provider"] as? String, "MANUAL")
        XCTAssertNil(encoded["providerPlaceId"])
    }

    func testUpdateDestination_invalidManualName_failsWithoutNetwork() async {
        let vm = makeVM()

        let result = await vm.updateDestination(nil, manualName: "   ")
        XCTAssertFalse(result)
        XCTAssertEqual(vm.mutationError, "请输入目的地")
        XCTAssertTrue(stub.recordedRequests().isEmpty)
    }

    // MARK: - 快照一致性

    func testUpdateResponse_isCanonicalAndNextMutationUsesIt() async throws {
        let vm = makeVM()
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "PUT",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-1", title: "新名")
        )

        let titleResult = await vm.updateTitle("新名")
        XCTAssertTrue(titleResult)
        XCTAssertEqual(vm.trip.title, "新名")
        XCTAssertEqual(stub.recordedRequests().filter { $0.httpMethod == "GET" }.count, 0)

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "PUT",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-1", title: "新名")
        )
        let destinationResult = await vm.updateDestination(nil, manualName: "大阪")
        XCTAssertTrue(destinationResult)

        let secondBody = try requestBody(at: 1)
        XCTAssertEqual(secondBody["title"] as? String, "新名", "后续全量 PUT 必须基于上次 PUT 返回快照")
    }

    // MARK: - 日期确认

    func testUpdateDates_completedTrip_confirmContinuesSameMutationAndReturnsSuccess() async throws {
        let vm = makeVM(trip: makeTrip(status: .completed))
        var promptCount = 0
        vm.onDateChangeNeedsConfirmation = { _, onConfirm, _ in
            promptCount += 1
            onConfirm()
        }
        stubSuccessfulUpdate(status: "PLANNING")

        let start = TripDateFormatting.date(from: "2099-08-01")!
        let futureEnd = TripDateFormatting.date(from: "2099-08-05")!
        let ok = await vm.updateDates(start: start, end: futureEnd)

        XCTAssertTrue(ok)
        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(try requestBody()["statusChangeConfirmed"] as? Bool, true)
        XCTAssertNil(vm.activeMutation)
    }

    func testUpdateDates_completedTrip_cancelDoesNotWrite() async {
        let vm = makeVM(trip: makeTrip(status: .completed))
        vm.onDateChangeNeedsConfirmation = { _, _, onCancel in onCancel() }

        let start = TripDateFormatting.date(from: "2099-08-01")!
        let futureEnd = TripDateFormatting.date(from: "2099-08-05")!

        let result = await vm.updateDates(start: start, end: futureEnd)
        XCTAssertFalse(result)
        XCTAssertTrue(stub.recordedRequests().isEmpty)
        XCTAssertNil(vm.activeMutation)
    }

    func testUpdateDates_missingConfirmationPresenter_surfacesError() async {
        let vm = makeVM(trip: makeTrip(status: .completed))
        let start = TripDateFormatting.date(from: "2099-08-01")!
        let futureEnd = TripDateFormatting.date(from: "2099-08-05")!

        let result = await vm.updateDates(start: start, end: futureEnd)
        XCTAssertFalse(result)
        XCTAssertNotNil(vm.mutationError)
        XCTAssertTrue(stub.recordedRequests().isEmpty)
    }

    func testUpdateDates_server42235_confirmRetriesOnce() async throws {
        let vm = makeVM()
        stub.stubAPIBusinessError(
            path: "/api/v1/trips/trip-1",
            method: "PUT",
            code: TripAPIBusinessCode.statusChangeRequiresConfirm,
            message: "修改日期会改变旅程状态"
        )
        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-1",
            method: "GET",
            dataJSON: TripServiceFixtures.tripJSON(id: "trip-1", title: "旧名")
        )
        vm.onDateChangeNeedsConfirmation = { [stub] _, onConfirm, _ in
            stub?.stubAPISuccess(
                path: "/api/v1/trips/trip-1",
                method: "PUT",
                dataJSON: TripServiceFixtures.tripJSON(id: "trip-1", title: "旧名")
            )
            onConfirm()
        }

        let start = TripDateFormatting.date(from: "2026-09-01")!
        let end = TripDateFormatting.date(from: "2026-09-05")!

        let result = await vm.updateDates(start: start, end: end)
        XCTAssertTrue(result)
        XCTAssertEqual(stub.recordedRequests().filter { $0.httpMethod == "PUT" }.count, 2)
        XCTAssertEqual(try requestBody(at: 1)["statusChangeConfirmed"] as? Bool, true)
    }

    func testUpdateDates_invalidRange_failsWithoutNetwork() async {
        let vm = makeVM()
        let start = TripDateFormatting.date(from: "2026-09-05")!
        let end = TripDateFormatting.date(from: "2026-09-01")!

        let result = await vm.updateDates(start: start, end: end)
        XCTAssertFalse(result)
        XCTAssertEqual(vm.mutationError, "结束日期不能早于开始日期")
        XCTAssertTrue(stub.recordedRequests().isEmpty)
    }

    // MARK: - 封面

    func testUploadCover_afterFileConfirm_writesCoverFileIdToTrip() async throws {
        let vm = makeVM(coverUploader: { _, _, _, _, _, _ in
            FileConfirmResponse(id: "cover-file-2", previewUrl: "https://example.com/cover.jpg")
        })
        stubSuccessfulUpdate()

        let ok = await vm.uploadCover(
            imageData: Data([0x01, 0x02]),
            fileName: "cover.jpg",
            contentType: "image/jpeg",
            width: 1200,
            height: 800
        )

        XCTAssertTrue(ok)
        XCTAssertEqual(try requestBody()["coverFileId"] as? String, "cover-file-2")
        XCTAssertNil(vm.activeMutation)
    }

    // MARK: - 删除

    func testDeleteTrip_withPermission_succeeds() async {
        let vm = makeVM()
        stub.stubAPISuccess(path: "/api/v1/trips/trip-1", method: "DELETE", dataJSON: "null")

        let result = await vm.deleteTrip()
        XCTAssertTrue(result)
        XCTAssertNil(vm.deleteError)
        XCTAssertFalse(vm.isDeleting)
    }

    func testDeleteTrip_withoutPermission_failsWithoutNetwork() async {
        let access = TripAccessContext(role: .editor, permissions: [.updateTrip])
        let vm = makeVM(access: access)

        let result = await vm.deleteTrip()
        XCTAssertFalse(result)
        XCTAssertEqual(vm.deleteError, "没有权限删除此旅程")
        XCTAssertTrue(stub.recordedRequests().isEmpty)
    }

    func testDeleteTrip_networkError_setsDeleteError() async {
        let vm = makeVM()
        stub.stubHTTPError(
            path: "/api/v1/trips/trip-1",
            method: "DELETE",
            statusCode: 500,
            code: 50000,
            message: "boom"
        )

        let result = await vm.deleteTrip()
        XCTAssertFalse(result)
        XCTAssertNotNil(vm.deleteError)
        XCTAssertFalse(vm.isDeleting)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
