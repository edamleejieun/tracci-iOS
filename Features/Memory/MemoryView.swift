import SwiftUI
import UIKit

private enum MemoryMetrics {
    static var tabBarClearance: CGFloat {
        AppNavigationMetrics.contentInset(for: SafeAreaMetrics.bottom)
    }
    static let launcherToStoryDelay: UInt64 = 180_000_000
}

struct MemoryView: View {
    @Bindable var pageViewModel: MemoryPageViewModel
    let userId: String?
    @Binding var isContentImmersive: Bool
    @Binding var memoryNavigationRequest: MemoryNavigationRequest?
    /// Same empty-account Demo source as Home; never enters the real memory archive.
    var demoBundle: DemoJourneyBundle? = nil
    var tripDataRevision: Int = 0
    var deletedTripId: String?
    /// When true, this tab is the active main-tab selection (used to re-fetch stage-overview).
    var isTabSelected: Bool = true
    var bottomTabBarContentInset: CGFloat = MemoryMetrics.tabBarClearance
    var onCreateTrip: () -> Void = {}
    var onOpenTripRecord: (String, TripDetailTab) -> Void = { _, _ in }
    var onRootStateChange: (Bool) -> Void = { _ in }
    var onRootScrollOffsetChange: (CGFloat) -> Void = { _ in }
    @State private var launcherTrip: Trip?
    /// Captured before `markTripViewed` so first open still shows first-visit launcher copy.
    @State private var launcherIsRevisit = false
    @State private var storyTrip: Trip?
    @State private var demoStoryViewModel: MemoryStoryViewModel?
    @State private var isLaunchingStory = false
    @State private var storyLaunchTask: Task<Void, Never>?
    @State private var toastMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var memoryLaunchNamespace

    private var isOnMemoryRoot: Bool {
        storyTrip == nil && launcherTrip == nil && !isLaunchingStory
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    AppAtmosphereBackground(style: .memory)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: AppSpacing.pageHeaderToContent) {
                            AppTabPageHeader(
                                systemImage: AppTab.export.systemImage,
                                title: AppTab.export.title,
                                subtitle: "查看旅程里的照片、日志和花费",
                                titleAccessory: {
                                    if pageViewModel.isLoadingTrips && pageViewModel.hasTrips {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(AppColors.brandPrimary)
                                    }
                                }
                            )

                            content
                        }
                        .animation(
                            AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion),
                            value: pageViewModel.isLoadingTrips && !pageViewModel.hasTrips
                        )
                        .padding(.horizontal, AppSpacing.pageX)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: RootScrollOffsetKey.self,
                                    value: -proxy.frame(in: .named("MemoryRootScroll")).minY
                                )
                            }
                        }
                    }
                    .coordinateSpace(name: "MemoryRootScroll")
                    .tracciRootScrollOffset { offset in
                        guard isOnMemoryRoot else {
                            onRootScrollOffsetChange(0)
                            return
                        }
                        onRootScrollOffsetChange(max(0, offset))
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: bottomTabBarContentInset)
                    }
                    .refreshable {
                        AppHaptics.lightImpact()
                        await pageViewModel.refreshTrips()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }

            // Dim overlay — always in hierarchy, only animates opacity (no layout reflow)
            Color.black
                .opacity(launcherTrip != nil ? 0.22 : 0)
                .ignoresSafeArea()
                .animation(AppMotion.launcherPresent, value: launcherTrip != nil)
                .zIndex(15)
                .contentShape(Rectangle())
                .allowsHitTesting(launcherTrip != nil)
                .onTapGesture {
                    AppHaptics.lightImpact()
                    dismissLauncher()
                }

            if let launcherTrip {
                MemoryStartModal(
                    trip: launcherTrip,
                    dateRangeText: pageViewModel.dateRangeText(for: launcherTrip),
                    storyViewModel: launcherStoryViewModel(for: launcherTrip),
                    coverURL: launcherCoverURL(for: launcherTrip),
                    isRevisit: launcherIsRevisit,
                    onStart: {
                        beginStoryLaunch(from: launcherTrip)
                    },
                    onClose: {
                        dismissLauncher()
                    },
                    launchNamespace: memoryLaunchNamespace
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: AppMotion.modalCloseScale, anchor: .center))
                )
                .zIndex(20)
            }

            if let storyTrip {
                storyExperience(for: storyTrip)
                    .transition(.opacity)
                    .zIndex(40)
            }
        }
        .task {
            pageViewModel.setUserScope(userId)
            await pageViewModel.refreshTrips()
        }
        .onChange(of: userId) { _, newUserId in
            pageViewModel.setUserScope(newUserId)
        }
        .onChange(of: memoryNavigationRequest) { _, _ in
            consumeMemoryNavigationRequest()
        }
        .onChange(of: demoBundle?.contentVersion) { oldVersion, newVersion in
            guard demoStoryViewModel != nil, oldVersion != newVersion else { return }
            closeDemoExperience()
        }
        .onChange(of: tripDataRevision) { _, _ in
            if let deletedTripId {
                handleDeletedTrip(deletedTripId)
            } else {
                Task { await pageViewModel.refreshTrips() }
            }
        }
        .onChange(of: isTabSelected) { _, selected in
            guard selected else { return }
            Task { await pageViewModel.refreshTrips() }
        }
        .onAppear {
            consumeMemoryNavigationRequest()
            reportRootState()
        }
        .onChange(of: storyTrip) { _, trip in
            isContentImmersive = trip != nil
            reportRootState()
        }
        .onChange(of: launcherTrip) { _, trip in
            if trip == nil, storyTrip == nil, !isLaunchingStory {
                isContentImmersive = false
            }
            reportRootState()
        }
        .onChange(of: isLaunchingStory) { _, _ in
            reportRootState()
        }
        .onDisappear {
            storyLaunchTask?.cancel()
            storyLaunchTask = nil
            isLaunchingStory = false
            isContentImmersive = false
            onRootStateChange(true)
        }
        .tracciToast(
            Binding(
                get: { toastMessage.map { TracciToastMessage.info($0) } },
                set: { newValue in
                    if newValue == nil { toastMessage = nil }
                }
            ),
            bottomPadding: AppNavigationMetrics.overlayBottomPadding(for: SafeAreaMetrics.bottom) + AppSpacing.cardSmall
        )
    }

    private func reportRootState() {
        onRootStateChange(isOnMemoryRoot)
    }

    @ViewBuilder
    private var content: some View {
        if let scene = demoMemoryScene {
            demoMemoryContent(scene)
        } else if pageViewModel.isLoadingTrips && !pageViewModel.hasTrips {
            MemoryListSkeletonView()
                .frame(maxWidth: .infinity)
                .tracciRevealTransition(reduceMotion: reduceMotion)
        } else if let error = pageViewModel.tripsError, !pageViewModel.hasTrips {
            ErrorStateView(title: "暂时没能打开回忆", message: error, retryTitle: "再试一次") {
                Task { await pageViewModel.refreshTrips() }
            }
            .tracciRevealTransition(reduceMotion: reduceMotion)
        } else if let overview = pageViewModel.stageOverview {
            switch overview.phase {
            case .noTrip:
                memoryNoTrip
            case .planning:
                memoryPlanning(overview)
            case .ongoing:
                memoryOngoing(overview)
            case .completed:
                completedMemoryList
            }
        } else if !pageViewModel.hasTrips {
            memoryNoTrip
        } else {
            completedMemoryList
        }
    }

    private var demoMemoryScene: DemoJourneyScene? {
        guard !pageViewModel.hasTrips else { return nil }
        return demoBundle?.scene(.completed)
    }

    private func demoMemoryContent(_ scene: DemoJourneyScene) -> some View {
        let coverURLs = MemoryPageViewModel
            .preferredDemoStoryCoverPhoto(in: scene.summary)?
            .storyCardURLs ?? []

        return VStack(spacing: AppSpacing.lg) {
            MemoryEmptyHeroCard()
                .fadeSlideIn(index: 0, offset: 14)

            MemoryDemoStoryEntryCard(
                trip: scene.trip,
                dateRangeText: pageViewModel.dateRangeText(for: scene.trip),
                daysText: pageViewModel.daysSummary(for: scene.trip),
                journalCount: scene.summary.stats.journalCount,
                photoCount: scene.summary.stats.photoCount,
                coverURL: coverURLs.first,
                coverFallbackURL: coverURLs.dropFirst().first,
                onOpen: {
                    openDemoStory(scene)
                },
                launchNamespace: memoryLaunchNamespace
            )
            .fadeSlideIn(index: 1, offset: 16)

            MemoryMaterialSourcesView()
                .fadeSlideIn(index: 2, offset: 14)

            // Demo card already demonstrates the finished memory — no static teaser needed.
            OutlinedButton(title: TracciEmptyTripCTA.title, systemImage: TracciEmptyTripCTA.systemImage) {
                onCreateTrip()
            }
            .fadeSlideIn(index: 3, offset: 10)
        }
    }

    private var memoryNoTrip: some View {
        VStack(spacing: AppSpacing.lg) {
            MemoryEmptyHeroCard()
                .fadeSlideIn(index: 0, offset: 14)

            MemoryMaterialSourcesView()
                .fadeSlideIn(index: 1, offset: 14)

            // Keep in sync with Stats no-trip empty CTA (same action, same weight).
            OutlinedButton(title: TracciEmptyTripCTA.title, systemImage: TracciEmptyTripCTA.systemImage) {
                onCreateTrip()
            }
            .fadeSlideIn(index: 2, offset: 10)
        }
    }

    /// Layer A (planning focus) + Layer B (completed archive).
    /// Multi planning trips: only focus is shown here; others live on the 旅程 tab.
    private func memoryPlanning(_ overview: TripStageOverview) -> some View {
        VStack(spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("出发前")
                    .font(AppTypography.sectionEyebrow)
                    .foregroundStyle(AppColors.textMuted)

                Text("先理清行程，路上再补照片和日志")
                    .font(AppTypography.dayTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(planningScene(overview))
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fadeSlideIn(index: 0, offset: 12)

            if let focus = overview.focusTrip {
                let tripId = focus.id
                MemoryPlanningFocusCard(
                    title: focus.title,
                    destinationName: focus.destinationName,
                    dateRange: pageViewModel.dateRangeText(forFocus: focus),
                    departureText: planningDepartureText(overview),
                    onOpen: {
                        onOpenTripRecord(tripId, .itinerary)
                    }
                )
                .fadeSlideIn(index: 1, offset: 14)
            } else if let trip = pageViewModel.selectedTrip {
                MemoryPlanningFocusCard(
                    title: trip.title,
                    destinationName: trip.destinationName,
                    dateRange: pageViewModel.dateRangeText(for: trip),
                    departureText: planningDepartureText(overview),
                    onOpen: {
                        onOpenTripRecord(trip.id, .itinerary)
                    }
                )
                .fadeSlideIn(index: 1, offset: 14)
            }

            completedArchiveSection(animationBaseIndex: 2)
        }
    }

    /// Layer A (ongoing light surface) + Layer B (completed archive).
    /// Materials & soft record CTA only — Insight owns today's rhythm.
    private func memoryOngoing(_ overview: TripStageOverview) -> some View {
        VStack(spacing: AppSpacing.lg) {
            MemoryOngoingStatusStrip(overview: overview)
                .fadeSlideIn(index: 0, offset: 12)

            MemoryEncourageCard(
                insight: "不用一次写全，想起来再记也很好",
                scene: ongoingScene(overview),
                meta: ongoingMeta(overview)
            )
            .fadeSlideIn(index: 1, offset: 14)

            // Only when counts > 0 — never show zero chips.
            if MemoryMaterialProgressCard.hasMaterials(overview.memory) {
                MemoryMaterialProgressCard(memory: overview.memory)
                    .fadeSlideIn(index: 2, offset: 12)
            }

            // Materials strip is bound to focus/ongoing trip only — not archive story selection.
            if let focusId = overview.focusTrip?.id,
               let materialsVM = pageViewModel.materialsViewModel,
               materialsVM.tripId == focusId,
               let summary = materialsVM.summary,
               MemoryMaterialFlow.hasVisibleContent(summary) {
                MemoryMaterialFlow(
                    summary: summary,
                    onToggleFeatured: overview.permissions?.canFeaturePhoto == true ? { photo in
                        Task {
                            let success = await pageViewModel.toggleFeaturedPhoto(photo)
                            if !success { toastMessage = pageViewModel.tripsError }
                        }
                    } : nil
                )
                .fadeSlideIn(index: 3, offset: 12)
            } else if let focusId = overview.focusTrip?.id,
                      pageViewModel.materialsViewModel?.tripId == focusId,
                      pageViewModel.materialsViewModel?.isLoading == true,
                      MemoryMaterialProgressCard.hasMaterials(overview.memory) {
                // Skeleton only when we already know materials exist (avoid empty-state noise).
                PhotoStripSkeletonView()
                    .fadeSlideIn(index: 3, offset: 10)
            }

            if overview.permissions?.canAddJournal == true,
               let tripId = overview.focusTrip?.id {
                Button {
                    AppHaptics.lightImpact()
                    onOpenTripRecord(tripId, .journal)
                } label: {
                    memorySoftActionLabel("写一句日志", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .accessibilityHint("去旅程里写一条日志")
                .fadeSlideIn(index: 4, offset: 10)
            }

            completedArchiveSection(animationBaseIndex: 5)
        }
    }

    /// Pure completed phase — lightweight entry list opens Story (no cover, no list metrics).
    private var completedMemoryList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if pageViewModel.completedTrips.isEmpty {
                AppElevationCard(level: .l1, role: .archive, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                        Text("还没有已结束的旅程")
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("旅程结束后会出现在这里。也可以先去看看准备中或进行中的旅程。")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineSpacing(4)
                        if let trip = pageViewModel.selectedTrip ?? pageViewModel.trips.first {
                            Button {
                                onOpenTripRecord(trip.id, trip.effectiveStatus == .planning ? .itinerary : .journal)
                            } label: {
                                memorySoftActionLabel(
                                    trip.effectiveStatus == .planning ? "查看旅程安排" : "继续记录旅程",
                                    systemImage: trip.effectiveStatus == .planning ? "arrow.right" : "square.and.pencil"
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                }
            } else {
                completedArchiveHeader
                completedArchiveList(animationBaseIndex: 0)
            }
        }
    }

    /// Layer B — always available when there are completed trips (including during planning/ongoing).
    @ViewBuilder
    private func completedArchiveSection(animationBaseIndex: Int) -> some View {
        if !pageViewModel.completedTrips.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                completedArchiveHeader
                    .padding(.top, AppSpacing.xs)
                completedArchiveList(animationBaseIndex: animationBaseIndex)
            }
            .fadeSlideIn(index: animationBaseIndex, offset: 12)
        }
    }

    private var completedArchiveHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Text("已完成的旅程")
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textMuted)
            Text("点开即可查看照片、日志和花费")
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func completedArchiveList(animationBaseIndex: Int) -> some View {
        MemoryTripList(
            trips: pageViewModel.completedTrips,
            dateRangeText: pageViewModel.dateRangeText(for:),
            daysText: pageViewModel.daysSummary(for:),
            isNew: pageViewModel.isTripNew(_:),
            onOpenReport: openTripFromList,
            launchNamespace: memoryLaunchNamespace
        )
        .fadeSlideIn(index: animationBaseIndex + 1, offset: 10)
    }

    /// Memory scene — tool-first, lightly warm; no AI-style metaphors.
    private func ongoingScene(_ overview: TripStageOverview) -> String {
        let memory = overview.memory
        let journals = memory?.journalCount ?? 0
        let photos = memory?.photoCount ?? 0
        if journals == 0 && photos == 0 {
            return "想拍就拍，想写就写。有内容后会出现在这里。"
        }
        if photos == 0 {
            return "已经有日志了。有空也可以再补几张照片。"
        }
        if journals == 0 {
            return "已经有照片了。想写两句当时的感受，随时可以。"
        }
        return "照片和日志都有一些了。特别想留的，可以点亮星标。"
    }

    private func ongoingMeta(_ overview: TripStageOverview) -> String? {
        var parts: [String] = []
        if let name = overview.focusTrip?.destinationName, !name.isEmpty {
            parts.append(name)
        }
        if let today = overview.ongoing?.today {
            parts.append(Self.shortMonthDay(from: today.date) ?? today.date)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func planningDepartureText(_ overview: TripStageOverview) -> String {
        guard let days = overview.planning?.departureDays else { return "待出发" }
        if days <= 0 { return "今天出发" }
        return "\(days) 天后出发"
    }

    private func planningScene(_ overview: TripStageOverview) -> String {
        guard let planning = overview.planning else {
            return "出发后，照片、日志和花费会出现在这里。"
        }

        switch planning.density.level {
        case "EMPTY":
            return "不用一次排满。先加上几个最想去的地方就好。"
        case "LIGHT":
            return "行程还不算多。出发后，照片和日志会逐步出现在这里。"
        case "MODERATE":
            return "行程已经有个大概了。路上随手记一点，回来也好查。"
        case "DENSE":
            return "行程排得挺满。路上有空就记一句，不必勉强。"
        default:
            return "出发后，照片、日志和花费会出现在这里。"
        }
    }

    private static func shortMonthDay(from dateString: String) -> String? {
        guard let date = TripDateFormatting.date(from: dateString) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func memorySoftActionLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: systemImage)
        }
        .font(AppTypography.buttonTitle)
        .foregroundStyle(AppColors.brandPrimary)
        .padding(.horizontal, AppSpacing.card)
        .frame(height: 52)
        .background(
            AppColors.brandPrimaryBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
        )
    }

    private func openTripFromList(_ trip: Trip) {
        guard canOpenStory(for: trip) else {
            toastMessage = "旅程结束后，就可以在这里回看了"
            return
        }

        // Product: always present launcher before full-screen story (first visit and revisit).
        let isRevisit = !pageViewModel.isTripNew(trip.id)
        presentLauncher(for: trip, isRevisit: isRevisit)
        pageViewModel.markTripViewed(trip.id)
    }

    private func openDemoStory(_ scene: DemoJourneyScene) {
        Task { @MainActor in
            let viewModel = await pageViewModel.makeDemoStoryViewModel(for: scene)
            guard demoMemoryScene?.trip.id == scene.trip.id else { return }
            demoStoryViewModel = viewModel
            storyLaunchTask?.cancel()
            isLaunchingStory = false
            isContentImmersive = false
            launcherIsRevisit = false
            withAnimation(AppMotion.launcherPresent) {
                launcherTrip = scene.trip
            }
        }
    }

    private func launcherStoryViewModel(for trip: Trip) -> MemoryStoryViewModel? {
        if let demoStoryViewModel, demoStoryViewModel.tripId == trip.id {
            return demoStoryViewModel
        }
        guard pageViewModel.selectedTripId == trip.id else { return nil }
        return pageViewModel.storyViewModel
    }

    private func launcherCoverURL(for trip: Trip) -> URL? {
        guard demoStoryViewModel?.tripId == trip.id else { return nil }
        return demoStoryViewModel?.preferredCoverStoryCardURL
    }

    private func presentLauncher(for trip: Trip, isRevisit: Bool) {
        guard canOpenStory(for: trip) else {
            toastMessage = "旅程结束后，就可以在这里回看了"
            return
        }

        storyLaunchTask?.cancel()
        isLaunchingStory = false
        isContentImmersive = false
        launcherIsRevisit = isRevisit
        // Story selection must not replace ongoing materials strip (materialsViewModel is focus-bound).
        pageViewModel.selectTrip(trip, force: true)
        withAnimation(AppMotion.launcherPresent) {
            launcherTrip = trip
        }
        Task {
            await pageViewModel.storyViewModel?.loadIfNeeded()
        }
    }

    private func consumeMemoryNavigationRequest() {
        guard let request = memoryNavigationRequest else { return }
        memoryNavigationRequest = nil
        Task {
            await pageViewModel.refreshTrips()
            guard let trip = pageViewModel.trip(id: request.tripId) else { return }
            openTripFromList(trip)
        }
    }

    private func handleDeletedTrip(_ tripId: String) {
        pageViewModel.removeTrip(id: tripId)

        if launcherTrip?.id == tripId {
            dismissLauncher()
        }

        if storyTrip?.id == tripId {
            storyLaunchTask?.cancel()
            storyLaunchTask = nil
            storyTrip = nil
            isLaunchingStory = false
            isContentImmersive = false
            reportRootState()
        }
    }

    @ViewBuilder
    private func storyExperience(for trip: Trip) -> some View {
        if let storyVM = demoStoryViewModel, storyVM.tripId == trip.id {
            MemoryStoryContainerView(
                trip: trip,
                dateRangeText: pageViewModel.dateRangeText(for: trip),
                viewModel: storyVM,
                onClose: { closeStory() },
                onSaveToPhotoLibrary: {
                    toastMessage = DemoReadOnlyCopy.exportUnavailable
                },
                onShareFailed: { message in
                    toastMessage = message
                },
                allowsExportActions: false
            )
        } else if let storyVM = pageViewModel.storyViewModel, pageViewModel.selectedTripId == trip.id {
            MemoryStoryContainerView(
                trip: trip,
                dateRangeText: pageViewModel.dateRangeText(for: trip),
                viewModel: storyVM,
                onClose: { closeStory() },
                onSaveToPhotoLibrary: {
                    Task {
                        let success = await storyVM.saveReportImage()
                        toastMessage = success ? "回顾卡片已保存到相册" : (storyVM.errorMessage ?? "保存失败")
                    }
                },
                onShareFailed: { message in
                    toastMessage = message
                }
            )
        } else {
            Color.black.ignoresSafeArea()
                .task {
                    pageViewModel.selectTrip(trip)
                }
        }
    }

    private func dismissLauncher() {
        let isDismissingDemo = launcherTrip?.id == demoStoryViewModel?.tripId
        storyLaunchTask?.cancel()
        storyLaunchTask = nil
        isLaunchingStory = false

        withAnimation(AppMotion.launcherDismiss) {
            launcherTrip = nil
        }
        launcherIsRevisit = false
        if isDismissingDemo {
            demoStoryViewModel = nil
        }
        isContentImmersive = false
    }

    private func beginStoryLaunch(from trip: Trip) {
        guard canOpenStory(for: trip) else {
            toastMessage = "旅程结束后，就可以在这里回看了"
            return
        }

        storyLaunchTask?.cancel()
        isLaunchingStory = true
        if demoStoryViewModel?.tripId == trip.id {
            demoStoryViewModel?.resetPlayback()
        } else {
            pageViewModel.selectTrip(trip)
            pageViewModel.storyViewModel?.resetPlayback()
        }
        isContentImmersive = false

        withAnimation(AppMotion.launcherDismiss) {
            launcherTrip = nil
        }
        launcherIsRevisit = false

        storyLaunchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: MemoryMetrics.launcherToStoryDelay)
            guard !Task.isCancelled else { return }

            isContentImmersive = true
            withAnimation(AppMotion.storyEntry) {
                storyTrip = trip
            }
            isLaunchingStory = false
            storyLaunchTask = nil
        }
    }

    private func closeStory() {
        storyLaunchTask?.cancel()
        storyLaunchTask = nil
        isLaunchingStory = false
        withAnimation(.easeInOut(duration: 0.18)) {
            storyTrip = nil
        }
        demoStoryViewModel = nil
        isContentImmersive = false
    }

    private func closeDemoExperience() {
        storyLaunchTask?.cancel()
        storyLaunchTask = nil
        isLaunchingStory = false
        withAnimation(AppMotion.launcherDismiss) {
            launcherTrip = nil
            storyTrip = nil
        }
        launcherIsRevisit = false
        demoStoryViewModel = nil
        isContentImmersive = false
    }

    private func canOpenStory(for trip: Trip) -> Bool {
        trip.effectiveStatus == .completed
    }
}


struct MemoryShareCardView: View {
    let summary: TripSummaryResponse
    let image: UIImage?

    var body: some View {
        MemoryPosterTemplate(summary: summary, coverImage: image)
    }
}

#if DEBUG
#Preview("Memory - Empty") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.emptyPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Sparse List") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.sparseListPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Ready List") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.readyListPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Planning") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.planningPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Ongoing Viewer") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.ongoingViewerPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Ongoing With Materials") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.ongoingReadyPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Trips Error") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.tripsErrorPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Summary Error") {
    MemoryView(
        pageViewModel: MemoryPreviewFixtures.storyErrorPageViewModel(),
        userId: nil,
        isContentImmersive: .constant(false),
        memoryNavigationRequest: .constant(nil)
    )
}

#Preview("Memory - Launcher Sparse") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        MemoryStartModal(
            trip: MemoryPreviewFixtures.sparseTrip,
            dateRangeText: "2026.03.08 - 2026.03.09",
            storyViewModel: MemoryPreviewFixtures.sparseStoryViewModel(),
            isRevisit: false,
            onStart: {},
            onClose: {}
        )
        .padding(.horizontal, AppSpacing.pageX)
    }
}

#Preview("Memory - Story Stats Sparse") {
    StoryPageView(
        page: .stats,
        summary: MemoryPreviewFixtures.sparseSummary,
        image: nil,
        loadedImages: [],
        fullestDay: nil,
        currentPageIndex: 1,
        totalPageCount: 3
    )
    .frame(width: 390, height: 844)
}

#Preview("Memory - Story Stats Ready") {
    StoryPageView(
        page: .stats,
        summary: MemoryPreviewFixtures.readySummary,
        image: nil,
        loadedImages: [],
        fullestDay: MemoryPreviewFixtures.readySummary.dailyTimeline.first,
        currentPageIndex: 1,
        totalPageCount: 7
    )
    .frame(width: 390, height: 844)
}
#endif
