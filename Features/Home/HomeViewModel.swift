import Foundation
import Observation
import TracciNetworking

@MainActor
@Observable
final class HomeViewModel {
    enum ViewState: Equatable {
        case idle
        case loading
        case empty
        case loaded
        case error(String)
    }

    /// Independent of real trip list state. Demo never merges into `trips` / `total`.
    enum DemoLoadState: Equatable {
        case idle
        case loading
        case available
        case unavailable
    }

    private let tripService: TripService
    private let demoJourneyService: (any DemoJourneyLoading)?
    private let tripPageLoader: (_ page: Int, _ pageSize: Int) async throws -> PageResponse<Trip>

    private(set) var state: ViewState = .idle
    private(set) var trips: [Trip] = []
    private(set) var total = 0
    private(set) var isRefreshing = false

    /// Transient id of a just-created trip — drives the milestone entrance on its
    /// home card (G3.2). Presentation-only; cleared after the entrance window so
    /// the card never re-animates on scroll reappear.
    private(set) var newlyCreatedTripId: String?

    private(set) var demoLoadState: DemoLoadState = .idle
    private(set) var demoBundle: DemoJourneyBundle?

    var searchQuery: String = ""

    private var hasLoaded = false
    private var allTripsViewModel: AllTripsViewModel?
    private var demoLoadGeneration = 0

    /// Signed-in user id — keys the one-time demo-graduation marker per account.
    var currentUserId: String?

    private static let graduationKeyPrefix = "tracci.demo.graduated.v1"

    private var graduationKey: String? {
        guard let currentUserId, !currentUserId.isEmpty else { return nil }
        return "\(Self.graduationKeyPrefix).\(currentUserId)"
    }

    /// True once this account has ever had a real journey. Demo is a first-trip
    /// product tour: per 跨端技术方案「创建/加入首段真实旅程后资格失效」, this marker is
    /// permanent so the demo never returns after a trip is created then deleted.
    var hasGraduatedFromDemo: Bool {
        guard let key = graduationKey else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Persists the marker when a real trip list is observed non-empty.
    /// Non-sensitive product flag → `UserDefaults` is acceptable (tokens stay in Keychain).
    private func markGraduatedFromDemo() {
        guard let key = graduationKey else { return }
        UserDefaults.standard.set(true, forKey: key)
    }

    private var filteredTrips: [Trip] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trips }
        let query = trimmed.lowercased()
        return trips.filter { trip in
            trip.title.lowercased().contains(query)
                || (trip.destinationName?.lowercased().contains(query) ?? false)
        }
    }

    /// Home featured surface: ongoing first, else the next planning trip (“下一段”).
    /// Completed-only lists stay list-first (no archive hero).
    var featuredTrip: Trip? {
        if let ongoing = filteredTrips.first(where: { $0.effectiveStatus == .ongoing }) {
            return ongoing
        }

        return nextPlanningTrip
    }

    var regularTrips: [Trip] {
        filteredTrips.filter { $0.id != featuredTrip?.id }
    }

    /// Server total minus the featured surface. Search results use their local filtered count.
    var regularTripTotal: Int {
        if isSearching {
            return regularTrips.count
        }
        return max(0, total - (featuredTrip == nil ? 0 : 1))
    }

    /// Phase-grouped regular trips for the home list. Empty groups are kept so
    /// the caller can decide section visibility; sorting follows the user's
    /// journey arc: 进行中 → 即将出发 → 已结束.
    ///
    /// - ongoing: non-featured ongoing journeys (rare; featured usually absorbs
    ///   the only ongoing trip, but multiple ongoing trips are possible)
    /// - planning: non-featured planning journeys, sorted by nearest start date
    /// - completed: finished journeys, sorted by most recent end date
    struct GroupedRegularTrips: Equatable {
        var ongoing: [Trip] = []
        var planning: [Trip] = []
        var completed: [Trip] = []

        var isEmpty: Bool {
            ongoing.isEmpty && planning.isEmpty && completed.isEmpty
        }
    }

    /// The home keeps a compact cross-phase preview; the full list owns deeper browsing.
    var visibleGroupedRegularTrips: GroupedRegularTrips {
        let groups = groupedRegularTrips
        var visible = GroupedRegularTrips()
        var remaining = HomeJourneyListPolicy.visibleRegularTripLimit

        visible.ongoing = Array(groups.ongoing.prefix(remaining))
        remaining -= visible.ongoing.count

        visible.planning = Array(groups.planning.prefix(remaining))
        remaining -= visible.planning.count

        visible.completed = Array(groups.completed.prefix(remaining))
        return visible
    }

    /// A single global entry replaces per-phase overflow links.
    var showsAllTripsEntry: Bool {
        regularTripTotal > HomeJourneyListPolicy.visibleRegularTripLimit
    }

    var groupedRegularTrips: GroupedRegularTrips {
        var groups = GroupedRegularTrips()
        let featuredId = featuredTrip?.id

        for trip in regularTrips where trip.id != featuredId {
            switch trip.effectiveStatus {
            case .ongoing:
                groups.ongoing.append(trip)
            case .planning:
                groups.planning.append(trip)
            case .completed:
                groups.completed.append(trip)
            case .unknown:
                groups.planning.append(trip)
            }
        }

        // Planning: nearest departure first.
        groups.planning.sort { lhs, rhs in
            let lhsDays = daysUntilDeparture(for: lhs) ?? Int.max
            let rhsDays = daysUntilDeparture(for: rhs) ?? Int.max
            if lhsDays != rhsDays { return lhsDays < rhsDays }
            return lhs.title < rhs.title
        }

        // Completed: most recent first (by start date desc).
        groups.completed.sort { lhs, rhs in
            let lhsDate = Self.tripDate(from: lhs.startDate) ?? .distantPast
            let rhsDate = Self.tripDate(from: rhs.startDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        return groups
    }

    /// The next planning journey is the nearest dated future trip, independent of browse-list sorting.
    private var nextPlanningTrip: Trip? {
        let planningTrips = filteredTrips
            .enumerated()
            .filter { $0.element.effectiveStatus == .planning }

        return planningTrips.min { lhs, rhs in
            let lhsDate = Self.tripDate(from: lhs.element.startDate)
            let rhsDate = Self.tripDate(from: rhs.element.startDate)

            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.offset < rhs.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }?.element
    }

    /// Masthead companion when there is no featured surface to carry narrative.
    var mastheadCompanionText: String {
        if trips.contains(where: { $0.effectiveStatus == .completed }) {
            return "以前的旅程都在这里，想出发时再创建一段"
        }
        return "还没有旅程，想出发时就从这里开始"
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True only for real empty home (not searching). Demo never appears in search / error / loaded.
    var showsDemoJourney: Bool {
        !isSearching && displayableEmptyStateDemoBundle != nil
    }

    /// Card / navigation payload when `showsDemoJourney` is true.
    var displayableDemoBundle: DemoJourneyBundle? {
        showsDemoJourney ? demoBundle : nil
    }

    /// Shared Demo payload for other root tabs, such as Memory.
    /// Search is a Home-only presentation concern; real-trip eligibility is shared.
    var displayableEmptyStateDemoBundle: DemoJourneyBundle? {
        guard state == .empty,
              total == 0,
              trips.isEmpty,
              demoLoadState == .available,
              demoBundle?.isDisplayable == true,
              !hasGraduatedFromDemo
        else { return nil }
        return demoBundle
    }

    /// Pure display policy for unit tests and call sites.
    static func shouldDisplayDemo(
        viewState: ViewState,
        isSearching: Bool,
        demoLoadState: DemoLoadState,
        bundleIsDisplayable: Bool,
        hasGraduated: Bool = false
    ) -> Bool {
        viewState == .empty
            && !isSearching
            && demoLoadState == .available
            && bundleIsDisplayable
            && !hasGraduated
    }

    init(tripService: TripService, demoJourneyService: (any DemoJourneyLoading)? = nil) {
        self.tripService = tripService
        self.demoJourneyService = demoJourneyService
        self.tripPageLoader = { page, pageSize in
            try await tripService.listTrips(page: page, pageSize: pageSize)
        }
    }

    // MARK: - Test seams (production callers use normal load paths)

    #if DEBUG
    /// Injects the real-list loader so refresh continuity can be tested without network traffic.
    init(
        tripService: TripService,
        demoJourneyService: (any DemoJourneyLoading)? = nil,
        tripPageLoader: @escaping (_ page: Int, _ pageSize: Int) async throws -> PageResponse<Trip>
    ) {
        self.tripService = tripService
        self.demoJourneyService = demoJourneyService
        self.tripPageLoader = tripPageLoader
    }

    /// Applies a demo load outcome without network. Used by unit tests and offline tooling.
    func applyDemoLoadResultForTesting(_ result: DemoJourneyService.LoadResult) {
        switch result {
        case let .displayable(bundle):
            demoBundle = bundle
            demoLoadState = .available
        case .featureOff, .undisplayable, .failure:
            demoBundle = nil
            demoLoadState = .unavailable
        }
    }

    /// Sets real list state without calling `TripService`. Used by unit tests.
    func applyTripsStateForTesting(trips: [Trip], total: Int, state: ViewState) {
        self.trips = trips
        self.total = total
        self.state = state
        hasLoaded = true
        if total > 0 || !trips.isEmpty {
            markGraduatedFromDemo()
            clearDemoPresentation()
        }
    }
    #endif

    func allTripsListViewModel() -> AllTripsViewModel {
        if let allTripsViewModel {
            return allTripsViewModel
        }

        let viewModel = AllTripsViewModel(tripService: tripService)
        allTripsViewModel = viewModel
        return viewModel
    }

    func loadTripsIfNeeded() async {
        guard !hasLoaded else { return }
        await loadTrips()
    }

    func loadTrips(page: Int = 1, pageSize: Int = 20) async {
        state = .loading
        await fetchTrips(page: page, pageSize: pageSize)
    }

    func refreshTrips() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetchTrips(page: 1, pageSize: 20, keepsExistingContent: true)
        allTripsViewModel?.invalidateCache()
    }

    func upsertTrip(_ trip: Trip) {
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        } else {
            trips.insert(trip, at: 0)
            total += 1
        }
        trips = TripListSorting.sorted(trips)
        hasLoaded = true
        state = trips.isEmpty ? .empty : .loaded
        reevaluateDemoAfterTripListChange()
    }

    /// Marks a freshly created trip so its home card plays the milestone entrance
    /// (G3.2). Auto-clears after the entrance window; presentation-only state.
    func markNewlyCreated(tripId: String) {
        newlyCreatedTripId = tripId
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppMotion.milestoneEntranceWindow))
            guard let self, self.newlyCreatedTripId == tripId else { return }
            self.newlyCreatedTripId = nil
        }
    }

    /// Updates a trip already present on home — does not insert or change `total`.
    func updateTripIfExists(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        trips = TripListSorting.sorted(trips)
        state = trips.isEmpty ? .empty : .loaded
    }

    func removeTrip(id: String) {
        trips.removeAll { $0.id == id }
        total = max(0, total - 1)
        state = trips.isEmpty ? .empty : .loaded
        allTripsViewModel?.invalidateCache()
        reevaluateDemoAfterTripListChange()
    }

    /// Scene payload for Demo navigation. Returns `nil` if demo is not displayable.
    func demoScene(for kind: DemoJourneySceneKind) -> DemoJourneyScene? {
        displayableDemoBundle?.scene(kind) ?? demoBundle?.scene(kind)
    }

    func demoJourneyContext(scene: DemoJourneySceneKind) -> JourneyContext? {
        guard let bundle = demoBundle, bundle.isDisplayable else { return nil }
        return .demo(bundle: bundle, scene: scene)
    }

    func dateRangeText(for trip: Trip) -> String {
        let start = Self.displayDate(from: trip.startDate)
        let end = Self.displayDate(from: trip.endDate)

        switch (start.isEmpty, end.isEmpty) {
        case (false, false):
            return "\(start) - \(end)"
        case (false, true):
            return start
        case (true, false):
            return end
        case (true, true):
            return "日期待定"
        }
    }

    func totalDaysText(for trip: Trip) -> String {
        if let totalDays = trip.totalDays, totalDays > 0 {
            return "\(totalDays) 天"
        }

        guard
            let startDate = Self.tripDate(from: trip.startDate),
            let endDate = Self.tripDate(from: trip.endDate),
            let days = TracciDateContext.inclusiveDayCount(start: startDate, end: endDate)
        else {
            return "天数待定"
        }

        return "\(days) 天"
    }

    func expenseText(for trip: Trip) -> String {
        guard let totalCnyString = trip.totalCny, !totalCnyString.isEmpty else {
            return "¥0"
        }

        let totalCny = Double(totalCnyString) ?? 0
        guard totalCny > 0 else { return "¥0" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = totalCny.rounded() == totalCny ? 0 : 2
        formatter.minimumFractionDigits = 0

        return formatter.string(from: NSNumber(value: totalCny)) ?? "¥\(Int(totalCny))"
    }

    func destinationText(for trip: Trip) -> String {
        guard let destination = trip.destinationName, !destination.isEmpty else {
            return "未设置目的地"
        }
        return destination
    }

    func nodeCountText(for trip: Trip) -> String {
        "\(trip.nodeCount ?? 0) 个行程"
    }

    func journalCountText(for trip: Trip) -> String {
        "\(trip.journalCount ?? 0) 条日志"
    }

    func expenseCountText(for trip: Trip) -> String {
        if let expenseCount = trip.expenseCount {
            return "\(expenseCount) 笔开支"
        }

        return expenseText(for: trip)
    }

    /// Compact factual line for remaining-journey rows. Zero counts stay quiet instead of
    /// turning the archive into a dashboard of empty metrics.
    func archiveMetaTexts(for trip: Trip) -> [String] {
        var items = [totalDaysText(for: trip)]
        if let nodeCount = trip.nodeCount, nodeCount > 0 {
            items.append("\(nodeCount) 个行程")
        }
        if let journalCount = trip.journalCount, journalCount > 0 {
            items.append("\(journalCount) 条日志")
        }
        return items
    }

    /// Phase-aware meta line for `TripCard` row 3. Complements `phaseSubtitleText`
    /// (row 2) without repeating the same facts. Zero values stay hidden.
    ///
    /// - ongoing: "X 个行程 · X 条日志" (day count already in subtitle)
    /// - planning: "X 个行程" (departure count already in subtitle)
    /// - completed: empty (days + journals already in subtitle)
    /// - unknown: legacy archive meta
    func phaseMetaTexts(for trip: Trip) -> [String] {
        switch trip.effectiveStatus {
        case .ongoing:
            var items: [String] = []
            if let nodeCount = trip.nodeCount, nodeCount > 0 {
                items.append("\(nodeCount) 个行程")
            }
            if let journalCount = trip.journalCount, journalCount > 0 {
                items.append("\(journalCount) 条日志")
            }
            return items
        case .planning:
            var items: [String] = []
            if let nodeCount = trip.nodeCount, nodeCount > 0 {
                items.append("\(nodeCount) 个行程")
            }
            return items
        case .completed:
            // Subtitle already carries "X 天 · Y 篇日志"; meta line stays empty.
            return []
        case .unknown:
            return archiveMetaTexts(for: trip)
        }
    }

    /// Progress for the no-cover Creek Stage. It is derived entirely from existing trip dates
    /// and status; no additional backend field is required.
    func narrativeProgress(for trip: Trip) -> CGFloat {
        switch trip.effectiveStatus {
        case .planning:
            return 0.04
        case .ongoing:
            guard let pair = currentDayPair(for: trip), pair.total > 0 else { return 0.08 }
            return min(1, max(0.02, CGFloat(pair.current) / CGFloat(pair.total)))
        case .completed:
            return 1
        case .unknown:
            return 0.08
        }
    }

    func featuredCompanionText(for trip: Trip) -> String {
        let place = Self.compactPlaceName(trip.destinationName) ?? trip.title
        switch trip.effectiveStatus {
        case .ongoing:
            if let pair = currentDayPair(for: trip) {
                return "今天是\(place)的第 \(pair.current) 天，有空可以记一下今天。"
            }
            return "今天还在\(place)，有空可以写点日志。"
        case .planning:
            return "日期和目的地已经记好，接下来可以继续安排行程。"
        case .completed:
            return "这段旅程已经结束，照片和记录都在这里。"
        case .unknown:
            return "打开旅程，查看已有安排和记录。"
        }
    }

    func currentDayText(for trip: Trip) -> String? {
        guard let pair = currentDayPair(for: trip) else { return nil }
        // Kept for list/a11y; featured chrome prefers `featuredDayBadgeText`.
        return "第 \(pair.current) / \(pair.total) 天"
    }

    /// Chinese day badge for featured media/stage — matches UI language.
    func featuredDayBadgeText(for trip: Trip) -> String? {
        guard let pair = currentDayPair(for: trip) else { return nil }
        return "第 \(pair.current) 天"
    }

    /// Phase-aware status word for the featured hero chip. Replaces the generic
    /// `effectiveStatus.label` with a more concrete "where am I now" cue:
    /// ongoing → "在{目的地}", planning → "待出发", completed → "已结束".
    /// Falls back to `effectiveStatus.label` for `.unknown`.
    func featuredStatusWord(for trip: Trip) -> String {
        switch trip.effectiveStatus {
        case .ongoing:
            let place = Self.compactPlaceName(trip.destinationName) ?? trip.title
            return "在\(place)"
        case .planning:
            return "待出发"
        case .completed:
            return "已结束"
        case .unknown:
            return trip.effectiveStatus.label
        }
    }

    /// Phase-aware single-line subtitle for `TripCard` rows. Replaces the
    /// uniform "目的地 · 日期范围" line with stage-specific facts:
    /// - ongoing → "今日第 N 天 · {目的地}" (or "第 1 天 · {目的地}" on day 1)
    /// - planning → "还有 X 天出发" / "出发时间 待定"
    /// - completed → "X 天 · Y 篇日志" (zero values hidden)
    /// - unknown → destination + date range (legacy fallback)
    func phaseSubtitleText(for trip: Trip) -> String {
        switch trip.effectiveStatus {
        case .ongoing:
            let place = Self.compactPlaceName(trip.destinationName) ?? trip.title
            if let pair = currentDayPair(for: trip) {
                return "今日第 \(pair.current) 天 · \(place)"
            }
            return "第 1 天 · \(place)"
        case .planning:
            if let days = daysUntilDeparture(for: trip), days > 0 {
                return "还有 \(days) 天出发"
            }
            if let days = daysUntilDeparture(for: trip), days == 0 {
                return "今天出发"
            }
            return "出发时间 待定"
        case .completed:
            return archiveSummaryText(for: trip)
        case .unknown:
            return "\(destinationText(for: trip)) · \(dateRangeText(for: trip))"
        }
    }

    /// Compact archive summary: "X 天 · Y 篇日志". Zero journal count stays
    /// quiet so finished journeys never read as an empty dashboard.
    func archiveSummaryText(for trip: Trip) -> String {
        var parts: [String] = []
        let daysText = totalDaysText(for: trip)
        if daysText != "天数待定" {
            parts.append(daysText)
        }
        if let journalCount = trip.journalCount, journalCount > 0 {
            parts.append("\(journalCount) 篇日志")
        }
        if parts.isEmpty {
            return dateRangeText(for: trip)
        }
        return parts.joined(separator: " · ")
    }

    /// Days from today to trip start. Negative if already departed.
    /// Returns nil when start date is missing or unparseable.
    func daysUntilDeparture(for trip: Trip) -> Int? {
        guard let startDate = Self.tripDate(from: trip.startDate) else { return nil }
        let today = TracciDateContext.today()
        return TracciDateContext.calendar.dateComponents([.day], from: today, to: startDate).day
    }

    /// Remaining days text for the ongoing progress creek. Returns nil when
    /// the journey has no computable day pair (e.g. unknown total days).
    func remainingDaysText(for trip: Trip) -> String? {
        guard let pair = currentDayPair(for: trip) else { return nil }
        let remaining = pair.total - pair.current
        if remaining <= 0 { return nil }
        return "还剩 \(remaining) 天"
    }

    private func currentDayPair(for trip: Trip) -> (current: Int, total: Int)? {
        guard
            trip.effectiveStatus == .ongoing,
            let startDate = Self.tripDate(from: trip.startDate),
            let totalDays = trip.totalDays ?? inferredTotalDays(for: trip)
        else {
            return nil
        }

        let today = TracciDateContext.today()
        let dayOffset = TracciDateContext.calendar.dateComponents([.day], from: startDate, to: today).day ?? 0
        let currentDay = min(max(dayOffset + 1, 1), totalDays)
        return (currentDay, totalDays)
    }

    private func fetchTrips(page: Int, pageSize: Int, keepsExistingContent: Bool = false) async {
        do {
            let response = try await tripPageLoader(page, pageSize)
            trips = TripListSorting.sorted(response.list)
            total = response.total
            hasLoaded = true
            if response.total == 0 && trips.isEmpty {
                state = .empty
                // Real empty first; demo is additive and may fail silently.
                await loadDemoIfEligible(preservingCurrentBundleOnFailure: keepsExistingContent)
            } else {
                markGraduatedFromDemo()
                clearDemoPresentation()
                state = .loaded
            }
        } catch {
            hasLoaded = true
            if keepsExistingContent, canRetainCurrentDemoPresentation {
                // Pull-to-refresh must not remove a previously confirmed Demo merely because
                // the real-list revalidation failed transiently.
                state = .empty
                return
            }
            // Initial loads still surface the real-list error; loaded real content is retained.
            clearDemoPresentation()
            if keepsExistingContent, !trips.isEmpty {
                state = .loaded
            } else {
                state = .error(error.localizedDescription)
            }
        }
    }

    private func reevaluateDemoAfterTripListChange() {
        if total > 0 || !trips.isEmpty {
            markGraduatedFromDemo()
            clearDemoPresentation()
            return
        }
        state = .empty
        Task { await loadDemoIfEligible() }
    }

    private func clearDemoPresentation() {
        demoLoadGeneration += 1
        demoBundle = nil
        demoLoadState = .unavailable
    }

    /// Loads Demo only after a successful real empty list. Initial failures stay silent;
    /// pull-to-refresh may retain the last validated Bundle.
    private func loadDemoIfEligible(preservingCurrentBundleOnFailure: Bool = false) async {
        guard let demoJourneyService else {
            demoBundle = nil
            demoLoadState = .unavailable
            return
        }

        guard state == .empty, total == 0, trips.isEmpty, !hasGraduatedFromDemo else {
            clearDemoPresentation()
            return
        }

        demoLoadGeneration += 1
        let generation = demoLoadGeneration
        let retainedBundle = preservingCurrentBundleOnFailure && canRetainCurrentDemoPresentation
            ? demoBundle
            : nil
        if retainedBundle == nil {
            demoLoadState = .loading
        }

        let result = await demoJourneyService.loadDisplayableBundle()

        guard generation == demoLoadGeneration else { return }
        guard state == .empty, total == 0, trips.isEmpty else {
            clearDemoPresentation()
            return
        }

        switch result {
        case let .displayable(bundle):
            demoBundle = bundle
            demoLoadState = .available
        case .failure:
            if let retainedBundle {
                // Keep the last validated Demo during a transient pull-to-refresh failure.
                demoBundle = retainedBundle
                demoLoadState = .available
            } else {
                demoBundle = nil
                demoLoadState = .unavailable
            }
        case .featureOff, .undisplayable:
            // Explicit product/configuration changes must take effect immediately.
            clearDemoPresentation()
        }
    }

    private var canRetainCurrentDemoPresentation: Bool {
        state == .empty
            && total == 0
            && trips.isEmpty
            && demoLoadState == .available
            && demoBundle?.isDisplayable == true
            && !hasGraduatedFromDemo
    }

    private func inferredTotalDays(for trip: Trip) -> Int? {
        guard
            let startDate = Self.tripDate(from: trip.startDate),
            let endDate = Self.tripDate(from: trip.endDate),
            let days = TracciDateContext.inclusiveDayCount(start: startDate, end: endDate)
        else {
            return nil
        }

        return days
    }

    private static func displayDate(from value: String) -> String {
        guard let date = tripDate(from: value) ?? isoDate(from: value) else {
            return value
        }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private static func compactPlaceName(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        for suffix in ["特别行政区", "自治区", "省", "市"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            break
        }
        return value.isEmpty ? nil : value
    }

    private static func tripDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func isoDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum HomeJourneyListPolicy {
    static let visibleRegularTripLimit = 5
}
