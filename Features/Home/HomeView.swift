import SwiftUI
import UIKit
import TracciNetworking

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AuthSession.self) private var authSession
    @Bindable var viewModel: HomeViewModel
    @Bindable var tripListActions: TripListActions
    let tripService: TripService
    let itineraryService: ItineraryService
    let journalService: JournalService
    let expenseService: ExpenseService
    let exportService: ExportService
    let collaborationService: CollaborationService
    let savedPlaceService: SavedPlaceService
    let routeProvider: any TripRouteProviding
    let bottomTabBarContentInset: CGFloat
    @Binding var tripDetailNavigationRequest: TripDetailNavigationRequest?
    @Binding var navigationPath: NavigationPath
    @Binding var rootOverlayHidesTabBar: Bool
    /// Reports root list scroll offset so MainTab can collapse chrome.
    var onRootScrollOffsetChange: (CGFloat) -> Void = { _ in }
    var onTripDeleted: (String) -> Void = { _ in }
    /// Fired when trip content (journals, expenses, itinerary, etc.) changes so other tabs can refresh.
    var onTripContentChanged: () -> Void = {}
    var onOpenMemory: (String) -> Void = { _ in }
    /// Demo exit conversion: leave sample and open create-trip options (MainTab owns the sheet).
    var onCreateTripFromDemo: () -> Void = {}
    @State private var showingSearch = false

    // MARK: - Context menu state
    @State private var contextShareTrip: Trip?
    @State private var contextDeleteTrip: Trip?
    @State private var showingDeleteConfirm = false
    @State private var feedbackToast: TracciToastMessage?

    @FocusState private var isSearchFocused: Bool
    @State private var searchClearSnapshot: String?
    @State private var searchClearProgress: CGFloat = 0

    /// Shared-element zoom transition (G3.1): home trip cards → trip detail hero,
    /// iOS 18+ only; iOS 17 keeps the default push + `detailEnter` settle.
    @Namespace private var tripDetailZoomNamespace

    var body: some View {
        NavigationStack(path: $navigationPath) {
            homeNavigationRoot
        }
    }

    private var homeNavigationRoot: some View {
        homeRootContent
            .toolbar(.hidden, for: .navigationBar)
            .tracciNavigationPathUIKitPopSync(path: $navigationPath)
            .navigationDestination(for: HomeNavigationRoute.self) { route in
                homeNavigationDestination(for: route)
            }
            .onChange(of: tripDetailNavigationRequest) { _, _ in
                consumeTripDetailNavigationRequest()
            }
            .onAppear {
                rootOverlayHidesTabBar = showingSearch
                consumeTripDetailNavigationRequest()
            }
            .tracciBottomSheet(
                isPresented: Binding(
                    get: { contextShareTrip != nil },
                    set: { presented in
                        if !presented {
                            contextShareTrip = nil
                        }
                    }
                ),
                height: TracciDialogMetrics.tripShareSheetHeight(activeMemberCount: tripListActions.shareMembers.filter(\.isActive).count)
            ) {
                if let trip = contextShareTrip {
                    homeShareSheet(for: trip)
                }
            }
            .overlay {
                homeDeleteConfirmSheet
            }
            .tracciToast(
                $feedbackToast,
                bottomPadding: AppNavigationMetrics.overlayBottomPadding(for: SafeAreaMetrics.bottom) + AppSpacing.cardSmall
            )
            .onChange(of: contextShareTrip) { _, trip in
                if let trip {
                    Task { await tripListActions.loadShareMembers(tripId: trip.id) }
                } else {
                    tripListActions.clearShareMembers()
                }
            }
            .onChange(of: contextDeleteTrip) { _, trip in
                if trip != nil { showingDeleteConfirm = true }
            }
            .onChange(of: navigationPath.count) { oldCount, newCount in
                guard newCount != oldCount else { return }
                #if DEBUG
                print("[TabBarPath] navigationPath.count \(oldCount) -> \(newCount)")
                #endif
            }
            .onChange(of: showingSearch) { _, _ in
                rootOverlayHidesTabBar = showingSearch
            }
    }

    private var homeRootContent: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader
                    homeMasthead
                    tripSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, HomeLayout.topPadding)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: RootScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("HomeRootScroll")).minY
                        )
                    }
                }
            }
            .coordinateSpace(name: "HomeRootScroll")
            .tracciRootScrollOffset { offset in
                guard navigationPath.isEmpty, !showingSearch else {
                    onRootScrollOffsetChange(0)
                    return
                }
                onRootScrollOffsetChange(max(0, offset))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomTabBarContentInset)
            }
            .refreshable {
                await viewModel.refreshTrips()
            }
            .tracciAtmosphere(.creek)
            .task {
                await viewModel.loadTripsIfNeeded()
            }

            bottomFadeOverlay

            if showingSearch {
                searchOverlay
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }

    private func homeShareSheet(for trip: Trip) -> some View {
        TripShareSheet(
            tripTitle: trip.title,
            members: tripListActions.shareMembers,
            onCopyLink: {
                Task {
                    await copyShareLink(for: trip)
                }
            },
            onInviteFriends: {
                contextShareTrip = nil
            },
            onExportLongImage: {
                contextShareTrip = nil
            },
            onDismiss: {
                contextShareTrip = nil
            }
        )
    }

    private var homeDeleteConfirmSheet: some View {
        TracciConfirmSheet(
            isPresented: Binding(
                get: { contextDeleteTrip != nil && showingDeleteConfirm },
                set: { presented in
                    if !presented {
                        showingDeleteConfirm = false
                        contextDeleteTrip = nil
                    }
                }
            ),
            title: "确定要删除「\(contextDeleteTrip?.title ?? "")」吗？",
            message: "此操作不可撤销，所有行程、日志、消费记录将被清除。",
            confirmTitle: "删除旅程",
            sheetHeight: 340,
            onConfirm: {
                guard let trip = contextDeleteTrip else { return }
                let tripId = trip.id
                contextDeleteTrip = nil
                Task {
                    if await tripListActions.deleteTrip(id: tripId) {
                        withAnimation(AppMotion.animation(AppMotion.enter, reduceMotion: reduceMotion)) {
                            viewModel.removeTrip(id: tripId)
                        }
                        onTripDeleted(tripId)
                    } else if let message = tripListActions.errorMessage {
                        feedbackToast = .error(message)
                    }
                }
            },
            onCancel: {
                contextDeleteTrip = nil
            }
        )
    }

    private func copyShareLink(for trip: Trip) async {
        UIPasteboard.general.string = await tripListActions.makeShareLink(tripId: trip.id)
        contextShareTrip = nil
    }

    private var bottomFadeOverlay: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [
                    AppColors.creekMistBottom.opacity(0.0),
                    AppColors.creekMistBottom.opacity(0.28),
                    AppColors.creekMistBottom.opacity(0.78),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: HomeLayout.bottomFadeHeight)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var brandHeader: some View {
        HStack(alignment: .center) {
            BrandLockupView(style: .header)
            Spacer()
            HStack(spacing: AppSpacing.tight) {
                HeaderIconButton(systemImage: "magnifyingglass", accessibilityLabel: "搜索") {
                    AppHaptics.lightImpact()
                    withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
                        showingSearch = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isSearchFocused = true
                    }
                }
            }
        }
        .frame(minHeight: 54, alignment: .center)
    }

    /// Creek Masthead: compact editorial open, not an empty floating card.
    /// Empty-state narrative lives in the HomeEmptyState card below.
    private var homeMasthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(currentDateText)
                .font(AppTypography.homeMeta)
                .foregroundStyle(AppColors.textPlaceholder)
                .tracking(1.2)
                .padding(.bottom, AppSpacing.xs)

            greetingTitle
                .font(AppTypography.homeGreeting)
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(2)

            if viewModel.featuredTrip == nil {
                Text(mastheadCompanionLine)
                    .font(AppTypography.homeCompanion)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.xs)
            }

            // Structural creek measure: spans the content column and groups masthead with featured surface.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.brandPrimary.opacity(0.34),
                            AppColors.brandPrimary.opacity(0.14),
                            AppColors.borderSubtle.opacity(0.72),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: 1)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            GreetingCardDecoration()
                .frame(width: 220, height: 112)
                .clipped()
                .opacity(viewModel.featuredTrip == nil ? 1 : 0.38)
                .allowsHitTesting(false)
        }
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, viewModel.featuredTrip == nil ? AppSpacing.lg : AppSpacing.md)
        .fadeSlideIn(offset: AppMotion.largeFadeSlideOffset, animation: AppMotion.slow)
        .accessibilityElement(children: .combine)
    }

    private var mastheadCompanionLine: String {
        viewModel.mastheadCompanionText
    }

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if showsOuterTripSectionHeader {
                tripSectionHeader(title: "我的旅程", totalText: nil)
            }

            content
        }
        .animation(
            AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion),
            value: homeContentSignature
        )
    }

    private var homeContentSignature: String {
        switch viewModel.state {
        case .idle, .loading: "loading"
        case .empty: "empty"
        case .loaded: "loaded"
        case .error: "error"
        }
    }

    /// Loading / empty / error keep a simple section title; loaded list owns its own headers.
    private var showsOuterTripSectionHeader: Bool {
        switch viewModel.state {
        case .idle, .loading, .empty, .error:
            return true
        case .loaded:
            return false
        }
    }

    private func tripSectionHeader(
        title: String,
        totalText: String?,
        onSelectAll: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 8)
            if let totalText {
                if let onSelectAll {
                    Button(action: onSelectAll) {
                        HStack(spacing: 2) {
                            Text(totalText)
                            Image(systemName: "chevron.right")
                                .font(AppTypography.microSemibold)
                        }
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看\(totalText)")
                } else {
                    Text(totalText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }
        }
        .padding(.vertical, AppSpacing.sectionHeaderBottom)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            HomeLoadingStateView()
                .tracciRevealTransition(reduceMotion: reduceMotion)
        case .empty:
            homeEmptyContent
                .tracciRevealTransition(reduceMotion: reduceMotion)
        case .loaded:
            tripList
                .tracciRevealTransition(reduceMotion: reduceMotion)
        case let .error(message):
            HomeErrorStateView(message: message) {
                Task {
                    await viewModel.loadTrips()
                }
            }
            .tracciRevealTransition(reduceMotion: reduceMotion)
        }
    }

    /// Real empty create CTA, optionally with a secondary demo entry above it.
    private var homeEmptyContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let bundle = viewModel.displayableDemoBundle,
               let trip = bundle.defaultScenePayload()?.trip,
               let scene = bundle.validDefaultScene {
                NavigationLink(
                    value: HomeNavigationRoute.demoJourney(scene: scene)
                ) {
                    HomeDemoJourneyCard(
                        trip: trip,
                        dateRangeText: viewModel.dateRangeText(for: trip),
                        totalDaysText: viewModel.totalDaysText(for: trip)
                    )
                    .frame(maxWidth: .infinity)
                }
                .pressableCardStyle()
                .simultaneousGesture(cardTapFeedback)
                .fadeSlideIn(index: 0, offset: AppMotion.largeFadeSlideOffset)
                // Accessibility lives on `HomeDemoJourneyCard` only — avoid duplicate hints.
            } else if viewModel.demoLoadState == .loading {
                HomeDemoJourneyLoadingCard()
                    .fadeSlideIn(index: 0, offset: AppMotion.largeFadeSlideOffset)
            }

            HomeEmptyState()
                .fadeSlideIn(
                    index: viewModel.showsDemoJourney || viewModel.demoLoadState == .loading ? 1 : 0,
                    offset: AppMotion.largeFadeSlideOffset
                )
        }
    }

    private var tripList: some View {
        let groups = viewModel.visibleGroupedRegularTrips
        let hasFeatured = viewModel.featuredTrip != nil
        let showRegularBlock = !groups.isEmpty || hasFeatured

        return LazyVStack(spacing: HomeLayout.tripListSpacing) {
            if let featuredTrip = viewModel.featuredTrip {
                NavigationLink(value: HomeNavigationRoute.tripDetail(tripId: featuredTrip.id, initialTab: .preferred(for: featuredTrip))) {
                    HomeJourneyWorkbenchCard(
                        trip: featuredTrip,
                        viewModel: viewModel,
                        onShare: { contextShareTrip = featuredTrip },
                        onEdit: { openTripEdit(tripId: featuredTrip.id) },
                        onDelete: { contextDeleteTrip = featuredTrip }
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                // 与 phaseGroup 卡片一致:作为详情 hero 的 zoom 转场源,
                // 保持首页所有卡片进入详情的转场语言统一。
                .tracciHeroZoomSource(id: featuredTrip.id, in: tripDetailZoomNamespace)
                .pressableCardStyle(heroLift: 2)
                .simultaneousGesture(cardTapFeedback)
                .motionTransition(reduceMotion: reduceMotion)
                .fadeSlideIn(index: 0, offset: AppMotion.largeFadeSlideOffset)
            }

            if showRegularBlock {
                // Phase groups: 进行中 → 即将出发 → 已结束 (user's journey arc).
                // No top-level "其余旅程" header — phase titles carry the narrative.
                phaseGroup(title: "进行中", trips: groups.ongoing, startIndex: 1)
                phaseGroup(title: "即将出发", trips: groups.planning, startIndex: 1 + groups.ongoing.count)
                phaseGroup(title: "已结束", trips: groups.completed, startIndex: 1 + groups.ongoing.count + groups.planning.count)

                if viewModel.showsAllTripsEntry {
                    allTripsEntry
                        .fadeSlideIn(
                            index: HomeJourneyListPolicy.visibleRegularTripLimit + 1,
                            offset: AppMotion.largeFadeSlideOffset
                        )
                }

                if groups.isEmpty, hasFeatured {
                    HomeSparseArchiveState()
                        .fadeSlideIn(
                            index: 1,
                            offset: AppMotion.largeFadeSlideOffset
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Renders a single phase group with an editorial header (creek lead-in line
    /// + title) and its trip cards. Empty groups are skipped at the call site.
    @ViewBuilder
    private func phaseGroup(title: String, trips: [Trip], startIndex: Int) -> some View {
        if !trips.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                phaseGroupHeader(title: title)
                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                    NavigationLink(value: HomeNavigationRoute.tripDetail(tripId: trip.id, initialTab: .preferred(for: trip))) {
                        TripCard(
                            trip: trip,
                            onShare: { contextShareTrip = trip },
                            onEdit: { openTripEdit(tripId: trip.id) },
                            onDelete: { contextDeleteTrip = trip }
                        )
                        .milestoneEntrance(active: viewModel.newlyCreatedTripId == trip.id)
                    }
                    .tracciHeroZoomSource(id: trip.id, in: tripDetailZoomNamespace)
                    .pressableCardStyle()
                    .simultaneousGesture(cardTapFeedback)
                    .motionTransition(reduceMotion: reduceMotion)
                    .fadeSlideIn(
                        index: startIndex + index,
                        offset: AppMotion.largeFadeSlideOffset
                    )
                }
            }
        }
    }

    /// Editorial phase-group header: short brand-blue lead-in line + stage name.
    private func phaseGroupHeader(title: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.brandPrimary.opacity(0.42),
                            AppColors.brandPrimary.opacity(0.12),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 14, height: 1.2)
            Text(title)
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, AppSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var allTripsEntry: some View {
        Button {
            AppHaptics.lightImpact()
            pushHomeRoute(.allTrips)
        } label: {
            AppElevationCard(
                level: .l0,
                role: .content,
                padding: 0
            ) {
                HStack(spacing: AppSpacing.sm) {
                    Text("查看全部 \(viewModel.total) 段旅程")
                        .font(AppTypography.buttonTitleMedium)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer(minLength: AppSpacing.sm)

                    Image(systemName: "chevron.right")
                        .font(AppTypography.microSemibold)
                        .foregroundStyle(AppColors.brandPrimary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, AppSpacing.cardSmall)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .buttonStyle(PressableCardStyle(scale: AppMotion.pressScale, opacity: AppMotion.pressOpacity))
        .accessibilityLabel("查看全部 \(viewModel.total) 段旅程")
    }

    private var cardTapFeedback: some Gesture {
        TapGesture().onEnded {
            AppHaptics.lightImpact()
        }
    }

    private func prepareForTripDetailNavigationFromSearch() {
        viewModel.searchQuery = ""
        isSearchFocused = false
        showingSearch = false
        AppHaptics.lightImpact()
    }

    // MARK: - Search Overlay

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.cozy) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(AppTypography.listTitleMedium)
                        .foregroundStyle(AppColors.textPlaceholder)
                    TextField("搜索旅程、目的地...", text: $viewModel.searchQuery)
                        .font(AppTypography.listBody)
                        .foregroundStyle(AppColors.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isSearchFocused)
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            TracciClearDissolve.play(
                                text: $viewModel.searchQuery,
                                snapshot: $searchClearSnapshot,
                                progress: $searchClearProgress,
                                reduceMotion: reduceMotion
                            )
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.listBody)
                                .foregroundStyle(AppColors.textDisabled)
                        }
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .frame(height: 44)
                .background(AppColors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .overlay(alignment: .leading) {
                    TracciClearDissolveLayer(
                        text: searchClearSnapshot,
                        progress: searchClearProgress,
                        leadingInset: 40
                    )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .stroke(
                            isSearchFocused
                                ? AppColors.brandPrimary.opacity(0.3)
                                : AppColors.borderDefault.opacity(0.5),
                            lineWidth: isSearchFocused ? 1.5 : 0.7
                        )
                }

                Button {
                    AppHaptics.lightImpact()
                    viewModel.searchQuery = ""
                    isSearchFocused = false
                    withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
                        showingSearch = false
                    }
                } label: {
                    Text("取消")
                        .font(AppTypography.listTitleMedium)
                        .foregroundStyle(AppColors.interactiveText)
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, HomeLayout.topPadding)
            .padding(.bottom, AppSpacing.md)

            Rectangle()
                .fill(AppColors.borderDefault.opacity(0.3))
                .frame(height: 0.7)

            ScrollView {
                if viewModel.isSearching {
                    searchResults
                } else {
                    recentTripsSection
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .tracciAtmosphere(.creek)
        .tracciDismissKeyboardOnBlankTap()
    }

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.featuredTrip == nil, viewModel.regularTrips.isEmpty {
            searchNoResults
        } else {
            let count = (viewModel.featuredTrip != nil ? 1 : 0) + viewModel.regularTrips.count
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                Text("找到 \(count) 个结果")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.top, AppSpacing.cardSmall)

                LazyVStack(spacing: AppSpacing.sm) {
                    if let featuredTrip = viewModel.featuredTrip {
                        NavigationLink(value: HomeNavigationRoute.tripDetail(tripId: featuredTrip.id, initialTab: .preferred(for: featuredTrip))) {
                            SearchResultCard(trip: featuredTrip, viewModel: viewModel)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            prepareForTripDetailNavigationFromSearch()
                        })
                    }

                    ForEach(viewModel.regularTrips, id: \.id) { trip in
                        NavigationLink(value: HomeNavigationRoute.tripDetail(tripId: trip.id, initialTab: .preferred(for: trip))) {
                            SearchResultCard(trip: trip, viewModel: viewModel)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            prepareForTripDetailNavigationFromSearch()
                        })
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
            }
            .padding(.bottom, AppSpacing.pageTop)
        }
    }

    private var recentTripsSection: some View {
        let recent = Array(viewModel.trips.prefix(5))
        return VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            Text("最近旅程")
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.cardSmall)

            if recent.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "map")
                        .font(AppTypography.emptyIcon)
                        .foregroundStyle(AppColors.textDisabled)
                    VStack(spacing: 5) {
                        Text("还没有最近旅程")
                            .font(AppTypography.buttonTitleMedium)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("建好旅程后，会出现在这里")
                            .font(AppTypography.labelRegular)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(recent, id: \.id) { trip in
                        NavigationLink(value: HomeNavigationRoute.tripDetail(tripId: trip.id, initialTab: .preferred(for: trip))) {
                            SearchResultCard(trip: trip, viewModel: viewModel)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            prepareForTripDetailNavigationFromSearch()
                        })
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
            }
        }
        .padding(.bottom, AppSpacing.pageTop)
    }

    private var searchNoResults: some View {
        VStack(spacing: AppSpacing.cozy) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.emptyIcon)
                .foregroundStyle(AppColors.textDisabled)
            Text("没有找到「\(viewModel.searchQuery)」")
                .font(AppTypography.listTitleMedium)
                .foregroundStyle(AppColors.textPrimary)
            Text("试试搜索其他目的地或旅程名称")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var currentDateText: String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }

    private var greetingTitle: Text {
        Text(greetingText)
    }

    /// Time-of-day greeting + name. Nickname when set; otherwise「旅人」as a warm default.
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        switch hour {
        case 5..<12:
            prefix = "早上好"
        case 12..<18:
            prefix = "下午好"
        default:
            prefix = "晚上好"
        }

        return "\(prefix)，\(greetingName)"
    }

    private var greetingName: String {
        guard let nickname = authSession.currentUser?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nickname.isEmpty,
              !HomeLayout.technicalDisplayNames.contains(nickname.lowercased())
        else {
            return "旅人"
        }
        return nickname
    }

    @ViewBuilder
    private func homeNavigationDestination(for route: HomeNavigationRoute) -> some View {
        switch route {
        case .allTrips:
            AllTripsView(
                viewModel: viewModel.allTripsListViewModel(),
                tripListActions: tripListActions,
                tripService: tripService,
                itineraryService: itineraryService,
                journalService: journalService,
                expenseService: expenseService,
                exportService: exportService,
                collaborationService: collaborationService,
                navigationPath: $navigationPath,
                onTripDeleted: { tripId in
                    viewModel.removeTrip(id: tripId)
                    onTripDeleted(tripId)
                },
                onTripsLoaded: { trips in
                    for trip in trips {
                        viewModel.updateTripIfExists(trip)
                    }
                },
                tripDetailZoomNamespace: tripDetailZoomNamespace
            )
        case .tripDetail(let tripId, let initialTab):
            if let trip = trip(for: tripId) {
                tripDetailView(for: trip, initialTab: initialTab)
                    .tracciHeroZoomDestination(id: tripId, in: tripDetailZoomNamespace, reduceMotion: reduceMotion)
            }
        case .demoJourney(let scene):
            if let context = viewModel.demoJourneyContext(scene: scene),
               let demoTrip = context.demoScene?.trip {
                tripDetailView(
                    for: demoTrip,
                    initialTab: .preferred(for: demoTrip),
                    journeyContext: context
                )
            }
        case .tripEdit(let tripId, let access):
            if let trip = trip(for: tripId) {
                tripEditView(for: trip, access: access)
            }
        case .tripMembers(let tripId, let tripTitle, let access):
            TripMembersView(
                tripId: tripId,
                tripTitle: tripTitle,
                collaborationService: collaborationService,
                currentUserId: authSession.currentUser?.id,
                currentUserAccess: access
            )
        case .activityLog(let tripId):
            ActivityLogView(
                tripId: tripId,
                collaborationService: collaborationService
            )
        case .placeDetail(let placeId):
            // This Home route is only pushed from an itinerary node card today.
            // The place is already in the trip, so hide the wishlist collect card.
            // Profile → 想去的地点 uses ProfileRoute.placeDetail (default showsCollectAction).
            PlaceDetailView(service: savedPlaceService, placeId: placeId, showsCollectAction: false)
        }
    }

    private func tripDetailView(
        for trip: Trip,
        initialTab: TripDetailTab,
        journeyContext: JourneyContext? = nil
    ) -> some View {
        let isDemo = journeyContext?.isDemo == true
        return TripDetailView(
            trip: trip,
            sceneFactory: TripDetailSceneFactory(
                tripService: tripService,
                itineraryService: itineraryService,
                savedPlaceService: savedPlaceService,
                journalService: journalService,
                expenseService: expenseService,
                exportService: exportService,
                collaborationService: collaborationService,
                routeProvider: routeProvider
            ),
            initialTab: initialTab,
            onTripUpdated: { updatedTrip in
                guard !isDemo else { return }
                viewModel.upsertTrip(updatedTrip)
                onTripContentChanged()
            },
            onBack: {
                popHomeRoute()
            },
            shouldHandleInteractivePop: {
                navigationPath.count == 1
            },
            onInteractivePopFinished: {
                syncHomeRouteDepth(0)
            },
            onOpenMembers: { access in
                guard !isDemo else { return }
                pushHomeRoute(
                    .tripMembers(
                        tripId: trip.id,
                        tripTitle: trip.title,
                        access: access
                    )
                )
            },
            onOpenTripSettings: { access in
                guard !isDemo else { return }
                pushHomeRoute(.tripEdit(tripId: trip.id, access: access))
            },
            onOpenMemory: { tripId in
                guard !isDemo else { return }
                onOpenMemory(tripId)
            },
            onOpenPlaceDetail: { placeId in
                guard !isDemo else { return }
                pushHomeRoute(.placeDetail(placeId: placeId))
            },
            onCreateOwnTrip: {
                guard isDemo else { return }
                // Pop sample first so create options sit on the empty home root.
                popHomeRoute()
                // Let NavigationStack settle before the global create menu covers the root.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onCreateTripFromDemo()
                }
            },
            journeyContext: journeyContext
        )
    }

    private func tripEditView(for trip: Trip, access: TripAccessContext?) -> some View {
        TripEditView(
            trip: trip,
            tripService: tripService,
            currentUserAccess: access,
            onDeleted: {
                returnToHomeAfterDeletedTrip(trip.id)
            },
            onOpenMembers: { tripId, tripTitle, access in
                pushHomeRoute(.tripMembers(tripId: tripId, tripTitle: tripTitle, access: access))
            },
            onOpenActivityLog: { tripId in
                pushHomeRoute(.activityLog(tripId: tripId))
            },
            onTripUpdated: { updatedTrip in
                viewModel.updateTripIfExists(updatedTrip)
            }
        )
    }

    private func trip(for id: String) -> Trip? {
        viewModel.trips.first(where: { $0.id == id })
    }

    private func pushHomeRoute(_ route: HomeNavigationRoute) {
        showingSearch = false
        navigationPath.append(route)
    }

    private func openTripEdit(tripId: String) {
        pushHomeRoute(.tripEdit(tripId: tripId, access: nil))
    }

    private func popHomeRoute() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
        showingSearch = false
    }

    private func syncHomeRouteDepth(_ targetDepth: Int) {
        let normalizedTargetDepth = max(targetDepth, 0)
        guard navigationPath.count > normalizedTargetDepth else {
            showingSearch = false
            return
        }
        navigationPath.removeLast(navigationPath.count - normalizedTargetDepth)
        showingSearch = false
    }

    private func returnToHomeAfterDeletedTrip(_ tripId: String) {
        viewModel.removeTrip(id: tripId)
        onTripDeleted(tripId)
        navigationPath = NavigationPath()
        showingSearch = false
        rootOverlayHidesTabBar = false
    }

    private func consumeTripDetailNavigationRequest() {
        guard let request = tripDetailNavigationRequest else { return }
        tripDetailNavigationRequest = nil
        pushHomeRoute(
            .tripDetail(tripId: request.tripId, initialTab: request.initialTab)
        )
        Task {
            await viewModel.loadTripsIfNeeded()
        }
    }
}

/// Cool creek skylight only — no warm gold bloom on the home greeting.
private struct GreetingCardDecoration: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RadialGradient(
                colors: [
                    AppColors.brandPrimary.opacity(0.12),
                    AppColors.brandPrimary.opacity(0.04),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 168
            )
            .frame(width: 220, height: 176)
            .offset(x: 72, y: -48)

            RadialGradient(
                colors: [
                    AppColors.brandPrimaryLight.opacity(0.07),
                    AppColors.brandPrimaryLight.opacity(0.02),
                    .clear,
                ],
                center: .center,
                startRadius: 6,
                endRadius: 100
            )
            .frame(width: 140, height: 120)
            .offset(x: 40, y: 44)

            Circle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 14, height: 14)
                .blur(radius: 1.2)
                .offset(x: -18, y: 18)

            Circle()
                .fill(AppColors.brandPrimaryLight.opacity(0.12))
                .frame(width: 8, height: 8)
                .blur(radius: 0.6)
                .offset(x: -64, y: 68)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HeaderIconButton<Badge: View>: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder var badge: Badge

    init(
        systemImage: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void = {},
        @ViewBuilder badge: () -> Badge = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel ?? Self.defaultLabel(for: systemImage)
        self.action = action
        self.badge = badge()
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppTypography.listTitleMedium)
                .foregroundStyle(AppColors.textMuted)
                .frame(width: 46, height: 46)
                .background(AppColors.cardBackground.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppColors.borderDefault.opacity(0.42), lineWidth: 0.7)
                }
                .tracciElevation(.l0)
                .overlay(alignment: .topTrailing) {
                    badge
                }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .pressableCardStyle(scale: 0.94, opacity: 0.9)
        .accessibilityLabel(accessibilityLabel)
    }

    private static func defaultLabel(for systemImage: String) -> String {
        switch systemImage {
        case "magnifyingglass": return "搜索"
        case "bell": return "通知"
        case "gearshape": return "设置"
        case "plus": return "添加"
        case "ellipsis": return "更多"
        default: return systemImage
        }
    }
}

private enum HomeLayout {
    static let topPadding: CGFloat = 16
    static let tripListSpacing: CGFloat = AppSpacing.md
    static let bottomFadeHeight: CGFloat = 96
    static let technicalDisplayNames: Set<String> = ["admin", "administrator", "root", "test", "user"]
}

private struct SearchResultCard: View {
    let trip: Trip
    let viewModel: HomeViewModel

    var body: some View {
        HStack(spacing: AppSpacing.cozy) {
            TripCoverView(url: trip.coverThumbnailURL, fallbackURL: trip.coverPreviewURL, height: 52, cornerRadius: AppRadius.small)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AppSpacing.xs) {
                    Text(trip.title)
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    SearchStatusBadge(text: trip.effectiveStatus.label, statusColor: trip.effectiveStatus.statusColor)
                }
                Text("\(viewModel.destinationText(for: trip)) · \(viewModel.dateRangeText(for: trip))")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textDisabled.opacity(0.7))
        }
        .padding(AppSpacing.cozy)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .tracciElevation(.l0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(trip.title)，\(trip.effectiveStatus.label)，\(viewModel.destinationText(for: trip))，\(viewModel.dateRangeText(for: trip))"
        )
        .accessibilityHint("打开旅程详情")
        .accessibilityAddTraits(.isButton)
    }
}

private struct SearchStatusBadge: View {
    let text: String
    var statusColor: Color = AppColors.textMuted

    var body: some View {
        Text(text)
            .font(AppTypography.micro)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(minHeight: 20)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

private struct HomeLoadingStateView: View {
    var body: some View {
        TripListSkeletonView(featuredCount: 1, regularCount: 3, verticalPadding: AppSpacing.md)
    }
}

private struct HomeErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ErrorStateView(title: "旅程加载失败", message: message, retry: retry)
    }
}

/// Home empty state — informational only. Primary create action stays on the tab-bar `+`.
///
/// Quiet guide toward the bottom-trailing create control. Cool paper surface (not warm hero
/// gradient) so empty home still matches Creek Mist browse, not auth yellow paper.
struct HomeEmptyState: View {
    var body: some View {
        AppElevationCard(level: .l2, role: .content, radius: AppRadius.hero, padding: 0) {
            ZStack(alignment: .bottom) {
                HomeEmptyCreekBaseline()
                    .stroke(
                        AppColors.brandPrimary.opacity(0.11),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 8])
                    )
                    .frame(height: 64)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    HomeEmptyCreekConvergence()
                        .frame(width: 176, height: 78)
                        .padding(.bottom, AppSpacing.lg)
                        .tracciTextsReveal(index: 0)

                    Text("准备好出发了吗？")
                        .font(AppTypography.dayTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .tracciTextsReveal(index: 1)

                    Text("创建旅程，先把日期和目的地记下来")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, AppSpacing.tight)
                        .tracciTextsReveal(index: 2)

                    HomeEmptyCreateHint()
                        .padding(.top, AppSpacing.xl)
                        .tracciTextsReveal(index: 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xl)
                .padding(.bottom, AppSpacing.lg)
            }
            .background(alignment: .top) {
                RadialGradient(
                    colors: [
                        AppColors.brandPrimary.opacity(0.13),
                        AppColors.brandPrimary.opacity(0.035),
                        .clear,
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 190
                )
                .frame(height: 170)
                .allowsHitTesting(false)
            }
        }
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("还没有旅程。点右下角加号，新建旅程或输入邀请码加入。")
        .accessibilityHint("加号在屏幕底部导航栏最右侧")
    }
}

/// Quiet footer hint — aligned with trip-day empty FAB copy, not a second CTA surface.
private struct HomeEmptyCreateHint: View {
    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "plus.circle.fill")
                .font(AppTypography.label)
            Text("点右下角 + 创建第一段旅程")
                .font(AppTypography.caption)
        }
        .foregroundStyle(AppColors.interactiveText)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct HomeEmptyCreekConvergence: View {
    private let streams: [(start: UnitPoint, control: UnitPoint, opacity: Double, width: CGFloat)] = [
        (.topLeading, UnitPoint(x: 0.28, y: 0.10), 0.22, 1.2),
        (.topTrailing, UnitPoint(x: 0.72, y: 0.12), 0.22, 1.2),
        (.bottomLeading, UnitPoint(x: 0.30, y: 0.76), 0.18, 1.0),
        (.bottomTrailing, UnitPoint(x: 0.70, y: 0.76), 0.18, 1.0),
        (UnitPoint(x: 0.5, y: 0), UnitPoint(x: 0.5, y: 0.24), 0.30, 1.6),
    ]

    var body: some View {
        Canvas { context, size in
            let target = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
            for stream in streams {
                var path = Path()
                let start = CGPoint(x: stream.start.x * size.width, y: stream.start.y * size.height)
                let control = CGPoint(x: stream.control.x * size.width, y: stream.control.y * size.height)
                path.move(to: start)
                path.addQuadCurve(to: target, control: control)
                context.stroke(
                    path,
                    with: .color(AppColors.brandPrimary.opacity(stream.opacity)),
                    style: StrokeStyle(lineWidth: stream.width, lineCap: .round)
                )
            }

            context.fill(
                Path(ellipseIn: CGRect(x: target.x - 5, y: target.y - 5, width: 10, height: 10)),
                with: .color(AppColors.brandPrimary.opacity(0.18))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: target.x - 2.5, y: target.y - 2.5, width: 5, height: 5)),
                with: .color(AppColors.brandPrimary.opacity(0.55))
            )
        }
        .accessibilityHidden(true)
    }
}

private struct HomeEmptyCreekBaseline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -4, y: rect.height * 0.74))
        path.addCurve(
            to: CGPoint(x: rect.width * 1.02, y: rect.height * 0.24),
            control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.60),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * 0.48)
        )
        return path
    }
}

private struct HomeSparseArchiveState: View {
    var body: some View {
        VStack(spacing: AppSpacing.cozy) {
            Canvas { context, size in
                let lines: [(CGFloat, Double, [CGFloat])] = [
                    (0.24, 0.18, [3, 9]),
                    (0.50, 0.28, [4, 8]),
                    (0.76, 0.16, [3, 10]),
                ]
                for line in lines {
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * 0.04, y: size.height * line.0))
                    path.addCurve(
                        to: CGPoint(x: size.width * 0.96, y: size.height * (line.0 - 0.04)),
                        control1: CGPoint(x: size.width * 0.32, y: size.height * (line.0 - 0.10)),
                        control2: CGPoint(x: size.width * 0.64, y: size.height * (line.0 + 0.10))
                    )
                    context.stroke(
                        path,
                        with: .color(AppColors.brandPrimary.opacity(line.1)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: line.2)
                    )
                }
            }
            .frame(width: 180, height: 40)
            .accessibilityHidden(true)

            VStack(spacing: AppSpacing.xxs) {
                Text("还没有其他旅程")
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textSecondary)
                Text("以后创建的旅程会显示在这里")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Home empty") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            Text("2026年7月21日 星期二")
                .font(AppTypography.homeMeta)
                .foregroundStyle(AppColors.textPlaceholder)
                .tracking(1.2)
            Text("早上好，旅人")
                .font(AppTypography.homeGreeting)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, AppSpacing.xs)
            Text("还没有旅程，想出发时就从这里开始")
                .font(AppTypography.homeCompanion)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, AppSpacing.xs)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.brandPrimary.opacity(0.42),
                            AppColors.brandPrimary.opacity(0.10),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .padding(.vertical, AppSpacing.md)

            SectionHeader("我的旅程")
            HomeEmptyState()
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.pageTop)
    }
    .tracciAtmosphere(.creek)
}

#Preview("Home featured — no cover stage") {
    let apiClient = APIClient(config: .development, tokenProvider: nil)
    let viewModel = HomeViewModel(
        tripService: TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
    )
    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("早上好，旅人")
                .font(AppTypography.homeGreeting)
                .foregroundStyle(AppColors.textPrimary)
            Capsule()
                .fill(AppColors.brandPrimary.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 2)
            HomeJourneyWorkbenchCard(
                trip: MemoryPreviewFixtures.ongoingTrip,
                viewModel: viewModel
            )
            Text("其余旅程")
                .font(AppTypography.sectionTitle)
            TripCard(
                trip: MemoryPreviewFixtures.planningTrip
            )
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.pageTop)
    }
    .tracciAtmosphere(.creek)
}
#endif
