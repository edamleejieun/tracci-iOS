import Foundation
import Observation
import UIKit
import TracciNetworking

@MainActor
@Observable
final class ExportViewModel {
    let tripId: String
    let tripTitle: String
    let dateRangeText: String

    private let exportService: ExportService

    // Mode & configuration
    var exportMode: ExportMode = .shareCard
    var selectedTemplate: ExportTemplate = .travelCover
    var selectedFormat: ExportFormat = .square
    var contentOptions = ExportContentOptions()
    var itineraryFormat: ItineraryExportFormat = .image

    // Data
    private(set) var shareAssets: ExportAssetsResponse?
    private(set) var itineraryAssets: ItineraryExportAssetsResponse?
    private(set) var loadedPhotoImages: [UIImage] = []

    // Export state
    private(set) var phase: ExportPhase = .idle
    private(set) var errorMessage: String?
    private(set) var renderedImage: UIImage?
    private(set) var exportedPlainText: String?
    private(set) var statusMessage: String?
    private(set) var hasLoadedShareAssets = false
    private(set) var hasLoadedItineraryAssets = false
    private(set) var shareImageLoadWarning: String?

    var isLoading: Bool { phase == .loading }
    var isGenerating: Bool { phase == .generating }
    var canGenerate: Bool {
        switch exportMode {
        case .shareCard:
            !isLoading && !isGenerating
        case .itinerary:
            !isLoading && !isGenerating
        }
    }

    var itineraryDayCount: Int {
        itineraryAssets?.meta.totalDayCount ?? itineraryDays.count
    }

    var itineraryNodeCount: Int {
        itineraryAssets?.meta.totalNodeCount ?? itineraryDays.reduce(0) { $0 + $1.nodes.count }
    }

    var itineraryDays: [ItineraryExportDay] {
        itineraryAssets?.days ?? []
    }

    var shareCopyText: String {
        guard let assets = shareAssets else { return "" }
        return ExportFormatting.copyText(
            style: contentOptions.copyStyle,
            trip: assets.trip,
            stats: assets.stats
        )
    }

    var memoryHighlights: [ExportMemoryHighlight] {
        guard let assets = shareAssets else { return [] }
        var highlights: [ExportMemoryHighlight] = []

        highlights.append(
            ExportMemoryHighlight(
                id: "days",
                title: "旅程时长",
                value: "\(assets.trip.totalDays) 天",
                systemImage: "calendar"
            )
        )
        highlights.append(
            ExportMemoryHighlight(
                id: "itinerary",
                title: "行程节点",
                value: "\(assets.stats.itineraryCount) 个",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        )
        highlights.append(
            ExportMemoryHighlight(
                id: "journals",
                title: "旅行日志",
                value: "\(assets.stats.journalCount) 篇",
                systemImage: "book.pages"
            )
        )
        highlights.append(
            ExportMemoryHighlight(
                id: "photos",
                title: "精选照片",
                value: "\(assets.stats.photoCount) 张",
                systemImage: "photo.on.rectangle"
            )
        )
        if assets.stats.expenseCount > 0 || assets.stats.totalExpenseAmount > 0 {
            highlights.append(
                ExportMemoryHighlight(
                    id: "expense",
                    title: "总花费",
                    value: ExportFormatting.currencyText(
                        amount: assets.stats.totalExpenseAmount,
                        currency: assets.stats.currency
                    ),
                    systemImage: "creditcard"
                )
            )
        }
        return highlights
    }

    var shareAssetsEmptyHint: String? {
        guard let assets = shareAssets else { return nil }

        if assets.stats.photoCount == 0 && assets.photos.isEmpty && assets.trip.coverPhoto == nil {
            return "这趟还没有照片，会先用空白画面占位。补上日志照片后，卡片会更完整。"
        }
        if assets.stats.journalCount == 0 && assets.stats.itineraryCount == 0 {
            return "这趟还没有日志和行程，报告会先用旅程的基础信息。"
        }
        return nil
    }

    var itineraryEmptyHint: String? {
        guard let assets = itineraryAssets else { return nil }
        if assets.meta.totalNodeCount == 0 {
            return "这趟还没有行程安排，暂时只能导出一份空行程单。"
        }
        return nil
    }

    var primaryButtonTitle: String {
        switch exportMode {
        case .shareCard:
            phase == .success ? "再生成一次" : "生成旅程卡片"
        case .itinerary:
            switch itineraryFormat {
            case .image:
                phase == .success ? "再次保存行程单" : "保存行程单图片"
            case .text:
                phase == .success ? "再次复制文字" : "复制行程文字"
            }
        }
    }

    var primaryButtonIcon: String {
        switch exportMode {
        case .shareCard:
            "square.and.arrow.down"
        case .itinerary:
            itineraryFormat == .image ? "square.and.arrow.down" : "doc.on.doc"
        }
    }

    init(
        tripId: String,
        tripTitle: String,
        dateRangeText: String,
        exportMode: ExportMode = .shareCard,
        exportService: ExportService
    ) {
        self.tripId = tripId
        self.tripTitle = tripTitle
        self.dateRangeText = dateRangeText
        self.exportMode = exportMode
        self.exportService = exportService
    }

    func loadInitialDataIfNeeded() async {
        switch exportMode {
        case .shareCard:
            guard !hasLoadedShareAssets else { return }
            await loadShareAssets(initializeContentOptions: true)
        case .itinerary:
            guard !hasLoadedItineraryAssets else { return }
            await loadItineraryAssets()
        }
    }

    func onExportModeChanged() async {
        resetExport()
        await loadInitialDataIfNeeded()
    }

    func refreshExportStatusIfNeeded() async {
        switch exportMode {
        case .shareCard:
            await loadShareAssets(force: true, initializeContentOptions: false)
        case .itinerary:
            await loadItineraryAssets(force: true)
        }
    }

    func generateExport() async {
        errorMessage = nil
        statusMessage = nil
        renderedImage = nil
        exportedPlainText = nil

        switch exportMode {
        case .shareCard:
            await generateShareCard()
        case .itinerary:
            await generateItineraryExport()
        }
    }

    func resetExport() {
        phase = .idle
        errorMessage = nil
        statusMessage = nil
        renderedImage = nil
        exportedPlainText = nil
    }

    func previewExport() -> UIImage? {
        renderedImage
    }

    func shareItems() -> [Any] {
        if let renderedImage {
            return [renderedImage]
        }
        if let exportedPlainText {
            return [exportedPlainText]
        }
        return []
    }

    // MARK: - Private

    private func loadShareAssets(force: Bool = false, initializeContentOptions: Bool = false) async {
        if hasLoadedShareAssets, !force { return }

        phase = .loading
        errorMessage = nil
        shareImageLoadWarning = nil

        do {
            let response = try await exportService.fetchExportAssets(
                tripId: tripId,
                template: selectedTemplate,
                format: selectedFormat
            )
            shareAssets = response
            if initializeContentOptions {
                if let template = ExportTemplate(rawValue: response.exportOptions.template) {
                    selectedTemplate = template
                }
                if let format = ExportFormat(rawValue: response.exportOptions.format) {
                    selectedFormat = format
                }
            }
            await preloadShareImages(from: response)
            hasLoadedShareAssets = true
            phase = .idle
        } catch {
            shareAssets = nil
            hasLoadedShareAssets = false
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func loadItineraryAssets(force: Bool = false) async {
        if hasLoadedItineraryAssets, !force, itineraryAssets != nil { return }

        phase = .loading
        errorMessage = nil

        do {
            let response = try await exportService.fetchItineraryExportAssets(
                tripId: tripId,
                selectedDates: nil
            )
            itineraryAssets = response
            hasLoadedItineraryAssets = true
            phase = .idle
        } catch {
            itineraryAssets = nil
            hasLoadedItineraryAssets = false
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func preloadShareImages(from assets: ExportAssetsResponse) async {
        var urls: [URL] = assets.photos.compactMap(\.renderURL)
        if urls.isEmpty, let cover = assets.trip.coverPhoto, let url = URL(string: cover) {
            urls = [url]
        }
        let result = await ExportShareHelper.loadImages(from: urls)
        loadedPhotoImages = result.images
        if result.failedCount > 0, result.totalCount > 0 {
            shareImageLoadWarning = "部分图片加载失败，将使用占位图继续生成"
        }
    }

    private func generateShareCard() async {
        phase = .generating

        if shareAssets == nil || !hasLoadedShareAssets {
            await loadShareAssets(force: true, initializeContentOptions: true)
            guard shareAssets != nil else {
                phase = .failed
                return
            }
        }

        guard let assets = shareAssets else {
            phase = .failed
            errorMessage = errorMessage ?? "暂时没有可导出的记录"
            return
        }

        let size = selectedFormat.exportPixelSize
        let view = ExportShareCardView(
            template: selectedTemplate,
            format: selectedFormat,
            assets: assets,
            contentOptions: contentOptions,
            loadedImages: loadedPhotoImages,
            copyText: shareCopyText
        )

        guard let image = ExportShareHelper.renderImage(content: view, size: size) else {
            phase = .failed
            errorMessage = ExportShareError.renderFailed.errorDescription
            return
        }

        renderedImage = image
        phase = .success
        statusMessage = "旅程回顾已生成，可预览、分享或保存到相册"
        notifySuccess()
    }

    private func generateItineraryExport() async {
        if itineraryAssets == nil || !hasLoadedItineraryAssets {
            await loadItineraryAssets()
            guard itineraryAssets != nil else { return }
        }

        guard let assets = itineraryAssets else {
            phase = .failed
            errorMessage = "暂无行程数据"
            return
        }

        let days = assets.days

        guard !days.isEmpty else {
            phase = .failed
            errorMessage = "暂无可导出的行程"
            return
        }

        phase = .generating

        let allDates = Set(days.map(\.date))

        switch itineraryFormat {
        case .text:
            let text = ExportFormatting.itineraryPlainText(
                trip: assets.trip,
                days: assets.days,
                selectedDates: allDates
            )
            exportedPlainText = text
            ExportShareHelper.copyToPasteboard(text)
            phase = .success
            statusMessage = "行程文字已复制到剪贴板"
            notifySuccess()

        case .image:
            let view = ItineraryExportCardView(
                trip: assets.trip,
                days: days,
                watermark: assets.watermark,
                maxDaysShown: days.count
            )
            let nodeCount = days.reduce(0) { $0 + $1.nodes.count }
            let height = max(1440, 520 + CGFloat(days.count) * 170 + CGFloat(nodeCount) * 58)
            let size = CGSize(width: 1080, height: height)

            guard let image = ExportShareHelper.renderImage(content: view, size: size) else {
                phase = .failed
                errorMessage = ExportShareError.renderFailed.errorDescription
                return
            }

            renderedImage = image
            phase = .success
            statusMessage = "行程单图片已生成，可预览、分享或保存到相册"
            notifySuccess()
        }
    }

    func saveToPhotoLibrary() async -> Bool {
        guard let renderedImage else { return false }

        do {
            try await ExportShareHelper.saveToPhotoLibrary(renderedImage)
            statusMessage = "已保存到相册"
            notifySuccess()
            return true
        } catch {
            errorMessage = error.localizedDescription
            notifyFailure()
            return false
        }
    }

    private func notifySuccess() {
        AppHaptics.success()
    }

    private func notifyFailure() {
        AppHaptics.error()
    }
}

#if DEBUG
extension ExportViewModel {
    static func previewLoaded() -> ExportViewModel {
        let vm = ExportViewModel(
            tripId: "trip_preview",
            tripTitle: "京都五日旅行",
            dateRangeText: "2026.05.01 - 05.05",
            exportService: ExportService(apiClient: APIClient(config: .development))
        )
        vm.shareAssets = ExportPreviewFixtures.shareAssets
        vm.itineraryAssets = ExportPreviewFixtures.itineraryAssets
        vm.hasLoadedShareAssets = true
        vm.hasLoadedItineraryAssets = true
        return vm
    }
}

enum ExportPreviewFixtures {
    static let previewTrip: Trip = {
        let json = """
        {"id":"trip_preview","title":"京都五日旅行","startDate":"2026-05-01","endDate":"2026-05-05","status":"completed","totalDays":5,"nodeCount":12,"journalCount":8}
        """
        return try! JSONDecoder().decode(Trip.self, from: Data(json.utf8))
    }()

    static let shareAssets = ExportAssetsResponse(
        trip: ExportTripInfo(
            id: "trip_preview",
            title: "京都五日旅行",
            destination: "京都",
            startDate: "2026-05-01",
            endDate: "2026-05-05",
            totalDays: 5,
            coverPhoto: nil
        ),
        stats: ExportStats(
            itineraryCount: 12,
            journalCount: 8,
            photoCount: 26,
            expenseCount: 18,
            totalExpenseAmount: 5860.5,
            averageDailyExpense: 1172.1,
            currency: "CNY"
        ),
        photos: [],
        visitedPlaces: ["清水寺", "伏见稻荷大社"],
        expenseCategoryStats: [
            ExportExpenseCategoryStat(category: "food", categoryName: "餐饮", amount: 2100, percentage: 35.83, count: 12)
        ],
        watermark: ExportWatermark(enabled: true, text: "趣溪"),
        exportOptions: ExportOptionsResponse(
            template: "travel-cover",
            format: "square",
            contentOptions: ExportContentOptionsResponse(
                showDate: true,
                showDays: true,
                showItineraryCount: true,
                showJournalCount: true,
                showExpense: true,
                showVisitedPlaces: true,
                showExpenseDistribution: true,
                showWatermark: true,
                copyStyle: "none"
            )
        )
    )

    static let itineraryAssets = ItineraryExportAssetsResponse(
        trip: ItineraryExportTripInfo(
            id: "trip_preview",
            title: "京都五日旅行",
            destination: "京都",
            startDate: "2026-05-01",
            endDate: "2026-05-05",
            totalDays: 5
        ),
        days: [
            ItineraryExportDay(
                id: "day_1",
                dayIndex: 1,
                date: "2026-05-01",
                nodeCount: 1,
                nodes: [
                    ItineraryExportNode(
                        id: "node_1",
                        title: "清水寺",
                        type: "attraction",
                        typeName: "景点",
                        startTime: "09:00",
                        endTime: "11:00",
                        locationName: "清水寺",
                        locationAddress: "京都府京都市东山区",
                        note: nil,
                        sortOrder: 1000
                    )
                ]
            )
        ],
        meta: ItineraryExportMeta(totalDayCount: 5, totalNodeCount: 12, selectedDayCount: 5, selectedNodeCount: 12),
        watermark: ExportWatermark(enabled: true, text: "趣溪")
    )
}
#endif
