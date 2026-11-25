import Foundation
import Observation
import TracciNetworking

struct AllTripsStatusCounts: Equatable {
    var all: Int = 0
    var ongoing: Int = 0
    var planning: Int = 0
    var completed: Int = 0

    func count(for status: TripStatus?) -> Int {
        switch status {
        case nil:
            return all
        case .ongoing:
            return ongoing
        case .planning:
            return planning
        case .completed:
            return completed
        case .unknown:
            return 0
        }
    }
}

@MainActor
@Observable
final class AllTripsViewModel {
    enum ViewState: Equatable {
        case idle
        case loading
        case empty
        case loaded
        case error(String)
    }

    static let pageSize = 10

    private let tripService: TripService
    private(set) var state: ViewState = .idle
    private(set) var trips: [Trip] = []
    private(set) var total = 0
    private(set) var currentPage = 0
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false
    private(set) var loadMoreError: String?
    private(set) var statusCounts = AllTripsStatusCounts()
    var selectedStatus: TripStatus?
    private(set) var reloadToken = 0
    private(set) var hasCompletedInitialLoad = false
    private var hasLoaded = false
    private var loadedItemCount = 0
    private var reloadGeneration = 0
    /// Serializes list reloads so a new filter tap cancels the previous in-flight load cleanly.
    private var reloadTask: Task<Void, Never>?

    #if DEBUG
    var disablesAutoLoad = false
    #endif

    init(tripService: TripService) {
        self.tripService = tripService
    }

    var isCurrentFilterEmpty: Bool {
        guard case .loaded = state else { return false }
        // Avoid flashing empty state while a filter reload is in flight.
        guard !isRefreshing else { return false }
        return trips.isEmpty
    }

    var summaryText: String {
        guard hasCompletedInitialLoad else { return "" }
        // Hide while the very first full-screen load is still resolving.
        if state == .loading, trips.isEmpty { return "" }

        if let selectedStatus {
            return "共 \(total) 段\(selectedStatus.label)的旅程"
        }
        return "共 \(total) 段旅程"
    }

    var listTransitionID: String {
        selectedStatus?.rawValue ?? "all"
    }

    /// Chip id + current row identities so the list can cross-fade when data arrives.
    var listContentSignature: String {
        "\(listTransitionID)|\(trips.map(\.id).joined(separator: ","))"
    }

    var loadedTripsForSync: [Trip] {
        trips
    }

    func loadTripsIfNeeded() async {
        guard !hasLoaded else { return }
        await reloadTrips(showFullScreenLoading: !hasCompletedInitialLoad, refreshCounts: true)
    }

    func loadAllTrips() async {
        await reloadTrips(showFullScreenLoading: !hasCompletedInitialLoad, refreshCounts: true)
    }

    func refreshTrips() async {
        await reloadTrips(showFullScreenLoading: false, refreshCounts: true)
    }

    func invalidateCache() {
        hasLoaded = false
        reloadToken += 1
    }

    /// Filter chip selection — cancels any in-flight reload and starts a new one.
    func selectStatus(_ status: TripStatus?) {
        guard selectedStatus != status else { return }
        selectedStatus = status
        // Filter change only needs the trip page; counts stay valid across filters.
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.reloadTrips(showFullScreenLoading: false, refreshCounts: false)
        }
    }

    func loadMoreIfNeeded() async {
        guard hasMore, !isLoadingMore, !isRefreshing, loadMoreError == nil, case .loaded = state else { return }

        let generation = reloadGeneration
        let statusFilter = selectedStatus

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let response = try await fetchPage(page: nextPage, status: statusFilter)
            guard isCurrentLoad(generation: generation, status: statusFilter) else { return }
            applyPageResponse(response, page: nextPage, append: true)
            loadMoreError = nil
        } catch {
            guard !Self.isCancellation(error) else { return }
            guard isCurrentLoad(generation: generation, status: statusFilter) else { return }
            loadMoreError = error.localizedDescription
        }
    }

    func retryLoadMore() async {
        loadMoreError = nil
        await loadMoreIfNeeded()
    }

    func countForStatus(_ status: TripStatus?) -> Int {
        statusCounts.count(for: status)
    }

    // MARK: - Private

    private func reloadTrips(showFullScreenLoading: Bool, refreshCounts: Bool) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let statusFilter = selectedStatus

        if showFullScreenLoading || state == .idle || !hasCompletedInitialLoad {
            state = .loading
        } else {
            isRefreshing = true
        }
        defer {
            // Only clear refreshing if this generation is still the latest.
            if generation == reloadGeneration {
                isRefreshing = false
            }
        }

        // Keep existing rows visible during filter switches to avoid empty flash +
        // ScrollView identity churn that cancels in-flight URLSession tasks.
        if showFullScreenLoading || !hasCompletedInitialLoad {
            currentPage = 0
            trips = []
            hasMore = false
            total = 0
            loadedItemCount = 0
        }
        loadMoreError = nil

        do {
            if refreshCounts {
                let previousCounts = statusCounts
                let counts = await refreshStatusCounts(fallback: previousCounts)
                guard isCurrentLoad(generation: generation, status: statusFilter) else { return }
                statusCounts = counts
            }

            // Sequential fetch (no async-let) so an early generation exit cannot
            // cancel a sibling request and surface as APIError.underlying("cancelled").
            let firstPage = try await fetchPage(page: 1, status: statusFilter)
            guard isCurrentLoad(generation: generation, status: statusFilter) else { return }

            applyPageResponse(firstPage, page: 1, append: false)
            updateStateAfterLoad()
        } catch {
            guard !Self.isCancellation(error) else { return }
            guard isCurrentLoad(generation: generation, status: statusFilter) else { return }
            // Full-screen error only when we have nothing to show; otherwise toast-level
            // would be nicer, but keep existing error overlay contract.
            if trips.isEmpty {
                state = .error(Self.userFacingMessage(for: error))
            } else {
                // Keep prior list; surface a soft failure via loadMore-style messaging.
                loadMoreError = Self.userFacingMessage(for: error)
                state = .loaded
            }
        }
    }

    private func isCurrentLoad(generation: Int, status: TripStatus?) -> Bool {
        !Task.isCancelled && generation == reloadGeneration && status == selectedStatus
    }

    private func fetchPage(page: Int, status: TripStatus?) async throws -> PageResponse<Trip> {
        try await tripService.listTrips(
            page: page,
            pageSize: Self.pageSize,
            status: status
        )
    }

    private func refreshStatusCounts(fallback: AllTripsStatusCounts) async -> AllTripsStatusCounts {
        async let allCount = fetchTotal(for: nil, fallback: fallback.all)
        async let ongoingCount = fetchTotal(for: .ongoing, fallback: fallback.ongoing)
        async let planningCount = fetchTotal(for: .planning, fallback: fallback.planning)
        async let completedCount = fetchTotal(for: .completed, fallback: fallback.completed)

        return AllTripsStatusCounts(
            all: await allCount,
            ongoing: await ongoingCount,
            planning: await planningCount,
            completed: await completedCount
        )
    }

    private func fetchTotal(for status: TripStatus?, fallback: Int) async -> Int {
        do {
            let response = try await tripService.listTrips(page: 1, pageSize: 1, status: status)
            return response.total
        } catch {
            if Self.isCancellation(error) { return fallback }
            return fallback
        }
    }

    private func applyPageResponse(_ response: PageResponse<Trip>, page: Int, append: Bool) {
        total = response.total
        currentPage = page

        if append {
            let existingIDs = Set(trips.map(\.id))
            let newTrips = response.list.filter { !existingIDs.contains($0.id) }
            trips.append(contentsOf: newTrips)
            loadedItemCount += newTrips.count
        } else {
            trips = response.list
            loadedItemCount = response.list.count
        }

        trips = TripListSorting.sorted(trips)
        hasMore = loadedItemCount < total
    }

    private func updateStateAfterLoad() {
        hasLoaded = true
        hasCompletedInitialLoad = true
        state = .loaded
    }

    /// URLSession cancel → APIClient wraps as `underlying("cancelled")`. Never treat as a real failure.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if Task.isCancelled { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        if let apiError = error as? APIError, case .underlying(let message) = apiError {
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "cancelled" || normalized == "canceled" {
                return true
            }
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return description == "cancelled" || description == "canceled"
    }

    private static func userFacingMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty || message.lowercased() == "cancelled" || message.lowercased() == "canceled" {
            return "网络连接暂时不可用，请稍后再试。"
        }
        return message
    }

    #if DEBUG
    func configureForPreview(
        state: ViewState = .loaded,
        trips: [Trip] = [],
        total: Int = 0,
        selectedStatus: TripStatus? = nil,
        statusCounts: AllTripsStatusCounts = AllTripsStatusCounts(all: 12, ongoing: 1, planning: 4, completed: 7),
        hasMore: Bool = false,
        isLoadingMore: Bool = false,
        isRefreshing: Bool = false,
        loadMoreError: String? = nil,
        disablesAutoLoad: Bool = true
    ) {
        self.state = state
        self.trips = trips
        self.total = total
        self.selectedStatus = selectedStatus
        self.statusCounts = statusCounts
        self.currentPage = trips.isEmpty ? 0 : 1
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.isRefreshing = isRefreshing
        self.loadMoreError = loadMoreError
        self.disablesAutoLoad = disablesAutoLoad
        self.hasLoaded = disablesAutoLoad
        self.hasCompletedInitialLoad = disablesAutoLoad
    }
    #endif
}
