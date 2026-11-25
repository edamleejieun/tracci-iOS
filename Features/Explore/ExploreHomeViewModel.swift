import Foundation
import Observation
import TracciNetworking

// MARK: - Country segment

/// 探索首页的「国内 / 国外」分段。
///
/// 契约 §15.4.2 没有地区字段，规格 §6.4 要求纯客户端按 `country` 现算：
/// 切换分段不重新请求，只在已加载的列表上过滤。
enum ExploreCountrySegment: String, CaseIterable, Identifiable, Sendable {
    case domestic
    case overseas

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .domestic: "国内"
        case .overseas: "国外"
        }
    }

    /// `country == "中国"` 归国内；其余（含缺失）归国外。
    /// 缺失按国外处理，避免无国家信息的城市在两个分段里都消失。
    func matches(country: String?) -> Bool {
        switch self {
        case .domestic: Self.normalized(country) == "中国"
        case .overseas: Self.normalized(country) != "中国"
        }
    }

    private static func normalized(_ country: String?) -> String {
        country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - View model

@MainActor
@Observable
final class ExploreHomeViewModel {
    enum LoadPhase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    /// 本接口 `pageSize` 上限 50，一次尽量把首屏城市取全，减少「加载更多」的点击。
    static let pageSize = PublishedPlacesQuery.pageSizeLimit

    private let service: any SavedPlaceServicing

    private(set) var phase: LoadPhase = .idle
    private(set) var cities: [PublishedPlace] = []
    private(set) var total = 0
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?

    /// 用户明确点过的分段。`nil` = 沿用规格 §6.4 的默认落位（国内优先，国内为空则国外），
    /// 这样下拉刷新拿到新数据后默认规则会重新判定，而用户的显式选择不会被刷新冲掉。
    private(set) var selectedSegment: ExploreCountrySegment?

    private var currentPage = 0
    private var hasLoaded = false
    private var reloadGeneration = 0

    init(service: any SavedPlaceServicing) {
        self.service = service
    }

    // MARK: Derived state

    /// 规格 §6.4：列表里出现 ≥ 2 个不同 `country` 才显示分段，否则整条控件不出现。
    var showsSegment: Bool { distinctCountries.count >= 2 }

    var resolvedSegment: ExploreCountrySegment {
        if let selectedSegment { return selectedSegment }
        let hasDomestic = cities.contains { ExploreCountrySegment.domestic.matches(country: $0.country) }
        return hasDomestic ? .domestic : .overseas
    }

    var visibleCities: [PublishedPlace] {
        guard showsSegment else { return cities }
        let segment = resolvedSegment
        return cities.filter { segment.matches(country: $0.country) }
    }

    /// 用分页游标判定，不用去重后的卡片数：服务端跨页返回重叠记录时，
    /// 卡片数永远追不上 `total`，「加载更多」会变成一个点了没反应的死按钮。
    var hasMore: Bool { currentPage > 0 && currentPage * Self.pageSize < total }

    /// 首屏骨架只在「还没有任何卡片可显示」时铺满，刷新时保留旧内容。
    /// 含 `.idle`：`.task` 起跑前不要闪一帧空白。
    var showsSkeleton: Bool { cities.isEmpty && (phase == .idle || phase == .loading) }

    var failureMessage: String? {
        guard case let .failed(message) = phase else { return nil }
        return message
    }

    // MARK: Actions

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload(showsFullScreenLoading: true)
    }

    func retry() async {
        await reload(showsFullScreenLoading: cities.isEmpty)
    }

    /// 规格 §6.6：下拉刷新整页替换第 1 页，不追加、不保留旧的分页游标。
    func refresh() async {
        await reload(showsFullScreenLoading: false)
    }

    func select(_ segment: ExploreCountrySegment) {
        selectedSegment = segment
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, phase != .loading, loadMoreError == nil else { return }
        let generation = reloadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let response = try await fetch(page: nextPage)
            guard generation == reloadGeneration else { return }
            apply(response, page: nextPage, append: true)
            loadMoreError = nil
        } catch {
            guard !ExploreRequestCancellation.isCancelled(error), generation == reloadGeneration else { return }
            loadMoreError = SavedPlaceErrorMessage.resolve(error)
        }
    }

    /// 分页失败后列表还在，用底部的「重试」再来一次；不清掉错误 `loadMore()` 会直接 return。
    func retryLoadMore() async {
        loadMoreError = nil
        await loadMore()
    }

    // MARK: Private

    private func reload(showsFullScreenLoading: Bool) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        hasLoaded = true

        if showsFullScreenLoading {
            phase = .loading
            currentPage = 0
            cities = []
            total = 0
        }
        loadMoreError = nil

        do {
            let response = try await fetch(page: 1)
            guard generation == reloadGeneration else { return }
            apply(response, page: 1, append: false)
            phase = cities.isEmpty ? .empty : .loaded
        } catch {
            guard !ExploreRequestCancellation.isCancelled(error), generation == reloadGeneration else { return }
            let message = SavedPlaceErrorMessage.resolve(error)
            if cities.isEmpty {
                phase = .failed(message)
            } else {
                // 已有内容时不整页翻红：保留列表，用分页位的软提示承接失败。
                loadMoreError = message
                phase = .loaded
            }
        }
    }

    private func fetch(page: Int) async throws -> PageResponse<PublishedPlace> {
        try await service.publishedPlaces(
            PublishedPlacesQuery(
                placeScope: .destination,
                page: page,
                pageSize: Self.pageSize
            )
        )
    }

    private func apply(_ response: PageResponse<PublishedPlace>, page: Int, append: Bool) {
        total = response.total
        currentPage = page

        if append {
            let existingIDs = Set(cities.map(\.id))
            cities.append(contentsOf: response.list.filter { !existingIDs.contains($0.id) })
        } else {
            cities = response.list
        }
        // 分页拼接后必须整体重排：追加页里可能有更新时间更早的城市。
        cities = ExplorePublishedPlaceSorting.sorted(cities)
    }

    private var distinctCountries: Set<String> {
        Set(cities.compactMap { place in
            guard let country = place.country?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !country.isEmpty else { return nil }
            return country
        })
    }
}

// MARK: - Cancellation

/// 取消不是失败：`APIClient` 会把 URLSession 的取消包成 `underlying("cancelled")`，
/// 直接落进错误态会让 Tab 切换 / 返回时页面闪一下红。
enum ExploreRequestCancellation {
    static func isCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if Task.isCancelled { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }

        if let apiError = error as? APIError, case let .underlying(message) = apiError {
            return isCancelledText(message)
        }
        return isCancelledText(error.localizedDescription)
    }

    private static func isCancelledText(_ text: String) -> Bool {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cancelled", "canceled": return true
        default: return false
        }
    }
}
