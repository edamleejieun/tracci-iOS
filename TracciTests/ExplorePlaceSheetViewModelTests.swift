import XCTest
@testable import Tracci
import TracciNetworking

/// 地点半层（`探索Tab-编辑向第一版` §8）的规格门禁：
/// 可用性矩阵、Hero 三级降级依据、收藏写回、加入行程的前置静默收藏、正文顺序与时长本地化。
@MainActor
final class ExplorePlaceSheetViewModelTests: XCTestCase {

    // MARK: - §8.3 可用性矩阵

    func testAddTitleReadsJoinTripWhenActiveTripsExist() async {
        let model = makeModel(detail: placeDetail(), trips: [tripSummary()])

        await model.load()

        XCTAssertEqual(model.addTitle, "加入行程")
        XCTAssertTrue(model.hasCoordinate)
    }

    func testAddTitleReadsCreateTripFirstWhenNoActiveTrips() async {
        let model = makeModel(detail: placeDetail(), trips: [])

        await model.load()

        XCTAssertEqual(model.addTitle, "先创建旅程")
    }

    /// 规格 §8.3：没有 provider 也读「先创建旅程」——点了仍能进创建表单，不是死路。
    func testAddTitleFallsBackToCreateTripWithoutProvider() async {
        let model = makeModel(detail: placeDetail(), trips: nil)

        await model.load()

        XCTAssertEqual(model.addTitle, "先创建旅程")
    }

    func testAddTitleFallsBackToCreateTripWhenTripsCannotLoad() async {
        let model = makeModel(
            detail: placeDetail(),
            tripProvider: ExploreTripProviderStub(trips: [], failsToLoadTrips: true)
        )

        await model.load()

        XCTAssertEqual(model.addTitle, "先创建旅程")
        XCTAssertNil(model.errorMessage, "旅程列表失败不该污染详情的错误态")
    }

    /// 规格 §5.3：`supportedUsages` 在城市页与半层都「不用」——可用性以详情 `userContext` +
    /// 旅程列表为准，目的地是否匹配交服务端判（`42243`），客户端不做第二套预判。
    func testAvailabilityDoesNotConsultSupportedUsages() async {
        let model = makeModel(
            detail: placeDetail(supportedUsages: [.tripDestination]),
            trips: [tripSummary()]
        )

        await model.load()

        XCTAssertEqual(model.addTitle, "加入行程")
    }

    // MARK: - §8.2 Hero 三级降级

    func testHeroUsesPhotoBandWhenMediaPresent() async {
        let model = makeModel(detail: placeDetail(media: [media("m1"), media("m2")]), trips: [])

        await model.load()

        XCTAssertEqual(model.mediaItems.count, 2)
    }

    func testHeroFallsBackToCoordinateMapWithoutMedia() async {
        let model = makeModel(detail: placeDetail(media: nil), trips: [])

        await model.load()

        XCTAssertTrue(model.mediaItems.isEmpty)
        XCTAssertTrue(model.hasCoordinate, "无图但有坐标 → 地图（§8.2 第二级）")
    }

    func testHeroFallsBackToCategoryPlaceholderWithoutMediaOrCoordinate() async {
        let model = makeModel(detail: placeDetail(latitude: nil, longitude: nil), trips: [])

        await model.load()

        XCTAssertTrue(model.mediaItems.isEmpty)
        XCTAssertFalse(model.hasCoordinate, "两者都无 → 品类占位，操作栏的地图项整条隐藏")
    }

    func testDetailFailureSurfacesResolvedContractMessage() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in throw APIError.business(code: 40422, message: "gone") }
        let model = makeModel(service: service, trips: [])

        await model.load()

        XCTAssertEqual(model.errorMessage, "这个地点不存在或已不可用")
        XCTAssertNil(model.detail)
        XCTAssertFalse(model.isLoading)
    }

    // MARK: - §8.3 / §8.4 收藏

    func testSaveToastsWhereToFindItAndWritesBackToCityList() async {
        let service = SavedPlaceServicingStub()
        let box = DetailBox(placeDetail())
        service.placeDetailHandler = { _ in try box.next() }
        service.createHandler = { _ in
            box.value = self.placeDetail(isSaved: true, savedPlaceId: "saved-9")
            return SavedPlaceFixtures.sample
        }
        let recorder = SavedStateRecorder()
        let model = makeModel(service: service, trips: [], recorder: recorder)
        await model.load()
        XCTAssertFalse(model.isSaved)

        await model.save()

        XCTAssertTrue(model.isSaved, "热更新半层自身的 userContext（§8.4）")
        XCTAssertEqual(model.toast, TracciToastMessage.success("已收藏，可在「我的 → 想去的地点」看到"))
        XCTAssertEqual(recorder.placeIds, ["place-gugong"])
        XCTAssertEqual(recorder.savedFlags, [true])
        XCTAssertEqual(service.createdRequests.first?.placeId, "place-gugong")
    }

    /// 契约决策 9：`40901` 视为成功——不报错，照样回写城市页。
    func testSaveTreatsAlreadySavedAsIdempotentSuccess() async {
        let service = SavedPlaceServicingStub()
        let box = DetailBox(placeDetail())
        service.placeDetailHandler = { _ in try box.next() }
        service.createHandler = { _ in
            box.value = self.placeDetail(isSaved: true, savedPlaceId: "saved-9")
            throw APIError.business(code: 40901, message: "duplicated")
        }
        let recorder = SavedStateRecorder()
        let model = makeModel(service: service, trips: [], recorder: recorder)
        await model.load()

        await model.save()

        XCTAssertNil(model.toast, "40901 不是失败，不该弹「收藏没成功」")
        XCTAssertTrue(model.isSaved)
        XCTAssertEqual(recorder.savedFlags, [true])
    }

    func testSaveFailureToastsAndDoesNotWriteBack() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in self.placeDetail() }
        service.createHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        let recorder = SavedStateRecorder()
        let model = makeModel(service: service, trips: [], recorder: recorder)
        await model.load()

        await model.save()

        XCTAssertEqual(model.toast, TracciToastMessage.error("收藏没成功，稍后再试"))
        XCTAssertTrue(recorder.placeIds.isEmpty, "失败不能把城市页那一行也改成已收藏")
        XCTAssertFalse(model.isSaved)
    }

    func testSaveOnSavedPlaceNeverUnsaves() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in self.placeDetail(isSaved: true, savedPlaceId: "saved-9") }
        let model = makeModel(service: service, trips: [])
        await model.load()

        await model.save()

        XCTAssertTrue(service.recorder.wasNotCalled(.create))
        XCTAssertTrue(service.recorder.wasNotCalled(.delete), "取消收藏只在二次确认层里做")
        XCTAssertTrue(model.isSaved)
    }

    func testUnsaveWritesBackFalseOnSuccess() async {
        let service = SavedPlaceServicingStub()
        let box = DetailBox(placeDetail(isSaved: true, savedPlaceId: "saved-9"))
        service.placeDetailHandler = { _ in try box.next() }
        service.deleteHandler = { _ in box.value = self.placeDetail() }
        let recorder = SavedStateRecorder()
        let model = makeModel(service: service, trips: [], recorder: recorder)
        await model.load()

        let didDismiss = await model.unsave()

        XCTAssertTrue(didDismiss)
        XCTAssertNil(model.unsaveErrorMessage)
        XCTAssertEqual(service.recorder.arguments(for: .delete, at: 0), ["saved-9"])
        XCTAssertEqual(recorder.savedFlags, [false])
        XCTAssertFalse(model.isSaved)
    }

    func testUnsaveFailureKeepsSheetOpenWithResolvedContractMessage() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in self.placeDetail(isSaved: true, savedPlaceId: "saved-9") }
        service.deleteHandler = { _ in throw APIError.business(code: 40423, message: "gone") }
        let recorder = SavedStateRecorder()
        let model = makeModel(service: service, trips: [], recorder: recorder)
        await model.load()

        let didDismiss = await model.unsave()

        XCTAssertFalse(didDismiss)
        XCTAssertEqual(model.unsaveErrorMessage, "这条收藏已不可用，请刷新后重试")
        XCTAssertTrue(recorder.placeIds.isEmpty)
        XCTAssertTrue(model.isSaved, "失败不能把 UI 切成未收藏")
    }

    /// 列表只给 `isSaved` 不给 `savedPlaceId`：拿不到 id 就老实说明，不要发一个注定失败的 delete。
    func testUnsaveWithoutSavedPlaceIdExplainsInsteadOfCallingDelete() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in self.placeDetail(isSaved: true, savedPlaceId: nil) }
        let model = makeModel(service: service, trips: [])
        await model.load()

        let didDismiss = await model.unsave()

        XCTAssertFalse(didDismiss)
        XCTAssertEqual(model.unsaveErrorMessage, "这条收藏已不可用，请刷新后重试")
        XCTAssertTrue(service.recorder.wasNotCalled(.delete))
    }

    // MARK: - §8.3 加入行程

    /// 契约 §15.8 要 `savedPlaceId`：已收藏时直接复用，不重复 POST。
    func testPrepareAddToTripReusesExistingSavedPlace() async throws {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in self.placeDetail(isSaved: true, savedPlaceId: "saved-9") }
        let model = makeModel(service: service, trips: [tripSummary()])
        await model.load()

        let prepared = await model.prepareAddToTrip()
        let savedPlace = try XCTUnwrap(prepared)

        XCTAssertEqual(savedPlace.id, "saved-9")
        XCTAssertEqual(savedPlace.placeId, "place-gugong", "用详情自己的字段拼，不用 stub 的默认样本")
        XCTAssertTrue(service.recorder.wasNotCalled(.create))
        XCTAssertNil(model.toast)
    }

    func testPrepareAddToTripSilentlySavesFirstWhenNotSaved() async throws {
        let service = SavedPlaceServicingStub()
        let box = DetailBox(placeDetail())
        service.placeDetailHandler = { _ in try box.next() }
        service.createHandler = { _ in
            box.value = self.placeDetail(isSaved: true, savedPlaceId: "saved-9")
            return SavedPlaceFixtures.sample
        }
        let recorder = SavedStateRecorder()
        let model = makeModel(service: service, trips: [tripSummary()], recorder: recorder)
        await model.load()

        let prepared = await model.prepareAddToTrip()
        let savedPlace = try XCTUnwrap(prepared)

        XCTAssertEqual(savedPlace.id, "saved-9")
        XCTAssertEqual(model.toast, TracciToastMessage.info("已加入想去的地点"))
        XCTAssertEqual(recorder.savedFlags, [true])
    }

    /// 收藏已经成功、只是随后那次详情刷新读失败：用 create 的返回值兜底，不打断「加入行程」。
    func testPrepareAddToTripFallsBackToCreatedPlaceWhenReloadFails() async throws {
        let service = SavedPlaceServicingStub()
        let box = DetailBox(placeDetail())
        box.failsAfterFirstRead = true
        service.placeDetailHandler = { _ in try box.next() }
        let model = makeModel(service: service, trips: [tripSummary()])
        await model.load()

        let prepared = await model.prepareAddToTrip()
        let savedPlace = try XCTUnwrap(prepared)

        XCTAssertEqual(savedPlace.id, SavedPlaceFixtures.sample.id)
        XCTAssertEqual(model.toast, TracciToastMessage.info("已加入想去的地点"))
    }

    func testPrepareAddToTripReturnsNilWhenSilentSaveFails() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in self.placeDetail() }
        service.createHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        let recorder = SavedStateRecorder()
        let model = makeModel(service: service, trips: [tripSummary()], recorder: recorder)
        await model.load()

        let savedPlace = await model.prepareAddToTrip()

        XCTAssertNil(savedPlace, "拿不到 savedPlaceId 就不开选择器")
        XCTAssertEqual(model.toast, TracciToastMessage.error("收藏没成功，稍后再试"))
        XCTAssertTrue(recorder.placeIds.isEmpty)
    }

    func testPrepareAddToTripTreatsAlreadySavedAsSuccess() async throws {
        let service = SavedPlaceServicingStub()
        let box = DetailBox(placeDetail())
        service.placeDetailHandler = { _ in try box.next() }
        service.createHandler = { _ in
            box.value = self.placeDetail(isSaved: true, savedPlaceId: "saved-9")
            throw APIError.business(code: 40901, message: "duplicated")
        }
        let model = makeModel(service: service, trips: [tripSummary()])
        await model.load()

        let prepared = await model.prepareAddToTrip()
        let savedPlace = try XCTUnwrap(prepared)

        XCTAssertEqual(savedPlace.id, "saved-9")
        XCTAssertNil(model.toast, "40901 是幂等成功，不该弹提示")
    }

    /// 规格 §8.3：无旅程时只给轻提示 + 打开创建表单，POI **不**预填为目的地——所以这里不发任何写请求。
    func testPromptCreateTripOnlyToasts() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in self.placeDetail() }
        let model = makeModel(service: service, trips: [])
        await model.load()
        service.resetRecordedCalls()

        model.promptCreateTrip()

        XCTAssertEqual(model.toast, TracciToastMessage.info("先创建一趟旅程，再把这里加进去"))
        XCTAssertEqual(service.recorder.callCount(for: .create), 0)
    }

    // MARK: - §8.2 建议时长本地化

    func testDurationUnderOneHourIsNotRounded() {
        // 规格给的例子是 45 → 「约 45 分钟」；抹到最近的 30 分钟会读成 30 或 60，把编辑写的时长说错。
        XCTAssertEqual(ExploreDurationText.localized(30), "约 30 分钟")
        XCTAssertEqual(ExploreDurationText.localized(45), "约 45 分钟")
        XCTAssertEqual(ExploreDurationText.localized(59), "约 59 分钟")
    }

    func testDurationAtOrAboveOneHourRoundsToNearestHalfHour() {
        XCTAssertEqual(ExploreDurationText.localized(60), "约 1 小时")
        XCTAssertEqual(ExploreDurationText.localized(75), "约 1.5 小时")
        XCTAssertEqual(ExploreDurationText.localized(90), "约 1.5 小时")
        XCTAssertEqual(ExploreDurationText.localized(105), "约 2 小时")
        XCTAssertEqual(ExploreDurationText.localized(180), "约 3 小时")
    }

    func testDurationIsHiddenWhenMissingOrNonPositive() {
        XCTAssertNil(ExploreDurationText.localized(0))
        XCTAssertNil(ExploreDurationText.localized(-30))
    }

    // MARK: - §8.2 正文块顺序

    func testEditorialBlocksFollowContractOrder() {
        let content = PlaceEditorialContent(
            version: 3,
            introduction: "明清两代的皇宫。",
            highlights: ["中轴线三大殿"],
            recommendedDurationMinutes: 180,
            visitTips: ["周一闭馆"],
            bestVisitTime: "春秋两季",
            reservationTips: "提前七天预约",
            notice: "禁止自拍杆"
        )

        let blocks = ExplorePlaceEditorialContent.blocks(from: content)

        XCTAssertEqual(
            blocks.map(\.title),
            ["介绍", "亮点", "建议时长", "宜访时段", "游览提示", "预约提示", "须知"]
        )
        XCTAssertEqual(blocks[1].body, .bullets(["中轴线三大殿"]))
        XCTAssertEqual(blocks[2].body, .duration("约 3 小时"))
    }

    func testEditorialBlocksHideEmptySectionsEntirely() {
        let content = PlaceEditorialContent(
            version: 3,
            introduction: "   ",
            highlights: [],
            recommendedDurationMinutes: 0,
            visitTips: ["", "从午门进"],
            bestVisitTime: nil,
            reservationTips: nil,
            notice: nil
        )

        let blocks = ExplorePlaceEditorialContent.blocks(from: content)

        XCTAssertEqual(blocks.map(\.title), ["游览提示"], "空白项算空，整段隐藏")
        XCTAssertEqual(blocks.first?.body, .bullets(["从午门进"]))
    }

    /// 规格 §8.2 第 5 条：全空时视图读「暂无更多介绍」，靠的就是这里返回空数组。
    func testEditorialBlocksAreEmptyWhenNothingIsFilled() {
        XCTAssertTrue(ExplorePlaceEditorialContent.blocks(from: nil).isEmpty)
        XCTAssertTrue(ExplorePlaceEditorialContent.blocks(from: emptyEditorialContent()).isEmpty)
    }

    // MARK: - Fixtures

    private func makeModel(
        detail: PlaceDetail,
        trips: [SavedPlaceTripSummary]? = [],
        tripProvider: (any SavedPlaceTripProviding)? = nil,
        recorder: SavedStateRecorder? = nil
    ) -> ExplorePlaceSheetViewModel {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in detail }
        return makeModel(service: service, trips: trips, tripProvider: tripProvider, recorder: recorder)
    }

    private func makeModel(
        service: SavedPlaceServicingStub,
        trips: [SavedPlaceTripSummary]? = [],
        tripProvider: (any SavedPlaceTripProviding)? = nil,
        recorder: SavedStateRecorder? = nil
    ) -> ExplorePlaceSheetViewModel {
        ExplorePlaceSheetViewModel(
            placeId: "place-gugong",
            service: service,
            tripProvider: tripProvider ?? trips.map { ExploreTripProviderStub(trips: $0) },
            onSavedStateChange: { placeId, isSaved in
                recorder?.record(placeId, isSaved)
            }
        )
    }

    private func placeDetail(
        isSaved: Bool = false,
        savedPlaceId: String? = nil,
        latitude: Double? = 39.9163,
        longitude: Double? = 116.3972,
        media: [PlaceMedia]? = nil,
        supportedUsages: [SupportedPlaceUsage] = [.itineraryNode]
    ) -> PlaceDetail {
        PlaceDetail(
            id: "place-gugong",
            name: "故宫博物院",
            placeScope: .poi,
            category: .attraction,
            address: "北京市东城区景山前街4号",
            cityName: "北京",
            country: "中国",
            latitude: latitude,
            longitude: longitude,
            supportedUsages: supportedUsages,
            userContext: PlaceUserContext(
                isSaved: isSaved,
                savedPlaceId: savedPlaceId,
                note: nil,
                usageSummary: nil
            ),
            editorialContent: nil,
            contentMeta: PlaceContentMeta(
                aiAssisted: true,
                label: "内容由趣溪编辑整理，经人工审核",
                verifiedAt: nil,
                nextReviewAt: nil,
                reviewDue: nil
            ),
            media: media
        )
    }

    private func emptyEditorialContent() -> PlaceEditorialContent {
        PlaceEditorialContent(
            version: 3,
            introduction: nil,
            highlights: nil,
            recommendedDurationMinutes: nil,
            visitTips: nil,
            bestVisitTime: nil,
            reservationTips: nil,
            notice: nil
        )
    }

    private func media(_ id: String) -> PlaceMedia {
        PlaceMedia(
            id: id,
            url: "https://cdn.example.com/\(id).jpg",
            thumbnailUrl: nil,
            previewUrl: nil,
            width: 900,
            height: 600,
            altText: nil,
            attribution: nil
        )
    }

    private func tripSummary() -> SavedPlaceTripSummary {
        SavedPlaceTripSummary(
            trip: Trip(
                id: "trip-1",
                title: "北京之旅",
                startDate: "2026-10-01",
                endDate: "2026-10-04",
                status: .planning,
                totalDays: 4,
                destination: TripDestination(name: "北京", country: "中国", cityName: "北京"),
                nodeCount: 0
            )
        )
    }
}

// MARK: - Stubs

/// 半层的详情会随收藏结果变化，用一个盒子让 handler 每次读到最新值。
private final class DetailBox {
    var value: PlaceDetail
    /// 置为真后，第一次之后的读取一律失败——验证「写已成功、读失败」不该打断意图。
    var failsAfterFirstRead = false
    private var didRead = false

    init(_ value: PlaceDetail) {
        self.value = value
    }

    func next() throws -> PlaceDetail {
        if failsAfterFirstRead, didRead {
            throw APIError.business(code: 50000, message: "boom")
        }
        didRead = true
        return value
    }
}

/// 记录规格 §8.4 的回写：半层里的收藏结果要落到城市页那一行。
private final class SavedStateRecorder {
    private(set) var placeIds: [String] = []
    private(set) var savedFlags: [Bool] = []

    func record(_ placeId: String, _ isSaved: Bool) {
        placeIds.append(placeId)
        savedFlags.append(isSaved)
    }
}

@MainActor
private final class ExploreTripProviderStub: SavedPlaceTripProviding {
    let trips: [SavedPlaceTripSummary]
    let failsToLoadTrips: Bool

    init(trips: [SavedPlaceTripSummary], failsToLoadTrips: Bool = false) {
        self.trips = trips
        self.failsToLoadTrips = failsToLoadTrips
    }

    func loadActiveTrips() async throws -> [SavedPlaceTripSummary] {
        if failsToLoadTrips {
            throw APIError.business(code: 50000, message: "boom")
        }
        return trips
    }

    func loadTripDays(tripId: String) async throws -> [SavedPlaceTripDay] { [] }

    func addSavedPlace(_ place: SavedPlace, toTripId tripId: String, dayId: String) async throws -> String {
        "node-1"
    }
}
