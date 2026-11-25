import SwiftUI
import TracciNetworking

/// 地点半层（规格 §8）：探索的第三层，从城市页地点卡上滑出。
///
/// 详情与收藏写操作由 `ExplorePlaceSheetViewModel` 组合 `PlaceDetailViewModel` 完成，
/// 本文件只管呈现：260pt 沉浸 Hero（三级降级）+ 上移压住 Hero 的白卡 + 底部三格操作栏。
struct ExplorePlaceSheetView: View {
    /// `.sheet(item:)` 的闭包会被 SwiftUI 反复求值，所以 VM 必须落在 `@State`：
    /// 否则每次父层重渲染都会换一个新实例，刚加载的详情会丢（同 `PlaceDetailView` 写法）。
    @State private var viewModel: ExplorePlaceSheetViewModel
    @State private var showingUnsaveConfirm = false
    @State private var addToTripPlace: SavedPlace?
    @State private var currentMediaID: String?

    private let tripProvider: (any SavedPlaceTripProviding)?
    /// 规格 §8.3：无旅程时第一格读「先创建旅程」，打开创建表单——POI **不**预填为目的地。
    private let onCreateTrip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        placeId: String,
        service: any SavedPlaceServicing,
        tripProvider: (any SavedPlaceTripProviding)? = nil,
        onSavedStateChange: @escaping @MainActor (String, Bool) -> Void = { _, _ in },
        onCreateTrip: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: ExplorePlaceSheetViewModel(
            placeId: placeId,
            service: service,
            tripProvider: tripProvider,
            onSavedStateChange: onSavedStateChange
        ))
        self.tripProvider = tripProvider
        self.onCreateTrip = onCreateTrip
    }

    /// 尺寸取自 `designs/explore-v2`（`.place-hero` / `.sheet-card` / `.action-bar`），
    /// 设计系统没有对应 token，集中在这里而不是散落在 body。
    private enum Layout {
        static let heroHeight: CGFloat = 260
        /// 系统拖拽指示器落在这条页底色窄带上，不压在封面上（设计稿 `.grabber` margin 8 + 高 5）。
        static let heroTopPadding: CGFloat = 13
        static let heroBottomScrimHeight: CGFloat = 90
        /// `.b1 { width: calc(100% - 34px) }` + 8pt 间距 ⇒ 下一张正好露出 26pt（`.hero-peek`）。
        static let heroPeekInset: CGFloat = 34
        static let heroBandSpacing: CGFloat = 8
        /// `.hero-peek { border-radius: 8px 0 0 8px }`。
        static let heroPeekCornerRadius: CGFloat = 8
        static let heroDotsTrailing: CGFloat = 14
        static let heroDotsBottom: CGFloat = 62
        static let heroDotSize: CGFloat = 5
        static let heroDotActiveWidth: CGFloat = 14
        static let heroDotGap: CGFloat = 5
        static let heroGlyphPointSize: CGFloat = 54
        /// `.sheet-card { margin: -34px 14px 0 }`。
        static let cardTopOverlap: CGFloat = -34
        static let cardHorizontalMargin: CGFloat = 14
        static let cardTopPadding: CGFloat = 22
        static let cardHorizontalPadding: CGFloat = 18
        static let cardBottomPadding: CGFloat = 20
        static let metaTopPadding: CGFloat = 8
        static let contentMetaTopPadding: CGFloat = 10
        static let actionItemMinHeight: CGFloat = 54
        static let actionIconSize: CGFloat = 22
        static let actionGap: CGFloat = 4
        /// 规格 §8.1：半层 0.94，下拉可关，不做 push 全屏页。
        static let sheetFraction: CGFloat = 0.94
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                contentCard
                    .padding(.top, Layout.cardTopOverlap)
                    .padding(.horizontal, Layout.cardHorizontalMargin)
                    .padding(.bottom, Layout.cardBottomPadding)
            }
        }
        .background(AppColors.pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actionBar }
        .overlay { unsaveConfirmSheet }
        .sheet(item: $addToTripPlace) { place in
            addToTripSheet(for: place)
        }
        .task { await viewModel.load() }
        .tracciToast($viewModel.toast)
        // 规格 §8.1：半层天然覆盖底栏，指示器可见、下拉可关。
        .tracciSheetPresentation(.subSheetFraction(Layout.sheetFraction))
    }

    // MARK: - Hero

    /// 规格 §8.2：Hero 260pt 沉浸，底部 scrim 保证标题可读，白卡上移压住它。
    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            heroSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            heroBottomScrim
                .frame(maxWidth: .infinity)

            // 自己画指示器而不用 `TabView(.page)`：分页容器会接管竖向手势，和外层滚动打架。
            if viewModel.mediaItems.count > 1 {
                heroDots
                    .padding(.trailing, Layout.heroDotsTrailing)
                    .padding(.bottom, Layout.heroDotsBottom)
            }
        }
        .frame(height: Layout.heroHeight)
        .clipped()
        .padding(.top, Layout.heroTopPadding)
    }

    /// 三级降级：照片带 → 坐标地图 → 品类占位（规格 §8.2）。
    @ViewBuilder
    private var heroSurface: some View {
        if viewModel.isLoading {
            // 加载中先给墨色底：等详情回来再决定降级到哪一级，避免品牌渐变闪一下。
            AppColors.textPrimary
                .overlay { AppShimmerOverlay() }
                .accessibilityHidden(true)
        } else if !viewModel.mediaItems.isEmpty {
            heroMediaBand
        } else if let detail = viewModel.detail,
                  let latitude = detail.latitude,
                  let longitude = detail.longitude {
            heroMap(name: detail.name, latitude: latitude, longitude: longitude)
        } else {
            // 规格 §8.2：两者都无 → 品类占位，不假装有照片。
            ExploreCoverFallback(
                scope: .poi,
                category: viewModel.detail?.category ?? .attraction,
                glyphPointSize: Layout.heroGlyphPointSize
            )
        }
    }

    private var heroMediaBand: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Layout.heroBandSpacing) {
                ForEach(viewModel.mediaItems) { media in
                    heroPhoto(media)
                        .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                            length - Layout.heroPeekInset
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentMediaID)
        // 缝隙里露出的是 Hero 墨色底，不是白。
        .background(AppColors.textPrimary)
    }

    /// 规格 §11：授权与过期由服务端过滤，客户端不兜底显示；没有可用 URL 就退回品类占位。
    private func heroPhoto(_ media: PlaceMedia) -> some View {
        // 设计稿 `.hero-band`：对齐位直角，露出的下一张只给左缘 8pt 圆角
        // （`.hero-peek { border-radius: 8px 0 0 8px }`）。
        let isAligned = media.id == resolvedMediaID

        return ZStack {
            AppColors.textPrimary

            if let url = photoURL(media) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            } else {
                ExploreCoverFallback(
                    scope: .poi,
                    category: viewModel.detail?.category ?? .attraction,
                    glyphPointSize: Layout.heroGlyphPointSize
                )
            }
        }
        .frame(height: Layout.heroHeight)
        .clipShape(photoShape(isAligned: isAligned))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photoSpokenLabel(media))
    }

    private func photoShape(isAligned: Bool) -> some Shape {
        if isAligned {
            return AnyShape(Rectangle())
        }
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: Layout.heroPeekCornerRadius,
            bottomLeadingRadius: Layout.heroPeekCornerRadius,
            style: .continuous
        ))
    }

    /// 规格 §8.2 第二级：活的 `Map` 会吃掉滚动手势，所以禁掉它的命中测试，
    /// 由一个铺满的透明按钮承担「点按打开系统地图」。
    private func heroMap(name: String, latitude: Double, longitude: Double) -> some View {
        ZStack {
            PlaceCoordinateMap(name: name, latitude: latitude, longitude: longitude)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Button {
                AppHaptics.lightImpact()
                PlaceMapLauncher.open(name: name, latitude: latitude, longitude: longitude)
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("在地图中打开")
        }
    }

    private var heroBottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: AppColors.pageBackground.opacity(0), location: 0),
                .init(color: AppColors.pageBackground, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Layout.heroBottomScrimHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 设计稿 `.hero-dots`：5pt 圆点，当前项拉成 14pt 胶囊。
    private var heroDots: some View {
        HStack(spacing: Layout.heroDotGap) {
            ForEach(viewModel.mediaItems) { media in
                let isActive = media.id == resolvedMediaID
                Capsule()
                    .fill(Color.white.opacity(isActive ? 1 : 0.45))
                    .frame(
                        width: isActive ? Layout.heroDotActiveWidth : Layout.heroDotSize,
                        height: Layout.heroDotSize
                    )
            }
        }
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: resolvedMediaID)
        .accessibilityHidden(true)
    }

    private var resolvedMediaID: String? {
        currentMediaID ?? viewModel.mediaItems.first?.id
    }

    private func photoURL(_ media: PlaceMedia) -> URL? {
        guard let raw = media.heroURL, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// 服务端给了 `altText` 就用它，没有才退回地点名——不把占位文案念成照片内容。
    private func photoSpokenLabel(_ media: PlaceMedia) -> String {
        if let altText = trimmed(media.altText) { return altText }
        return viewModel.detail?.name ?? ""
    }

    // MARK: - Content card

    /// 规格 §8.2 的白卡：墨色地名 + meta + 内容标签 + 固定顺序正文。elevation 用 `content`（§10）。
    private var contentCard: some View {
        AppElevationCard(
            level: .l1,
            role: .content,
            radius: AppRadius.extraLarge,
            padding: 0
        ) {
            Group {
                if viewModel.isLoading {
                    cardSkeleton
                } else if let detail = viewModel.detail {
                    cardContent(detail)
                } else if let errorMessage = viewModel.errorMessage {
                    cardError(errorMessage)
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .padding(.top, Layout.cardTopPadding)
            .padding(.bottom, Layout.cardBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cardContent(_ detail: PlaceDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 规格 §10：地点名一律墨色，禁止蓝色地名。
            Text(detail.name)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHeading(.h1)

            if let meta = placeMeta(detail) {
                Text(meta)
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.metaTopPadding)
            }

            // 规格 §11：`contentMeta.label` 原文展示，`aiAssisted` 时必须可见，客户端不自己拼文案。
            if let label = trimmed(detail.contentMeta?.label) {
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.contentMetaTopPadding)
            }

            ExplorePlaceEditorialContent(content: detail.editorialContent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 规格 §8.2：`cityName · country · category.displayName`，空项不渲染。
    private func placeMeta(_ detail: PlaceDetail) -> String? {
        let parts = [detail.cityName, detail.country, detail.category.displayName]
            .compactMap { trimmed($0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func cardError(_ message: String) -> some View {
        ErrorStateView(title: "地点详情暂时不可用", message: message, retryTitle: "重试") {
            Task { await viewModel.load() }
        }
    }

    /// 规格 §8.1：加载中给骨架，不给空白。
    private var cardSkeleton: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            AppSkeletonBone(width: 168, height: 22, cornerRadius: 5)
            AppSkeletonBone(width: 132, height: 12, cornerRadius: 4)
            AppSkeletonBone(height: 12, cornerRadius: 4)
            AppSkeletonBone(height: 12, cornerRadius: 4)
            AppSkeletonBone(width: 220, height: 12, cornerRadius: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载地点详情")
    }

    // MARK: - Action bar

    /// 规格 §8.3：`safeAreaInset(edge: .bottom)` 固定三格等宽，图标 + 文字，每项 ≥ 44pt。
    private var actionBar: some View {
        TracciFixedBottomCTA(backgroundColor: AppColors.cardBackground) {
            HStack(spacing: 0) {
                addButton
                bookmarkButton
                // 无坐标时整项隐藏，前两格各占 1/2。
                if viewModel.hasCoordinate {
                    mapButton
                }
            }
        }
    }

    /// 位置 1：有规划中 / 进行中旅程读「加入行程」，否则「先创建旅程」；主色填充，唯一实心主操作。
    private var addButton: some View {
        actionButton(
            icon: "plus.circle.fill",
            title: viewModel.addTitle,
            tint: AppColors.brandPrimary,
            isLoading: viewModel.isPreparingAddToTrip,
            isEnabled: !viewModel.isBusy,
            accessibilityLabel: viewModel.addTitle,
            accessibilityHint: viewModel.hasActiveTrips
                ? "把地点加入某个旅程的某一天"
                : "先创建一趟旅程，再把这里加进去"
        ) {
            Task { await handleAdd() }
        }
    }

    /// 位置 2：未收藏「收藏地点」，已收藏「已收藏」+ 品牌蓝实心（规格 §10 的三处蓝色之一）。
    private var bookmarkButton: some View {
        actionButton(
            icon: viewModel.isSaved ? "bookmark.fill" : "bookmark",
            title: viewModel.isSaved ? "已收藏" : "收藏地点",
            tint: viewModel.isSaved ? AppColors.brandPrimary : AppColors.textSecondary,
            isLoading: viewModel.isSaving,
            isEnabled: !viewModel.isBusy,
            accessibilityLabel: viewModel.isSaved ? "已收藏" : "收藏地点",
            accessibilityHint: viewModel.isSaved ? "再次点击可取消收藏" : "加入我的想去的地点"
        ) {
            toggleSave()
        }
    }

    /// 位置 3：跳系统地图，不是写操作，所以写请求在途时也保持可点。
    private var mapButton: some View {
        actionButton(
            icon: "arrow.up.right.square",
            title: "地图",
            tint: AppColors.textSecondary,
            isLoading: false,
            isEnabled: true,
            accessibilityLabel: "在地图中打开",
            accessibilityHint: nil
        ) {
            openSystemMaps()
        }
    }

    /// `accessibilityHint` 没有吃 `String?` 的重载，所以按有无 hint 分两支，而不是塞空串。
    @ViewBuilder
    private func actionButton(
        icon: String,
        title: String,
        tint: Color,
        isLoading: Bool,
        isEnabled: Bool,
        accessibilityLabel: String,
        accessibilityHint: String?,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            VStack(spacing: Layout.actionGap) {
                if isLoading {
                    AppProgressIndicator(tint: tint, diameter: Layout.actionIconSize)
                } else {
                    Image(systemName: icon)
                        .font(AppFont.system(Layout.actionIconSize, weight: .medium))
                        .foregroundStyle(isEnabled ? tint : AppColors.textDisabled)
                        .frame(
                            width: Layout.actionIconSize,
                            height: Layout.actionIconSize
                        )
                        // 规格 §10.1：收藏反馈 = 图标 scale + opacity 一次，不额外加装饰动画。
                        .id(icon)
                        .transition(.scale(scale: 1.12).combined(with: .opacity))
                }

                Text(title)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(isEnabled ? AppColors.textSecondary : AppColors.textDisabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Layout.actionItemMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
        .disabled(!isEnabled)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: icon)
        .accessibilityLabel(accessibilityLabel)

        if let accessibilityHint {
            button.accessibilityHint(accessibilityHint)
        } else {
            button
        }
    }

    // MARK: - Actions

    /// 规格 §8.3 矩阵：POI + 有旅程 → 选旅程选天；POI + 无旅程 → 轻提示 + 创建表单。
    /// 目的地是否匹配交服务端判（`42243`），客户端只在「有无旅程」这一层分支。
    private func handleAdd() async {
        AppHaptics.lightImpact()

        guard viewModel.hasActiveTrips else {
            viewModel.promptCreateTrip()
            onCreateTrip()
            return
        }

        // 契约 §15.8 要 `savedPlaceId`：未收藏先静默收藏，与城市页 §7.3 同一口径。
        guard let savedPlace = await viewModel.prepareAddToTrip() else { return }
        addToTripPlace = savedPlace
    }

    /// 规格 §7.5 / §8.3：已收藏点按**不直接取消**，走二次确认。
    private func toggleSave() {
        AppHaptics.lightImpact()
        if viewModel.isSaved {
            showingUnsaveConfirm = true
        } else {
            Task { await viewModel.save() }
        }
    }

    private func openSystemMaps() {
        guard let detail = viewModel.detail,
              let latitude = detail.latitude,
              let longitude = detail.longitude else { return }
        AppHaptics.lightImpact()
        PlaceMapLauncher.open(name: detail.name, latitude: latitude, longitude: longitude)
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
            onConfirmAsync: { await viewModel.unsave() }
        )
    }

    @ViewBuilder
    private func addToTripSheet(for place: SavedPlace) -> some View {
        if let tripProvider {
            SavedPlaceAddToTripSheet(
                place: place,
                provider: tripProvider,
                onDismiss: { _ in
                    addToTripPlace = nil
                }
            )
            .tracciSheetPresentation(.subSheetFraction(0.92))
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Previews

/// 半层只看详情接口，其余方法在 Preview 里没有调用方。
private struct ExplorePlaceSheetPreviewService: SavedPlaceServicing {
    var detail: PlaceDetail?
    var fails = false
    var hangs = false

    func placeDetail(placeId: String) async throws -> PlaceDetail {
        if hangs {
            try await Task.sleep(nanoseconds: 600_000_000_000)
        }
        if fails { throw PreviewUnavailable() }
        guard let detail else { throw PreviewUnavailable() }
        return detail
    }

    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace { throw PreviewUnavailable() }
    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> { throw PreviewUnavailable() }
    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace { throw PreviewUnavailable() }
    func delete(savedPlaceId: String) async throws { throw PreviewUnavailable() }
    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> { throw PreviewUnavailable() }

    private struct PreviewUnavailable: Error {}
}

private func previewPlaceDetail(
    media: [PlaceMedia]?,
    latitude: Double?,
    longitude: Double?,
    isSaved: Bool,
    editorialContent: PlaceEditorialContent?
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
        supportedUsages: [.itineraryNode],
        userContext: PlaceUserContext(
            isSaved: isSaved,
            savedPlaceId: isSaved ? "saved-gugong" : nil,
            note: nil,
            usageSummary: nil
        ),
        editorialContent: editorialContent,
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

private func previewMedia(_ seed: String) -> PlaceMedia {
    PlaceMedia(
        id: "media-\(seed)",
        url: "https://picsum.photos/seed/\(seed)/900/600",
        thumbnailUrl: nil,
        previewUrl: nil,
        width: 900,
        height: 600,
        altText: "\(seed) 的照片",
        attribution: nil
    )
}

private func previewEditorialContent() -> PlaceEditorialContent {
    PlaceEditorialContent(
        version: 3,
        introduction: "明清两代的皇宫，沿中轴线展开，前后三殿与内廷六宫连成一片。走完中轴线大约需要三小时，东西六宫则要另算。",
        highlights: ["中轴线上的三大殿", "钟表馆与珍宝馆需单独购票"],
        recommendedDurationMinutes: 180,
        visitTips: ["周一闭馆，法定节假日除外", "从午门进，神武门出"],
        bestVisitTime: "春秋两季，上午光线最好",
        reservationTips: "需提前七天在官方渠道实名预约",
        notice: "院内禁止使用自拍杆与三脚架"
    )
}

private func previewSheet(
    detail: PlaceDetail?,
    fails: Bool = false,
    hangs: Bool = false
) -> ExplorePlaceSheetView {
    ExplorePlaceSheetView(
        placeId: "place-gugong",
        service: ExplorePlaceSheetPreviewService(detail: detail, fails: fails, hangs: hangs)
    )
}

#Preview("地点半层 · 多图 + 全量正文") {
    previewSheet(detail: previewPlaceDetail(
        media: [previewMedia("gugong-a"), previewMedia("gugong-b"), previewMedia("gugong-c")],
        latitude: 39.9163,
        longitude: 116.3972,
        isSaved: false,
        editorialContent: previewEditorialContent()
    ))
}

#Preview("地点半层 · 无图有坐标") {
    previewSheet(detail: previewPlaceDetail(
        media: nil,
        latitude: 39.9163,
        longitude: 116.3972,
        isSaved: true,
        editorialContent: previewEditorialContent()
    ))
}

#Preview("地点半层 · 无图无坐标") {
    previewSheet(detail: previewPlaceDetail(
        media: nil,
        latitude: nil,
        longitude: nil,
        isSaved: false,
        editorialContent: nil
    ))
}

#Preview("地点半层 · 加载中") {
    previewSheet(detail: nil, hangs: true)
}

#Preview("地点半层 · 加载失败") {
    previewSheet(detail: nil, fails: true)
}
