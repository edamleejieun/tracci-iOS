import Foundation

// MARK: - Stats Models Index
//
// Stats 模型按职责拆分到独立文件：
//   - StatsOverviewModels.swift   → StatsOverviewResponse / StatsScope / StatsOverview / StatsExpenseStats / StatsCategoryStat / StatsRecentTrip / StatsMonthlyTrendItem / StatsDailyTrendItem / StatsInsightItem / StatsAnalysisEntry / StatsMemoryFacts
//   - StatsSpendAnalysisModels.swift → StatsSpendAnalysis / StatsTripSpendEfficiency
//   - StatsRecordsAnalysisModels.swift → StatsRecordsAnalysis / StatsTripRecords
//   - StatsFootprintAnalysisModels.swift → StatsFootprintAnalysis / StatsCityFootprint / StatsNodeTypeStat
//
// 本文件仅保留 Trip Stage 相关模型。

// MARK: - Trip Stage Overview

struct TripStageOverview: Decodable, Equatable {
    let generatedDate: String
    let timeZone: String
    let timeZoneFallbackApplied: Bool
    let phase: TripStagePhase
    let focusTrip: TripStageFocusTrip?
    let permissions: TripStagePermissions?
    let selection: TripStageSelection
    let planning: TripStagePlanning?
    let ongoing: TripStageOngoing?
    let memory: TripStageMemory?
    let completed: TripStageCompleted?
    let actions: [TripStageAction]
}

struct TripStagePermissions: Decodable, Equatable {
    let canAddJournal: Bool
    let canFeaturePhoto: Bool
}

enum TripStagePhase: String, Decodable, Equatable {
    case noTrip = "NO_TRIP"
    case planning = "PLANNING"
    case ongoing = "ONGOING"
    case completed = "COMPLETED"
}

struct TripStageFocusTrip: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let destinationName: String
    let startDate: String
    let endDate: String
    let totalDays: Int
}

struct TripStageSelection: Decodable, Equatable {
    let mode: String
    let reason: String
    let candidateCount: Int
}

struct TripStagePlanning: Decodable, Equatable {
    let totalDays: Int
    let scheduledDayCount: Int
    let dailyNodeCounts: [TripStageDailyNodeCount]
    let density: TripStageDensity
    let departureDays: Int
    let weather: TripStageWeather
    let unplannedDates: [String]
}

struct TripStageDailyNodeCount: Decodable, Equatable, Identifiable {
    let date: String
    let dayIndex: Int
    let nodeCount: Int
    var id: String { date }
}

struct TripStageDensity: Decodable, Equatable {
    let level: String
    let nodeCount: Int
    let totalDays: Int
    let averageNodesPerDay: String
    let ruleVersion: String
}

struct TripStageWeather: Decodable, Equatable {
    let available: Bool
    let status: String
    let message: String
}

struct TripStageOngoing: Decodable, Equatable {
    let today: TripStageToday
    let suggestions: [TripStageSuggestion]
}

struct TripStageToday: Decodable, Equatable {
    let date: String
    let itineraryCount: Int
    let expenseAmount: String
    let currency: String
    let journalCount: Int
    let photoCount: Int
}

struct TripStageSuggestion: Decodable, Equatable, Identifiable {
    let suggestionKey: String
    let date: String
    let facts: [String: Int]
    let action: String
    let targetDate: String
    var id: String { suggestionKey }
}

struct TripStageMemory: Decodable, Equatable {
    let journalCount: Int
    let photoCount: Int
    let userFeaturedJournalCount: Int
    let userFeaturedPhotoCount: Int
    let systemRecommendedPhotoCount: Int
    let dailyMaterials: [TripStageDailyMaterial]
    let recentFragments: [TripStageRecentFragment]
    let cover: TripStageCover
    let displayableContent: TripStageDisplayableContent
}

struct TripStageDailyMaterial: Decodable, Equatable, Identifiable {
    let date: String
    let dayIndex: Int
    let itineraryCount: Int
    let journalCount: Int
    let photoCount: Int
    var id: String { date }
}

struct TripStageRecentFragment: Decodable, Equatable, Identifiable {
    let journalId: String
    let date: String
    let hasText: Bool
    let photoCount: Int
    var id: String { journalId }
}

struct TripStageCover: Decodable, Equatable {
    let available: Bool
    let source: String
}

struct TripStageDisplayableContent: Decodable, Equatable {
    let sections: [String]
    let presentation: String
}

struct TripStageCompleted: Decodable, Equatable {
    let totalExpenseAmount: String
    let averageDailyExpense: String
    let currency: String
    let categoryStats: [TripStageExpenseCategory]
    let dailyTrend: [TripStageDailyTrend]
    let pace: TripStagePace
}

struct TripStageExpenseCategory: Decodable, Equatable, Identifiable {
    let category: String
    let categoryName: String
    let amount: String
    let percentage: String
    let count: Int
    var id: String { category }
}

struct TripStageDailyTrend: Decodable, Equatable, Identifiable {
    let date: String
    let dayIndex: Int
    let itineraryCount: Int
    let journalCount: Int
    let photoCount: Int
    let expenseAmount: String
    let paceLevel: String
    var id: String { date }
}

struct TripStagePace: Decodable, Equatable {
    let level: String
    let busiestDate: String?
    let busiestDayNodeCount: Int
    let ruleVersion: String
}

struct TripStageAction: Decodable, Equatable, Identifiable {
    let type: String
    let title: String
    let tripId: String?
    let date: String?
    var id: String { [type, tripId ?? "", date ?? ""].joined(separator: ":") }
}
