import Foundation
import Observation
import UIKit
import TracciNetworking

@MainActor
@Observable
final class MemoryStoryViewModel: DemoModeProviding {
    let tripId: String
    let tripTitle: String

    private let exportService: ExportService
    /// Demo Journey read-only guard.
    var isDemoMode = false

    private(set) var summary: TripSummaryResponse?
    private(set) var loadedImages: [UIImage] = []
    private(set) var isLoading = false
    private(set) var isGeneratingImage = false
    private(set) var errorMessage: String?
    private(set) var renderedImage: UIImage?
    private(set) var statusMessage: String?
    private(set) var preferredCoverPhoto: TripSummaryPhoto?
    var selectedPageIndex = 0
    var photoCarouselIndex = 0

    var isDemo: Bool { isDemoMode }

    var preferredCoverStoryCardURL: URL? {
        preferredCoverPhoto?.storyCardURLs.first
    }

    init(tripId: String, tripTitle: String, exportService: ExportService) {
        self.tripId = tripId
        self.tripTitle = tripTitle
        self.exportService = exportService
    }

    var hasLoaded: Bool {
        summary != nil
    }

    var shareCopy: ShareCopyResult? {
        summary.map(ExportFormatting.shareCopy(from:))
    }

    var storyPageKinds: [StoryPageKind] {
        guard let summary else { return [.cover, .ending] }
        return MemoryStoryPagePlanner.pages(for: summary, visitedPlaceCount: visitedPlaceCount)
    }

    func normalizeSelectedPageIndex() {
        let maxIndex = max(storyPageKinds.count - 1, 0)
        if selectedPageIndex > maxIndex {
            selectedPageIndex = maxIndex
        }
    }

    func pageKind(at index: Int) -> StoryPageKind {
        let pages = storyPageKinds
        guard index >= 0, index < pages.count else { return .ending }
        return pages[index]
    }

    func storyImage(for page: StoryPageKind) -> UIImage? {
        switch page {
        case .cover, .photos:
            return loadedImages.first
        default:
            return nil
        }
    }

    var fullestDay: TripSummaryDay? {
        summary?.dailyTimeline.max { lhs, rhs in
            (lhs.itineraries.count + lhs.logs.count) < (rhs.itineraries.count + rhs.logs.count)
        }
    }

    var visitedPlaceCount: Int {
        guard let s = summary else { return 0 }
        let names = s.dailyTimeline.flatMap { day in
            day.itineraries.compactMap { $0.locationName?.isEmpty == false ? $0.locationName : $0.title }
        }
        return Set(names).count
    }

    func loadIfNeeded() async {
        guard !isDemoMode else { return }
        guard summary == nil, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        guard !isDemoMode else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }

        do {
            let response = try await exportService.fetchTripSummary(tripId: tripId)
            preferredCoverPhoto = nil
            summary = response
            selectedPageIndex = 0
            renderedImage = nil
            await preloadImages(from: response)
            normalizeSelectedPageIndex()
        } catch {
            summary = nil
            loadedImages = []
            errorMessage = error.localizedDescription
        }
    }

    /// Demo Journey: hydrate story pages from Bundle `summary` without network.
    func applyDemoSummary(
        _ summary: TripSummaryResponse,
        preferredCoverPhoto: TripSummaryPhoto? = nil
    ) async {
        isDemoMode = true
        self.summary = summary
        self.preferredCoverPhoto = preferredCoverPhoto
        selectedPageIndex = 0
        photoCarouselIndex = 0
        renderedImage = nil
        errorMessage = nil
        statusMessage = nil
        isLoading = false
        await preloadImages(
            from: summary,
            maxImages: 12,
            preferredCoverPhoto: preferredCoverPhoto
        )
        normalizeSelectedPageIndex()
    }

    func copyShareText() {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.exportUnavailable
            statusMessage = DemoReadOnlyCopy.exportUnavailable
            notifyFailure()
            return
        }
        guard let text = shareCopy?.fullText, !text.isEmpty else { return }
        ExportShareHelper.copyToPasteboard(text)
        statusMessage = "分享文案已复制"
        notifySuccess()
    }

    func shareItems() -> [Any] {
        if let renderedImage {
            return [renderedImage]
        }
        return []
    }

    func prepareShareImage() async -> Bool {
        if renderedImage != nil { return true }
        return await generateShareImage()
    }

    func resetPlayback() {
        selectedPageIndex = 0
    }

    func generateShareImage() async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.exportUnavailable
            statusMessage = DemoReadOnlyCopy.exportUnavailable
            notifyFailure()
            return false
        }
        if summary == nil {
            await refresh()
        }
        guard let summary else { return false }

        isGeneratingImage = true
        defer { isGeneratingImage = false }

        let view = MemoryPosterTemplate(summary: summary, coverImage: loadedImages.first)
        guard let image = ExportShareHelper.renderImage(content: view, size: CGSize(width: 1080, height: 1920)) else {
            errorMessage = ExportShareError.renderFailed.errorDescription
            notifyFailure()
            return false
        }

        renderedImage = image
        statusMessage = "报告图已生成"
        notifySuccess()
        return true
    }

    func saveReportImage() async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.exportUnavailable
            statusMessage = DemoReadOnlyCopy.exportUnavailable
            notifyFailure()
            return false
        }
        if renderedImage == nil {
            let generated = await generateShareImage()
            guard generated else { return false }
        }

        guard let renderedImage else { return false }
        do {
            try await ExportShareHelper.saveToPhotoLibrary(renderedImage)
            statusMessage = "报告图已保存到相册"
            notifySuccess()
            return true
        } catch {
            errorMessage = error.localizedDescription
            notifyFailure()
            return false
        }
    }

    // MARK: - Time Formatting

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Format a log's ISO8601 `logTime` into a Chinese time display like "5月3日 傍晚 18:42".
    /// Falls back to「第 N 天」when parsing fails or `logTime` is nil.
    static func formattedLogTime(_ log: TripSummaryLog, dayIndex: Int) -> String {
        guard let timeStr = log.logTime,
              let date = iso8601Formatter.date(from: timeStr) else {
            return "第 \(dayIndex) 天"
        }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        let timeOfDay: String = {
            if hour < 6 { return "凌晨" }
            if hour < 12 { return "上午" }
            if hour < 18 { return "下午" }
            return "傍晚"
        }()

        return String(format: "%d月%d日 %@ %02d:%02d", month, day, timeOfDay, hour, minute)
    }

    // MARK: - Image Loading

    private func preloadImages(
        from summary: TripSummaryResponse,
        maxImages: Int = .max,
        preferredCoverPhoto: TripSummaryPhoto? = nil
    ) async {
        var photos = summary.featuredPhotos
        if let preferredCoverPhoto {
            photos.removeAll { $0.id == preferredCoverPhoto.id }
            photos.insert(preferredCoverPhoto, at: 0)
        }

        var candidates: [[URL]] = photos.map(\.storyPortraitURLs).filter { !$0.isEmpty }
        if candidates.isEmpty, let coverURLs = summary.trip.coverPhoto?.storyPortraitURLs, !coverURLs.isEmpty {
            candidates = [coverURLs]
        }
        let limited = maxImages == .max ? candidates : Array(candidates.prefix(maxImages))
        loadedImages = await ExportShareHelper.loadImages(from: limited).images
    }

    private func notifySuccess() {
        AppHaptics.success()
    }

    private func notifyFailure() {
        AppHaptics.error()
    }
}

#if DEBUG
extension MemoryStoryViewModel {
    @MainActor
    func configureForPreview(
        summary: TripSummaryResponse? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.summary = summary
        self.selectedPageIndex = 0
        self.errorMessage = errorMessage
        self.isLoading = isLoading
    }

    static func previewLoaded() -> MemoryStoryViewModel {
        let vm = MemoryStoryViewModel(
            tripId: "trip_preview",
            tripTitle: "京都五日旅行",
            exportService: ExportService(apiClient: APIClient(config: .development))
        )
        vm.summary = TripSummaryResponse(
            trip: TripSummaryTrip(
                id: "trip_preview",
                title: "京都五日旅行",
                destination: "京都",
                startDate: "2026-05-01",
                endDate: "2026-05-05",
                dayCount: 5,
                status: "completed",
                coverPhoto: nil
            ),
            stats: TripSummaryStats(
                dayCount: 5,
                itineraryCount: 12,
                journalCount: 8,
                photoCount: 26,
                expenseCount: 18,
                totalExpenseAmount: "5860.50",
                currency: "CNY",
                highlightCount: 3
            ),
            expenseSummary: TripSummaryExpenseSummary(
                totalAmount: "5860.50",
                currency: "CNY",
                categoryStats: [
                    TripSummaryExpenseCategory(category: "food", categoryName: "餐饮", amount: "2100.00", percentage: "35.83", count: 12),
                    TripSummaryExpenseCategory(category: "hotel", categoryName: "住宿", amount: "1800.00", percentage: "30.71", count: 4),
                    TripSummaryExpenseCategory(category: "transport", categoryName: "交通", amount: "960.50", percentage: "16.39", count: 6)
                ]
            ),
            highlightLogs: [
                TripSummaryLog(id: "log_1", content: "傍晚从鸭川边慢慢走回去，风很轻，路灯刚好亮起来。", locationName: "鸭川", logTime: nil, isHighlight: true, photos: [])
            ],
            userFeaturedPhotos: [],
            recommendedPhotos: [],
            dailyTimeline: [
                TripSummaryDay(
                    date: "2026-05-01",
                    dayIndex: 1,
                    itineraries: [
                        TripSummaryItineraryNode(id: "node_1", title: "清水寺", locationName: "清水寺", startTime: "09:00", endTime: "11:00"),
                        TripSummaryItineraryNode(id: "node_2", title: "二年坂", locationName: "二年坂", startTime: "14:00", endTime: "15:30")
                    ],
                    logs: []
                )
            ]
        )
        return vm
    }
}
#endif
