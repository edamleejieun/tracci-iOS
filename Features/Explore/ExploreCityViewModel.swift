import Foundation
import Observation
import TracciNetworking

/// 城市页的类别筛选 chip（规格 §7.6）。`全部` 恒定首位，其余按该城市内数量 DESC。
enum ExploreCityChip: Hashable, Identifiable {
    case all
    case category(PlaceCategory)

    var id: String {
        switch self {
        case .all: "all"
        case let .category(category): category.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: "全部"
        case let .category(category): category.displayName
        }
    }

    var category: PlaceCategory? {
        guard case let .category(category) = self else { return nil }
        return category
    }
}

/// 从首页城市卡带进城市页的种子字段。
///
/// 列表契约（§15.4.2）已经返回这些字段，带上它们城市页才能：Hero 封面无缝承接、
/// 详情返回前先把标题与 meta 立起来、详情失败时页面仍有内容可渲染。
struct ExploreCitySeed: Hashable {
    let id: String
    let name: String
    let country: String?
    let category: PlaceCategory
    let highlight: String?
    let isSaved: Bool
    let coverURL: String?

    /// 首页列表项已经带齐这些字段，直接承接（规格 §10.1「封面承上」）。
    init(place: PublishedPlace) {
        self.init(
            id: place.id,
            name: place.name,
            country: place.country,
            category: place.category,
            highlight: place.highlight,
            isSaved: place.isSavedLocally,
            coverURL: place.cover?.displayURL
        )
    }

    init(
        id: String,
        name: String,
        country: String?,
        category: PlaceCategory,
        highlight: String?,
        isSaved: Bool,
        coverURL: String?
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.category = category
        self.highlight = highlight
        self.isSaved = isSaved
        self.coverURL = coverURL
    }
}

@MainActor
@Observable
final class ExploreCityViewModel {
    enum ListPhase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    static let pageSize = PublishedPlacesQuery.pageSizeLimit

    let seed: ExploreCitySeed
    private let service: any SavedPlaceServicing

    private(set) var listPhase: ListPhase = .idle
    private(set) var places: [PublishedPlace] = []
    private(set) var total = 0
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?

    private(set) var detail: PlaceDetail?
    private(set) var isDetailLoading = true
    /// 规格 §7.2：详情失败不整页报错，简介区一行提示，地点流照常。
    private(set) var isIntroFailed = false

    /// 城市收藏态。先用首页列表的 `isSaved` 兜底，详情回来后由 `userContext` 精确化。
    private(set) var citySaved: Bool
    private(set) var citySavedPlaceId: String?

    /// 会话内的 ♡ 乐观覆盖（规格 §7.5）；退出页面即失效，下次以服务端为准。
    private(set) var savedOverrides: [String: Bool] = [:]

    var selectedChip: ExploreCityChip = .all
    /// 取消收藏确认层里的失败提示（保留弹层，用户可重试或「保留」）。
    var unsaveErrorMessage: String?
    var toast: TracciToastMessage?

    private var currentPage = 0
    private var hasLoaded = false
    private var reloadGeneration = 0

    init(seed: ExploreCitySeed, service: any SavedPlaceServicing) {
        self.seed = seed
        self.service = service
        self.citySaved = seed.isSaved
    }

    // MARK: Derived

    var cityName: String { detail?.name ?? seed.name }

    var cityCountry: String? { trimmed(detail?.country ?? seed.country) }

    var cityHighlight: String? { trimmed(detail?.editorialContent?.highlights?.first ?? seed.highlight) }

    var cityCategoryDisplayName: String { (detail?.category ?? seed.category).displayName }

    /// Hero 图优先级：详情媒体大图 → 列表封面 → 品牌渐变兜底（规格 §8.2 的三级降级同源）。
    var heroURL: URL? {
        let raw = detail?.media?.first?.heroURL ?? seed.coverURL
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var introduction: String? { trimmed(detail?.editorialContent?.introduction) }

    var contentMetaLabel: String? { trimmed(detail?.contentMeta?.label) }

    var showsSkeleton: Bool { places.isEmpty && (listPhase == .idle || listPhase == .loading) }

    var failureMessage: String? {
        guard case let .failed(message) = listPhase else { return nil }
        return message
    }

    var hasMore: Bool { currentPage > 0 && currentPage * Self.pageSize < total }

    /// 规格 §7.6：地点数 ≥ 12 且覆盖 ≥ 3 个类别才显示 chips，避免内容不足还硬撑功能。
    var showsChips: Bool { places.count >= 12 && categoryCounts.count >= 3 }

    var chips: [ExploreCityChip] {
        guard showsChips else { return [] }
        return [.all] + categoryCounts.map { ExploreCityChip.category($0.category) }
    }

    /// 纯本地过滤，不发请求（规格 §7.6）。
    var visiblePlaces: [PublishedPlace] {
        guard let category = selectedChip.category else { return places }
        return places.filter { $0.category == category }
    }

    var visibleCount: Int { visiblePlaces.count }

    func isSaved(_ place: PublishedPlace) -> Bool {
        savedOverrides[place.id] ?? place.isSavedLocally
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload(showsFullScreenLoading: true)
    }

    func refresh() async {
        await reload(showsFullScreenLoading: false)
    }

    func retry() async {
        await reload(showsFullScreenLoading: places.isEmpty)
    }

    /// 规格 §7.2：只补详情，地点流不动。
    func retryIntro() async {
        isDetailLoading = true
        applyDetail(await fetchDetail())
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, listPhase != .loading, loadMoreError == nil else { return }

        let generation = reloadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let response = try await fetchPage(page: nextPage)
            guard generation == reloadGeneration else { return }
            applyPage(response, page: nextPage, append: true)
            loadMoreError = nil
        } catch {
            guard !ExploreRequestCancellation.isCancelled(error), generation == reloadGeneration else { return }
            loadMoreError = SavedPlaceErrorMessage.resolve(error)
        }
    }

    func retryLoadMore() async {
        loadMoreError = nil
        await loadMore()
    }

    func select(_ chip: ExploreCityChip) {
        selectedChip = chip
    }

    // MARK: 快捷收藏（规格 §7.5）

    /// 已收藏态点按不取消——取消只在确认层里做，避免误触丢收藏。
    /// 乐观翻转在第一个 `await` 之前完成，所以反馈仍然是即时的。
    func quickSave(_ place: PublishedPlace) async {
        guard !isSaved(place) else { return }

        savedOverrides[place.id] = true
        AppHaptics.lightImpact()

        do {
            _ = try await service.create(.existingPlace(placeId: place.id, note: nil))
        } catch {
            // 40901 = 服务端认为已收藏：保持实心、不报错（幂等）。
            guard !SavedPlaceErrorMessage.isAlreadySaved(error) else { return }
            savedOverrides[place.id] = false
            toast = .error("收藏没成功，稍后再试")
        }
    }

    /// 规格 §8.4：半层里收藏 / 取消收藏后回写这一行的收藏态。
    /// 只写内存覆盖，不重拉列表——回首页也不刷新，退出会话即失效。
    func applySavedStateChange(placeId: String, isSaved: Bool) {
        savedOverrides[placeId] = isSaved
    }

    // MARK: 城市收藏（规格 §7.3）

    func saveCity() async {
        guard !citySaved else { return }

        do {
            let saved = try await service.create(.existingPlace(placeId: seed.id, note: nil))
            citySaved = true
            citySavedPlaceId = saved.id
            toast = .success("已收藏，可在「我的 → 想去的地点」看到")
        } catch {
            if SavedPlaceErrorMessage.isAlreadySaved(error) {
                citySaved = true
                return
            }
            toast = .error("收藏没成功，稍后再试")
        }
    }

    /// 确认层异步路径：成功返回 `true` 关层，失败返回 `false` 保留弹层并显示原因。
    func unsaveCity() async -> Bool {
        let id = await resolvedSavedPlaceId()
        guard let id else {
            unsaveErrorMessage = "收藏没成功，稍后再试"
            return false
        }
        do {
            try await service.delete(savedPlaceId: id)
            citySaved = false
            citySavedPlaceId = nil
            unsaveErrorMessage = nil
            return true
        } catch {
            unsaveErrorMessage = SavedPlaceErrorMessage.resolve(error)
            return false
        }
    }

    /// 「用这里创建旅程」：未收藏先静默收藏（规格 §7.3），返回用于预填的 savedPlaceId。
    /// 放弃创建表单**不回滚**这次收藏。
    func beginCreateTrip() async -> String? {
        if let citySavedPlaceId { return citySavedPlaceId }

        do {
            let saved = try await service.create(.existingPlace(placeId: seed.id, note: nil))
            citySaved = true
            citySavedPlaceId = saved.id
            toast = .info("已加入想去的地点")
            return saved.id
        } catch {
            if SavedPlaceErrorMessage.isAlreadySaved(error) {
                citySaved = true
                let id = await resolvedSavedPlaceId()
                citySavedPlaceId = id
                toast = .info("已加入想去的地点")
                return id
            }
            toast = .error("收藏没成功，稍后再试")
            return nil
        }
    }

    // MARK: Private

    /// 列表只给 `isSaved` 不给 `savedPlaceId`；详情失败时补一次详情拿 id。
    private func resolvedSavedPlaceId() async -> String? {
        if let citySavedPlaceId { return citySavedPlaceId }
        guard citySaved else { return nil }
        if case let .success(detail) = await fetchDetail() {
            applyDetail(.success(detail))
            return detail.userContext?.savedPlaceId
        }
        return nil
    }

    private func reload(showsFullScreenLoading: Bool) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        hasLoaded = true

        if showsFullScreenLoading {
            listPhase = .loading
            places = []
            total = 0
            currentPage = 0
        }
        loadMoreError = nil
        isDetailLoading = true

        // 规格 §7.2：两个请求并行；详情失败不能拖累地点流。
        async let detailResult = fetchDetail()
        async let listResult = fetchPage(page: 1)

        applyDetail(await detailResult)
        guard generation == reloadGeneration else { return }

        do {
            let response = try await listResult
            guard generation == reloadGeneration else { return }
            applyPage(response, page: 1, append: false)
            listPhase = places.isEmpty ? .empty : .loaded
        } catch {
            guard !ExploreRequestCancellation.isCancelled(error), generation == reloadGeneration else { return }
            let message = SavedPlaceErrorMessage.resolve(error)
            if places.isEmpty {
                listPhase = .failed(message)
            } else {
                loadMoreError = message
                listPhase = .loaded
            }
        }
    }

    private func fetchDetail() async -> Result<PlaceDetail, Error> {
        do {
            return .success(try await service.placeDetail(placeId: seed.id))
        } catch {
            return .failure(error)
        }
    }

    private func fetchPage(page: Int) async throws -> PageResponse<PublishedPlace> {
        try await service.publishedPlaces(
            PublishedPlacesQuery(
                placeScope: .poi,
                cityName: seed.name,
                page: page,
                pageSize: Self.pageSize
            )
        )
    }

    private func applyDetail(_ result: Result<PlaceDetail, Error>) {
        isDetailLoading = false
        switch result {
        case let .success(detail):
            self.detail = detail
            isIntroFailed = false
            citySaved = detail.userContext?.isSaved ?? citySaved
            citySavedPlaceId = detail.userContext?.savedPlaceId ?? citySavedPlaceId
        case let .failure(error):
            guard !ExploreRequestCancellation.isCancelled(error) else { return }
            isIntroFailed = true
        }
    }

    private func applyPage(_ response: PageResponse<PublishedPlace>, page: Int, append: Bool) {
        total = response.total
        currentPage = page

        if append {
            let existingIDs = Set(places.map(\.id))
            places.append(contentsOf: response.list.filter { !existingIDs.contains($0.id) })
        } else {
            places = response.list
        }
        places = ExplorePublishedPlaceSorting.sorted(places)
    }

    private var categoryCounts: [(category: PlaceCategory, count: Int)] {
        var counts: [PlaceCategory: Int] = [:]
        for place in places { counts[place.category, default: 0] += 1 }
        return counts
            .map { (category: $0.key, count: $0.value) }
            .filter { $0.count > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.category.displayName < rhs.category.displayName
            }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// 探索两层共用的排序（规格 §6.5）：`publishedAt` 降序，同值 `name` 升序，缺值排最后。
///
/// 客户端自己收口而不信服务端顺序，翻页拼接后整体重排才稳定。`name` 用 Swift 的 `<`
/// 是码位序而非拼音序——这是有意的：与设备 locale 无关，每台机器顺序一致。
enum ExplorePublishedPlaceSorting {
    static func sorted(_ places: [PublishedPlace]) -> [PublishedPlace] {
        places.enumerated()
            .map { (index: $0.offset, date: $0.element.publishedDate, place: $0.element) }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (left?, right?) where left != right:
                    return left > right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    if lhs.place.name != rhs.place.name { return lhs.place.name < rhs.place.name }
                    return lhs.index < rhs.index
                }
            }
            .map(\.place)
    }
}
