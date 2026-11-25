import Foundation

// MARK: - Stats Spend Analysis

struct StatsSpendAnalysis: Decodable, Equatable {
    let totalAmount: String
    let averageDailyExpense: String?
    let averageTripExpense: String?
    let expenseCount: Int
    let currency: String?
    let topCategory: String?
    let topCategoryName: String?
    let insight: String?
    let categoryStats: [StatsCategoryStat]
    let tripEfficiency: [StatsTripSpendEfficiency]

    enum CodingKeys: String, CodingKey {
        case totalAmount
        case averageDailyExpense
        case averageTripExpense
        case expenseCount
        case currency
        case topCategory
        case topCategoryName
        case insight
        case categoryStats
        case tripEfficiency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalAmount = try container.decode(String.self, forKey: .totalAmount)
        averageDailyExpense = try container.decodeIfPresent(String.self, forKey: .averageDailyExpense)
        averageTripExpense = try container.decodeIfPresent(String.self, forKey: .averageTripExpense)
        expenseCount = try container.decodeIfPresent(Int.self, forKey: .expenseCount) ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        topCategory = try container.decodeIfPresent(String.self, forKey: .topCategory)
        topCategoryName = try container.decodeIfPresent(String.self, forKey: .topCategoryName)
        insight = try container.decodeIfPresent(String.self, forKey: .insight)
        categoryStats = try container.decodeIfPresent([StatsCategoryStat].self, forKey: .categoryStats) ?? []
        tripEfficiency = try container.decodeIfPresent([StatsTripSpendEfficiency].self, forKey: .tripEfficiency) ?? []
    }
}

struct StatsTripSpendEfficiency: Decodable, Equatable, Identifiable {
    let tripId: String
    let title: String?
    let destinationName: String?
    let totalDays: Int?
    let totalAmount: String?
    let averageDailyExpense: String?

    var id: String { tripId }
}
