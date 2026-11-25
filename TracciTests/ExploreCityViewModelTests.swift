import XCTest
@testable import Tracci
import TracciNetworking

/// 城市页 ViewModel 的规格门禁（`探索Tab-编辑向第一版` §7.2 / §7.3 / §7.5 / §7.6 / §7.7）。
@MainActor
final class ExploreCityViewModelTests: XCTestCase {

    // MARK: - §7.2 并行请求与降级

    func testLoadRequestsCityDetailAndPOIListWithContractPaging() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail()
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)

        await makeModel(service: service).loadIfNeeded()

        XCTAssertEqual(service.recorder.arguments(for: .placeDetail, at: 0), ["place-hangzhou"])
        XCTAssertEqual(
            service.publishedPlaceQueries,
            [PublishedPlacesQuery(placeScope: .poi, cityName: "杭州", page: 1, pageSize: 50)]
        )
    }

    func testPageSizeNeverExceedsContractLimit() {
        // 契约对非法分页返回 42201 而不是夹紧，所以客户端必须自己收口在 50。
        XCTAssertLessThanOrEqual(ExploreCityViewModel.pageSize, PublishedPlacesQuery.pageSizeLimit)
    }

    func testLoadIfNeededRunsOnlyOnce() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)
        let model = makeModel(service: service)

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        XCTAssertEqual(service.publishedPlaceQueries.count, 1)
        XCTAssertEqual(service.recorder.callCount(for: .placeDetail), 1)
    }

    /// 规格 §7.2 的核心：详情失败**不整页报错**，用户看地点的目的不能被次要内容阻塞。
    func testIntroFailureKeepsPlaceStreamUsable() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        service.defaultPublishedPlaces = page([poi("雷峰塔"), poi("楼外楼")], total: 2)

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertTrue(model.isIntroFailed)
        XCTAssertNil(model.introduction)
        XCTAssertEqual(model.listPhase, .loaded)
        XCTAssertEqual(model.places.count, 2)
        XCTAssertNil(model.failureMessage)
    }

    func testRetryIntroRefetchesDetailOnly() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        XCTAssertTrue(model.isIntroFailed)

        service.placeDetailHandler = nil
        service.defaultDetail = cityDetail(introduction: "杭州以西湖为中心。")
        await model.retryIntro()

        XCTAssertFalse(model.isIntroFailed)
        XCTAssertEqual(model.introduction, "杭州以西湖为中心。")
        XCTAssertEqual(service.publishedPlaceQueries.count, 1, "重试简介不应重新拉地点流")
        XCTAssertEqual(service.recorder.callCount(for: .placeDetail), 2)
    }

    func testListFailureFailsPageWithResolvedContractMessage() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail()
        service.publishedPlacesHandler = { _ in throw APIError.business(code: 42201, message: "bad paging") }

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertEqual(model.failureMessage, "分页或筛选参数不正确")
        XCTAssertFalse(model.isIntroFailed)
        XCTAssertEqual(model.introduction, "杭州以西湖为中心，山湖与城市贴得很近。")
    }

    /// 规格 §7.7：地点流为空时页面其余部分照常，创建旅程仍可用。
    func testEmptyPlaceListKeepsCityContent() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail()
        service.defaultPublishedPlaces = page([], total: 0)

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertEqual(model.listPhase, .empty)
        XCTAssertEqual(model.introduction, "杭州以西湖为中心，山湖与城市贴得很近。")
        XCTAssertFalse(model.showsSkeleton)
        XCTAssertFalse(model.hasMore)
    }

    // MARK: - 种子承接（§10.1 封面承上）

    func testSeedRendersHeadBeforeDetailArrives() {
        let model = makeModel(service: SavedPlaceServicingStub())

        XCTAssertEqual(model.cityName, "杭州")
        XCTAssertEqual(model.cityCountry, "中国")
        XCTAssertEqual(model.cityHighlight, "西湖十景")
        XCTAssertEqual(model.cityCategoryDisplayName, "城市")
        XCTAssertEqual(model.heroURL?.absoluteString, "https://cdn.example.com/hangzhou-thumb.jpg")
        XCTAssertFalse(model.citySaved)
        XCTAssertTrue(model.showsSkeleton, "未开始加载时先出骨架，不出错误")
    }

    func testDetailOverridesSeedNameHighlightAndCover() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail(
            name: "杭州市",
            introduction: "杭州以西湖为中心，山湖与城市贴得很近。",
            highlights: ["西湖十景", "龙井茶山"],
            heroURL: "https://cdn.example.com/hangzhou-hero.jpg"
        )
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertEqual(model.cityName, "杭州市")
        XCTAssertEqual(model.cityHighlight, "西湖十景")
        XCTAssertEqual(model.heroURL?.absoluteString, "https://cdn.example.com/hangzhou-hero.jpg")
        XCTAssertEqual(model.contentMetaLabel, "内容由编辑整理")
    }

    func testCitySavedStateRefinesFromDetailUserContext() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail(isSaved: true, savedPlaceId: "saved-9")
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)

        let model = makeModel(service: service)
        XCTAssertFalse(model.citySaved, "种子里是未收藏")

        await model.loadIfNeeded()

        XCTAssertTrue(model.citySaved)
        XCTAssertEqual(model.citySavedPlaceId, "saved-9")
    }

    // MARK: - §7.6 类别 chips

    func testChipsHiddenWhenFewerThanTwelvePlaces() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page(mixedPOIs(count: 11), total: 11)

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertFalse(model.showsChips)
        XCTAssertTrue(model.chips.isEmpty)
    }

    func testChipsHiddenWhenFewerThanThreeCategories() async {
        let service = SavedPlaceServicingStub()
        let places = (0..<12).map { poi("景点\($0)", category: .attraction) }
        service.defaultPublishedPlaces = page(places, total: 12)

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertEqual(model.places.count, 12)
        XCTAssertFalse(model.showsChips, "只有一个类别时 chips 没有筛选价值")
    }

    func testChipsLeadWithAllThenCategoryCountDescending() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page(chipFixturePlaces(), total: 12)

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertTrue(model.showsChips)
        XCTAssertEqual(
            model.chips,
            [.all, .category(.attraction), .category(.restaurant), .category(.hotel)]
        )
        XCTAssertEqual(model.chips.first?.title, "全部")
    }

    func testChipSelectionFiltersLocallyWithoutNewRequest() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page(chipFixturePlaces(), total: 12)
        let model = makeModel(service: service)
        await model.loadIfNeeded()

        model.select(.category(.restaurant))

        XCTAssertEqual(model.visiblePlaces.map(\.name), ["楼外楼", "知味观", "餐饮0", "餐饮1"])
        XCTAssertEqual(model.visibleCount, 4)
        XCTAssertEqual(service.publishedPlaceQueries.count, 1, "chips 是纯本地过滤，不发请求")

        model.select(.all)
        XCTAssertEqual(model.visibleCount, 12)
    }

    // MARK: - §6.5 排序 + 分页

    func testPlacesSortByPublishedAtDescendingThenNameAscending() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            poi("雷峰塔", publishedAt: "2026-08-01 10:00:00"),
            poi("楼外楼", publishedAt: "2026-08-20 10:00:00"),
            poi("知味观", publishedAt: "2026-08-20 10:00:00"),
            poi("西湖博物馆", publishedAt: nil),
        ], total: 4)

        let model = makeModel(service: service)
        await model.loadIfNeeded()

        // 同 `publishedAt` 用 name 升序兜底：Swift 的 `<` 是码位序，
        // 与设备 locale 无关，保证每台机器顺序一致（同首页 §6.5）。
        XCTAssertEqual(
            model.places.map(\.name),
            ["楼外楼", "知味观", "雷峰塔", "西湖博物馆"]
        )
    }

    func testLoadMoreAppendsDedupesAndTerminatesOnCursor() async {
        let service = SavedPlaceServicingStub()
        let firstPage = page([poi("雷峰塔"), poi("楼外楼")], total: 60)
        // 服务端返回重叠记录：靠 id 去重后条数不涨，`hasMore` 必须按游标判定而不是按条数。
        let secondPage = page([poi("楼外楼"), poi("西湖博物馆")], total: 60)
        service.publishedPlacesHandler = { query in query.page == 1 ? firstPage : secondPage }

        let model = makeModel(service: service)
        await model.loadIfNeeded()
        XCTAssertTrue(model.hasMore)

        await model.loadMore()

        XCTAssertEqual(model.places.map(\.name), ["楼外楼", "西湖博物馆", "雷峰塔"])
        XCTAssertFalse(model.hasMore, "第 2 页游标已越过 total，按钮必须消失")
    }

    func testLoadMoreFailureBlocksUntilExplicitRetry() async {
        let service = SavedPlaceServicingStub()
        let firstPage = page([poi("雷峰塔")], total: 60)
        let secondPage = page([poi("楼外楼")], total: 60)
        service.publishedPlacesHandler = { query in
            if query.page == 1 { return firstPage }
            throw APIError.business(code: 42201, message: "bad paging")
        }

        let model = makeModel(service: service)
        await model.loadIfNeeded()
        await model.loadMore()

        XCTAssertEqual(model.loadMoreError, "分页或筛选参数不正确")
        XCTAssertEqual(model.places.count, 1)

        await model.loadMore()
        XCTAssertEqual(model.places.count, 1, "失败后继续点不应重复请求")

        service.publishedPlacesHandler = { _ in secondPage }
        await model.retryLoadMore()

        XCTAssertNil(model.loadMoreError)
        XCTAssertEqual(model.places.map(\.name), ["楼外楼", "雷峰塔"])
    }

    // MARK: - §7.5 列表内快捷收藏

    func testQuickSaveFlipsOptimisticallyAndKeepsOnSuccess() async throws {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        let place = try XCTUnwrap(model.places.first)

        await model.quickSave(place)

        XCTAssertTrue(model.isSaved(place))
        XCTAssertNil(model.toast)
        XCTAssertEqual(service.createdRequests.first?.placeId, place.id)
    }

    func testQuickSaveTreatsAlreadySavedAsIdempotentSuccess() async throws {
        let service = SavedPlaceServicingStub()
        service.createHandler = { _ in throw APIError.business(code: 40901, message: "duplicated") }
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        let place = try XCTUnwrap(model.places.first)

        await model.quickSave(place)

        XCTAssertTrue(model.isSaved(place), "40901 保持实心")
        XCTAssertNil(model.toast, "40901 不报错")
    }

    func testQuickSaveRollsBackAndToastsOnFailure() async throws {
        let service = SavedPlaceServicingStub()
        service.createHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        service.defaultPublishedPlaces = page([poi("雷峰塔")], total: 1)
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        let place = try XCTUnwrap(model.places.first)

        await model.quickSave(place)

        XCTAssertFalse(model.isSaved(place))
        XCTAssertEqual(model.toast, TracciToastMessage.error("收藏没成功，稍后再试"))
    }

    func testQuickSaveOnSavedPlaceNeverUnsaves() async throws {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([poi("雷峰塔", isSaved: true)], total: 1)
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        let place = try XCTUnwrap(model.places.first)

        await model.quickSave(place)

        XCTAssertTrue(service.recorder.wasNotCalled(.create), "已收藏态点按不取消（§7.5）")
        XCTAssertTrue(model.isSaved(place))
    }

    // MARK: - §7.3 城市收藏

    func testSaveCityMarksSavedAndSaysWhereToFindIt() async {
        let service = SavedPlaceServicingStub()
        let model = makeModel(service: service)

        await model.saveCity()

        XCTAssertTrue(model.citySaved)
        XCTAssertEqual(model.citySavedPlaceId, SavedPlaceFixtures.sample.id)
        XCTAssertEqual(model.toast, TracciToastMessage.success("已收藏，可在「我的 → 想去的地点」看到"))
    }

    func testUnsaveCityClearsStateOnSuccess() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail(isSaved: true, savedPlaceId: "saved-9")
        let model = makeModel(service: service)
        await model.loadIfNeeded()

        let didDismiss = await model.unsaveCity()

        XCTAssertTrue(didDismiss)
        XCTAssertFalse(model.citySaved)
        XCTAssertNil(model.citySavedPlaceId)
        XCTAssertNil(model.unsaveErrorMessage)
        XCTAssertEqual(service.recorder.arguments(for: .delete, at: 0), ["saved-9"])
    }

    func testUnsaveCityKeepsSheetOpenWithReasonOnFailure() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail(isSaved: true, savedPlaceId: "saved-9")
        service.deleteHandler = { _ in throw APIError.business(code: 40423, message: "gone") }
        let model = makeModel(service: service)
        await model.loadIfNeeded()

        let didDismiss = await model.unsaveCity()

        XCTAssertFalse(didDismiss)
        XCTAssertTrue(model.citySaved, "失败不能把 UI 切成未收藏")
        XCTAssertEqual(model.unsaveErrorMessage, "这条收藏已不可用，请刷新后重试")
    }

    /// 列表只给 `isSaved` 不给 `savedPlaceId`：详情没回来时补拉一次详情把 id 找回来。
    func testUnsaveCityRecoversMissingSavedPlaceIdFromDetail() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail(isSaved: true, savedPlaceId: "saved-9")
        let model = makeModel(service: service, isSaved: true)
        XCTAssertNil(model.citySavedPlaceId)

        let didDismiss = await model.unsaveCity()

        XCTAssertTrue(didDismiss)
        XCTAssertEqual(service.recorder.arguments(for: .delete, at: 0), ["saved-9"])
        XCTAssertEqual(service.recorder.callCount(for: .placeDetail), 1)
    }

    func testUnsaveCityFailsWhenSavedPlaceIdCannotBeResolved() async {
        let service = SavedPlaceServicingStub()
        service.placeDetailHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        let model = makeModel(service: service, isSaved: true)

        let didDismiss = await model.unsaveCity()

        XCTAssertFalse(didDismiss)
        XCTAssertEqual(model.unsaveErrorMessage, "收藏没成功，稍后再试")
        XCTAssertTrue(service.recorder.wasNotCalled(.delete))
    }

    // MARK: - §7.3 用这里创建旅程

    func testBeginCreateTripReusesExistingSavedPlaceId() async {
        let service = SavedPlaceServicingStub()
        service.defaultDetail = cityDetail(isSaved: true, savedPlaceId: "saved-9")
        let model = makeModel(service: service)
        await model.loadIfNeeded()

        let savedPlaceId = await model.beginCreateTrip()

        XCTAssertEqual(savedPlaceId, "saved-9")
        XCTAssertTrue(service.recorder.wasNotCalled(.create), "已收藏不应重复收藏")
        XCTAssertNil(model.toast, "已收藏走静默路径时不需要轻提示")
    }

    func testBeginCreateTripSilentlySavesThenHandsOffSavedPlaceId() async {
        let service = SavedPlaceServicingStub()
        let model = makeModel(service: service)

        let savedPlaceId = await model.beginCreateTrip()

        XCTAssertEqual(savedPlaceId, SavedPlaceFixtures.sample.id)
        XCTAssertTrue(model.citySaved)
        XCTAssertEqual(model.toast, TracciToastMessage.info("已加入想去的地点"))
        XCTAssertEqual(service.createdRequests.first?.placeId, "place-hangzhou")
    }

    func testBeginCreateTripReturnsNilWhenSilentSaveFails() async {
        let service = SavedPlaceServicingStub()
        service.createHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        let model = makeModel(service: service)

        let savedPlaceId = await model.beginCreateTrip()

        XCTAssertNil(savedPlaceId, "拿不到 savedPlaceId 就不能打开创建表单")
        XCTAssertFalse(model.citySaved)
        XCTAssertEqual(model.toast, TracciToastMessage.error("收藏没成功，稍后再试"))
    }

    // MARK: - Fixtures

    private func makeSeed(isSaved: Bool) -> ExploreCitySeed {
        ExploreCitySeed(
            id: "place-hangzhou",
            name: "杭州",
            country: "中国",
            category: .city,
            highlight: "西湖十景",
            isSaved: isSaved,
            coverURL: "https://cdn.example.com/hangzhou-thumb.jpg"
        )
    }

    private func makeModel(service: SavedPlaceServicingStub, isSaved: Bool = false) -> ExploreCityViewModel {
        ExploreCityViewModel(seed: makeSeed(isSaved: isSaved), service: service)
    }

    private func page(_ list: [PublishedPlace], total: Int) -> PageResponse<PublishedPlace> {
        PageResponse(list: list, total: total, page: 1, pageSize: PublishedPlacesQuery.pageSizeLimit)
    }

    private func poi(
        _ name: String,
        category: PlaceCategory = .attraction,
        publishedAt: String? = "2026-08-20 10:00:00",
        isSaved: Bool = false
    ) -> PublishedPlace {
        PublishedPlace(
            id: "place-\(name)",
            name: name,
            placeScope: .poi,
            category: category,
            cityName: "杭州",
            country: "中国",
            latitude: nil,
            longitude: nil,
            supportedUsages: [.itineraryNode],
            highlight: nil,
            publishedAt: publishedAt,
            isSaved: isSaved,
            cover: nil
        )
    }

    /// 12 个地点：6 景点 / 4 餐饮 / 2 住宿 —— 满足 §7.6 的「≥ 12 且 ≥ 3 类」。
    private func chipFixturePlaces() -> [PublishedPlace] {
        var places: [PublishedPlace] = []
        for index in 0..<6 { places.append(poi("景点\(index)", category: .attraction)) }
        places.append(poi("楼外楼", category: .restaurant))
        places.append(poi("知味观", category: .restaurant))
        for index in 0..<2 { places.append(poi("餐饮\(index)", category: .restaurant)) }
        for index in 0..<2 { places.append(poi("住宿\(index)", category: .hotel)) }
        return places
    }

    private func mixedPOIs(count: Int) -> [PublishedPlace] {
        let categories: [PlaceCategory] = [.attraction, .restaurant, .hotel]
        return (0..<count).map { poi("地点\($0)", category: categories[$0 % categories.count]) }
    }

    private func cityDetail(
        name: String = "杭州",
        introduction: String? = "杭州以西湖为中心，山湖与城市贴得很近。",
        highlights: [String]? = ["西湖十景"],
        isSaved: Bool = false,
        savedPlaceId: String? = nil,
        heroURL: String? = nil
    ) -> PlaceDetail {
        PlaceDetail(
            id: "place-hangzhou",
            name: name,
            placeScope: .destination,
            category: .city,
            address: nil,
            cityName: "杭州",
            country: "中国",
            latitude: 30.2741,
            longitude: 120.1551,
            supportedUsages: [.tripDestination],
            userContext: PlaceUserContext(
                isSaved: isSaved,
                savedPlaceId: savedPlaceId,
                note: nil,
                usageSummary: nil
            ),
            editorialContent: PlaceEditorialContent(
                version: 3,
                introduction: introduction,
                highlights: highlights,
                recommendedDurationMinutes: nil,
                visitTips: nil,
                bestVisitTime: nil,
                reservationTips: nil,
                notice: nil
            ),
            contentMeta: PlaceContentMeta(
                aiAssisted: true,
                label: "内容由编辑整理",
                verifiedAt: nil,
                nextReviewAt: nil,
                reviewDue: nil
            ),
            media: heroURL.map {
                [PlaceMedia(
                    id: "media-1",
                    url: $0,
                    thumbnailUrl: nil,
                    previewUrl: nil,
                    width: nil,
                    height: nil,
                    altText: nil,
                    attribution: nil
                )]
            }
        )
    }
}
