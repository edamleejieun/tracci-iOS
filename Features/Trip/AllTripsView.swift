import SwiftUI
import TracciNetworking

struct AllTripsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: AllTripsViewModel
    @Bindable var tripListActions: TripListActions
    let tripService: TripService
    let itineraryService: ItineraryService
    let journalService: JournalService
    let expenseService: ExpenseService
    let exportService: ExportService
    let collaborationService: CollaborationService
    @Binding var navigationPath: NavigationPath
    var onTripDeleted: (String) -> Void = { _ in }

    // MARK: - Context menu state
    @State private var contextShareTrip: Trip?
    @State private var contextDeleteTrip: Trip?
    @State private var showingDeleteConfirm = false
    @State private var feedbackToast: TracciToastMessage?

    var onTripsLoaded: ([Trip]) -> Void = { _ in }
    var tripDetailZoomNamespace: Namespace.ID? = nil
    @Namespace private var filterSelectionNamespace
    @Namespace private var previewZoomNamespace

    private var resolvedTripZoomNamespace: Namespace.ID {
        tripDetailZoomNamespace ?? previewZoomNamespace
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                if viewModel.hasCompletedInitialLoad {
                    tripListScroll
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                } else {
                    loadingContent
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                }
            case .empty:
                tripListScroll
                    .tracciRevealTransition(reduceMotion: reduceMotion)
            case .loaded:
                tripListScroll
                    .tracciRevealTransition(reduceMotion: reduceMotion)
            case let .error(message):
                if viewModel.hasCompletedInitialLoad {
                    tripListScroll
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                        .overlay {
                            errorOverlay(message: message)
                        }
                } else {
                    errorContent(message: message)
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                }
            }
        }
        .animation(
            AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion),
            value: viewModel.hasCompletedInitialLoad
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("全部旅程")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .task(id: viewModel.reloadToken) {
            #if DEBUG
            guard !viewModel.disablesAutoLoad else { return }
            #endif
            await viewModel.loadTripsIfNeeded()
            syncTripsToHome()
        }
        .refreshable {
            await viewModel.refreshTrips()
            syncTripsToHome()
        }
        // MARK: - Context menu: share sheet
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
                TripShareSheet(
                    tripTitle: trip.title,
                    members: tripListActions.shareMembers,
                    onCopyLink: {
                        Task {
                            UIPasteboard.general.string = await tripListActions.makeShareLink(tripId: trip.id)
                            contextShareTrip = nil
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
        }
        .overlay {
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
                            onTripDeleted(tripId)
                            await viewModel.refreshTrips()
                            syncTripsToHome()
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
        .tracciToast($feedbackToast, bottomPadding: 28)
        .onChange(of: contextShareTrip) { _, trip in
            if let trip {
                Task { await tripListActions.loadShareMembers(tripId: trip.id) }
            } else {
                tripListActions.clearShareMembers()
            }
        }
        .onChange(of: contextDeleteTrip) { _, trip in
            let hasPendingDelete = trip != nil
            if hasPendingDelete {
                showingDeleteConfirm = true
            }
        }
    }

    // MARK: - Main content

    private var showsFilterBar: Bool {
        viewModel.hasCompletedInitialLoad
            || viewModel.state == .loaded
            || viewModel.state == .empty
    }

    private var tripListScroll: some View {
        ScrollView {
            tripList
                .padding(.horizontal, AppSpacing.pageX)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsFilterBar {
                pinnedFilterChrome
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 24)
        }
    }

    /// Pinned below the inline navigation title via `safeAreaInset`.
    private var pinnedFilterChrome: some View {
        filterHeader
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.creekMistBottom)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColors.borderDefault.opacity(0.24))
                    .frame(height: 0.5)
            }
    }

    private var tripList: some View {
        LazyVStack(spacing: AppSpacing.cardSmall) {
            if viewModel.isRefreshing, viewModel.trips.isEmpty {
                InlineLoadingStateView(message: "正在加载旅程", verticalPadding: 48)
            } else if viewModel.isCurrentFilterEmpty {
                filterEmptyContent
            } else {
                tripCardsContent
            }

            if showsPaginationFooter {
                paginationFooter
            }
        }
        // Animate content changes without resetting ScrollView identity (`.id` was
        // cancelling in-flight list requests and surfacing as "cancelled").
        .animation(
            AppMotion.animation(AppMotion.enter, reduceMotion: reduceMotion),
            value: viewModel.listContentSignature
        )
        .padding(.top, AppSpacing.cardSmall)
        .padding(.bottom, AppSpacing.tight)
    }

    private var showsPaginationFooter: Bool {
        !viewModel.isCurrentFilterEmpty
            && !(viewModel.isRefreshing && viewModel.trips.isEmpty)
    }

    /// 全部旅程统一小横条卡片，与首页大封面主卡形成差异。
    @ViewBuilder
    private var tripCardsContent: some View {
        ForEach(Array(viewModel.trips.enumerated()), id: \.element.id) { index, trip in
            NavigationLink(value: HomeNavigationRoute.tripDetail(tripId: trip.id, initialTab: .preferred(for: trip))) {
                TripCard(
                    trip: trip,
                    onShare: { contextShareTrip = trip },
                    onEdit: { openTripEdit(tripId: trip.id) },
                    onDelete: { contextDeleteTrip = trip }
                )
            }
            .tracciHeroZoomSource(id: trip.id, in: resolvedTripZoomNamespace)
            .pressableCardStyle()
            .simultaneousGesture(tripDetailTapGesture)
            .fadeSlideIn(index: index, offset: AppMotion.largeFadeSlideOffset)
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.isLoadingMore {
            InlineLoadingStateView(message: "加载更多旅程", verticalPadding: 24)
        } else if let loadMoreError = viewModel.loadMoreError {
            loadMoreErrorContent(message: loadMoreError)
        } else if viewModel.hasMore {
            paginationTrigger
        }
    }

    private var paginationTrigger: some View {
        Color.clear
            .frame(height: 24)
            .onAppear {
                Task { await viewModel.loadMoreIfNeeded() }
            }
    }

    private func loadMoreErrorContent(message: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.retryLoadMore() }
            } label: {
                Text("重试加载")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.card)
    }

    private var filterEmptyContent: some View {
        VStack(spacing: 0) {
            if let selectedStatus = viewModel.selectedStatus {
                EmptyStateView(
                    title: "没有\(selectedStatus.label)的旅程",
                    subtitle: "切换筛选条件查看其他旅程",
                    buttonTitle: nil
                )
                .padding(.vertical, 48)
            } else {
                EmptyStateView(
                    title: "还没有旅程",
                    subtitle: "创建旅程后，可以添加行程、开支和日志",
                    buttonTitle: nil
                )
                .padding(.vertical, 48)
            }
        }
        .fadeSlideIn(offset: AppMotion.fadeSlideOffset, animation: AppMotion.quick)
    }

    private var tripDetailTapGesture: some Gesture {
        TapGesture().onEnded {
            AppHaptics.lightImpact()
        }
    }

    private func openTripEdit(tripId: String) {
        onTripsLoaded(viewModel.loadedTripsForSync)
        navigationPath.append(HomeNavigationRoute.tripEdit(tripId: tripId, access: nil))
    }

    private func syncTripsToHome() {
        onTripsLoaded(viewModel.loadedTripsForSync)
    }

    // MARK: - Filter bar

    private var filterHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            filterBar

            if !viewModel.summaryText.isEmpty {
                Text(viewModel.summaryText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.horizontal, AppSpacing.pageX)
            }
        }
        .padding(.top, AppSpacing.tight)
        .padding(.bottom, AppSpacing.sm)
    }

    /// Stable ids — avoid `ForEach` over `TripStatus?` with `id: \.?.rawValue` (nil id is flaky).
    private var filterOptions: [(id: String, status: TripStatus?)] {
        [
            ("all", nil),
            ("ongoing", .ongoing),
            ("planning", .planning),
            ("completed", .completed)
        ]
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.tight) {
                ForEach(filterOptions, id: \.id) { option in
                    filterChip(
                        status: option.status,
                        isSelected: viewModel.selectedStatus == option.status,
                        count: viewModel.countForStatus(option.status)
                    )
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
        }
        // Fixed cross-axis size so chips always paint; horizontal scroll only.
        .frame(height: 40)
        .animation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion), value: viewModel.selectedStatus)
    }

    private func filterChip(status: TripStatus?, isSelected: Bool, count: Int) -> some View {
        let label = status?.label ?? "全部"

        return Button {
            AppHaptics.selection()
            withAnimation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion)) {
                viewModel.selectStatus(status)
            }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Text(label)
                    .font(AppFont.system(13, weight: isSelected ? .semibold : .medium))

                if count > 0 {
                    TracciNumberPopIn(
                        text: "\(count)",
                        font: AppTypography.microSemibold,
                        color: isSelected ? AppColors.brandPrimary : AppColors.textMuted
                    )
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        isSelected
                            ? AppColors.brandPrimary.opacity(0.14)
                            : AppColors.subtleBackground
                    )
                    .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 36)
            .background {
                Capsule()
                    .fill(isSelected ? Color.clear : AppColors.cardBackground)
                TracciSlidingSelectionPill(
                    isSelected: isSelected,
                    namespace: filterSelectionNamespace,
                    fill: AppColors.brandPrimaryBackground,
                    shape: Capsule()
                )
            }
            .overlay {
                Capsule()
                    .stroke(
                        isSelected
                            ? AppColors.brandPrimary.opacity(0.34)
                            : AppColors.borderDefault.opacity(0.55),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading state

    private var loadingContent: some View {
        ScrollView {
            TripListSkeletonView(featuredCount: 1, regularCount: 4, verticalPadding: AppSpacing.lg)
                .padding(.horizontal, AppSpacing.pageX)
        }
        .scrollDisabled(true)
    }

    // MARK: - Error state

    private func errorOverlay(message: String) -> some View {
        VStack {
            Spacer()
            ErrorStateView(title: "旅程加载失败", message: message) {
                Task { await viewModel.loadAllTrips() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary.opacity(0.92))
    }

    private func errorContent(message: String) -> some View {
        VStack {
            Spacer()
            ErrorStateView(title: "旅程加载失败", message: message) {
                Task { await viewModel.loadAllTrips() }
            }
            Spacer()
        }
    }
}

#if DEBUG
private enum AllTripsPreviewSupport {
    static var apiClient: APIClient {
        APIClient(config: .development, tokenProvider: nil)
    }

    static var tripService: TripService {
        let apiClient = apiClient
        return TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
    }

    @MainActor
    static func loadedViewModel() -> AllTripsViewModel {
        let viewModel = AllTripsViewModel(tripService: tripService)
        viewModel.configureForPreview(
            trips: [
                MemoryPreviewFixtures.ongoingTrip,
                MemoryPreviewFixtures.readyTrip,
                MemoryPreviewFixtures.planningTrip
            ],
            total: 12,
            statusCounts: AllTripsStatusCounts(all: 12, ongoing: 1, planning: 4, completed: 7),
            hasMore: true
        )
        return viewModel
    }

    @MainActor
    static func filterEmptyViewModel() -> AllTripsViewModel {
        let viewModel = AllTripsViewModel(tripService: tripService)
        viewModel.configureForPreview(
            total: 0,
            selectedStatus: .planning,
            statusCounts: AllTripsStatusCounts(all: 12, ongoing: 1, planning: 0, completed: 7)
        )
        return viewModel
    }

    static func previewTrips(count: Int) -> [Trip] {
        (0 ..< count).map { index in
            Trip(
                id: "all-trips-preview-\(index)",
                title: "旅程 \(index + 1)",
                startDate: "2026-05-0\((index % 5) + 1)",
                endDate: "2026-05-0\((index % 5) + 3)",
                status: .completed,
                totalDays: 3,
                destination: TripDestination(name: "京都"),
                nodeCount: 6,
                journalCount: 4
            )
        }
    }

    @MainActor
    static func loadingMoreViewModel() -> AllTripsViewModel {
        let viewModel = AllTripsViewModel(tripService: tripService)
        viewModel.configureForPreview(
            trips: previewTrips(count: 10),
            total: 18,
            statusCounts: AllTripsStatusCounts(all: 18, ongoing: 2, planning: 6, completed: 10),
            hasMore: true,
            isLoadingMore: true
        )
        return viewModel
    }

    @MainActor
    static func loadMoreErrorViewModel() -> AllTripsViewModel {
        let viewModel = AllTripsViewModel(tripService: tripService)
        viewModel.configureForPreview(
            trips: previewTrips(count: 10),
            total: 18,
            statusCounts: AllTripsStatusCounts(all: 18, ongoing: 2, planning: 6, completed: 10),
            hasMore: true,
            loadMoreError: "网络连接暂时不可用，请稍后再试。"
        )
        return viewModel
    }

    @MainActor
    static func errorViewModel() -> AllTripsViewModel {
        let viewModel = AllTripsViewModel(tripService: tripService)
        viewModel.configureForPreview(
            state: .error("网络连接暂时不可用，请稍后再试。")
        )
        return viewModel
    }
}

extension AllTripsView {
    @MainActor
    init(previewViewModel: AllTripsViewModel) {
        let apiClient = AllTripsPreviewSupport.apiClient
        let fileUploadService = FileUploadService(apiClient: apiClient)
        self.viewModel = previewViewModel
        self.tripListActions = TripListActions(
            tripService: AllTripsPreviewSupport.tripService,
            collaborationService: CollaborationService(apiClient: apiClient)
        )
        self.tripService = AllTripsPreviewSupport.tripService
        self.itineraryService = ItineraryService(apiClient: apiClient)
        self.journalService = JournalService(
            apiClient: apiClient,
            fileUploadService: fileUploadService
        )
        self.expenseService = ExpenseService(apiClient: apiClient)
        self.exportService = ExportService(apiClient: apiClient)
        self.collaborationService = CollaborationService(apiClient: apiClient)
        self._navigationPath = .constant(NavigationPath())
    }
}

#Preview("全部旅程 · 列表") {
    NavigationStack {
        AllTripsView(previewViewModel: AllTripsPreviewSupport.loadedViewModel())
    }
}

#Preview("全部旅程 · 筛选空态") {
    NavigationStack {
        AllTripsView(previewViewModel: AllTripsPreviewSupport.filterEmptyViewModel())
    }
}

#Preview("全部旅程 · 加载更多") {
    NavigationStack {
        AllTripsView(previewViewModel: AllTripsPreviewSupport.loadingMoreViewModel())
    }
}

#Preview("全部旅程 · 分页失败") {
    NavigationStack {
        AllTripsView(previewViewModel: AllTripsPreviewSupport.loadMoreErrorViewModel())
    }
}

#Preview("全部旅程 · 加载失败") {
    NavigationStack {
        AllTripsView(previewViewModel: AllTripsPreviewSupport.errorViewModel())
    }
}
#endif
