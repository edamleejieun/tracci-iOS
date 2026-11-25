import Foundation

// MARK: - Export Mode

enum ExportMode: String, CaseIterable, Identifiable {
    case shareCard
    case itinerary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shareCard: "旅程回顾"
        case .itinerary: "行程单"
        }
    }

    var systemImage: String {
        switch self {
        case .shareCard: "sparkles.rectangle.stack"
        case .itinerary: "doc.text"
        }
    }
}

enum ExportPhase: Equatable {
    case idle
    case loading
    case generating
    case success
    case failed
}

// MARK: - Share Card

enum ExportTemplate: String, CaseIterable, Identifiable {
    case travelCover = "travel-cover"
    case filmCollage = "film-collage"
    case minimalSummary = "minimal-summary"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .travelCover: "小红书封面"
        case .filmCollage: "胶片拼贴"
        case .minimalSummary: "极简总结"
        }
    }

    var description: String {
        switch self {
        case .travelCover: "大图主体，适合作为首图"
        case .filmCollage: "多图拼贴，复古手工感"
        case .minimalSummary: "数据为主，留白高级"
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case square
    case portrait

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .square: "方图 1:1"
        case .portrait: "竖图 9:16"
        }
    }

    var semanticLabel: String {
        switch self {
        case .square: "小红书 / 方图"
        case .portrait: "回顾 / 长图"
        }
    }

    var exportPixelSize: CGSize {
        switch self {
        case .square: CGSize(width: 1080, height: 1080)
        case .portrait: CGSize(width: 1080, height: 1920)
        }
    }

    var previewPixelSize: CGSize {
        switch self {
        case .square: CGSize(width: 280, height: 280)
        case .portrait: CGSize(width: 200, height: 355)
        }
    }
}

enum ExportCopyStyle: String, CaseIterable, Identifiable {
    case none
    case concise
    case mood

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "不显示文案"
        case .concise: "简洁总结"
        case .mood: "简短文案"
        }
    }
}

struct ExportMemoryHighlight: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
}

struct ExportContentOptions: Equatable {
    var showDate = true
    var showDays = true
    var showItineraryCount = true
    var showJournalCount = true
    var showExpense = true
    var showVisitedPlaces = true
    var showExpenseDistribution = true
    var showWatermark = true
    var copyStyle: ExportCopyStyle = .none

    init() {}

    init(from response: ExportContentOptionsResponse) {
        showDate = response.showDate
        showDays = response.showDays
        showItineraryCount = response.showItineraryCount
        showJournalCount = response.showJournalCount
        showExpense = response.showExpense
        showVisitedPlaces = response.showVisitedPlaces
        showExpenseDistribution = response.showExpenseDistribution
        showWatermark = response.showWatermark
        copyStyle = ExportCopyStyle(rawValue: response.copyStyle) ?? .none
    }

    var enabledCount: Int {
        [
            showDate,
            showDays,
            showItineraryCount,
            showJournalCount,
            showExpense,
            showVisitedPlaces,
            showExpenseDistribution,
            showWatermark
        ].filter { $0 }.count
    }
}

// MARK: - Export Assets Response

struct ExportAssetsResponse: Decodable, Equatable {
    let trip: ExportTripInfo
    let stats: ExportStats
    let photos: [ExportPhoto]
    let visitedPlaces: [String]
    let expenseCategoryStats: [ExportExpenseCategoryStat]
    let watermark: ExportWatermark
    let exportOptions: ExportOptionsResponse
}

struct ExportTripInfo: Decodable, Equatable {
    let id: String
    let title: String
    let destination: String
    let startDate: String
    let endDate: String
    let totalDays: Int
    let coverPhoto: String?
}

struct ExportStats: Decodable, Equatable {
    let itineraryCount: Int
    let journalCount: Int
    let photoCount: Int
    let expenseCount: Int
    let totalExpenseAmount: Double
    let averageDailyExpense: Double
    let currency: String
}

struct ExportPhoto: Decodable, Equatable, Identifiable {
    let fileId: String
    let journalId: String?
    let url: String
    let thumbnailUrl: String?
    let previewUrl: String?
    let exportUrl: String?
    let storyPortraitUrl: String?
    let storyCardUrl: String?
    let squareUrl: String?
    let width: Int?
    let height: Int?
    let sortOrder: Int

    var id: String { fileId }

    var renderURL: URL? {
        URL(string: exportUrl ?? storyPortraitUrl ?? previewUrl ?? url)
    }

    var storyPortraitURL: URL? {
        [storyPortraitUrl, exportUrl, previewUrl, url, thumbnailUrl]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }

    var storyCardURL: URL? {
        [storyCardUrl, previewUrl, url, thumbnailUrl]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }
}

struct ExportExpenseCategoryStat: Decodable, Equatable, Identifiable {
    let category: String
    let categoryName: String
    let amount: Double
    let percentage: Double
    let count: Int

    var id: String { category }
}

struct ExportWatermark: Decodable, Equatable {
    let enabled: Bool
    let text: String
}

struct ExportOptionsResponse: Decodable, Equatable {
    let template: String
    let format: String
    let contentOptions: ExportContentOptionsResponse
}

struct ExportContentOptionsResponse: Decodable, Equatable {
    let showDate: Bool
    let showDays: Bool
    let showItineraryCount: Bool
    let showJournalCount: Bool
    let showExpense: Bool
    let showVisitedPlaces: Bool
    let showExpenseDistribution: Bool
    let showWatermark: Bool
    let copyStyle: String
}
