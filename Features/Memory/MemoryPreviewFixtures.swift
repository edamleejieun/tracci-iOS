import Foundation
import TracciNetworking

#if DEBUG
enum MemoryPreviewFixtures {
    static var exportService: ExportService {
        ExportService(apiClient: APIClient(config: .development, tokenProvider: nil))
    }

    static var tripService: TripService {
        let apiClient = APIClient(config: .development, tokenProvider: nil)
        return TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
    }

    static var journalService: JournalService {
        let apiClient = APIClient(config: .development, tokenProvider: nil)
        return JournalService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
    }

    static let sparseTrip = Trip(
        id: "memory-preview-sparse",
        title: "周末短途放空",
        startDate: "2026-03-08",
        endDate: "2026-03-09",
        status: .completed,
        totalDays: 2,
        destination: TripDestination(name: "安吉"),
        nodeCount: 0,
        journalCount: 0,
        expenseCount: 0
    )

    static let planningTrip = Trip(
        id: "memory-preview-planning",
        title: "杭州三日",
        startDate: "2026-07-03",
        endDate: "2026-07-05",
        status: .planning,
        totalDays: 3,
        destination: TripDestination(name: "杭州")
    )

    static let ongoingTrip = Trip(
        id: "memory-preview-ongoing",
        title: "东京慢慢走",
        startDate: "2026-06-22",
        endDate: "2026-06-24",
        status: .ongoing,
        totalDays: 3,
        destination: TripDestination(name: "东京")
    )

    static let readyTrip = Trip(
        id: "memory-preview-ready",
        title: "京都五日旅行",
        startDate: "2026-05-01",
        endDate: "2026-05-05",
        status: .completed,
        totalDays: 5,
        destination: TripDestination(name: "京都"),
        totalCny: "5860.50",
        nodeCount: 12,
        journalCount: 8,
        expenseCount: 18
    )

    static let sparseSummary = TripSummaryResponse(
        trip: TripSummaryTrip(
            id: sparseTrip.id,
            title: sparseTrip.title,
            destination: sparseTrip.destinationName ?? "安吉",
            startDate: sparseTrip.startDate,
            endDate: sparseTrip.endDate,
            dayCount: 2,
            status: "completed",
            coverPhoto: nil
        ),
        stats: TripSummaryStats(
            dayCount: 2,
            itineraryCount: 0,
            journalCount: 0,
            photoCount: 0,
            expenseCount: 0,
            totalExpenseAmount: "0",
            currency: "CNY",
            highlightCount: 0
        ),
        expenseSummary: nil,
        highlightLogs: [],
        userFeaturedPhotos: [],
        recommendedPhotos: [],
        dailyTimeline: []
    )

    static let readySummary = TripSummaryResponse(
        trip: TripSummaryTrip(
            id: readyTrip.id,
            title: readyTrip.title,
            destination: readyTrip.destinationName ?? "京都",
            startDate: readyTrip.startDate,
            endDate: readyTrip.endDate,
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
                TripSummaryExpenseCategory(category: "food", categoryName: "餐饮", amount: "2100.00", percentage: "35.83", count: 12)
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
                    TripSummaryItineraryNode(id: "node_1", title: "清水寺", locationName: "清水寺", startTime: "09:00", endTime: "11:00")
                ],
                logs: []
            )
        ]
    )

    @MainActor
    static func emptyPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        viewModel.configureForPreview(trips: [])
        return viewModel
    }

    @MainActor
    static func sparseListPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        viewModel.configureForPreview(trips: [sparseTrip, readyTrip])
        return viewModel
    }

    @MainActor
    static func readyListPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        viewModel.configureForPreview(trips: [readyTrip])
        return viewModel
    }

    @MainActor
    static func planningPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        // Focus planning + completed archive (A + B).
        viewModel.configureForPreview(
            trips: [planningTrip, readyTrip, sparseTrip],
            selectedTripId: planningTrip.id,
            stageOverview: decodeStage(planningStageJSON)
        )
        return viewModel
    }

    @MainActor
    static func ongoingViewerPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        // Ongoing with zero materials + completed archive under it.
        viewModel.configureForPreview(
            trips: [ongoingTrip, readyTrip, sparseTrip],
            selectedTripId: ongoingTrip.id,
            stageOverview: decodeStage(ongoingEmptyStageJSON)
        )
        return viewModel
    }

    @MainActor
    static func ongoingReadyPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        let storyViewModel = MemoryStoryViewModel(
            tripId: ongoingTrip.id,
            tripTitle: ongoingTrip.title,
            exportService: exportService
        )
        storyViewModel.configureForPreview(summary: readySummary)
        viewModel.configureForPreview(
            trips: [ongoingTrip, readyTrip, sparseTrip],
            selectedTripId: ongoingTrip.id,
            storyViewModel: storyViewModel,
            stageOverview: decodeStage(ongoingViewerStageJSON)
        )
        return viewModel
    }

    @MainActor
    static func tripsErrorPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        viewModel.configureForPreview(trips: [], tripsError: "网络连接暂时不可用，请稍后再试。")
        return viewModel
    }

    @MainActor
    static func storyErrorPageViewModel() -> MemoryPageViewModel {
        let viewModel = MemoryPageViewModel(tripService: tripService, exportService: exportService, journalService: journalService)
        let storyViewModel = MemoryStoryViewModel(
            tripId: ongoingTrip.id,
            tripTitle: ongoingTrip.title,
            exportService: exportService
        )
        storyViewModel.configureForPreview(errorMessage: "素材服务暂时没有响应。")
        viewModel.configureForPreview(
            trips: [ongoingTrip],
            selectedTripId: ongoingTrip.id,
            storyViewModel: storyViewModel,
            stageOverview: decodeStage(ongoingViewerStageJSON)
        )
        return viewModel
    }

    @MainActor
    static func sparseStoryViewModel() -> MemoryStoryViewModel {
        let viewModel = MemoryStoryViewModel(
            tripId: sparseTrip.id,
            tripTitle: sparseTrip.title,
            exportService: exportService
        )
        viewModel.configureForPreview(summary: sparseSummary)
        return viewModel
    }

    @MainActor
    static func readyStoryViewModel() -> MemoryStoryViewModel {
        let viewModel = MemoryStoryViewModel(
            tripId: readyTrip.id,
            tripTitle: readyTrip.title,
            exportService: exportService
        )
        viewModel.configureForPreview(summary: readySummary)
        return viewModel
    }

    private static func decodeStage(_ json: String) -> TripStageOverview {
        do {
            return try JSONDecoder().decode(TripStageOverview.self, from: Data(json.utf8))
        } catch {
            fatalError("Trip stage preview decode failed: \(error)")
        }
    }

    private static let planningStageJSON = """
    {
      "generatedDate":"2026-06-23","timeZone":"Asia/Shanghai","timeZoneFallbackApplied":false,"phase":"PLANNING",
      "focusTrip":{"id":"memory-preview-planning","title":"杭州三日","destinationName":"杭州","startDate":"2026-07-03","endDate":"2026-07-05","totalDays":3},
      "permissions":{"canAddJournal":true,"canFeaturePhoto":true},
      "selection":{"mode":"DEFAULT","reason":"NEAREST_PLANNING_TRIP","candidateCount":1},
      "planning":{"totalDays":3,"scheduledDayCount":1,"dailyNodeCounts":[],"density":{"level":"LIGHT","nodeCount":2,"totalDays":3,"averageNodesPerDay":"0.67","ruleVersion":"nodes_per_trip_day_v1"},"departureDays":10,"weather":{"available":false,"status":"DATE_TOO_FAR","message":"临近出行时再看看天气。"},"unplannedDates":[]},
      "memory":{"journalCount":0,"photoCount":0,"userFeaturedJournalCount":0,"userFeaturedPhotoCount":0,"systemRecommendedPhotoCount":0,"dailyMaterials":[],"recentFragments":[],"cover":{"available":false,"source":"NONE"},"displayableContent":{"sections":["TRIP_OVERVIEW","BRAND_PLACEHOLDER"],"presentation":"LIGHTWEIGHT"}},"actions":[]
    }
    """

    /// Ongoing with no journals/photos — zero chips / empty flow must not render.
    private static let ongoingEmptyStageJSON = """
    {
      "generatedDate":"2026-06-23","timeZone":"Asia/Shanghai","timeZoneFallbackApplied":false,"phase":"ONGOING",
      "focusTrip":{"id":"memory-preview-ongoing","title":"东京慢慢走","destinationName":"东京","startDate":"2026-06-22","endDate":"2026-06-24","totalDays":3},
      "permissions":{"canAddJournal":true,"canFeaturePhoto":false},
      "selection":{"mode":"DEFAULT","reason":"ONGOING_TRIP","candidateCount":1},
      "ongoing":{"today":{"date":"2026-06-23","itineraryCount":2,"expenseAmount":"66.00","currency":"CNY","journalCount":0,"photoCount":0},"suggestions":[]},
      "memory":{"journalCount":0,"photoCount":0,"userFeaturedJournalCount":0,"userFeaturedPhotoCount":0,"systemRecommendedPhotoCount":0,"dailyMaterials":[],"recentFragments":[],"cover":{"available":false,"source":"NONE"},"displayableContent":{"sections":["TRIP_OVERVIEW"],"presentation":"LIGHTWEIGHT"}},"actions":[]
    }
    """

    private static let ongoingViewerStageJSON = """
    {
      "generatedDate":"2026-06-23","timeZone":"Asia/Shanghai","timeZoneFallbackApplied":false,"phase":"ONGOING",
      "focusTrip":{"id":"memory-preview-ongoing","title":"东京慢慢走","destinationName":"东京","startDate":"2026-06-22","endDate":"2026-06-24","totalDays":3},
      "permissions":{"canAddJournal":true,"canFeaturePhoto":true},
      "selection":{"mode":"DEFAULT","reason":"ONGOING_TRIP","candidateCount":1},
      "ongoing":{"today":{"date":"2026-06-23","itineraryCount":2,"expenseAmount":"66.00","currency":"CNY","journalCount":1,"photoCount":2},"suggestions":[]},
      "memory":{"journalCount":1,"photoCount":2,"userFeaturedJournalCount":0,"userFeaturedPhotoCount":0,"systemRecommendedPhotoCount":2,"dailyMaterials":[],"recentFragments":[],"cover":{"available":true,"source":"SYSTEM_DESTINATION"},"displayableContent":{"sections":["TRIP_OVERVIEW","JOURNALS","PHOTOS"],"presentation":"LIGHTWEIGHT"}},"actions":[]
    }
    """
}
#endif
