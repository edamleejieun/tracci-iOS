import SwiftUI
import UIKit
import MapKit

struct TripDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let sceneFactory: TripDetailSceneFactory
    let onTripUpdated: (Trip) -> Void
    let onBack: () -> Void
    let shouldHandleInteractivePop: () -> Bool
    let onInteractivePopFinished: () -> Void
    let onOpenMembers: (TripAccessContext?) -> Void
    let onOpenTripSettings: (TripAccessContext?) -> Void
    let onOpenMemory: (String) -> Void
    let onOpenPlaceDetail: (String) -> Void
    /// Demo exit conversion: leave sample and open create-trip flow.
    let onCreateOwnTrip: () -> Void
    let journeyContext: JourneyContext

    @Environment(AuthSession.self) private var authSession
    @State private var viewModel: TripDetailViewModel
    @State private var formRouter = TripDetailFormRouter()
    @State private var scrollY: CGFloat = 0
    @State private var showingShareMenu = false
    @State private var showingInviteSheet = false
    @State private var inviteViewModel: CollaborationViewModel?
    @State private var showingItineraryExportSheet = false
    @State private var showingInsightSheet = false
    @State private var actionToast: String?

    // Day feed state
    @State private var selectedDayIndex: Int
    @State private var heroMode: TripHeroMode = .cover
    @State private var mapExpansion: MapExpansionSnapPoint = .compact
    @State private var dragOffset: CGFloat = 0
    /// 大地图沉浸阶段；与 heroMode 协同，但允许叠层常驻 MKMapView。
    @State private var mapExplorePhase: MapExplorePhase = .dismissed
    /// 0…1 驱动分层转场（地图淡入 / dock 上滑）。
    @State private var mapExploreProgress: CGFloat = 0
    /// 一旦有地图数据即挂载 Surface，避免反复销毁 Metal 层。
    @State private var mapExploreMounted = false
    /// 后台预热：短暂 isMapVisible，不展示 chrome。
    @State private var mapExplorePrewarming = false
    @State private var mapExploreTransitionTask: Task<Void, Never>?
    /// 封面 Hero 在详情根坐标系中的 frame，供地图几何展开。
    @State private var heroFrameInRoot: CGRect = .zero
    @State private var linkedNodeId: String?
    @State private var heroMapViewport: TripHeroMapViewport = .routeOverview
    @State private var heroMapData: TripHeroMapData = .empty
    /// Hero 地图数据范围：总览 Tab 打开地图时为全旅程（按天分色路线），
    /// 其余 Tab / 选中具体天时为单日。
    @State private var heroMapScope: HeroMapScope = .day
    @State private var executionClock = Date()
    @State private var itineraryNodeToDelete: ItineraryNodeItem?
    @State private var showingNodeDeleteConfirm = false
    /// Same-day itinerary reorder session (narrow mode).
    @State private var isNodeReorderMode = false
    @State private var reorderBaselineNodeIds: [String] = []
    @State private var isReorderSubmitting = false
    @State private var showingAbandonReorderConfirm = false
    @State private var pendingNavigationAfterAbandon: PendingReorderNavigation?
    @State private var dayFeedSlideOffset: CGFloat = 0
    @State private var dayFeedOpacity: Double = 1
    /// Soft depth settle after day slide (P2 parallax layer; not a second content copy).
    @State private var dayFeedDepthScale: CGFloat = 1
    @State private var itineraryScrollToNodeId: String?
    // P2 creation milestone state
    @State private var newlyCreatedNodeId: String?
    /// Selected workspace surface shared by the explicit Tab buttons and programmatic navigation.
    @State private var selectedWorkspaceTab: TripDetailTab? = .itinerary
    @State private var createdFromEmptyDay = false
    @State private var creationHaloOpacity: Double = 0
    @State private var fabModel = TripDetailFABModel()
    @State private var safeAreaTop = SafeAreaMetrics.top
    @State private var hasCompletedInitialAppearance = false
    /// Soft entrance when the detail shell appears (V5 memory moment).
    @State private var detailContentRevealed = false
    /// Demo-only full-screen memory story (hydrated from Bundle summary).
    @State private var demoStoryViewModel: MemoryStoryViewModel?
    @State private var demoStoryTrip: Trip?
    @State private var showingDemoMemoryStory = false
    @State private var showingDemoActivityLog = false
    @State private var showingDemoMembers = false
    @State private var showingSettlement = false
    @State private var isSwitchingDemoScene = false
    /// Local selection so the stage rail updates immediately while Bundle scene hydrates.
    @State private var demoSceneSelectionState: DemoJourneySceneKind = .ongoing
    @State private var demoFeedDimmed = false
    @State private var showDemoSoftCoach = false

    init(
        trip: Trip,
        sceneFactory: TripDetailSceneFactory,
        initialTab: TripDetailTab = .itinerary,
        onTripUpdated: @escaping (Trip) -> Void,
        onBack: @escaping () -> Void = {},
        shouldHandleInteractivePop: @escaping () -> Bool = { true },
        onInteractivePopFinished: @escaping () -> Void = {},
        onOpenMembers: @escaping (TripAccessContext?) -> Void = { _ in },
        onOpenTripSettings: @escaping (TripAccessContext?) -> Void = { _ in },
        onOpenMemory: @escaping (String) -> Void = { _ in },
        onOpenPlaceDetail: @escaping (String) -> Void = { _ in },
        onCreateOwnTrip: @escaping () -> Void = {},
        journeyContext: JourneyContext? = nil
    ) {
        let resolvedContext = journeyContext ?? .live(tripID: trip.id)
        self.sceneFactory = sceneFactory
        self.onTripUpdated = onTripUpdated
        self.onBack = onBack
        self.shouldHandleInteractivePop = shouldHandleInteractivePop
        self.onInteractivePopFinished = onInteractivePopFinished
        self.onOpenMembers = onOpenMembers
        self.onOpenTripSettings = onOpenTripSettings
        self.onOpenMemory = onOpenMemory
        self.onOpenPlaceDetail = onOpenPlaceDetail
        self.onCreateOwnTrip = onCreateOwnTrip
        self.journeyContext = resolvedContext
        _selectedDayIndex = State(initialValue: Self.computeInitialDayIndex(trip: trip))
        _selectedWorkspaceTab = State(initialValue: initialTab as TripDetailTab?)
        _heroMapScope = State(
            initialValue: initialTab == .overview && (trip.totalDays ?? 1) > 1 ? .fullTrip : .day
        )
        if case let .demo(_, scene) = resolvedContext {
            _demoSceneSelectionState = State(initialValue: scene)
        }
        _showDemoSoftCoach = State(
            initialValue: resolvedContext.isDemo && !DemoJourneyPreferences.hasDismissedSoftCoach
        )

        _viewModel = State(
            initialValue: sceneFactory.makeViewModel(
                trip: trip,
                initialTab: initialTab,
                journeyContext: resolvedContext
            )
        )
    }

    private var isDemo: Bool { journeyContext.isDemo }

    private var nodeFormMode: ItineraryNodeFormMode? {
        get { formRouter.nodeFormMode }
        nonmutating set { formRouter.nodeFormMode = newValue }
    }

    private var expenseFormMode: ExpenseFormMode? {
        get { formRouter.expenseFormMode }
        nonmutating set { formRouter.expenseFormMode = newValue }
    }

    private var journalFormMode: JournalFormMode? {
        get { formRouter.journalFormMode }
        nonmutating set { formRouter.journalFormMode = newValue }
    }

    private var journalFormInitialSection: JournalFormInitialSection {
        get { formRouter.journalInitialSection }
        nonmutating set { formRouter.journalInitialSection = newValue }
    }

    private var nodeFormBinding: Binding<ItineraryNodeFormMode?> {
        Binding(
            get: { formRouter.nodeFormMode },
            set: { formRouter.nodeFormMode = $0 }
        )
    }

    private var expenseFormBinding: Binding<ExpenseFormMode?> {
        Binding(
            get: { formRouter.expenseFormMode },
            set: { formRouter.expenseFormMode = $0 }
        )
    }

    private var journalFormBinding: Binding<JournalFormMode?> {
        Binding(
            get: { formRouter.journalFormMode },
            set: { formRouter.journalFormMode = $0 }
        )
    }

    /// 角色可写 + 旅程未结束：允许新增节点/日志/开支
    private var contentAddAllowed: Bool {
        guard !isDemo else { return false }
        return TripEditPolicy.canEditContent(viewModel.currentUserAccess)
            && TripEditPolicy.contentAddOutcome(trip: viewModel.trip).isAllowed
    }

    /// 角色可写 + 旅程未结束：允许编辑/删除已有内容（节点备注例外，见 noteOnly 路径）
    private var contentEditAllowed: Bool {
        guard !isDemo else { return false }
        return TripEditPolicy.canEditContent(viewModel.currentUserAccess)
            && TripEditPolicy.contentEditOutcome(trip: viewModel.trip).isAllowed
    }

    // MARK: - Surfaces (browse / mapExplore)

    /// 正常详情：封面 Hero + Day/Tab + 竖向 feed。
    private var browseScrollSurface: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    scrollOffsetReader

                    heroHeader
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TripHeroFramePreferenceKey.self,
                                    value: proxy.frame(in: .named(TripMapExploreCoordinateSpace.root))
                                )
                            }
                        }

                    if let errorMessage = viewModel.errorMessage {
                        detailErrorBanner(message: errorMessage)
                            .padding(.horizontal, TripDetailLayout.pageInset)
                            .padding(.top, AppSpacing.cardSmall)
                    }

                    Section {
                        dayFeedSectionContent
                            .padding(.top, TripDetailLayout.feedTopPadding)
                            .padding(.bottom, bottomContentPadding)
                    } header: {
                        TripDayWorkspaceHeader(
                            selectedTab: tabSelectionBinding,
                            selectedDayIndex: daySelectionBinding,
                            totalDays: totalDays,
                            tripStartDate: viewModel.trip.startDate,
                            pinnedProgress: controlBandPinnedProgress,
                            navOverlayProgress: navMaterialProgress,
                            safeAreaTop: safeAreaTop,
                            hidesTabBar: false,
                            insightShowsSoftDot: viewModel.insightViewModel.entryShowsSoftDot,
                            stageSeamColor: stageAtmosphere.heroSeamColor,
                            onOpenInsight: {
                                showingInsightSheet = true
                            }
                        )
                    }
                }
            }
            .coordinateSpace(name: "TripDetailScroll")
            .onPreferenceChange(TripDetailScrollOffsetKey.self) { scrollY = $0 }
            .tracciImmersiveHeroScroll()
            .onChange(of: scrollY) { oldValue, newValue in
                let scrollDelta = newValue - oldValue
                if abs(scrollDelta) > 2.0 {
                    fabModel.noteScrolling(reduceMotion: reduceMotion)
                }
            }
            .onChange(of: itineraryScrollToNodeId) { _, nodeId in
                guard let nodeId else { return }
                let scrollToNode = {
                    scrollProxy.scrollTo(
                        TripUnifiedCreekFeed.nodeScrollAnchorID(for: nodeId),
                        anchor: .center
                    )
                }
                if reduceMotion {
                    scrollToNode()
                } else {
                    withAnimation(AppMotion.normal) {
                        scrollToNode()
                    }
                }
            }
        }
    }

    /// 大地图沉浸：全幅地图 + 轻量 Day Tab + 横向行程卡（常驻叠层）。
    private var mapExploreSurface: some View {
        let isFullTrip = heroMapData.isFullTripOverview
        return TripMapExploreSurface(
            trip: viewModel.trip,
            routeProvider: sceneFactory.routeProvider,
            heroMapData: heroMapData,
            dayLabel: isFullTrip ? "全程" : selectedDayLabel,
            totalDays: totalDays,
            tripStartDate: viewModel.trip.startDate,
            carouselNodes: carouselNodes,
            dayDate: currentDayDate,
            autoHighlightNodeId: isFullTrip ? nil : autoHighlightedRouteNodeId,
            safeAreaTop: safeAreaTop,
            sourceHeroFrame: heroFrameInRoot,
            presentationProgress: mapExploreProgress,
            isInteractive: mapExplorePhase.isInteractive,
            isMapVisible: mapExplorePhase.isMapSurfaceActive || mapExplorePrewarming,
            suppressCameraAnimation: mapExplorePhase.isTransitioning || mapExplorePrewarming,
            fullTripSummaryText: fullTripSummaryText,
            selectedDayIndex: $selectedDayIndex,
            linkedNodeId: $linkedNodeId,
            mapViewport: $heroMapViewport,
            heroMode: heroModeBinding,
            onSelectNode: { id in
                // 横滑卡片 → marker 聚焦；镜头短动画与 Day Tab 同节奏。
                handleLinkedNode(id: id, shouldScroll: false)
            },
            onNavigateToNode: openNavigation,
            onNavigateAnnotation: openHeroNavigation,
            onSelectDay: { dayIndex in
                let isSameDay = dayIndex == selectedDayIndex
                guard !isSameDay || heroMapScope != .day else { return }
                linkedNodeId = nil
                heroMapViewport = .routeOverview
                heroMapScope = .day
                if isSameDay {
                    // 全程态点当前天回退单日：保持转场语言一致，避免硬切。
                    withAnimation(reduceMotion ? nil : AppMotion.mapExploreDayCamera) {
                        refreshHeroMapData()
                    }
                } else {
                    withAnimation(reduceMotion ? nil : AppMotion.mapExploreDayCamera) {
                        selectedDayIndex = dayIndex
                    }
                    refreshHeroMapData()
                }
            },
            onSelectFullTrip: {
                guard heroMapScope != .fullTrip else { return }
                AppHaptics.selection()
                linkedNodeId = nil
                heroMapViewport = .routeOverview
                heroMapScope = .fullTrip
                refreshHeroMapData()
            },
            onDismiss: dismissMapExplore
        )
    }

    // MARK: - Map explore presentation

    private func presentMapExplore() {
        // 总览打开地图先切到全旅程数据再判断可用性，
        // 避免「选中天无节点」挡住「全程有节点」的地图入口。
        syncHeroMapScopeWithTab()
        guard heroMapData.isMapAvailable else { return }
        guard mapExplorePhase == .dismissed || mapExplorePhase == .dismissing else {
            // 已在呈现/已呈现：仅对齐 mode。
            heroMode = .map
            return
        }

        mapExploreTransitionTask?.cancel()
        AppHaptics.selection()
        ensureMapExploreMounted()
        heroMode = .map
        mapExplorePhase = .presenting
        linkedNodeId = nil
        heroMapViewport = .routeOverview

        // 等 Surface 挂入后再开动画；首帧先把 progress 置到极小非 0，立刻盖住 Hero 区域，减少「空一帧」。
        mapExploreTransitionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, mapExplorePhase == .presenting else { return }

            // 无动画点亮 clip 起点（贴在 Hero 上），底层封面仍清晰可见。
            mapExploreProgress = 0.02

            if reduceMotion {
                withAnimation(AppMotion.mapExploreReduced) {
                    mapExploreProgress = 1
                }
                mapExplorePhase = .presented
                return
            }

            // 下一帧再播展开，给 MKMapView 一次 layout。
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled, mapExplorePhase == .presenting else { return }

            withAnimation(AppMotion.mapExploreEnter) {
                mapExploreProgress = 1
            }
            let ns = UInt64(AppMotion.mapExploreEnterDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled, mapExplorePhase == .presenting else { return }
            mapExplorePhase = .presented
        }
    }

    private func dismissMapExplore() {
        guard mapExplorePhase == .presented
                || mapExplorePhase == .presenting
                || (heroMode == .map && mapExploreProgress > 0.01)
        else {
            heroMode = .cover
            return
        }

        mapExploreTransitionTask?.cancel()
        AppHaptics.selection()
        mapExplorePhase = .dismissing
        linkedNodeId = nil
        heroMapViewport = .routeOverview
        // 立刻切回 cover，toggle 与 browse chrome 状态同步。
        heroMode = .cover

        if reduceMotion {
            withAnimation(AppMotion.mapExploreReduced) {
                mapExploreProgress = 0
            }
            finishMapExploreDismiss()
            return
        }

        withAnimation(AppMotion.mapExploreExit) {
            mapExploreProgress = 0
        }
        mapExploreTransitionTask = Task { @MainActor in
            let ns = UInt64(AppMotion.mapExploreExitDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled, mapExplorePhase == .dismissing else { return }
            finishMapExploreDismiss()
        }
    }

    private func finishMapExploreDismiss() {
        mapExplorePhase = .dismissed
        mapExploreProgress = 0
        mapExpansion = .compact
        dragOffset = 0
        mapExplorePrewarming = false
    }

    /// 首次点开地图后再挂载 Surface。进详情不做 Metal 预热，避免 push 转场期 SIGABRT。
    private func ensureMapExploreMounted() {
        guard heroMapData.isMapAvailable else { return }
        mapExploreMounted = true
        mapExplorePrewarming = false
    }

    private var heroHeader: some View {
        VStack(spacing: 0) {
            TripDetailHeader(
                trip: viewModel.trip,
                routeProvider: sceneFactory.routeProvider,
                destinationText: TripPresentation.destinationText(for: viewModel.trip),
                dateRangeText: TripPresentation.dateRangeText(for: viewModel.trip),
                totalDaysText: TripPresentation.totalDaysText(for: viewModel.trip),
                safeAreaTop: safeAreaTop,
                onBack: handleBackWhileMaybeReordering,
                heroMode: browseHeroModeBinding,
                heroMapData: heroMapData,
                focusedNodeId: $linkedNodeId,
                mapViewport: $heroMapViewport,
                dayLabel: selectedDayLabel,
                mapExpansion: $mapExpansion,
                dragOffset: $dragOffset,
                currentDayText: TripPresentation.currentDayText(for: viewModel.trip),
                pullOffset: max(0, scrollY),
                onMembers: {
                    if isDemo {
                        AppHaptics.lightImpact()
                        showingDemoMembers = true
                    } else {
                        onOpenMembers(viewModel.currentUserAccess)
                    }
                },
                onShare: isDemo ? nil : { showingShareMenu = true },
                onSettings: isDemo ? nil : { onOpenTripSettings(viewModel.currentUserAccess) },
                canUpdateTrip: isDemo ? false : TripEditPolicy.canUpdateTrip(viewModel.currentUserAccess),
                members: viewModel.members,
                atmosphereStyle: stageAtmosphere,
                autoHighlightNodeId: autoHighlightedRouteNodeId,
                onSelectNode: handleHeroMapNodeSelected,
                onNavigateToNode: openHeroNavigation
            )

            if isDemo {
                demoReadOnlyBanner
                    .padding(.horizontal, TripDetailLayout.pageInset)
                    .padding(.top, AppSpacing.sm)
            }
        }
    }

    /// Utility chrome under Hero: identity + stage rail + activity entry.
    /// Kept L0 so it does not compete with the immersive cover.
    private var demoReadOnlyBanner: some View {
        TripDetailDemoBanner(
            isSwitchingScene: isSwitchingDemoScene,
            sceneSelection: demoSceneSelection,
            showsSoftCoach: showDemoSoftCoach,
            reduceMotion: reduceMotion,
            onCreateOwnTrip: onCreateOwnTrip,
            onOpenActivity: { showingDemoActivityLog = true },
            onDismissSoftCoach: dismissDemoSoftCoach
        )
    }

    private func dismissDemoSoftCoach() {
        AppHaptics.lightImpact()
        DemoJourneyPreferences.hasDismissedSoftCoach = true
        withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
            showDemoSoftCoach = false
        }
    }

    private var demoSceneSelection: Binding<DemoJourneySceneKind> {
        Binding(
            get: { demoSceneSelectionState },
            set: { newKind in
                guard newKind != demoSceneSelectionState else { return }
                demoSceneSelectionState = newKind
                Task { await switchDemoScene(to: newKind) }
            }
        )
    }

    @MainActor
    private func switchDemoScene(to kind: DemoJourneySceneKind) async {
        guard isDemo, !isSwitchingDemoScene else { return }
        isSwitchingDemoScene = true
        withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
            demoFeedDimmed = true
        }

        let ok = await viewModel.switchDemoScene(to: kind)
        if ok {
            selectedDayIndex = viewModel.itineraryViewModel.selectedDayIndex
            refreshHeroMapData()
            demoSceneSelectionState = kind
        } else {
            demoSceneSelectionState = viewModel.demoSceneKind ?? .ongoing
            showActionToast(DemoReadOnlyCopy.toast, feedback: .light)
        }

        isSwitchingDemoScene = false
        withAnimation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion)) {
            demoFeedDimmed = false
        }
    }

    /// 封面 Hero 上的模式切换：点地图只进入沉浸 Surface，不在 Hero 内嵌第二张地图。
    private var browseHeroModeBinding: Binding<TripHeroMode> {
        Binding(
            get: { .cover },
            set: { newValue in
                guard !isNodeReorderMode else { return }
                if newValue == .map {
                    presentMapExplore()
                }
            }
        )
    }

    private enum PendingReorderNavigation: Equatable {
        case day(Int)
        case tab(TripDetailTab)
        case back
    }

    /// Hero 地图数据范围。
    private enum HeroMapScope: Equatable {
        /// 全旅程总览：所有天的节点与按天路线段。
        case fullTrip
        /// 单日：当前选中天。
        case day
    }

    private var isReorderDirty: Bool {
        guard isNodeReorderMode else { return false }
        let current = viewModel.itineraryViewModel.groupedNodes
            .first { $0.dayIndex == selectedDayIndex }?
            .nodes.map(\.id) ?? []
        return current != reorderBaselineNodeIds
    }

    private var heroModeBinding: Binding<TripHeroMode> {
        Binding(
            get: { isNodeReorderMode ? .cover : heroMode },
            set: { newValue in
                guard !isNodeReorderMode else { return }
                switch newValue {
                case .map:
                    presentMapExplore()
                case .cover:
                    dismissMapExplore()
                }
            }
        )
    }

    /// browse 可交互：地图未展开或已完全收起。
    private var isBrowseInteractive: Bool {
        mapExplorePhase == .dismissed || mapExploreProgress < 0.12
    }

    /// 大地图沉浸态 UI（含转场）。
    private var isMapExploreChromeVisible: Bool {
        mapExplorePhase.isMapSurfaceActive || mapExploreProgress > 0.01
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Browse 始终在底层且保持不透明：地图以裁剪展开盖在上面。
            // 切勿在转场中把 browse 淡到接近 0，否则 clip 外区域会透出黑底 → 黑屏。
            browseScrollSurface
                .allowsHitTesting(isBrowseInteractive)

            // 仅用户进入过大地图后挂载；禁止进详情就创建 MKMapView（导航转场 + Metal 易 SIGABRT）。
            if mapExploreMounted {
                mapExploreSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .zIndex(2)
            }

            if isBrowseInteractive {
                collapsedNavigationBar(safeAreaTop: safeAreaTop)
            }

            // FAB 仅 browse 且非 Demo：示例只读时隐藏写入口，避免半透明禁用态误导。
            if isBrowseInteractive, selectedWorkspaceTab != .overview, !isDemo {
                TripDetailFABChrome(
                    model: fabModel,
                    selectedDayIndex: selectedDayIndex,
                    selectedDayHasContent: selectedDayHasContent,
                    canEdit: contentAddAllowed && !isNodeReorderMode,
                    safeAreaTop: safeAreaTop,
                    onAddNode: {
                        guard contentAddAllowed else { return }
                        createdFromEmptyDay = isSelectedDayItineraryEmpty
                        nodeFormMode = .create(defaultDayIndex: selectedDayIndex)
                    },
                    onAddJournal: {
                        guard contentAddAllowed else { return }
                        journalFormInitialSection = .content
                        journalFormMode = .create(defaultDate: dateForSelectedDay)
                    },
                    onAddPhotoJournal: {
                        guard contentAddAllowed else { return }
                        journalFormInitialSection = .photos
                        journalFormMode = .create(defaultDate: dateForSelectedDay)
                    },
                    onAddExpense: {
                        guard contentAddAllowed else { return }
                        expenseFormMode = .create(defaultDate: dateForSelectedDay, itineraryLink: nil)
                    }
                )
            }

        }
        .coordinateSpace(name: TripMapExploreCoordinateSpace.root)
        .onPreferenceChange(TripHeroFramePreferenceKey.self) { frame in
            heroFrameInRoot = frame
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .tracciInteractivePopGesture(
            shouldHandlePop: {
                if isMapExploreChromeVisible {
                    dismissMapExplore()
                    return false
                }
                if isNodeReorderMode, isReorderDirty {
                    pendingNavigationAfterAbandon = .back
                    showingAbandonReorderConfirm = true
                    return false
                }
                if isNodeReorderMode {
                    exitNodeReorderMode(restoringBaseline: false)
                }
                return shouldHandleInteractivePop()
            },
            onPopFinished: onInteractivePopFinished
        )
        .refreshable {
            await viewModel.refreshAll()
        }
        .task {
            viewModel.insightViewModel.setUserScope(authSession.currentUser?.id)
            await viewModel.refreshAll()
            if isDemo {
                // Align day rail with Demo reference day after hydrate.
                selectedDayIndex = viewModel.itineraryViewModel.selectedDayIndex
            }
        }
        .task {
            await viewModel.loadMembers()
            await viewModel.expenseViewModel.loadCustomCategories()
        }
        .task {
            // Live trips tick wall clock; Demo freezes at referenceDate for stable “进行中”展示.
            guard !isDemo else { return }
            await runExecutionClock()
        }
        .opacity(detailContentRevealed ? 1 : 0)
        .scaleEffect(
            reduceMotion || detailContentRevealed ? 1 : AppMotion.detailEnterScale,
            anchor: .top
        )
        .onChange(of: selectedDayIndex) { _, _ in
            refreshHeroMapData()
            linkedNodeId = nil
            heroMapViewport = .routeOverview
        }
        .onChange(of: viewModel.itineraryViewModel.groupedNodes) { _, _ in
            refreshHeroMapData()
        }
        .onChange(of: heroMapData.isMapAvailable) { _, available in
            guard !available else { return }
            if mapExplorePhase == .presented || mapExplorePhase == .presenting {
                // 呈现中数据变空（如选了无坐标的天）：走正常收起转场，避免硬切。
                dismissMapExplore()
            } else if mapExplorePhase.isMapSurfaceActive || heroMode == .map || mapExploreMounted {
                mapExploreTransitionTask?.cancel()
                mapExploreProgress = 0
                mapExplorePhase = .dismissed
                mapExplorePrewarming = false
                mapExploreMounted = false
                heroMode = .cover
            }
        }
        .onChange(of: viewModel.selectedTab) { _, newTab in
            guard selectedWorkspaceTab != newTab else { return }
            withAnimation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion)) {
                selectedWorkspaceTab = newTab as TripDetailTab?
            }
        }
        .onChange(of: selectedWorkspaceTab) { _, _ in
            syncHeroMapScopeWithTab()
        }
        .onAppear {
            refreshSafeAreaTop()
            refreshHeroMapData()
            if hasCompletedInitialAppearance {
                Task {
                    await viewModel.loadTripDetail()
                    // Demo is not a real trip — never write it back into home list.
                    if !isDemo {
                        onTripUpdated(viewModel.trip)
                    }
                }
            } else {
                hasCompletedInitialAppearance = true
            }
            fabModel.revealAfterTransition(reduceMotion: reduceMotion)
            if !detailContentRevealed {
                withAnimation(AppMotion.animation(AppMotion.detailEnter, reduceMotion: reduceMotion)) {
                    detailContentRevealed = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TripAccessUpdate.notification)) { notification in
            guard TripAccessUpdate.tripId(from: notification) == viewModel.trip.id,
                  let access = TripAccessUpdate.access(from: notification)
            else { return }
            viewModel.applyAccess(access)
        }
        .onDisappear {
            mapExploreTransitionTask?.cancel()
            fabModel.hideForNavigationPop()
        }
        .tracciAtmosphere(isMapExploreChromeVisible ? .none : stageAtmosphere)
        .overlay {
            if isBrowseInteractive {
                AppColors.brandPrimary
                    .opacity(0.04 * creationHaloOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .background {
            NavigationLifecycleReporter(
                onReappear: {
                    refreshSafeAreaTop()
                    fabModel.revealAfterTransition(reduceMotion: reduceMotion)
                },
                onPopCompleted: {
                    fabModel.hideForNavigationPop()
                },
                onPopFinished: {
                    onBack()
                }
            )
        }
        .tracciReadsSafeAreaTop($safeAreaTop)
        .tracciBottomSheet(
            isPresented: $showingShareMenu,
            height: TracciDialogMetrics.tripShareSheetHeight(activeMemberCount: viewModel.members.filter(\.isActive).count)
        ) {
            shareMenuSheet
        }
        .sheet(item: nodeFormBinding) { mode in
            switch mode {
            case let .create(defaultDayIndex):
                ItineraryNodeCreateSheet(
                    defaultDayIndex: defaultDayIndex,
                    viewModel: viewModel.itineraryViewModel,
                    onSuccess: handleNodeFormSuccess,
                    onCancel: { nodeFormMode = nil }
                )
                .tracciTaskSheet()
            case .edit, .editNote:
                ItineraryNodeEditView(
                    mode: mode,
                    itinerary: viewModel.itineraryViewModel,
                    onUpdated: handleNodeFieldUpdated,
                    onClose: { nodeFormMode = nil }
                )
                .tracciFormSheet()
            }
        }
        .sheet(item: expenseFormBinding) { mode in
            NavigationStack {
                ExpenseFormView(
                    expense: mode.existingExpense,
                    duplicate: mode.duplicateExpense,
                    defaultDate: mode.defaultDate,
                    tripId: viewModel.trip.id,
                    tripStartDate: viewModel.trip.startDate,
                    tripEndDate: viewModel.trip.endDate,
                    baseCurrency: viewModel.trip.baseCurrency ?? "CNY",
                    isSubmitting: viewModel.expenseViewModel.isSubmitting,
                    submitError: viewModel.expenseViewModel.submitError,
                    members: viewModel.members,
                    currentUserId: authSession.currentUser?.id,
                    itineraryOptions: ExpenseItineraryLink.options(from: viewModel.itineraryViewModel.days),
                    customCategories: viewModel.expenseViewModel.customCategories,
                    categoryError: viewModel.expenseViewModel.categoryErrorMessage,
                    onAddCategory: { name in
                        guard let created = await viewModel.expenseViewModel.addCustomCategory(name: name) else {
                            return nil
                        }
                        await refreshTripDetailAfterContentMutation()
                        return created
                    },
                    onDeleteCategory: { categoryId in
                        let success = await viewModel.expenseViewModel.removeCustomCategory(categoryId: categoryId)
                        if success { await refreshTripDetailAfterContentMutation() }
                        return success
                    },
                    initialLink: mode.itineraryLink
                ) { request in
                    if isDemo {
                        showActionToast(DemoReadOnlyCopy.toast, feedback: .light)
                        return false
                    }
                    switch mode {
                    case .create, .duplicate:
                        let success = await viewModel.expenseViewModel.createExpense(request)
                        if success {
                            await refreshTripDetailAfterContentMutation()
                        }
                        return success
                    case .edit(let expense):
                        let updateRequest = UpdateExpenseRequest(
                            amountInput: request.amountInput,
                            currency: request.currency,
                            category: request.category,
                            note: request.note,
                            spentAt: request.spentAt,
                            expenseScope: request.expenseScope,
                            payerMemberId: request.payerMemberId,
                            participantMemberIds: request.participantMemberIds,
                            splitMethod: request.splitMethod,
                            linkedNodeId: request.linkedNodeId ?? "",
                            linkedStayGroupId: request.linkedStayGroupId ?? ""
                        )
                        let success = await viewModel.expenseViewModel.updateExpense(expenseId: expense.id, request: updateRequest)
                        if success {
                            await refreshTripDetailAfterContentMutation()
                        }
                        return success
                    }
                }
            }
        }
        .sheet(item: journalFormBinding) { mode in
            NavigationStack {
                sceneFactory.makeJournalForm(
                    mode: mode,
                    tripId: viewModel.trip.id,
                    searchContext: viewModel.journalViewModel.placeSearchContext,
                    defaultDate: mode.defaultDate,
                    initialSection: journalFormInitialSection,
                    dayWeather: journalFormWeatherItem,
                    onToggleFeaturedPhoto: { photo in
                        let succeeded = await viewModel.journalViewModel.setPhotoFeatured(
                            photoId: photo.id,
                            isCurrentlyFeatured: photo.userFeatured
                        )
                        return succeeded ? nil : viewModel.journalViewModel.errorMessage
                    },
                    onSave: { formState in
                        if isDemo {
                            return DemoReadOnlyCopy.toast
                        }
                        switch mode {
                        case .create:
                            let success = await viewModel.journalViewModel.createEntry(form: formState)
                            if success {
                                await refreshTripDetailAfterContentMutation()
                                selectDayMatchingJournal(formState)
                                return nil
                            }
                            return viewModel.journalViewModel.errorMessage
                        case .edit(let entry):
                            let success = await viewModel.journalViewModel.updateEntry(entry, form: formState)
                            if success {
                                await refreshTripDetailAfterContentMutation()
                                return nil
                            }
                            return viewModel.journalViewModel.errorMessage
                        }
                    },
                    onCancel: {
                        journalFormMode = nil
                    }
                )
            }
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: $showingNodeDeleteConfirm,
                title: "确定删除这个行程节点吗？",
                message: "删除后无法恢复，需要重新添加。",
                confirmTitle: "删除",
                onConfirm: {
                    guard let node = itineraryNodeToDelete else { return }
                    Task {
                        let success = await viewModel.itineraryViewModel.deleteNode(node)
                        if success {
                            await refreshTripDetailAfterContentMutation()
                            showActionToast("行程节点已删除", feedback: .success)
                        } else {
                            showActionToast(viewModel.itineraryViewModel.errorMessage ?? "删除失败，请稍后重试", feedback: .error)
                        }
                        itineraryNodeToDelete = nil
                    }
                },
                onCancel: {
                    itineraryNodeToDelete = nil
                }
            )
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: $showingAbandonReorderConfirm,
                title: "放弃本次调整？",
                message: "尚未保存的排序会恢复为调整前的顺序。",
                confirmTitle: "放弃",
                onConfirm: {
                    discardReorderAndResumePendingNavigation()
                },
                onCancel: {
                    pendingNavigationAfterAbandon = nil
                }
            )
        }
        .onChange(of: showingInviteSheet) { _, isShowing in
            if !isShowing {
                inviteViewModel = nil
            }
        }
        .tracciBottomSheet(
            isPresented: $showingInviteSheet,
            height: TracciDialogMetrics.invitationSheetHeight(
                state: inviteViewModel?.invitationSheetState ?? .create,
                errorMessage: inviteViewModel?.invitationError,
                dynamicTypeSize: dynamicTypeSize
            ),
            showDragBar: false
        ) {
            if let inviteViewModel {
                CreateInvitationView(
                    tripTitle: viewModel.trip.title,
                    viewModel: inviteViewModel,
                    onClose: { showingInviteSheet = false }
                )
            }
        }
        .sheet(isPresented: $showingItineraryExportSheet) {
            sceneFactory.makeItineraryExport(
                tripId: viewModel.trip.id,
                tripTitle: viewModel.trip.title,
                dateRangeText: TripPresentation.dateRangeText(for: viewModel.trip),
                onToast: { message, isSuccess in
                    showActionToast(
                        message,
                        feedback: isSuccess ? .success : .error,
                        playHaptic: !isSuccess
                    )
                }
            )
            .tracciNavigationFormSheet()
        }
        .sheet(isPresented: $showingInsightSheet) {
            insightSheet
        }
        .fullScreenCover(
            isPresented: $showingDemoMemoryStory,
            onDismiss: clearDemoMemoryStory
        ) {
            if let storyVM = demoStoryViewModel, let trip = demoStoryTrip {
                MemoryStoryContainerView(
                    trip: trip,
                    dateRangeText: TripPresentation.dateRangeText(for: trip),
                    viewModel: storyVM,
                    onClose: { showingDemoMemoryStory = false },
                    onSaveToPhotoLibrary: {
                        showActionToast(DemoReadOnlyCopy.exportUnavailable, feedback: .light)
                    },
                    onShareFailed: { message in
                        showActionToast(message, feedback: .light)
                    },
                    allowsExportActions: false
                )
            }
        }
        .sheet(isPresented: $showingDemoActivityLog) {
            NavigationStack {
                sceneFactory.makeActivityLog(
                    tripId: viewModel.trip.id,
                    demoLogs: viewModel.demoActivityLogs
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showingDemoActivityLog = false }
                            .font(AppTypography.buttonTitle)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDemoMembers) {
            NavigationStack {
                sceneFactory.makeMembers(
                    tripId: viewModel.trip.id,
                    tripTitle: viewModel.trip.title,
                    currentUserId: authSession.currentUser?.id,
                    currentUserAccess: viewModel.currentUserAccess,
                    demoMembers: viewModel.demoMembers
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showingDemoMembers = false }
                            .font(AppTypography.buttonTitle)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showingSettlement) {
            sceneFactory.makeSettlement(
                tripId: viewModel.trip.id,
                currentUserMemberId: viewModel.members.first(where: { $0.userId == authSession.currentUser?.id })?.id,
                demoSettlement: isDemo ? viewModel.demoSettlement : nil
            )
        }
        .overlay(alignment: .bottom) {
            if let actionToast {
                actionToastView(actionToast)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(AppMotion.animation(AppMotion.enter, reduceMotion: reduceMotion), value: viewModel.selectedTab)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: showingShareMenu)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: actionToast)
    }

    private func clearDemoMemoryStory() {
        demoStoryViewModel = nil
        demoStoryTrip = nil
    }

    private func actionToastView(_ message: String) -> some View {
        AppGlassSurface(radius: AppRadius.pill, padding: 0) {
            Text(message)
                .font(TripDetailTypography.toast)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, AppSpacing.cozy)
        }
            .padding(.bottom, max(28, SafeAreaMetrics.bottom + 16))
    }

    private var shareMenuSheet: some View {
        TripShareSheet(
            tripTitle: viewModel.trip.title,
            members: viewModel.members,
            onCopyLink: {
                copyInvitationLink()
            },
            onInviteFriends: {
                guard !isDemo else {
                    showActionToast(DemoReadOnlyCopy.inviteUnavailable, feedback: .light)
                    return
                }
                AppHaptics.lightImpact()
                inviteViewModel = makeInviteViewModel()
                showingShareMenu = false
                showingInviteSheet = true
            },
            onExportLongImage: {
                guard !isDemo else {
                    showActionToast(DemoReadOnlyCopy.exportUnavailable, feedback: .light)
                    return
                }
                AppHaptics.lightImpact()
                withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
                    showingShareMenu = false
                }
                Task { @MainActor in
                    let delay = reduceMotion ? 0.12 : 0.22
                    try? await Task.sleep(for: .seconds(delay))
                    openItineraryExport()
                }
            },
            onDismiss: {
                showingShareMenu = false
            }
        )
    }

    private func makeInviteViewModel() -> CollaborationViewModel {
        sceneFactory.makeInviteViewModel(
            tripId: viewModel.trip.id,
            tripTitle: viewModel.trip.title,
            currentUserId: authSession.currentUser?.id,
            currentUserAccess: viewModel.currentUserAccess
        )
    }

    /// Export entry from the share sheet.
    private func openItineraryExport() {
        guard !isDemo else {
            showActionToast(DemoReadOnlyCopy.exportUnavailable, feedback: .light)
            return
        }
        guard DemoMutationGuard.allows(.export, in: journeyContext) else {
            showActionToast(DemoReadOnlyCopy.exportUnavailable, feedback: .light)
            return
        }
        showingItineraryExportSheet = true
    }

    private var scrollOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: TripDetailScrollOffsetKey.self,
                    value: proxy.frame(in: .named("TripDetailScroll")).minY
                )
        }
        .frame(height: 0)
    }

    private var navMaterialProgress: Double {
        let raw = (-scrollY - 150) / 80
        return min(max(Double(raw), 0), 1)
    }

    private func collapsedNavigationBar(safeAreaTop: CGFloat) -> some View {
        HStack(spacing: AppSpacing.cozy) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(TripDetailTypography.chromeIcon)
                    .foregroundStyle(navMaterialProgress > 0.45 ? AppColors.textPrimary : .white)
                    .frame(width: 38, height: 38)
                    .background(navMaterialProgress > 0.45 ? AppColors.cardBackground.opacity(0.92) : .white.opacity(0.18))
                    .background(.ultraThinMaterial, in: Circle())
                    .clipShape(Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .pressableCardStyle(scale: 0.94, opacity: 0.9)
            .accessibilityLabel("返回")
            .accessibilityHint("返回旅程列表")

            Text(viewModel.trip.title)
                .font(TripDetailTypography.chromeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .opacity(navMaterialProgress)

            Spacer()
        }
        .padding(.horizontal, TripDetailLayout.pageInset)
        .padding(.top, safeAreaTop + 8)
        .padding(.bottom, AppSpacing.tight)
        .opacity(navMaterialProgress)
        .allowsHitTesting(navMaterialProgress > 0.05)
        .background {
            Rectangle()
                .fill(AppColors.creekMistTop.opacity(0.82 * navMaterialProgress))
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(navMaterialProgress)
                }
                .overlay(alignment: .bottom) {
                    AppCreekDivider()
                        .opacity(navMaterialProgress)
                }
        }
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: navMaterialProgress)
    }

    private func refreshSafeAreaTop() {
        let resolved = SafeAreaMetrics.top
        guard resolved > 0 else { return }
        safeAreaTop = resolved
    }

    /// Compute the Date for the currently selected day index.
    private var dateForSelectedDay: Date? {
        dateForDayIndex(selectedDayIndex)
    }

    private var journalFormWeatherItem: TripWeatherDisplayItem? {
        guard let date = dateForSelectedDay else { return nil }
        let today = TracciDateContext.startOfBusinessDay(for: TracciDateContext.today())
        guard TracciDateContext.startOfBusinessDay(for: date) == today else { return nil }
        guard case .available(let display) = viewModel.weatherState else { return nil }
        let key = TripDateFormatting.apiString(from: date)
        return display.items.first { $0.date == key } ?? display.items.first
    }

    private func selectDayMatchingJournal(_ form: JournalFormState) {
        let resolved = JournalOccurrenceDate.resolveCreate(
            capturedAt: form.occurredAtOverride,
            dayAnchor: form.defaultOccurredDate,
            tripStartDate: TripDateFormatting.date(from: viewModel.trip.startDate),
            tripEndDate: TripDateFormatting.date(from: viewModel.trip.endDate)
        )
        guard let startDate = TripDateFormatting.date(from: viewModel.trip.startDate),
              let dayIndex = TracciDateContext.dayIndex(for: resolved, startDate: startDate),
              (1...totalDays).contains(dayIndex)
        else { return }
        selectedDayIndex = dayIndex
    }

    private func dateForDayIndex(_ dayIndex: Int) -> Date? {
        guard let startDate = TripDateFormatting.date(from: viewModel.trip.startDate) else { return nil }
        return TracciDateContext.calendar.date(
            byAdding: .day,
            value: dayIndex - 1,
            to: TracciDateContext.startOfBusinessDay(for: startDate)
        )
    }

    /// Journey-stage atmosphere. All stages share the system grouped canvas;
    /// the enum is kept so existing call sites and hero-seam wiring stay stable.
    private var stageAtmosphere: AppAtmosphereStyle {
        switch viewModel.trip.effectiveStatus {
        case .planning: return .creek
        case .ongoing: return .creekOngoing
        case .completed: return .creekCompleted
        case .unknown: return .creek
        }
    }

    private func selectWorkspaceDate(_ dateString: String) {
        guard let date = TripDateFormatting.date(from: dateString),
              let startDate = TripDateFormatting.date(from: viewModel.trip.startDate)
        else { return }

        guard let dayIndex = TracciDateContext.dayIndex(for: date, startDate: startDate),
              (1...totalDays).contains(dayIndex)
        else { return }
        daySelectionBinding.wrappedValue = dayIndex
    }

    private func addJournalFromInsight(_ dateString: String?) {
        guard contentAddAllowed else {
            rejectDemoMutationIfNeeded()
            return
        }
        if let dateString {
            selectWorkspaceDate(dateString)
        }
        let date = dateString.flatMap(TripDateFormatting.date(from:)) ?? dateForSelectedDay
        journalFormInitialSection = .content
        journalFormMode = .create(defaultDate: date)
    }

    private func handleNodeFormSuccess(_ createdNodeId: String?) {
        Task {
            // Itinerary mutation already refreshes its own list. Keep Trip header counters
            // and the selected Day synchronized, then run the existing creation milestone.
            await refreshTripDetailAfterContentMutation()
            let targetDay = viewModel.itineraryViewModel.selectedDayIndex
            if selectedDayIndex != targetDay {
                selectedDayIndex = targetDay
            }
            if let createdNodeId {
                runCreationMilestone(nodeId: createdNodeId)
            }
        }
        nodeFormMode = nil
    }

    private func handleNodeFieldUpdated() {
        Task {
            await refreshTripDetailAfterContentMutation()
            let targetDay = viewModel.itineraryViewModel.selectedDayIndex
            if selectedDayIndex != targetDay {
                selectedDayIndex = targetDay
            }
        }
    }

    private func addExpenseFromInsight(_ dateString: String?) {
        guard contentAddAllowed else {
            rejectDemoMutationIfNeeded()
            return
        }
        if let dateString {
            selectWorkspaceDate(dateString)
        }
        let date = dateString.flatMap(TripDateFormatting.date(from:)) ?? dateForSelectedDay
        expenseFormMode = .create(defaultDate: date, itineraryLink: nil)
    }

    /// Live: hand off to Memory tab. Demo: present Bundle summary story in-place (prefer COMPLETED scene).
    private func openMemoryFromInsight() {
        if isDemo {
            Task { await presentDemoMemoryStory() }
            return
        }
        onOpenMemory(viewModel.trip.id)
    }

    @MainActor
    private func presentDemoMemoryStory() async {
        guard case let .demo(bundle, _) = journeyContext else {
            showActionToast(DemoReadOnlyCopy.memoryUnavailable, feedback: .light)
            return
        }

        // Prefer completed scene for fuller memory materials; fall back to current scene.
        let scene = bundle.scene(.completed) ?? journeyContext.demoScene
        guard let scene else {
            showActionToast(DemoReadOnlyCopy.memoryUnavailable, feedback: .light)
            return
        }

        let storyVM = sceneFactory.makeMemoryStoryViewModel(
            tripId: scene.trip.id,
            tripTitle: scene.trip.title
        )
        await storyVM.applyDemoSummary(
            scene.summary,
            preferredCoverPhoto: MemoryPageViewModel.preferredDemoStoryCoverPhoto(in: scene.summary)
        )
        demoStoryViewModel = storyVM
        demoStoryTrip = scene.trip
        showingDemoMemoryStory = true
    }

    @discardableResult
    private func rejectDemoMutationIfNeeded() -> Bool {
        guard isDemo else { return false }
        showActionToast(DemoReadOnlyCopy.toast, feedback: .light)
        return true
    }

    private var insightSheet: some View {
        NavigationStack {
            ScrollView {
                TripInsightWorkspaceSection(
                    viewModel: viewModel.insightViewModel,
                    onSelectDate: { dateString in
                        showingInsightSheet = false
                        selectWorkspaceDate(dateString)
                    },
                    onAddJournal: { dateString in
                        showingInsightSheet = false
                        addJournalFromInsight(dateString)
                    },
                    onAddExpense: { dateString in
                        showingInsightSheet = false
                        addExpenseFromInsight(dateString)
                    },
                    onOpenMemory: {
                        showingInsightSheet = false
                        openMemoryFromInsight()
                    },
                    usesPageInset: false,
                    canAddExpense: contentAddAllowed,
                    allowsSuggestionDismiss: !isDemo,
                    tripNodeCount: viewModel.trip.nodeCount ?? 0,
                    tripJournalCount: viewModel.trip.journalCount ?? 0,
                    tripExpenseText: TripPresentation.expenseText(for: viewModel.trip)
                )
                .padding(.horizontal, TripDetailLayout.pageInset)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
            .tracciAtmosphere(.creek)
            .navigationTitle(viewModel.insightViewModel.entryTitle)
            .navigationBarTitleDisplayMode(.inline)
            // 只读浏览 Sheet：无表单/提交态，靠拖动手势与系统下滑关闭即可，不放「完成」。
            .task {
                // Demo overview already hydrated; never re-hit stage-overview.
                if !isDemo {
                    await viewModel.insightViewModel.refresh()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AppRadius.hero)
    }

    private func runExecutionClock() async {
        while !Task.isCancelled {
            executionClock = Date()
            try? await Task.sleep(for: TripDayExecutionSnapshot.refreshInterval)
        }
    }

    /// Whether the currently selected day has no itinerary nodes yet.
    private var isSelectedDayItineraryEmpty: Bool {
        let day = viewModel.itineraryViewModel.groupedNodes.first { $0.dayIndex == selectedDayIndex }
        return (day?.nodeCount ?? 0) == 0
    }

    /// P2 creation ceremony: milestone entrance on the new card + FAB success pulse,
    /// plus a soft brand-blue halo when this is the day's first node.
    private func runCreationMilestone(nodeId: String) {
        newlyCreatedNodeId = nodeId
        fabModel.celebrateCreation(reduceMotion: reduceMotion)

        // Clear the flag after the entrance so the row cannot stay in an
        // “active but unsettled” invisible state if animation is interrupted.
        let clearDelay: TimeInterval = reduceMotion ? 0.05 : 0.55
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) {
            if newlyCreatedNodeId == nodeId {
                newlyCreatedNodeId = nil
            }
        }

        guard createdFromEmptyDay, !reduceMotion else { return }
        creationHaloOpacity = 0
        withAnimation(.easeOut(duration: AppMotion.pressDuration)) {
            creationHaloOpacity = 1
        } completion: {
            withAnimation(.easeOut(duration: AppMotion.normalDuration)) {
                creationHaloOpacity = 0
            }
        }
    }

    private func openNavigation(to node: ItineraryNodeItem) {
        guard let latitude = node.location?.latitude,
              let longitude = node.location?.longitude
        else {
            // 无坐标时：进行中可全量编辑；已结束仅允许改备注。Demo 永不进入编辑。
            guard !isDemo else { return }
            if contentEditAllowed {
                nodeFormMode = .edit(node)
            } else if TripEditPolicy.canEditContent(viewModel.currentUserAccess)
                        && TripEditPolicy.noteEditOutcome(trip: viewModel.trip).isAllowed {
                nodeFormMode = .editNote(node)
            }
            return
        }

        AppHaptics.lightImpact()
        let mapItem = MKMapItem(
            placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        )
        mapItem.name = node.displayTitle
        mapItem.openInMaps()
    }

    // MARK: - Hero Map Support

    /// 根据当前 Tab 同步 Hero 地图数据范围。
    /// 总览 + 多天旅程 → 全旅程；其余（含单日的总览）→ 单日。
    private func syncHeroMapScopeWithTab() {
        let scope: HeroMapScope =
            (selectedWorkspaceTab == .overview && totalDays > 1) ? .fullTrip : .day
        guard heroMapScope != scope else { return }
        heroMapScope = scope
        linkedNodeId = nil
        refreshHeroMapData()
    }

    /// 重新计算 Hero 地图数据：按 `heroMapScope` 分为全旅程总览与单日两种。
    private func refreshHeroMapData() {
        let destCoordinate = viewModel.trip.destination.flatMap { dest -> CLLocationCoordinate2D? in
            guard let lat = dest.latitude, let lng = dest.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        switch heroMapScope {
        case .day:
            let day = viewModel.itineraryViewModel.groupedNodes.first { $0.dayIndex == selectedDayIndex }
            let nodes = day?.nodes ?? []
            var annotations: [TripHeroMapData.HeroMapAnnotation] = []
            var sequence = 0
            for node in nodes {
                guard let lat = node.location?.latitude,
                      let lng = node.location?.longitude
                else { continue }
                sequence += 1
                annotations.append(
                    TripHeroMapData.HeroMapAnnotation(
                        id: node.id,
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        title: node.displayTitle,
                        timeText: node.startTime,
                        index: sequence
                    )
                )
            }

            heroMapData = TripHeroMapData(
                annotationNodes: annotations,
                destinationCoordinate: destCoordinate,
                destinationName: viewModel.trip.destinationName
            )

        case .fullTrip:
            // 全旅程：按天收集节点与路线段；天与天之间不连线（不虚构跨天移动）。
            let days = viewModel.itineraryViewModel.groupedNodes
                .sorted { $0.dayIndex < $1.dayIndex }
            var annotations: [TripHeroMapData.HeroMapAnnotation] = []
            var segments: [TripHeroMapData.DayRouteSegment] = []

            for day in days {
                var dayCoordinates: [CLLocationCoordinate2D] = []
                var sequence = 0
                for node in day.nodes {
                    guard let lat = node.location?.latitude,
                          let lng = node.location?.longitude
                    else { continue }
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    sequence += 1
                    dayCoordinates.append(coordinate)
                    annotations.append(
                        TripHeroMapData.HeroMapAnnotation(
                            id: node.id,
                            coordinate: coordinate,
                            title: node.displayTitle,
                            timeText: node.startTime,
                            index: sequence,
                            dayIndex: day.dayIndex
                        )
                    )
                }
                if dayCoordinates.count > 1 {
                    segments.append(
                        TripHeroMapData.DayRouteSegment(
                            dayIndex: day.dayIndex,
                            coordinates: dayCoordinates
                        )
                    )
                }
            }

            // 节点过多时降级：只保留每天起点（badge 编号即天数），路线保持完整。
            if annotations.count > TripHeroMapData.fullTripAnnotationCap {
                annotations = annotations.compactMap { annotation in
                    guard annotation.index == 1 else { return nil }
                    return TripHeroMapData.HeroMapAnnotation(
                        id: annotation.id,
                        coordinate: annotation.coordinate,
                        title: annotation.title,
                        timeText: annotation.timeText,
                        index: annotation.dayIndex,
                        dayIndex: annotation.dayIndex
                    )
                }
            }

            heroMapData = TripHeroMapData(
                annotationNodes: annotations,
                destinationCoordinate: destCoordinate,
                destinationName: viewModel.trip.destinationName,
                daySegments: segments,
                isFullTripOverview: true,
                fullTripDayCount: totalDays
            )
        }
    }

    /// 全旅程总览 dock 摘要：行程点使用完整节点数，避免把地图可用点误写成总数。
    private var fullTripSummaryText: String {
        let nodeCount = viewModel.itineraryViewModel.groupedNodes
            .flatMap(\.nodes)
            .count
        return "全程共 \(totalDays) 天 · \(nodeCount) 个行程点"
    }

    /// 时间线或地图 marker 被选中时统一处理。
    private func handleLinkedNode(id: String, shouldScroll: Bool) {
        let isReselect = linkedNodeId == id
        if !isReselect {
            // 切换节点时轻触反馈；同一节点重复点不抖。
            AppHaptics.selection()
        }
        linkedNodeId = id
        heroMapViewport = .focusedNode(id)
        if shouldScroll {
            itineraryScrollToNodeId = id
        }
    }

    /// Hero 地图 marker 点击 → 选中节点并滚动时间线。
    private func handleHeroMapNodeSelected(_ id: String) {
        handleLinkedNode(id: id, shouldScroll: true)
    }

    /// 打开 Hero 地图 marker 对应的导航。
    private func openHeroNavigation(_ annotation: TripHeroMapData.HeroMapAnnotation) {
        AppHaptics.lightImpact()
        let mapItem = MKMapItem(
            placemark: MKPlacemark(coordinate: annotation.coordinate)
        )
        mapItem.name = annotation.title
        mapItem.openInMaps()
    }

    /// 当前选中天的展示标签，例如「第 1 天」。
    private var selectedDayLabel: String {
        "第 \(selectedDayIndex) 天"
    }

    /// 自动高亮当前进行中的节点（仅进行中的旅程）。
    private var autoHighlightedRouteNodeId: String? {
        let day = viewModel.itineraryViewModel.groupedNodes.first { $0.dayIndex == selectedDayIndex }
        guard let day else { return nil }
        return day.nodes.first { node in
            guard node.location?.latitude != nil, node.location?.longitude != nil else { return false }
            return ItineraryTimeFormatting.displayStatus(for: node, dayDate: day.date) == .current
        }?.id
    }

    private var daySlideAnimation: Animation {
        AppMotion.animation(AppMotion.daySwitch, reduceMotion: reduceMotion)
            ?? .easeInOut(duration: 0.28)
    }

    private var dayFeedSectionContent: some View {
        // browse 壳层拥有唯一竖向 ScrollView；大地图已拆为 mapExplore Surface。
        let effectiveTab = selectedWorkspaceTab ?? viewModel.selectedTab
        let demoDimOpacity: Double = demoFeedDimmed ? 0.42 : 1
        return workspaceTabContent(tab: effectiveTab)
            .frame(maxWidth: .infinity)
            .id(effectiveTab)
            .transition(AppMotion.transition(reduceMotion: reduceMotion, yOffset: 8))
            .offset(x: dayFeedSlideOffset)
            .scaleEffect(dayFeedDepthScale, anchor: .center)
            .opacity(dayFeedOpacity * demoDimOpacity)
    }

    @ViewBuilder
    private func workspaceTabContent(tab: TripDetailTab) -> some View {
        switch tab {
        case .overview:
            overviewPage
        case .itinerary, .journal, .expense:
            dayFeedContent(tab: tab)
        }
    }

    // MARK: - Carousel Helpers

    /// 当天有坐标的节点，用于横排轮播。
    private var carouselNodes: [ItineraryNodeItem] {
        let day = viewModel.itineraryViewModel.groupedNodes.first { $0.dayIndex == selectedDayIndex }
        return day?.nodes.filter { $0.location?.latitude != nil && $0.location?.longitude != nil } ?? []
    }

    /// 当前选中天的日期。
    private var currentDayDate: Date? {
        let day = viewModel.itineraryViewModel.groupedNodes.first { $0.dayIndex == selectedDayIndex }
        guard let dateString = day?.date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    /// 总览页 — 仅展示每日行程总览。
    private var overviewPage: some View {
        TripOverviewPageView(
            groupedNodes: viewModel.itineraryViewModel.groupedNodes,
            totalDays: totalDays,
            tripStartDate: viewModel.trip.startDate,
            onSelectDay: { dayIndex in
                // 从总览跳回工作 Tab 时，定位到对应天
                if dayIndex != selectedDayIndex {
                    selectedDayIndex = dayIndex
                }
                selectedWorkspaceTab = .itinerary
                viewModel.selectedTab = .itinerary
            }
        )
    }

    /// Natural-height content for itinerary / journal / expense. The outer
    /// detail ScrollView owns scrolling and pull-to-refresh.
    private func dayFeedContent(tab: TripDetailTab) -> some View {
        TripUnifiedCreekFeed(
            selectedDayIndex: selectedDayIndex,
            selectedTab: tab,
            trip: viewModel.trip,
            isItineraryLoading: viewModel.itineraryViewModel.isLoading,
            itineraryErrorMessage: viewModel.itineraryViewModel.errorMessage,
            itineraryGroups: viewModel.itineraryViewModel.groupedNodes,
            isJournalLoading: viewModel.journalViewModel.isLoading,
            journalErrorMessage: viewModel.journalViewModel.errorMessage,
            expenses: viewModel.expenseViewModel.expenses,
            journalDayGroups: viewModel.journalViewModel.dayGroups,
            isExpenseLoading: viewModel.expenseViewModel.isLoading,
            expenseErrorMessage: viewModel.expenseViewModel.errorMessage,
            weatherState: viewModel.weatherState,
            executionSnapshot: viewModel.executionSnapshot(for: selectedDayIndex, now: executionClock),
            onRefreshWeather: { Task { await viewModel.loadWeather() } },
            onRetryItinerary: { Task { await viewModel.itineraryViewModel.refresh() } },
            onRetryJournal: { Task { await viewModel.journalViewModel.refresh() } },
            onRetryExpense: { Task { await viewModel.expenseViewModel.refresh() } },
            onAddNode: {
                guard contentAddAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                createdFromEmptyDay = isSelectedDayItineraryEmpty
                nodeFormMode = .create(defaultDayIndex: selectedDayIndex)
            },
            onEditNode: { node in
                guard contentEditAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                nodeFormMode = .edit(node)
            },
            onEditNodeNote: { node in
                // 备注例外：已结束旅程仍允许改 note；Demo 永远只读。
                guard !isDemo, TripEditPolicy.canEditContent(viewModel.currentUserAccess) else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                nodeFormMode = .editNote(node)
            },
            onDeleteNode: { node in
                guard contentEditAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                itineraryNodeToDelete = node
                showingNodeDeleteConfirm = true
            },
            onOpenNodePlace: { node in
                guard !isDemo, let placeId = node.location?.placeId else { return }
                onOpenPlaceDetail(placeId)
            },
            onAddExpense: {
                guard contentAddAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                let date = dateForSelectedDay
                expenseFormMode = .create(defaultDate: date, itineraryLink: nil)
            },
            onAddExpenseForNode: { node in
                guard contentAddAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                expenseFormMode = .create(
                    defaultDate: dateForDayIndex(node.dayIndex),
                    itineraryLink: .from(node: node)
                )
            },
            onEditExpense: { expense in
                guard contentEditAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                expenseFormMode = .edit(expense)
            },
            onDuplicateExpense: { expense in
                guard contentAddAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                expenseFormMode = .duplicate(expense, defaultDate: dateForSelectedDay)
            },
            onDeleteExpense: { expense in
                guard contentEditAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                Task { await deleteExpense(expense) }
            },
            onOpenSettlement: {
                AppHaptics.lightImpact()
                showingSettlement = true
            },
            hasTripExpenses: viewModel.expenseViewModel.hasExpenses
                || (isDemo && viewModel.demoSettlementHasContent),
            members: viewModel.members,
            currentUserMemberId: viewModel.members.first(where: { $0.userId == authSession.currentUser?.id })?.id,
            settlement: isDemo ? viewModel.demoSettlement : viewModel.expenseViewModel.settlement,
            onAddJournal: {
                guard contentAddAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                let date = dateForSelectedDay
                journalFormInitialSection = .content
                journalFormMode = .create(defaultDate: date)
            },
            onAddPhotoJournal: {
                guard contentAddAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                let date = dateForSelectedDay
                journalFormInitialSection = .photos
                journalFormMode = .create(defaultDate: date)
            },
            onEditJournal: { entry in
                guard contentEditAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                journalFormInitialSection = .content
                journalFormMode = .edit(entry)
            },
            onToggleHighlight: { entry in
                guard contentEditAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                Task { _ = await viewModel.journalViewModel.toggleHighlight(entry) }
            },
            onToggleFeaturedPhoto: contentEditAllowed ? { photo in
                Task { _ = await viewModel.journalViewModel.toggleFeaturedPhoto(photo) }
            } : nil,
            onDeleteJournal: { entry in
                guard contentEditAllowed else {
                    rejectDemoMutationIfNeeded()
                    return
                }
                Task { await deleteJournal(entry) }
            },
            onNavigateToNode: openNavigation,
            // canEdit：角色可写即可（含已结束时的备注编辑入口）；增删改由 content* 与 noteOnly 再细分
            // Demo 强制只读，不单靠 access 猜测。
            canEdit: !isDemo && TripEditPolicy.canEditContent(viewModel.currentUserAccess),
            currentUserId: authSession.currentUser?.id,
            topSafeInset: resolvedTopSafeInset,
            emptyStateMinHeight: TripDetailLayout.emptyStateMinHeight(
                topSafeInset: resolvedTopSafeInset,
                bottomSafeInset: max(SafeAreaMetrics.bottom, 16)
            ),
            newlyCreatedNodeId: newlyCreatedNodeId,
            scrollToNodeId: $itineraryScrollToNodeId,
            showMapSection: false,
            isHeroMapVisible: mapExplorePhase.isMapSurfaceActive,
            linkedNodeId: linkedNodeId,
            onLinkNode: handleLinkedNode,
            isNodeReorderMode: isNodeReorderMode,
            onEnterNodeReorder: enterNodeReorderMode,
            onCancelNodeReorder: {
                if isReorderDirty {
                    pendingNavigationAfterAbandon = nil
                    showingAbandonReorderConfirm = true
                } else {
                    exitNodeReorderMode(restoringBaseline: false)
                }
            },
            onCommitNodeReorder: {
                Task { await commitNodeReorder() }
            },
            onMoveNode: moveNodeInReorderSession,
            isReorderSubmitting: isReorderSubmitting
        )
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func animateDaySelection(from oldIndex: Int, to newIndex: Int) {
        guard newIndex != oldIndex else { return }
        newlyCreatedNodeId = nil

        let isMovingForward = newIndex > oldIndex

        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedDayIndex = newIndex
                dayFeedSlideOffset = 0
                dayFeedDepthScale = 1
                dayFeedOpacity = AppMotion.daySwitchReducedMotionOpacity
            }
            withAnimation(AppMotion.quick) {
                dayFeedOpacity = 1
            }
            return
        }

        // Forward: new day enters from trailing (+x). Backward: from leading (-x).
        // Primary motion = horizontal slide; opacity/scale settle on the same curve —
        // a delayed parallax layer left residual on rapid Day taps, so there is none.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDayIndex = newIndex
            dayFeedSlideOffset = isMovingForward ? AppMotion.daySwitchDistance : -AppMotion.daySwitchDistance
            dayFeedDepthScale = AppMotion.daySwitchDepthScale
            dayFeedOpacity = AppMotion.daySwitchFadedOpacity
        }

        withAnimation(daySlideAnimation) {
            dayFeedSlideOffset = 0
            dayFeedOpacity = 1
            dayFeedDepthScale = 1
        }
    }

    private var daySelectionBinding: Binding<Int> {
        Binding(
            get: { selectedDayIndex },
            set: { newValue in
                guard newValue != selectedDayIndex else { return }
                if isNodeReorderMode, isReorderDirty {
                    pendingNavigationAfterAbandon = .day(newValue)
                    showingAbandonReorderConfirm = true
                    return
                }
                if isNodeReorderMode {
                    exitNodeReorderMode(restoringBaseline: false)
                }
                animateDaySelection(from: selectedDayIndex, to: newValue)
            }
        )
    }

    private var tabSelectionBinding: Binding<TripDetailTab> {
        Binding(
            get: { selectedWorkspaceTab ?? viewModel.selectedTab },
            set: { newValue in
                guard newValue != (selectedWorkspaceTab ?? viewModel.selectedTab) else { return }
                if isNodeReorderMode, isReorderDirty {
                    pendingNavigationAfterAbandon = .tab(newValue)
                    showingAbandonReorderConfirm = true
                    return
                }
                if isNodeReorderMode {
                    exitNodeReorderMode(restoringBaseline: false)
                }
                selectedWorkspaceTab = newValue
                viewModel.selectedTab = newValue
                // 总览为全局回看，清理按天地图高亮避免状态残留.
                if newValue == .overview {
                    linkedNodeId = nil
                    heroMapViewport = .routeOverview
                }
            }
        )
    }

    // MARK: - Node reorder session

    private func enterNodeReorderMode() {
        guard contentEditAllowed else {
            rejectDemoMutationIfNeeded()
            return
        }
        let nodes = viewModel.itineraryViewModel.groupedNodes
            .first { $0.dayIndex == selectedDayIndex }?
            .nodes ?? []
        guard nodes.count >= 2 else { return }

        withAnimation(reduceMotion ? nil : AppMotion.quick) {
            heroMode = .cover
            isNodeReorderMode = true
        }
        reorderBaselineNodeIds = nodes.map(\.id)
        linkedNodeId = nil
        heroMapViewport = .routeOverview
        fabModel.showingFabMenu = false
        AppHaptics.selection()
    }

    private func exitNodeReorderMode(restoringBaseline: Bool) {
        if restoringBaseline, !reorderBaselineNodeIds.isEmpty {
            _ = viewModel.itineraryViewModel.applyLocalNodeOrder(
                dayIndex: selectedDayIndex,
                orderedIds: reorderBaselineNodeIds
            )
        }
        isNodeReorderMode = false
        isReorderSubmitting = false
        reorderBaselineNodeIds = []
        pendingNavigationAfterAbandon = nil
        showingAbandonReorderConfirm = false
        refreshHeroMapData()
    }

    private func moveNodeInReorderSession(sourceId: String, targetId: String) {
        guard isNodeReorderMode, sourceId != targetId else { return }
        guard var ids = viewModel.itineraryViewModel.groupedNodes
            .first(where: { $0.dayIndex == selectedDayIndex })?
            .nodes.map(\.id)
        else { return }
        guard let from = ids.firstIndex(of: sourceId),
              let to = ids.firstIndex(of: targetId)
        else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        _ = viewModel.itineraryViewModel.applyLocalNodeOrder(
            dayIndex: selectedDayIndex,
            orderedIds: ids
        )
        refreshHeroMapData()
    }

    private func commitNodeReorder() async {
        guard isNodeReorderMode, !isReorderSubmitting else { return }
        let orderedIds = viewModel.itineraryViewModel.groupedNodes
            .first { $0.dayIndex == selectedDayIndex }?
            .nodes.map(\.id) ?? []

        if orderedIds == reorderBaselineNodeIds {
            exitNodeReorderMode(restoringBaseline: false)
            return
        }

        isReorderSubmitting = true
        let success = await viewModel.itineraryViewModel.commitNodeOrder(
            dayIndex: selectedDayIndex,
            orderedIds: orderedIds
        )
        isReorderSubmitting = false

        if success {
            showActionToast("顺序已更新", feedback: .success)
            exitNodeReorderMode(restoringBaseline: false)
            await refreshTripDetailAfterContentMutation()
        } else {
            _ = viewModel.itineraryViewModel.applyLocalNodeOrder(
                dayIndex: selectedDayIndex,
                orderedIds: reorderBaselineNodeIds
            )
            refreshHeroMapData()
            showActionToast(
                viewModel.itineraryViewModel.errorMessage ?? "排序未保存，请重试",
                feedback: .error
            )
        }
    }

    private func discardReorderAndResumePendingNavigation() {
        let pending = pendingNavigationAfterAbandon
        exitNodeReorderMode(restoringBaseline: true)
        switch pending {
        case .day(let day):
            animateDaySelection(from: selectedDayIndex, to: day)
        case .tab(let tab):
            viewModel.selectedTab = tab
        case .back:
            onBack()
        case .none:
            break
        }
    }

    private func handleBackWhileMaybeReordering() {
        if isNodeReorderMode, isReorderDirty {
            pendingNavigationAfterAbandon = .back
            showingAbandonReorderConfirm = true
            return
        }
        if isNodeReorderMode {
            exitNodeReorderMode(restoringBaseline: false)
        }
        onBack()
    }

    private var totalDays: Int {
        viewModel.trip.totalDays ?? 1
    }

    private var controlBandPinnedProgress: CGFloat {
        let progress = (-scrollY - 150) / 120
        return min(max(progress, 0), 1)
    }

    private var bottomContentPadding: CGFloat {
        max(SafeAreaMetrics.bottom + 72, 88)
    }

    private var selectedDayHasContent: Bool {
        let itineraryDay = viewModel.itineraryViewModel.groupedNodes.first { $0.dayIndex == selectedDayIndex }
        let nodeCount = itineraryDay?.nodeCount ?? 0

        let hasExpense = viewModel.expenseViewModel.expenses.contains { expense in
            dayIndexForExpense(expense) == selectedDayIndex
        }

        let journalDay = viewModel.journalViewModel.dayGroups.first { $0.dayIndex == selectedDayIndex }
        let hasJournal = !(journalDay?.entries.isEmpty ?? true)

        return nodeCount > 0 || hasExpense || hasJournal
    }

    private var resolvedTopSafeInset: CGFloat {
        max(safeAreaTop, SafeAreaMetrics.top)
    }

    private func dayIndexForExpense(_ expense: Expense) -> Int? {
        guard let spentDate = expense.spentAtDate,
              let startDate = TripDateFormatting.date(from: viewModel.trip.startDate)
        else { return nil }
        return TracciDateContext.dayIndex(for: spentDate, startDate: startDate)
    }

    static func computeInitialDayIndex(trip: Trip) -> Int {
        guard let startDate = TripDateFormatting.date(from: trip.startDate) else { return 1 }
        let today = TracciDateContext.today()
        if let totalDays = trip.totalDays,
           let idx = TracciDateContext.dayIndex(for: today, startDate: startDate),
           idx >= 1, idx <= totalDays {
            return idx
        }
        return 1
    }

    private func deleteExpense(_ expense: Expense) async {
        let success = await viewModel.expenseViewModel.deleteExpense(expense)
        if success {
            await refreshTripDetailAfterContentMutation()
        }
    }

    private func deleteJournal(_ entry: JournalEntry) async {
        viewModel.journalViewModel.confirmDelete(entry)
        let success = await viewModel.journalViewModel.performDelete()
        if success {
            await refreshTripDetailAfterContentMutation()
            showActionToast("日志已删除", feedback: .success)
        } else {
            showActionToast(viewModel.journalViewModel.errorMessage ?? "删除失败，请稍后重试", feedback: .error)
        }
    }

    private func refreshTripDetailAfterContentMutation() async {
        guard !isDemo else { return }
        await viewModel.loadTripDetail()
        onTripUpdated(viewModel.trip)
    }

    private func detailErrorBanner(message: String) -> some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.large, padding: 12) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.danger)
                Text(message)
                    .font(TripDetailTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                Spacer()
                Button("重试") {
                    Task { await viewModel.loadTripDetail() }
                }
                .font(TripDetailTypography.bodyMedium)
                .foregroundStyle(AppColors.interactiveText)
            }
        }
    }

    private func copyInvitationLink() {
        guard !isDemo, DemoMutationGuard.allows(.invite, in: journeyContext) else {
            showActionToast(DemoReadOnlyCopy.inviteUnavailable, feedback: .light)
            return
        }
        AppHaptics.lightImpact()
        Task {
            guard let invitation = await viewModel.createInvitationForSharing() else {
                if let message = viewModel.invitationErrorMessage {
                    showActionToast(message, feedback: .error)
                    showingShareMenu = false
                }
                return
            }
            ExportShareHelper.copyToPasteboard(invitationInviteURL(invitation))
            showActionToast("已复制邀请链接", feedback: .success)
            showingShareMenu = false
        }
    }

    private func invitationInviteURL(_ invitation: TripInvitationResp) -> String {
        if let webInviteUrl = invitation.webInviteUrl, !webInviteUrl.isEmpty {
            return webInviteUrl
        }
        if let appDeepLink = invitation.appDeepLink, !appDeepLink.isEmpty {
            return appDeepLink
        }
        return "https://tracci.cn/co-editor?id=\(invitation.tripId)&code=\(invitation.inviteCode)"
    }

    private enum ActionFeedback {
        case success
        case error
        case light
    }

    private func showActionToast(
        _ message: String,
        feedback: ActionFeedback = .light,
        playHaptic: Bool = true
    ) {
        if playHaptic {
            switch feedback {
            case .success:
                AppHaptics.success()
            case .error:
                AppHaptics.error()
            case .light:
                AppHaptics.lightImpact()
            }
        }

        actionToast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if actionToast == message {
                    actionToast = nil
                }
            }
        }
    }
}


private struct TripDetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
