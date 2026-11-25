import SwiftUI
import TracciNetworking

/// 探索首页（规格 §6）：分段筛选 + 城市卡网格。
///
/// 只负责呈现——数据、排序（§6.5）、分段默认落位（§6.4）都在 `ExploreHomeViewModel`；
/// 氛围底由 `ExploreRootView` 这层导航壳提供；页头用 `AppTabPageHeader`，与回忆/我的对齐。
struct ExploreHomeView: View {
    @Bindable var viewModel: ExploreHomeViewModel
    var bottomTabBarContentInset: CGFloat = AppNavigationMetrics.contentInset(for: SafeAreaMetrics.bottom)
    var onRootScrollOffsetChange: (CGFloat) -> Void = { _ in }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private enum StickySegment {
        /// 稿子 .segment-pin 的 rgba(255,255,255,0.82)。
        static let washOpacity = 0.82
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                AppTabPageHeader(
                    systemImage: AppTab.explore.systemImage,
                    title: AppTab.explore.title
                )
                .padding(.horizontal, AppSpacing.pageX)

                content
            }
            .padding(.bottom, AppSpacing.lg)
        }
        // 规格 §3.3（2026-09-15 拍板）：分段吸顶，滚动后不再跟手滚走。
        // `showsSegment == false` 时不渲染、不占位——分段本就不出现（决策 16），
        // 不能留一条空条。
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.showsSegment {
                stickySegmentBar
            }
        }
        .tracciRootScrollOffset { offset in
            onRootScrollOffsetChange(max(0, offset))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomTabBarContentInset)
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - Segment

    /// 吸顶条：满宽毛玻璃底 + 下分隔线。页头（AppTabPageHeader）随内容滚走后，
    /// 分段钉在安全区顶，读作「页头的第二行」，而不是另起一条独立浮条。
    private var stickySegmentBar: some View {
        TracciSegmentedControl(
            selection: segmentBinding,
            options: ExploreCountrySegment.allCases,
            title: { $0.displayLabel }
        )
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity)
        // 白 wash 压在毛玻璃上，读作导航栏第二行；Reduce Transparency 下毛玻璃近乎透明，
        // 换成不透明卡片白才不会让滚过的内容把字吃掉。
        .background {
            if reduceTransparency {
                AppColors.cardBackground
            } else {
                AppColors.cardBackground.opacity(StickySegment.washOpacity)
                    .background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("筛选城市")
    }

    private var segmentBinding: Binding<ExploreCountrySegment> {
        Binding(
            get: { viewModel.resolvedSegment },
            set: { viewModel.select($0) }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.showsSkeleton {
            ExploreCityGridSkeleton()
        } else if let message = viewModel.failureMessage {
            ErrorStateView(
                title: "探索暂时打不开",
                message: message,
                retryTitle: "重试"
            ) {
                Task { await viewModel.retry() }
            }
            .padding(.horizontal, AppSpacing.pageX)
        } else if viewModel.phase == .empty {
            EmptyStateView(
                title: "还没有可看的地点",
                subtitle: "内容会陆续补上。",
                buttonTitle: nil
            )
            .padding(.horizontal, AppSpacing.pageX)
        } else {
            cityGrid
            paginationFooter
        }
    }

    private var cityGrid: some View {
        let cities = viewModel.visibleCities
        return LazyVGrid(columns: columns(for: cities.count), spacing: AppSpacing.md) {
            ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                NavigationLink(value: ExploreNavigationRoute.city(ExploreCitySeed(place: city))) {
                    // 规格 §6.3：整卡可点，不显示计数；只有一座城市时改单列 16:9。
                    ExploreCityCard(place: city, aspectRatio: cities.count == 1 ? 16 / 9 : 1)
                }
                .pressableCardStyle()
                .fadeSlideIn(index: index)
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
    }

    private func columns(for count: Int) -> [GridItem] {
        count == 1 ? [GridItem(.flexible())] : ExploreCityGridSkeleton.columns
    }

    // MARK: - Pagination

    private var paginationFooter: some View {
        ExploreLoadMoreFooter(
            hasMore: viewModel.hasMore,
            isLoadingMore: viewModel.isLoadingMore,
            errorMessage: viewModel.loadMoreError,
            loadMoreHint: "加载下一页城市",
            retryHint: "重新加载下一页城市",
            onLoadMore: { Task { await viewModel.loadMore() } },
            onRetryLoadMore: { Task { await viewModel.retryLoadMore() } }
        )
    }
}

// MARK: - Previews

/// 模拟器连不到后端，网格只能靠 Preview 看。约定同 `SavedPlacesPreviewSupport`：
/// 只实现探索用到的 `publishedPlaces`，其余接口一律抛错。
private struct ExploreHomePreviewService: SavedPlaceServicing {
    var cities: [PublishedPlace] = []
    var fails = false

    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> {
        if fails { throw APIError.business(code: 50000, message: "网络连接暂时不可用，请稍后再试。") }
        return PageResponse(list: cities, total: cities.count, page: query.page, pageSize: query.pageSize)
    }

    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace { throw PreviewUnavailable() }
    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> { throw PreviewUnavailable() }
    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace { throw PreviewUnavailable() }
    func delete(savedPlaceId: String) async throws { throw PreviewUnavailable() }
    func placeDetail(placeId: String) async throws -> PlaceDetail { throw PreviewUnavailable() }

    private struct PreviewUnavailable: Error {}
}

private func previewCity(
    _ name: String,
    country: String?,
    highlight: String?,
    hasCover: Bool,
    publishedAt: String = "2026-08-20 10:00:00"
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
        highlight: highlight,
        publishedAt: publishedAt,
        isSaved: nil,
        cover: hasCover
            ? PublishedPlaceCover(
                id: "cover-\(name)",
                thumbnailUrl: "https://picsum.photos/seed/\(name)/600/600",
                previewUrl: nil,
                url: nil,
                altText: nil,
                attribution: nil
            )
            : nil
    )
}

@MainActor
private func previewHomeModel(
    cities: [PublishedPlace] = [],
    fails: Bool = false
) -> ExploreHomeViewModel {
    ExploreHomeViewModel(service: ExploreHomePreviewService(cities: cities, fails: fails))
}

#Preview("探索 · 双列网格 + 分段") {
    NavigationStack {
        ExploreHomeView(viewModel: previewHomeModel(cities: [
            previewCity("杭州", country: "中国", highlight: "西湖十景", hasCover: true),
            previewCity("苏州", country: "中国", highlight: nil, hasCover: false),
            previewCity("京都", country: "日本", highlight: "千年古都，寺院与町家", hasCover: true),
            previewCity("成都", country: "中国", highlight: "茶馆与小吃", hasCover: true),
            previewCity("重庆", country: "中国", highlight: nil, hasCover: false)
        ]))
    }
    .tracciAtmosphere(.creek)
}

#Preview("探索 · 单城市 16:9") {
    NavigationStack {
        ExploreHomeView(viewModel: previewHomeModel(cities: [
            previewCity("杭州", country: "中国", highlight: "西湖十景", hasCover: true)
        ]))
    }
    .tracciAtmosphere(.creek)
}

#Preview("探索 · 空态") {
    NavigationStack {
        ExploreHomeView(viewModel: previewHomeModel())
    }
    .tracciAtmosphere(.creek)
}

#Preview("探索 · 错误态") {
    NavigationStack {
        ExploreHomeView(viewModel: previewHomeModel(fails: true))
    }
    .tracciAtmosphere(.creek)
}
