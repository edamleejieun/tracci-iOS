import Foundation

// MARK: - Stats Overview (production `StatsOverviewResp`)

/// Full production shape for `GET /stats/overview` and Demo Bundle `stats.overview`.
struct StatsOverviewResponse: Decodable, Equatable {
    let scope: StatsScope?
    let overview: StatsOverview
    let expenseStats: StatsExpenseStats?
    let recentTrips: [StatsRecentTrip]
    let monthlyTrend: [StatsMonthlyTrendItem]
    let dailyTrend: [StatsDailyTrendItem]
    let insights: [StatsInsightItem]
    let analysisEntries: [StatsAnalysisEntry]
    let memory: StatsMemoryFacts?

    enum CodingKeys: String, CodingKey {
        case scope
        case overview
        case expenseStats
        case recentTrips
        case monthlyTrend
        case dailyTrend
        case insights
        case analysisEntries
        case memory
    }

    init(
        scope: StatsScope? = nil,
        overview: StatsOverview,
        expenseStats: StatsExpenseStats? = nil,
        recentTrips: [StatsRecentTrip] = [],
        monthlyTrend: [StatsMonthlyTrendItem] = [],
        dailyTrend: [StatsDailyTrendItem] = [],
        insights: [StatsInsightItem] = [],
        analysisEntries: [StatsAnalysisEntry] = [],
        memory: StatsMemoryFacts? = nil
    ) {
        self.scope = scope
        self.overview = overview
        self.expenseStats = expenseStats
        self.recentTrips = recentTrips
        self.monthlyTrend = monthlyTrend
        self.dailyTrend = dailyTrend
        self.insights = insights
        self.analysisEntries = analysisEntries
        self.memory = memory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decodeIfPresent(StatsScope.self, forKey: .scope)
        overview = try container.decode(StatsOverview.self, forKey: .overview)
        expenseStats = try container.decodeIfPresent(StatsExpenseStats.self, forKey: .expenseStats)
        recentTrips = try container.decodeIfPresent([StatsRecentTrip].self, forKey: .recentTrips) ?? []
        monthlyTrend = try container.decodeIfPresent([StatsMonthlyTrendItem].self, forKey: .monthlyTrend) ?? []
        dailyTrend = try container.decodeIfPresent([StatsDailyTrendItem].self, forKey: .dailyTrend) ?? []
        insights = try container.decodeIfPresent([StatsInsightItem].self, forKey: .insights) ?? []
        analysisEntries = try container.decodeIfPresent([StatsAnalysisEntry].self, forKey: .analysisEntries) ?? []
        memory = try container.decodeIfPresent(StatsMemoryFacts.self, forKey: .memory)
    }
}

struct StatsScope: Decodable, Equatable {
    let type: String?
    let tripId: String?
    let tripTitle: String?
}

struct StatsOverview: Decodable, Equatable {
    let tripCount: Int
    let totalTravelDays: Int
    let itineraryCount: Int
    let journalCount: Int
    let photoCount: Int
    let destinationCount: Int
    let expenseCount: Int
    let totalExpenseAmount: String
    let averageDailyExpense: String
    let currency: String
}

struct StatsExpenseStats: Decodable, Equatable {
    let totalAmount: String
    let currency: String
    let categoryStats: [StatsCategoryStat]
}

struct StatsCategoryStat: Decodable, Equatable, Identifiable {
    let category: String
    let categoryName: String
    let amount: String
    let percentage: String
    let count: Int

    var id: String { category }
}

struct StatsRecentTrip: Decodable, Equatable, Identifiable {
    let id: String
    let title: String?
    let destinationName: String?
    let startDate: String?
    let endDate: String?
    let status: String?
    let totalDays: Int?
    let totalExpenseAmount: String?
    let averageDailyExpense: String?
}

struct StatsMonthlyTrendItem: Decodable, Equatable, Identifiable {
    let yearMonth: String
    let amount: String?
    let count: Int?

    var id: String { yearMonth }
}

struct StatsDailyTrendItem: Decodable, Equatable, Identifiable {
    let date: String
    let dayIndex: Int?
    let highlight: String?
    let itineraryCount: Int?
    let journalCount: Int?
    let expenseAmount: String?
    let photoCount: Int?

    var id: String { date }
}

struct StatsInsightItem: Decodable, Equatable {
    let type: String?
    let text: String?
    let relatedTripId: String?
}

struct StatsAnalysisEntry: Decodable, Equatable, Identifiable {
    let kind: String
    let title: String?
    let subtitle: String?

    var id: String { kind }
}

struct StatsMemoryFacts: Decodable, Equatable {
    let journalCount: Int?
    let photoCount: Int?
    let userFeaturedJournalCount: Int?
    let userFeaturedPhotoCount: Int?
    let systemRecommendedPhotoCount: Int?
    let coverAvailable: Bool?
}
