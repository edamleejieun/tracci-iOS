import Foundation
import Observation

@MainActor
@Observable
final class MemoryPageViewModel {
    private(set) var trips: [Trip] = []
    var selectedTripId: String?
    var memoryMode: MemoryMode = .tripReview
    var exportMode: ExportMode = .shareCard
    private(set) var isLoadingTrips = false
    private(set) var tripsError: String?
    private(set) var stageOverview: TripStageOverview?
    var isShowingTripPicker = false

    /// Story / launcher playback for the trip the user is currently opening.
    private(set) var storyViewModel: MemoryStoryViewModel?
    /// Ongoing materials strip only — always bound to stage `focusTrip`, never archive story selection.
    private(set) var materialsViewModel: MemoryStoryViewModel?

    private let tripService: TripService
    private let exportService: ExportService
    private let journalService: JournalService
    private var userScope: String

    var selectedTrip: Trip? {
        guard let selectedTripId else { return nil }
        return trips.first { $0.id == selectedTripId }
    }

    var hasTrips: Bool {
        !trips.isEmpty
    }

    var completedTrips: [Trip] {
        trips
            .filter { $0.effectiveStatus == .completed }
            .sorted { lhs, rhs in
                if lhs.endDate != rhs.endDate {
                    return lhs.endDate > rhs.endDate
                }
                return lhs.startDate > rhs.startDate
            }
    }

    var hasSelectedTrip: Bool {
        selectedTrip != nil && storyViewModel != nil
    }

    var yearlyReports: [YearlyMemoryReport] {
        let grouped = Dictionary(grouping: trips) { trip in
            Int(trip.startDate.prefix(4)) ?? Calendar.current.component(.year, from: Date())
        }

        return grouped.map { year, trips in
            YearlyMemoryReport(
                year: year,
                trips: trips.count,
                days: trips.reduce(0) { $0 + ($1.totalDays ?? 0) },
                places: Set(trips.compactMap(\.destinationName)).count,
                coverURLs: trips.compactMap(\.coverThumbnailURL)
            )
        }
        .sorted { $0.year > $1.year }
    }

    init(
        tripService: TripService,
        exportService: ExportService,
        journalService: JournalService,
        userId: String? = nil
    ) {
        self.tripService = tripService
        self.exportService = exportService
        self.journalService = journalService
        self.userScope = userId.flatMap { $0.isEmpty ? nil : $0 } ?? "anonymous"
    }

    func setUserScope(_ userId: String?) {
        userScope = userId.flatMap { $0.isEmpty ? nil : $0 } ?? "anonymous"
    }

    func loadTripsIfNeeded() async {
        guard trips.isEmpty, !isLoadingTrips else { return }
        await refreshTrips()
    }

    func refreshTrips() async {
        isLoadingTrips = true
        tripsError = nil
        defer { isLoadingTrips = false }

        async let tripsRequest = tripService.listTrips(page: 1, pageSize: 100)
        async let stageRequest = tripService.stageOverview()
        var errors: [String] = []
        var didLoadTrips = false

        do {
            trips = try await tripsRequest.list
            didLoadTrips = true
        } catch {
            errors.append(error.localizedDescription)
        }

        do {
            stageOverview = try await stageRequest
        } catch {
            errors.append(error.localizedDescription)
        }

        tripsError = errors.first

        if let focusId = stageOverview?.focusTrip?.id,
           let focusTrip = trips.first(where: { $0.id == focusId }) {
            // Materials strip is focus-bound. Story VM is only forced to focus when not already
            // presenting another completed trip's launcher/story selection.
            await ensureMaterialsViewModel(for: focusTrip)
            if selectedTripId == nil
                || selectedTripId == focusId
                || !(trips.contains(where: { $0.id == selectedTripId && $0.effectiveStatus == .completed })) {
                selectTrip(focusTrip, force: true)
            }
            await storyViewModel?.loadIfNeeded()
        } else {
            materialsViewModel = nil
            if let selectedTripId, trips.contains(where: { $0.id == selectedTripId }) {
                rebuildExportViewModelIfNeeded()
            } else if let preferred = preferredTrip(from: completedTrips) {
                selectTrip(preferred)
            } else if didLoadTrips {
                self.selectedTripId = nil
                storyViewModel = nil
            }
        }
    }

    func selectTrip(_ trip: Trip, force: Bool = false) {
        if !force, selectedTripId == trip.id { return }
        selectedTripId = trip.id
        storyViewModel = makeStoryViewModel(for: trip)
        isShowingTripPicker = false
    }

    /// Builds a read-only Story VM from the Demo Bundle without selecting or
    /// inserting the synthetic trip into the user's real memory archive.
    func makeDemoStoryViewModel(for scene: DemoJourneyScene) async -> MemoryStoryViewModel {
        let viewModel = MemoryStoryViewModel(
            tripId: scene.trip.id,
            tripTitle: scene.trip.title,
            exportService: exportService
        )
        await viewModel.applyDemoSummary(
            scene.summary,
            preferredCoverPhoto: Self.preferredDemoStoryCoverPhoto(in: scene.summary)
        )
        return viewModel
    }

    /// Follow the Bundle's explicit Story cover. Fall back to featured material
    /// only for older compatible snapshots that do not provide `trip.coverPhoto`.
    static func preferredDemoStoryCoverPhoto(in summary: TripSummaryResponse) -> TripSummaryPhoto? {
        summary.trip.coverPhoto
            ?? summary.userFeaturedPhotos.first
            ?? summary.recommendedPhotos.first
    }

    func removeTrip(id: String) {
        trips.removeAll { $0.id == id }
        if selectedTripId == id {
            selectedTripId = nil
            storyViewModel = nil
        }

        if stageOverview?.focusTrip?.id == id {
            stageOverview = nil
            materialsViewModel = nil
        } else if materialsViewModel?.tripId == id {
            materialsViewModel = nil
        }

        if selectedTripId == nil, let preferred = preferredTrip(from: completedTrips) {
            selectTrip(preferred)
        }
    }

    func trip(id: String) -> Trip? {
        trips.first { $0.id == id }
    }

    func setExportMode(_ mode: ExportMode) {
        guard exportMode != mode else { return }
        exportMode = mode
    }

    func toggleFeaturedPhoto(_ photo: TripSummaryPhoto) async -> Bool {
        // Featured actions belong to the ongoing focus trip materials strip.
        guard stageOverview?.permissions?.canFeaturePhoto == true else { return false }
        let tripId = stageOverview?.focusTrip?.id
            ?? materialsViewModel?.tripId
        guard let tripId else { return false }
        do {
            if photo.userFeatured {
                _ = try await journalService.unfeaturePhoto(tripId: tripId, photoId: photo.id)
            } else {
                _ = try await journalService.featurePhoto(tripId: tripId, photoId: photo.id)
            }
            await materialsViewModel?.refresh()
            // Keep story VM in sync only when it is also the focus trip.
            if storyViewModel?.tripId == tripId {
                await storyViewModel?.refresh()
            }
            stageOverview = try await tripService.stageOverview(tripId: tripId)
            return true
        } catch {
            tripsError = error.localizedDescription
            return false
        }
    }

    /// Loads / refreshes materials for the ongoing focus trip without affecting story selection.
    func ensureMaterialsViewModel(for trip: Trip) async {
        if materialsViewModel?.tripId != trip.id {
            materialsViewModel = makeStoryViewModel(for: trip)
        }
        await materialsViewModel?.loadIfNeeded()
    }

    func dateRangeText(for trip: Trip) -> String {
        Self.dateRangeText(for: trip)
    }

    func dateRangeText(forFocus focus: TripStageFocusTrip) -> String {
        ExportFormatting.dateRangeText(startDate: focus.startDate, endDate: focus.endDate)
    }

    func daysSummary(for trip: Trip) -> String {
        if let totalDays = trip.totalDays, totalDays > 0 {
            return "\(totalDays)天"
        }
        return Self.dateRangeText(for: trip)
    }

    private func rebuildExportViewModelIfNeeded() {
        guard let trip = selectedTrip else {
            storyViewModel = nil
            return
        }
        storyViewModel = makeStoryViewModel(for: trip)
    }

    private func makeStoryViewModel(for trip: Trip) -> MemoryStoryViewModel {
        MemoryStoryViewModel(
            tripId: trip.id,
            tripTitle: trip.title,
            exportService: exportService
        )
    }

    // MARK: - NEW Badge Persistence

    private var viewedTripIDsKey: String {
        "memory.viewedTripIDs.\(userScope)"
    }

    func isTripNew(_ tripId: String) -> Bool {
        let ids = Set(UserDefaults.standard.stringArray(forKey: viewedTripIDsKey) ?? [])
        return !ids.contains(tripId)
    }

    func markTripViewed(_ tripId: String) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: viewedTripIDsKey) ?? [])
        ids.insert(tripId)
        UserDefaults.standard.set(Array(ids), forKey: viewedTripIDsKey)
    }

    func markCurrentTripViewed() {
        guard let id = selectedTripId else { return }
        markTripViewed(id)
    }

    #if DEBUG
    @MainActor
    func configureForPreview(
        trips: [Trip],
        isLoadingTrips: Bool = false,
        tripsError: String? = nil,
        selectedTripId: String? = nil,
        storyViewModel: MemoryStoryViewModel? = nil,
        materialsViewModel: MemoryStoryViewModel? = nil,
        stageOverview: TripStageOverview? = nil
    ) {
        self.trips = trips
        self.isLoadingTrips = isLoadingTrips
        self.tripsError = tripsError
        self.selectedTripId = selectedTripId ?? trips.first?.id
        self.stageOverview = stageOverview
        if let storyViewModel {
            self.storyViewModel = storyViewModel
        } else if let trip = trips.first(where: { $0.id == self.selectedTripId }) ?? trips.first {
            self.storyViewModel = makeStoryViewModel(for: trip)
        } else {
            self.storyViewModel = nil
        }

        if let materialsViewModel {
            self.materialsViewModel = materialsViewModel
        } else if let focusId = stageOverview?.focusTrip?.id,
                  let focusTrip = trips.first(where: { $0.id == focusId }) {
            // Default materials to focus trip; reuse story VM when it already is the focus.
            self.materialsViewModel = (self.storyViewModel?.tripId == focusId)
                ? self.storyViewModel
                : makeStoryViewModel(for: focusTrip)
        } else {
            self.materialsViewModel = nil
        }
    }
    #endif

    private func preferredTrip(from trips: [Trip]) -> Trip? {
        trips.first
    }

    private static func dateRangeText(for trip: Trip) -> String {
        ExportFormatting.dateRangeText(startDate: trip.startDate, endDate: trip.endDate)
    }
}

#if DEBUG
extension MemoryPageViewModel {
    static func previewLoaded() -> MemoryPageViewModel {
        MemoryPreviewFixtures.readyListPageViewModel()
    }
}
#endif
