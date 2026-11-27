import SwiftUI
import TracciNetworking

/// 城市页（规格 §7）：沉浸 Hero + 墨色城市名 + 操作行 + 简介 + 地点流。
///
/// 系统导航栏整条隐藏，返回改用浮层玻璃按钮——沿用旅程详情的沉浸页写法
/// （`tracciImmersiveHeroScroll` + `tracciReadsSafeAreaTop` + `tracciInteractivePopGesture`）。
/// Dock 显隐不在这里声明：由 `exploreNavigationPath` 深度经全局单一 preference 驱动。
struct ExploreCityView: View {
    /// `navigationDestination` 的闭包会被 SwiftUI 反复求值，所以 VM 必须落在 `@State`：
    /// 否则每次父层重渲染都会换一个新实例，已加载的详情与地点流全丢（同 `PlaceDetailView` 写法）。
    @State private var viewModel: ExploreCityViewModel
    var onBack: () -> Void = {}
    var shouldHandleInteractivePop: () -> Bool = { true }
    var onInteractivePopFinished: () -> Void = {}
    /// 「用这里创建旅程」把目的地交给创建表单做**只读预填**（规格 §7.3）。
    var onCreateTrip: ((TripCreateSeed) -> Void)?
    /// 半层第一格在**无旅程**时读「先创建旅程」：打开创建表单，但 POI **不**预填为目的地
    /// （规格 §8.3），所以与上面那条城市分支分开走。
    var onCreateTripFromPlace: (() -> Void)?
    /// 半层的「加入行程」要选旅程选天，复用 `SavedPlaceAddToTripSheet` 的同一个 provider。
    private let tripProvider: (any SavedPlaceTripProviding)?
    /// 半层自己发 `GET /places/{placeId}`，用同一份注入的服务。
    private let service: any SavedPlaceServicing

    @State private var safeAreaTop = SafeAreaMetrics.top
    @State private var isCreatingTrip = false
    @State private var showingUnsaveConfirm = false
    /// 点开半层的那个地点；`sheet(item:)` 用它兼作 dismiss 的清空点。
    @State private var sheetPlace: PublishedPlace?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        seed: ExploreCitySeed,
        service: any SavedPlaceServicing,
        tripProvider: (any SavedPlaceTripProviding)? = nil,
        onBack: @escaping () -> Void = {},
        shouldHandleInteractivePop: @escaping () -> Bool = { true },
        onInteractivePopFinished: @escaping () -> Void = {},
        onCreateTrip: ((TripCreateSeed) -> Void)? = nil,
        onCreateTripFromPlace: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: ExploreCityViewModel(seed: seed, service: service))
        self.service = service
        self.tripProvider = tripProvider
        self.onBack = onBack
        self.shouldHandleInteractivePop = shouldHandleInteractivePop
        self.onInteractivePopFinished = onInteractivePopFinished
        self.onCreateTrip = onCreateTrip
        self.onCreateTripFromPlace = onCreateTripFromPlace
    }

    /// 尺寸取自 `designs/explore-v2`（`.city-hero` / `.poi-thumb` / `.save-btn`），
    /// 设计系统没有对应 token，集中在这里而不是散落在 body。
    private enum Layout {
        static let heroHeight: CGFloat = 220
        static let heroTopScrimHeight: CGFloat = 108
        static let heroBottomScrimHeight: CGFloat = 96
        static let heroGlyphPointSize: CGFloat = 44
        static let chipHeight: CGFloat = 32
        static let skeletonRowCount = 4
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                cityHead
                actionRow
                introBlock
                placeStream
            }
            .padding(.bottom, AppSpacing.lg)
        }
        .tracciImmersiveHeroScroll()
        .background(AppColors.pageBackground.ignoresSafeArea())
        .overlay(alignment: .topLeading) { backButton }
        .overlay { unsaveConfirmSheet }
        .tracciReadsSafeAreaTop($safeAreaTop)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .tracciInteractivePopGesture(
            shouldHandlePop: shouldHandleInteractivePop,
            onPopFinished: onInteractivePopFinished
        )
        .sheet(item: $sheetPlace) { place in
            placeSheet(for: place)
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
        .tracciToast($viewModel.toast)
    }

    // MARK: - Place sheet

    /// 地点半层（规格 §8）。收藏 / 取消收藏的结果回写本页那一行的 ♡（§8.4），
    /// 不重拉列表、不引入跨 Tab 通知。
    private func placeSheet(for place: PublishedPlace) -> some View {
        let cityViewModel = viewModel
        return ExplorePlaceSheetView(
            placeId: place.id,
            service: service,
            tripProvider: tripProvider,
            onSavedStateChange: { placeId, isSaved in
                cityViewModel.applySavedStateChange(placeId: placeId, isSaved: isSaved)
            },
            onCreateTrip: { onCreateTripFromPlace?() }
        )
    }

    // MARK: - Hero

    /// Hero 高度含状态栏：沉浸页忽略顶部安全区，图自己铺到屏幕顶。
    private var hero: some View {
        ZStack {
            heroCover

            VStack(spacing: 0) {
                // 顶部压暗只为浮层返回按钮的可读性。
                LinearGradient(
                    stops: [
                        .init(color: AppColors.mediaScrimInk.opacity(0.42), location: 0),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Layout.heroTopScrimHeight)

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // 底部化进页面底色，Hero 与城市名之间不留硬边。
                LinearGradient(
                    stops: [
                        .init(color: AppColors.pageBackground.opacity(0), location: 0),
                        .init(color: AppColors.pageBackground, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Layout.heroBottomScrimHeight)
            }
        }
        .frame(height: Layout.heroHeight + safeAreaTop)
        .clipped()
        .accessibilityHidden(true)
    }

    /// 三级降级：详情媒体大图 → 首页带来的列表封面 → 品牌渐变 + 品类字形。
    /// 种子封面让第一帧就有图，实现规格 §10.1 的「封面承上」。
    private var heroCover: some View {
        ZStack {
            ExploreCoverFallback(
                scope: .destination,
                category: viewModel.seed.category,
                glyphPointSize: Layout.heroGlyphPointSize
            )

            if let heroURL = viewModel.heroURL {
                AsyncImage(url: heroURL) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            AppHaptics.lightImpact()
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(AppTypography.buttonIcon)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 38, height: 38)
                // 深色文字浮层：亮色 wash，Reduce Transparency 回退用实底白。
                .tracciMediaChromeGlass(
                    in: Circle(),
                    wash: .white.opacity(0.55),
                    opaqueFallback: .white.opacity(0.94)
                )
                .tracciElevation(.l1)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
        .pressableCardStyle(scale: 0.92, opacity: 0.85)
        .padding(.leading, AppSpacing.cardSmall)
        .padding(.top, safeAreaTop + AppSpacing.sm)
        .accessibilityLabel("返回")
        .accessibilityHint("回到探索首页")
    }

    // MARK: - City head

    private var cityHead: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 规格 §10：城市名一律墨色，禁止蓝色地名。
            Text(viewModel.cityName)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(cityMeta)
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.textMuted)
                .padding(.top, AppSpacing.xs)

            if let highlight = viewModel.cityHighlight {
                Text(highlight)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.cardSmall)
        .accessibilityElement(children: .contain)
    }

    /// 规格 §7.1：`country · category.displayName`，空项不渲染。
    private var cityMeta: String {
        [viewModel.cityCountry, viewModel.cityCategoryDisplayName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: AppSpacing.sm) {
            PrimaryButton(
                title: "用这里创建旅程",
                isLoading: isCreatingTrip,
                isEnabled: !isCreatingTrip
            ) {
                Task { await createTrip() }
            }
            .accessibilityHint("以这个城市为目的地新建一趟旅程")

            citySaveButton
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.cardSmall)
    }

    /// 规格 §7.3：未收藏直接收藏；已收藏点按**不直接取消**，走二次确认。
    private var citySaveButton: some View {
        Button(action: toggleCitySave) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: viewModel.citySaved ? "bookmark.fill" : "bookmark")
                    .font(AppTypography.buttonIconCompact)
                Text(viewModel.citySaved ? "已收藏" : "收藏")
                    .font(AppTypography.buttonTitleMedium)
            }
            .foregroundStyle(viewModel.citySaved ? AppColors.brandPrimary : AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.lg)
            .frame(minHeight: 52)
            .background(viewModel.citySaved ? AppColors.brandPrimaryBackground : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .stroke(
                        viewModel.citySaved
                            ? AppColors.brandPrimary.opacity(0.35)
                            : AppColors.borderDefault,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(TracciPressableButtonStyle())
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: viewModel.citySaved
        )
        .accessibilityLabel(viewModel.citySaved ? "已收藏" : "收藏地点")
        .accessibilityHint(viewModel.citySaved ? "再次点击可取消收藏" : "加入我的想去的地点")
    }

    private var unsaveConfirmSheet: some View {
        TracciConfirmSheet(
            isPresented: $showingUnsaveConfirm,
            tone: .destructive,
            title: "取消收藏？",
            message: "不会删除已经创建的旅程或行程节点。",
            cancelTitle: "保留",
            confirmTitle: "取消收藏",
            errorMessage: $viewModel.unsaveErrorMessage,
            onConfirmAsync: { await viewModel.unsaveCity() }
        )
    }

    private func toggleCitySave() {
        AppHaptics.lightImpact()
        if viewModel.citySaved {
            showingUnsaveConfirm = true
        } else {
            Task { await viewModel.saveCity() }
        }
    }

    /// 规格 §7.3：未收藏先静默收藏，再打开创建表单。放弃表单不回滚这次收藏。
    private func createTrip() async {
        guard !isCreatingTrip else { return }
        isCreatingTrip = true
        defer { isCreatingTrip = false }

        AppHaptics.lightImpact()
        guard let savedPlaceId = await viewModel.beginCreateTrip() else { return }
        // 用 `cityName` 而不是 `seed.name`：详情可能把名字改细了（杭州 → 杭州市），
        // 表单回显的要是用户在城市页读到的那个。
        onCreateTrip?(TripCreateSeed(
            destinationSavedPlaceId: savedPlaceId,
            destinationName: viewModel.cityName
        ))
    }

    // MARK: - Intro

    /// 规格 §7.2：无 `introduction` 时整块隐藏，不留空。
    @ViewBuilder
    private var introBlock: some View {
        if viewModel.isIntroFailed {
            introFailure
        } else if let introduction = viewModel.introduction {
            introContent(introduction)
        }
    }

    /// 详情失败不整页报错——用户的核心目的是看地点，简介区只留一行提示。
    private var introFailure: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("介绍暂时加载失败，可稍后重试")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppSpacing.sm)

            Button {
                Task { await viewModel.retryIntro() }
            } label: {
                Text("重试")
                    .font(AppTypography.labelSemibold)
                    .foregroundStyle(AppColors.interactiveText)
            }
            .buttonStyle(TracciPressableButtonStyle(scales: false))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityHint("重新加载城市介绍")
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.lg)
    }

    private func introContent(_ introduction: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(introduction)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            // 规格 §11：`contentMeta.label` 对用户诚实，不隐藏 AI 辅助。
            if let label = viewModel.contentMetaLabel {
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.lg)
    }

    // MARK: - Place stream

    private var placeStream: some View {
        VStack(spacing: 0) {
            sectionHead

            if viewModel.showsChips {
                chipsRow
            }

            listContent
        }
    }

    private var sectionHead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(viewModel.cityName)的地点")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: AppSpacing.sm)

            Text("\(viewModel.visibleCount) 个地点")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(viewModel.cityName)的地点，\(viewModel.visibleCount) 个")
        .accessibilityHeading(.h2)
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.showsSkeleton {
            placeListSkeleton
        } else if let message = viewModel.failureMessage {
            ErrorStateView(
                title: "探索暂时打不开",
                message: message,
                retryTitle: "重试"
            ) {
                Task { await viewModel.retry() }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.cozy)
        } else if viewModel.listPhase == .empty {
            // 规格 §7.7：城市有内容但没有 POI —— 一行说明，不做整页空态，创建旅程仍可用。
            Text("这个城市的地点正在补充")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.vertical, AppSpacing.xl)
        } else {
            placeList
            paginationFooter
        }
    }

    private var placeList: some View {
        LazyVStack(spacing: AppSpacing.sm) {
            ForEach(viewModel.visiblePlaces) { place in
                ExplorePlaceRow(
                    place: place,
                    isSaved: viewModel.isSaved(place),
                    onOpen: { sheetPlace = place },
                    onSave: { Task { await viewModel.quickSave(place) } }
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.cozy)
        // 规格 §10.1：chips 切换只做列表交叉淡入，不计入每屏主动画。
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: viewModel.selectedChip
        )
    }

    private var placeListSkeleton: some View {
        VStack(spacing: AppSpacing.sm) {
            ForEach(0..<Layout.skeletonRowCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .fill(AppColors.subtleBackground)
                    .frame(minHeight: 92)
                    .overlay {
                        AppShimmerOverlay()
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                    }
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.cozy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载这个城市的地点")
    }

    private var paginationFooter: some View {
        ExploreLoadMoreFooter(
            hasMore: viewModel.hasMore,
            isLoadingMore: viewModel.isLoadingMore,
            errorMessage: viewModel.loadMoreError,
            loadMoreHint: "加载下一页地点",
            retryHint: "重新加载下一页地点",
            onLoadMore: { Task { await viewModel.loadMore() } },
            onRetryLoadMore: { Task { await viewModel.retryLoadMore() } }
        )
        .padding(.horizontal, AppSpacing.pageX)
    }

    // MARK: - Chips

    /// 规格 §7.6：纯本地过滤，不发请求，点选后列表即时切换。
    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.tight) {
                ForEach(viewModel.chips) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.bottom, AppSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("按类别筛选地点")
    }

    private func chipButton(_ chip: ExploreCityChip) -> some View {
        let isSelected = viewModel.selectedChip == chip

        return Button {
            AppHaptics.selection()
            viewModel.select(chip)
        } label: {
            Text(chip.title)
                .font(isSelected ? AppTypography.labelSemibold : AppTypography.label)
                .foregroundStyle(isSelected ? AppColors.textPrimaryInverse : AppColors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.md)
                .frame(height: Layout.chipHeight)
                // 选中态用墨色而不是品牌蓝：蓝只留给选中 Tab、收藏实心与主操作填充。
                .background(Capsule().fill(isSelected ? AppColors.textPrimary : AppColors.cardBackground))
                .overlay {
                    Capsule().stroke(
                        isSelected ? AppColors.textPrimary : AppColors.borderDefault,
                        lineWidth: 1
                    )
                }
                // 视觉 32pt，命中区 44pt（规格 §10.2 所有点击区 ≥ 44pt）。
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
        .accessibilityLabel(chip.title)
        .accessibilityHint("只看这一类")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

/// 城市页要同时看详情与地点流，Preview 服务把两个接口都实现掉。
private struct ExploreCityPreviewService: SavedPlaceServicing {
    var places: [PublishedPlace] = []
    var detail: PlaceDetail?
    var introFails = false

    func placeDetail(placeId: String) async throws -> PlaceDetail {
        if introFails { throw PreviewUnavailable() }
        guard let detail else { throw PreviewUnavailable() }
        return detail
    }

    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> {
        PageResponse(list: places, total: places.count, page: query.page, pageSize: query.pageSize)
    }

    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace { throw PreviewUnavailable() }
    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> { throw PreviewUnavailable() }
    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace { throw PreviewUnavailable() }
    func delete(savedPlaceId: String) async throws { throw PreviewUnavailable() }

    private struct PreviewUnavailable: Error {}
}

private func previewCitySeed() -> ExploreCitySeed {
    ExploreCitySeed(
        id: "place-hangzhou",
        name: "杭州",
        country: "中国",
        category: .city,
        highlight: "西湖十景",
        isSaved: false,
        coverURL: "https://picsum.photos/seed/hangzhou/900/600"
    )
}

private func previewCityService(
    places: [PublishedPlace] = [],
    introduction: String? = nil,
    introFails: Bool = false
) -> ExploreCityPreviewService {
    ExploreCityPreviewService(
        places: places,
        detail: introduction.map { previewCityDetail(introduction: $0) },
        introFails: introFails
    )
}

private func previewCityDetail(introduction: String) -> PlaceDetail {
    PlaceDetail(
        id: "place-hangzhou",
        name: "杭州",
        placeScope: .destination,
        category: .city,
        address: nil,
        cityName: "杭州",
        country: "中国",
        latitude: 30.2741,
        longitude: 120.1551,
        supportedUsages: [.tripDestination],
        userContext: PlaceUserContext(isSaved: false, savedPlaceId: nil, note: nil, usageSummary: nil),
        editorialContent: PlaceEditorialContent(
            version: 3,
            introduction: introduction,
            highlights: ["西湖十景"],
            recommendedDurationMinutes: nil,
            visitTips: nil,
            bestVisitTime: nil,
            reservationTips: nil,
            notice: nil
        ),
        contentMeta: PlaceContentMeta(
            aiAssisted: true,
            label: "内容由编辑整理，部分段落由 AI 辅助生成",
            verifiedAt: nil,
            nextReviewAt: nil,
            reviewDue: nil
        ),
        media: nil
    )
}

private func previewPlace(_ name: String, category: PlaceCategory, highlight: String?, isSaved: Bool) -> PublishedPlace {
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
        highlight: highlight,
        publishedAt: "2026-08-18 09:30:00",
        isSaved: isSaved,
        cover: nil
    )
}

#Preview("城市页 · 有简介 + 地点流") {
    NavigationStack {
        ExploreCityView(
            seed: previewCitySeed(),
            service: previewCityService(
                places: [
                    previewPlace("雷峰塔", category: .attraction, highlight: "夜色下的湖面与塔影", isSaved: false),
                    previewPlace("楼外楼", category: .restaurant, highlight: nil, isSaved: true),
                    previewPlace("西湖博物馆", category: .attraction, highlight: "免费，周一闭馆", isSaved: false)
                ],
                introduction: "杭州以西湖为中心，山湖与城市贴得很近。城区不大，多数景点可以在一天内串联起来。"
            )
        )
    }
}

#Preview("城市页 · 简介加载失败") {
    NavigationStack {
        ExploreCityView(
            seed: previewCitySeed(),
            service: previewCityService(
                places: [previewPlace("雷峰塔", category: .attraction, highlight: nil, isSaved: false)],
                introFails: true
            )
        )
    }
}

#Preview("城市页 · 地点流为空") {
    NavigationStack {
        ExploreCityView(
            seed: previewCitySeed(),
            service: previewCityService(
                introduction: "内容还在补充中，先看看这座城市的介绍。"
            )
        )
    }
}
