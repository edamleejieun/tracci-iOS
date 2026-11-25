import Foundation
import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Phase 2 表征：`TripCreateViewModel` 的 title 建议 / titleOrigin / 日期天数 / 校验 /
/// 重复提交 / 创建请求体 / 取消与 dismiss。
///
/// Create-only VM 与 Edit 共用 `TripService.createTrip` / `CreateTripRequest`，
/// 因此本测试聚焦 Create 独有的 presentation 行为（自动名称、origin 语义、Create 路径
/// 无 cover/member/permission）。HTTPStub 模式在 setUp/tearDown 中隔离，避免跨用例残留。
@MainActor
final class TripCreateViewModelTests: XCTestCase {
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
        TripService(apiClient: stub.makeAPIClient(),
                    fileUploadService: FileUploadService(apiClient: stub.makeAPIClient()))
    }

    private func makeVM() -> TripCreateViewModel {
        TripCreateViewModel(tripService: makeService())
    }

    /// 探索城市页「用这里创建旅程」带过来的目的地（规格 §7.3）。
    private func makeSeededVM() -> TripCreateViewModel {
        TripCreateViewModel(
            tripService: makeService(),
            seed: TripCreateSeed(destinationSavedPlaceId: "saved-9", destinationName: "杭州")
        )
    }

    private func makeDates(startOffset: Int, endOffset: Int) -> (start: Date, end: Date) {
        let calendar = TracciDateContext.calendar
        let today = TracciDateContext.today()
        let start = calendar.date(byAdding: .day, value: startOffset, to: today)!
        let end = calendar.date(byAdding: .day, value: endOffset, to: start)!
        return (start, end)
    }

    // MARK: - Title suggestion rule

    func testSuggestedTitle_noDestinationReturnsNil() {
        XCTAssertNil(TripCreateViewModel.suggestedTitle(destinationName: "", startDate: nil, endDate: nil))
        XCTAssertNil(TripCreateViewModel.suggestedTitle(destinationName: "   ", startDate: nil, endDate: nil))
    }

    func testSuggestedTitle_noDatesReturnsNil() {
        let title = TripCreateViewModel.suggestedTitle(destinationName: "京都", startDate: nil, endDate: nil)
        XCTAssertNil(title)
    }

    func testSuggestedTitle_inclusiveDayCount() {
        let (start, end) = makeDates(startOffset: 0, endOffset: 2) // 3 inclusive days
        let title = TripCreateViewModel.suggestedTitle(destinationName: "京都", startDate: start, endDate: end)
        XCTAssertEqual(title, "京都 3 日游")
    }

    func testSuggestedTitle_singleDayRange() {
        let (start, end) = makeDates(startOffset: 5, endOffset: 0) // same day
        let title = TripCreateViewModel.suggestedTitle(destinationName: "大阪", startDate: start, endDate: end)
        XCTAssertEqual(title, "大阪 1 日游")
    }

    // MARK: - Auto-title on destination / date selection

    func testSelectDestination_generatesDefaultTitle() {
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.updateDates(start: start, end: end)

        vm.selectDestination(TripDestination(name: "京都", country: "日本", latitude: 35.0, longitude: 135.7, cityName: "京都"))

        XCTAssertEqual(vm.title, "京都 3 日游")
        XCTAssertTrue(vm.showsTitleEditor)
    }

    func testUpdateDates_regeneratesTitleWhileGenerated() {
        let vm = makeVM()
        vm.selectDestination(TripDestination(name: "京都"))
        XCTAssertEqual(vm.title, "")
        XCTAssertFalse(vm.showsTitleEditor)

        let (start, end) = makeDates(startOffset: 0, endOffset: 4)
        vm.updateDates(start: start, end: end)
        XCTAssertEqual(vm.title, "京都 5 日游")
        XCTAssertTrue(vm.showsTitleEditor)
    }

    func testTitleEditorAppearsOnlyAfterDestinationAndValidDateRange() {
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)

        vm.selectDestination(TripDestination(name: "京都"))
        XCTAssertFalse(vm.showsTitleEditor)

        vm.updateDates(start: end, end: start)
        XCTAssertFalse(vm.showsTitleEditor)
        XCTAssertEqual(vm.title, "")

        vm.updateDates(start: start, end: end)
        XCTAssertTrue(vm.showsTitleEditor)
        XCTAssertEqual(vm.title, "京都 3 日游")
    }

    // MARK: - Title-origin semantics

    func testUserEditTitle_marksUserEditedAndStopsRegeneration() {
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.updateDates(start: start, end: end)
        vm.selectDestination(TripDestination(name: "京都"))
        XCTAssertEqual(vm.title, "京都 3 日游")

        // 用户手填名称
        vm.userDidEditTitle("我的京都之旅")
        XCTAssertEqual(vm.title, "我的京都之旅")

        // 目的地/日期变化不再覆盖手填名称
        let (start2, end2) = makeDates(startOffset: 0, endOffset: 6)
        vm.updateDates(start: start2, end: end2)
        XCTAssertEqual(vm.title, "我的京都之旅", "手填名称不应被目的地/日期变化静默覆盖")
    }

    func testClearingTitle_revertsToGeneratedAndReAdoptsSuggestion() {
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.updateDates(start: start, end: end)
        vm.selectDestination(TripDestination(name: "京都"))
        XCTAssertEqual(vm.title, "京都 3 日游")

        vm.userDidEditTitle("临时名称")
        vm.userDidEditTitle("") // 清空
        XCTAssertEqual(vm.title, "京都 3 日游", "清空标题应重新采用自动建议")
        XCTAssertTrue(vm.showsTitleEditor)
    }

    func testUserEditTitle_emptyBeforeAnyDestination_returnsEmpty() {
        let vm = makeVM()
        vm.userDidEditTitle("孤独的名称")
        XCTAssertEqual(vm.title, "孤独的名称")
        // 尚无 destination，清空后建议为 nil → 标题回到空
        vm.userDidEditTitle("")
        XCTAssertEqual(vm.title, "")
        XCTAssertFalse(vm.showsTitleEditor)
    }

    // MARK: - Inclusive day count

    func testInclusiveDayCount_matchesTracciDateContext() {
        let (start, end) = makeDates(startOffset: 0, endOffset: 4) // 5 inclusive days
        let expected = TracciDateContext.inclusiveDayCount(start: start, end: end)
        XCTAssertEqual(expected, 5)

        let title = TripCreateViewModel.suggestedTitle(destinationName: "东京", startDate: start, endDate: end)
        XCTAssertEqual(title, "东京 5 日游")
    }

    // MARK: - Validation matrix

    func testValidate_emptyForm() {
        let vm = makeVM()
        XCTAssertFalse(vm.validate())
        XCTAssertEqual(vm.validationMessage(for: .destination), "请输入旅行目的地")
        XCTAssertEqual(vm.validationMessage(for: .title), "请输入旅程名称")
        XCTAssertEqual(vm.validationMessage(for: .startDate), "请选择开始日期")
        XCTAssertEqual(vm.validationMessage(for: .endDate), "请选择结束日期")
    }

    func testValidate_titleBoundary50And51() {
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 1)
        vm.selectDestination(TripDestination(name: "东京"))
        vm.updateDates(start: start, end: end)

        vm.userDidEditTitle(String(repeating: "a", count: 50))
        XCTAssertTrue(vm.validate())

        vm.userDidEditTitle(String(repeating: "a", count: 51))
        XCTAssertFalse(vm.validate())
        XCTAssertEqual(vm.validationMessage(for: .title), "旅程名称不能超过 50 字")
    }

    func testValidate_destinationBoundary100And101() {
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 1)
        vm.updateDates(start: start, end: end)

        vm.useManualDestination(String(repeating: "目", count: 100))
        vm.userDidEditTitle("有效名称")
        XCTAssertTrue(vm.validate())
        XCTAssertTrue(vm.isFormValid)

        vm.useManualDestination(String(repeating: "目", count: 101))
        XCTAssertFalse(vm.validate())
        XCTAssertFalse(vm.isFormValid)
        XCTAssertEqual(vm.validationMessage(for: .destination), "目的地不能超过 100 字")
    }

    func testValidate_invertedDates() {
        let vm = makeVM()
        let calendar = TracciDateContext.calendar
        let today = TracciDateContext.today()
        vm.selectDestination(TripDestination(name: "东京"))
        // 手动构造 title 并通过 userDidEditTitle 写入
        vm.userDidEditTitle("东京 1 日游")
        vm.updateDates(start: calendar.date(byAdding: .day, value: 2, to: today)!, end: today)

        XCTAssertFalse(vm.validate())
        XCTAssertEqual(vm.validationMessage(for: .dateRange), "结束日期不能早于开始日期")
    }

    func testIsFormValid_completeForm() {
        let vm = makeVM()
        XCTAssertFalse(vm.isFormValid)

        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.selectDestination(TripDestination(name: "京都"))
        vm.updateDates(start: start, end: end)

        XCTAssertTrue(vm.isFormValid)
    }

    // MARK: - Submit

    func testSubmit_invalidFormSendsNoRequest() async throws {
        let vm = makeVM()
        let result = await vm.submit()
        XCTAssertNil(result)
        XCTAssertTrue(stub.recordedRequests().isEmpty)
    }

    func testSubmit_createPOSTBodyAndReturnsTrip() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips",
            method: "POST",
            dataJSON: TripServiceFixtures.tripJSON(id: "new-trip", title: "京都 3 日游")
        )
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.selectDestination(
            TripDestination(name: "京都", provider: "APPLE", country: "日本", latitude: 35.0, longitude: 135.7, cityName: "京都")
        )
        vm.updateDates(start: start, end: end)

        let result = await vm.submit()
        XCTAssertEqual(result?.id, "new-trip")

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"title\":\"京都 3 日游\""))
        XCTAssertTrue(body.contains("\"provider\":\"APPLE\""))
        // 从地图搜索创建：不携带 savedPlaceId（编码器会省略 nil 字段，因此该键不应出现）。
        XCTAssertFalse(body.contains("destinationSavedPlaceId"),
                       "Create via MapKit location should not send a savedPlaceId; body=\(body)")
    }

    func testSubmit_placeIdentityStillUsesOrdinaryDestinationWithoutSavedPlaceId() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips",
            method: "POST",
            dataJSON: TripServiceFixtures.tripJSON(id: "place-dest-trip", title: "京都 3 日游")
        )
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.updateDates(start: start, end: end)
        vm.selectDestination(
            TripDestination(name: "京都", country: "日本", latitude: 35.0, longitude: 135.7, cityName: "京都", placeId: "place-1")
        )

        let result = await vm.submit()
        XCTAssertEqual(result?.id, "place-dest-trip")

        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"destination\":"))
        XCTAssertFalse(body.contains("destinationSavedPlaceId"))
    }

    func testSubmit_manualDestination_sendsManualProvider() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips",
            method: "POST",
            dataJSON: TripServiceFixtures.tripJSON(id: "manual-trip", title: "自定义 1 日游")
        )
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 0)
        vm.useManualDestination("自定义")
        vm.updateDates(start: start, end: end)

        let result = await vm.submit()
        XCTAssertEqual(result?.id, "manual-trip")

        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"provider\":\"MANUAL\""))
    }

    func testSubmit_doubleSubmitOnlySendsOneRequest() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips",
            method: "POST",
            dataJSON: TripServiceFixtures.tripJSON(id: "once-trip", title: "东京 2 日游")
        )
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 1)
        vm.selectDestination(TripDestination(name: "东京"))
        vm.updateDates(start: start, end: end)

        // 直接 await 的 submit 会先执行：设置 isSubmitting = true 后挂起等待网络，
        // 此时并发 Task 中的 submit 看到 isSubmitting 即被守卫挡回（返回 nil）。
        let concurrent = Task { await vm.submit() }
        let awaitedResult = await vm.submit()
        XCTAssertNotNil(awaitedResult, "先完成的 submit 应返回新旅程")

        let concurrentResult = await concurrent.value
        XCTAssertNil(concurrentResult, "并发重复 submit 应被 isSubmitting 守卫挡回")

        let posts = stub.recordedRequests().filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 1, "重复 submit 不应发出第二次请求")
    }

    func testSubmit_businessFailureSetsErrorMessage() async throws {
        stub.stubAPIBusinessError(
            path: "/api/v1/trips",
            method: "POST",
            code: 40401,
            message: "Not Found"
        )
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 1)
        vm.selectDestination(TripDestination(name: "东京"))
        vm.updateDates(start: start, end: end)

        let result = await vm.submit()
        XCTAssertNil(result)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Dirty / dismiss

    func testIsDirty_reflectsDraftState() {
        let vm = makeVM()
        XCTAssertFalse(vm.isDirty)

        vm.userDidEditTitle("名称")
        XCTAssertTrue(vm.isDirty)

        // 仅标题被清空但 destination 仍在 → 仍 dirty
        let vm2 = makeVM()
        vm2.selectDestination(TripDestination(name: "京都"))
        vm2.userDidEditTitle("")
        XCTAssertTrue(vm2.isDirty, "有 destination 即使用户清空标题也应标记 dirty")
    }

    func testDismissDecision_coversCleanDirtyAndSubmittingStates() {
        XCTAssertEqual(
            TripCreateViewModel.dismissDecision(isDirty: false, isSubmitting: false),
            .dismissImmediately
        )
        XCTAssertEqual(
            TripCreateViewModel.dismissDecision(isDirty: true, isSubmitting: false),
            .confirmDiscard
        )
        XCTAssertEqual(
            TripCreateViewModel.dismissDecision(isDirty: false, isSubmitting: true),
            .blockedWhileSubmitting
        )
        XCTAssertEqual(
            TripCreateViewModel.dismissDecision(isDirty: true, isSubmitting: true),
            .blockedWhileSubmitting
        )
    }

    func testUseManualDestination_setsDisplayNameAndRegeneratesTitle() {
        let vm = makeVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 3)
        vm.updateDates(start: start, end: end)

        vm.useManualDestination("  自定义目的地  ")
        XCTAssertEqual(vm.destinationDisplayName, "自定义目的地")
        XCTAssertNil(vm.destination)
        XCTAssertEqual(vm.title, "自定义目的地 4 日游")
    }

    // MARK: - 探索带来的目的地种子（规格 §7.3）

    func testSeedLocksDestinationAndPrefillsDisplayName() {
        let vm = makeSeededVM()

        XCTAssertTrue(vm.isDestinationLocked)
        XCTAssertEqual(vm.destinationDisplayName, "杭州")
        XCTAssertTrue(vm.hasDestination)
        // 契约这条路径只发 `destinationSavedPlaceId`，所以本地不持有 `TripDestination`。
        XCTAssertNil(vm.destination)
    }

    func testUnseededFormDoesNotLockDestination() {
        XCTAssertFalse(makeVM().isDestinationLocked)
    }

    func testSeedSubmitsSavedPlaceIdInsteadOfDestination() async throws {
        stub.stubAPISuccess(
            path: "/api/v1/trips",
            method: "POST",
            dataJSON: TripServiceFixtures.tripJSON(id: "explore-trip", title: "杭州 3 日游")
        )
        let vm = makeSeededVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.updateDates(start: start, end: end)

        let result = await vm.submit()
        XCTAssertEqual(result?.id, "explore-trip")

        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"destinationSavedPlaceId\":\"saved-9\""), "body=\(body)")
        XCTAssertFalse(body.contains("\"destination\":"),
                       "带上 savedPlaceId 就不该再发 destination；body=\(body)")
    }

    func testSeedFeedsTitleSuggestion() {
        let vm = makeSeededVM()
        let (start, end) = makeDates(startOffset: 0, endOffset: 2)

        vm.updateDates(start: start, end: end)

        XCTAssertEqual(vm.title, "杭州 3 日游")
    }

    /// 种子是预填不是用户输入：还没碰表单就退出应直接关，不弹「放弃创建」。
    func testSeedIsNotDirtyUntilUserTouchesForm() {
        let vm = makeSeededVM()
        XCTAssertFalse(vm.isDirty)
        XCTAssertEqual(vm.dismissDecision, .dismissImmediately)

        let (start, end) = makeDates(startOffset: 0, endOffset: 2)
        vm.updateDates(start: start, end: end)

        XCTAssertTrue(vm.isDirty)
        XCTAssertEqual(vm.dismissDecision, .confirmDiscard)
    }
}
