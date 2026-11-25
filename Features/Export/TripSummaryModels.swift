import Foundation

// MARK: - Trip Review Summary

struct TripSummaryResponse: Decodable, Equatable {
    let trip: TripSummaryTrip
    let stats: TripSummaryStats
    let expenseSummary: TripSummaryExpenseSummary?
    let highlightLogs: [TripSummaryLog]
    let userFeaturedPhotos: [TripSummaryPhoto]
    let recommendedPhotos: [TripSummaryPhoto]
    let dailyTimeline: [TripSummaryDay]

    var featuredPhotos: [TripSummaryPhoto] {
        userFeaturedPhotos + recommendedPhotos
    }
}

struct TripSummaryTrip: Decodable, Equatable {
    let id: String
    let title: String
    let destination: String
    let startDate: String
    let endDate: String
    let dayCount: Int
    let status: String
    let coverPhoto: TripSummaryPhoto?
}

struct TripSummaryStats: Decodable, Equatable {
    let dayCount: Int
    let itineraryCount: Int
    let journalCount: Int
    let photoCount: Int
    let expenseCount: Int
    let totalExpenseAmount: String
    let currency: String
    let highlightCount: Int

    var totalExpenseValue: Double {
        Double(totalExpenseAmount) ?? 0
    }
}

struct TripSummaryExpenseSummary: Decodable, Equatable {
    let totalAmount: String
    let currency: String
    let categoryStats: [TripSummaryExpenseCategory]
}

struct TripSummaryExpenseCategory: Decodable, Equatable, Identifiable {
    let category: String
    let categoryName: String
    let amount: String
    let percentage: String
    let count: Int

    var id: String { category }

    var amountValue: Double {
        Double(amount) ?? 0
    }

    var percentageValue: Double {
        Double(percentage) ?? 0
    }
}

struct TripSummaryLog: Decodable, Equatable, Identifiable {
    let id: String
    let content: String?
    let locationName: String?
    let logTime: String?
    let isHighlight: Bool
    let photos: [TripSummaryPhoto]
}

struct TripSummaryPhoto: Decodable, Equatable, Identifiable {
    let id: String
    let fileId: String
    let journalId: String?
    let url: String
    let thumbnailUrl: String?
    let previewUrl: String?
    let exportUrl: String?
    let storyPortraitUrl: String?
    let storyCardUrl: String?
    let squareUrl: String?
    let watermarkedUrl: String?
    let width: Int?
    let height: Int?
    let sortOrder: Int?
    let userFeatured: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fileId
        case journalId
        case url
        case thumbnailUrl
        case previewUrl
        case exportUrl
        case storyPortraitUrl
        case storyCardUrl
        case squareUrl
        case watermarkedUrl
        case width
        case height
        case sortOrder
        case userFeatured
    }

    init(
        id: String,
        fileId: String,
        journalId: String?,
        url: String,
        thumbnailUrl: String?,
        previewUrl: String?,
        exportUrl: String?,
        storyPortraitUrl: String?,
        storyCardUrl: String?,
        squareUrl: String?,
        watermarkedUrl: String?,
        width: Int?,
        height: Int?,
        sortOrder: Int?,
        userFeatured: Bool
    ) {
        self.id = id
        self.fileId = fileId
        self.journalId = journalId
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.previewUrl = previewUrl
        self.exportUrl = exportUrl
        self.storyPortraitUrl = storyPortraitUrl
        self.storyCardUrl = storyCardUrl
        self.squareUrl = squareUrl
        self.watermarkedUrl = watermarkedUrl
        self.width = width
        self.height = height
        self.sortOrder = sortOrder
        self.userFeatured = userFeatured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fileId = try container.decodeIfPresent(String.self, forKey: .fileId) ?? ""

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? fileId
        self.fileId = fileId
        journalId = try container.decodeIfPresent(String.self, forKey: .journalId)
        url = try container.decode(String.self, forKey: .url)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl)
        exportUrl = try container.decodeIfPresent(String.self, forKey: .exportUrl)
        storyPortraitUrl = try container.decodeIfPresent(String.self, forKey: .storyPortraitUrl)
        storyCardUrl = try container.decodeIfPresent(String.self, forKey: .storyCardUrl)
        squareUrl = try container.decodeIfPresent(String.self, forKey: .squareUrl)
        watermarkedUrl = try container.decodeIfPresent(String.self, forKey: .watermarkedUrl)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        userFeatured = try container.decodeIfPresent(Bool.self, forKey: .userFeatured) ?? false
    }

    var renderURLs: [URL] {
        [storyPortraitUrl, storyCardUrl, exportUrl, previewUrl, url, thumbnailUrl]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
    }

    var storyPortraitURLs: [URL] {
        [storyPortraitUrl, exportUrl, previewUrl, url, storyCardUrl, thumbnailUrl]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
    }

    var storyCardURLs: [URL] {
        [storyCardUrl, previewUrl, url, thumbnailUrl, storyPortraitUrl]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
    }

    var squareURLs: [URL] {
        [squareUrl, thumbnailUrl, previewUrl, url]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
    }
}

struct TripSummaryDay: Decodable, Equatable, Identifiable {
    var id: String { date }

    let date: String
    let dayIndex: Int
    let itineraries: [TripSummaryItineraryNode]
    let logs: [TripSummaryLog]
}

struct TripSummaryItineraryNode: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let locationName: String?
    let startTime: String?
    let endTime: String?

    /// 展示用标题：优先展示地点名称，title 为空时兜底。
    var displayTitle: String {
        if let name = locationName, !name.isEmpty {
            return name
        }
        if !title.isEmpty {
            return title
        }
        return "未命名行程"
    }
}

struct ShareCopyResult: Equatable {
    let title: String
    let body: String
    let hashtags: [String]

    var fullText: String {
        ([title, body].filter { !$0.isEmpty } + [hashtags.joined(separator: " ")].filter { !$0.isEmpty })
            .joined(separator: "\n\n")
    }
}
