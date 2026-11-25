import XCTest
@testable import Tracci
import TracciNetworking

/// 探索首页 ViewModel 的规格门禁（`探索Tab-编辑向第一版` §6.4 / §6.5 / §6.6）。
@MainActor
final class ExploreHomeViewModelTests: XCTestCase {

    // MARK: - §6.6 请求与状态

    func testFirstLoadRequestsPublishedDestinationsWithContractPaging() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 1)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertEqual(
            service.publishedPlaceQueries,
            [PublishedPlacesQuery(placeScope: .destination, page: 1, pageSize: 50)]
        )
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.cities.map(\.name), ["杭州"])
    }

    func testPageSizeNeverExceedsContractLimit() {
        // 契约对非法分页返回 42201 而不是夹紧，所以客户端必须自己收口在 50。
        XCTAssertLessThanOrEqual(ExploreHomeViewModel.pageSize, PublishedPlacesQuery.pageSizeLimit)
        XCTAssertEqual(PublishedPlacesQuery(pageSize: 500).queryItems.last?.value, "50")
    }

    func testLoadIfNeededRunsOnlyOnce() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 1)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        XCTAssertEqual(service.publishedPlaceQueries.count, 1)
    }

    func testEmptyPageEntersEmptyState() async {
        let service = SavedPlaceServicingStub()
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertEqual(model.phase, .empty)
        XCTAssertTrue(model.cities.isEmpty)
        XCTAssertFalse(model.hasMore)
    }

    func testBusinessFailureSurfacesResolvedCopy() async {
        let service = SavedPlaceServicingStub()
        service.publishedPlacesHandler = { _ in throw APIError.business(code: 42201, message: "invalid") }
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertEqual(model.phase, .failed("分页或筛选参数不正确"))
        XCTAssertEqual(model.failureMessage, "分页或筛选参数不正确")
    }

    func testSkeletonShowsBeforeFirstPageButNotDuringRefresh() async {
        let service = SavedPlaceServicingStub()
        let model = ExploreHomeViewModel(service: service)
        XCTAssertTrue(model.showsSkeleton, "idle 阶段就要铺骨架，避免闪一帧空白")

        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 1)
        await model.loadIfNeeded()
        XCTAssertFalse(model.showsSkeleton)

        await model.refresh()
        XCTAssertFalse(model.showsSkeleton, "下拉刷新保留旧卡片，不整页翻骨架")
        XCTAssertEqual(service.publishedPlaceQueries.count, 2)
    }

    func testRefreshFailureKeepsExistingCities() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 1)
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()

        service.publishedPlacesHandler = { _ in throw APIError.business(code: 50000, message: "服务开小差了") }
        await model.refresh()

        XCTAssertEqual(model.cities.map(\.name), ["杭州"])
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.loadMoreError, "服务开小差了")
    }

    func testRefreshReplacesFirstPageInsteadOfAppending() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 2)
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()

        service.defaultPublishedPlaces = page([city("苏州", country: "中国")], total: 1)
        await model.refresh()

        XCTAssertEqual(model.cities.map(\.name), ["苏州"])
        XCTAssertEqual(model.total, 1)
        XCTAssertFalse(model.hasMore)
    }

    // MARK: - §6.5 排序

    func testCitiesSortByPublishedAtDescendingThenNameAscending() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("重庆", country: "中国", publishedAt: "2026-08-01 10:00:00"),
            city("北京", country: "中国", publishedAt: "2026-08-20 10:00:00"),
            city("上海", country: "中国", publishedAt: "2026-08-20 10:00:00"),
            city("杭州", country: "中国", publishedAt: "2026-08-10 10:00:00")
        ], total: 4)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        // 服务端可能按别的规则排；拼接后由客户端整体重排。
        // 同 `publishedAt` 的 tie-break 是码位序而不是拼音序——规格 §6.5 要的是
        // 客户端可复现的稳定顺序，跟着设备语言变的本地化排序反而不确定。
        XCTAssertEqual(model.cities.map(\.name), ["上海", "北京", "杭州", "重庆"])
    }

    func testCitiesWithoutPublishedAtSortLast() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("未知", country: "中国", publishedAt: nil),
            city("杭州", country: "中国", publishedAt: "2026-08-10 10:00:00")
        ], total: 2)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertEqual(model.cities.map(\.name), ["杭州", "未知"])
    }

    // MARK: - §6.4 分段

    func testSegmentHiddenWhenFewerThanTwoCountries() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("杭州", country: "中国"),
            city("苏州", country: "中国"),
            city("缺国家", country: nil)
        ], total: 3)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertFalse(model.showsSegment, "只有一个非空 country 时整条分段控件不出现")
        XCTAssertEqual(model.visibleCities.count, 3, "不分段时全部城市都显示")
    }

    func testSegmentAppearsAndDefaultsToDomestic() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("京都", country: "日本"),
            city("杭州", country: "中国")
        ], total: 2)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertTrue(model.showsSegment)
        XCTAssertEqual(model.resolvedSegment, .domestic)
        XCTAssertEqual(model.visibleCities.map(\.name), ["杭州"])
    }

    func testSegmentFallsBackToOverseasWhenDomesticBucketIsEmpty() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("京都", country: "日本"),
            city("曼谷", country: "泰国"),
            city("缺国家", country: "  ")
        ], total: 3)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertEqual(model.resolvedSegment, .overseas)
        // 缺失 / 空白的 country 归国外，否则这些城市在两个分段里都看不到。
        XCTAssertEqual(model.visibleCities.map(\.name).sorted(), ["京都", "缺国家", "曼谷"].sorted())
    }

    func testSelectingSegmentIsClientSideOnly() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("京都", country: "日本"),
            city("杭州", country: "中国")
        ], total: 2)
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()

        model.select(.overseas)

        XCTAssertEqual(model.visibleCities.map(\.name), ["京都"])
        XCTAssertEqual(service.publishedPlaceQueries.count, 1, "切换分段不重新请求")
    }

    func testExplicitSegmentSurvivesRefresh() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("京都", country: "日本"),
            city("杭州", country: "中国")
        ], total: 2)
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()
        model.select(.overseas)

        await model.refresh()

        XCTAssertEqual(model.resolvedSegment, .overseas, "用户明确选过的分段不能被刷新冲掉")
        XCTAssertEqual(model.visibleCities.map(\.name), ["京都"])
    }

    func testCountrySegmentMatchingTreatsChinaAsDomestic() {
        XCTAssertTrue(ExploreCountrySegment.domestic.matches(country: "中国"))
        XCTAssertTrue(ExploreCountrySegment.domestic.matches(country: " 中国 "))
        XCTAssertFalse(ExploreCountrySegment.domestic.matches(country: "日本"))
        XCTAssertFalse(ExploreCountrySegment.domestic.matches(country: nil))
        XCTAssertTrue(ExploreCountrySegment.overseas.matches(country: nil))
        XCTAssertTrue(ExploreCountrySegment.overseas.matches(country: "日本"))
        XCTAssertFalse(ExploreCountrySegment.overseas.matches(country: "中国"))
        XCTAssertEqual(ExploreCountrySegment.allCases.map(\.displayLabel), ["国内", "国外"])
    }

    // MARK: - §6.6 分页

    func testLoadMoreAppendsDeduplicatesAndResorts() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([
            city("杭州", country: "中国", publishedAt: "2026-08-20 10:00:00")
        ], total: 60)
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()
        XCTAssertTrue(model.hasMore)

        service.defaultPublishedPlaces = page([
            city("杭州", country: "中国", publishedAt: "2026-08-20 10:00:00"), // 服务端重叠返回
            city("重庆", country: "中国", publishedAt: "2026-08-25 10:00:00")
        ], total: 60)
        await model.loadMore()

        XCTAssertEqual(service.publishedPlaceQueries.last?.page, 2)
        XCTAssertEqual(model.cities.map(\.name), ["重庆", "杭州"], "追加后整体重排，不去重会多出一张卡")
        XCTAssertFalse(model.hasMore, "第 2 页已经越过 total，分页要收口")
    }

    func testHasMoreTerminatesWhenServerReturnsOverlappingPages() async {
        // 回归：早期用「卡片数 < total」判定，服务端跨页重叠时去重后的卡片数
        // 永远追不上 total，「加载更多」会一直亮着但点了什么都不加。
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 3)
        let model = ExploreHomeViewModel(service: service)

        await model.loadIfNeeded()

        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoadingMore)
    }

    func testLoadMoreIsNoOpWhenEverythingIsLoaded() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 1)
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()

        await model.loadMore()

        XCTAssertEqual(service.publishedPlaceQueries.count, 1)
        XCTAssertNil(model.loadMoreError)
    }

    func testLoadMoreFailureBlocksUntilRetried() async {
        let service = SavedPlaceServicingStub()
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 60)
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()

        service.publishedPlacesHandler = { _ in throw APIError.business(code: 50000, message: "服务开小差了") }
        await model.loadMore()
        XCTAssertEqual(model.loadMoreError, "服务开小差了")
        XCTAssertEqual(model.cities.count, 1)

        // 错误没清掉时 loadMore 直接 return，底部的「重试」必须走 retryLoadMore。
        await model.loadMore()
        XCTAssertEqual(service.publishedPlaceQueries.count, 2)

        service.publishedPlacesHandler = nil
        service.defaultPublishedPlaces = page([city("重庆", country: "中国")], total: 60)
        await model.retryLoadMore()

        XCTAssertNil(model.loadMoreError)
        XCTAssertEqual(model.cities.map(\.name).sorted(), ["杭州", "重庆"])
    }

    func testRetryAfterFullFailureReloadsFirstPage() async {
        let service = SavedPlaceServicingStub()
        service.publishedPlacesHandler = { _ in throw APIError.business(code: 50000, message: "boom") }
        let model = ExploreHomeViewModel(service: service)
        await model.loadIfNeeded()
        guard case .failed = model.phase else {
            return XCTFail("首屏失败应进入 failed 态")
        }

        service.publishedPlacesHandler = nil
        service.defaultPublishedPlaces = page([city("杭州", country: "中国")], total: 1)
        await model.retry()

        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.cities.map(\.name), ["杭州"])
    }

    // MARK: - Fixtures

    private func page(_ list: [PublishedPlace], total: Int) -> PageResponse<PublishedPlace> {
        PageResponse(list: list, total: total, page: 1, pageSize: PublishedPlacesQuery.pageSizeLimit)
    }

    private func city(
        _ name: String,
        country: String?,
        publishedAt: String? = "2026-08-20 10:00:00"
    ) -> PublishedPlace {
        PublishedPlace(
            id: "place-\(name)",
            name: name,
            placeScope: .destination,
            category: .city,
            cityName: name,
            country: country,
            latitude: nil,
            longitude: nil,
            supportedUsages: [.tripDestination],
            highlight: nil,
            publishedAt: publishedAt,
            isSaved: nil,
            cover: nil
        )
    }
}
