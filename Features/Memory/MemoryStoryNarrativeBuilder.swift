import Foundation
import SwiftUI

enum MemoryStoryHeroMetricKind {
    case photos
    case journals
    case days

    var storyIcon: String {
        switch self {
        case .photos: "camera"
        case .journals: "heart.text.square"
        case .days: "calendar"
        }
    }
}

struct MemoryStoryHeroMetric {
    let kind: MemoryStoryHeroMetricKind
    let value: Int
    let unit: String
    let caption: String
    let color: Color
}

struct MemoryStoryNarrative {
    let stats: String
    let places: String
    let photos: String
    let expenses: String
    let memorable: String
    let journals: String
    let endingSummary: String
    let poster: String
}

enum MemoryStoryNarrativeBuilder {
    static func build(for summary: TripSummaryResponse) -> MemoryStoryNarrative {
        let facts = Facts(summary: summary)

        return MemoryStoryNarrative(
            stats: statsNarrative(facts),
            places: placesNarrative(facts),
            photos: photosNarrative(facts),
            expenses: expensesNarrative(facts),
            memorable: memorableNarrative(facts),
            journals: journalsNarrative(facts),
            endingSummary: endingSummary(facts),
            poster: posterNarrative(facts)
        )
    }

    static func primaryHeroMetric(for summary: TripSummaryResponse) -> MemoryStoryHeroMetric {
        let placeCount = visitedPlaces(from: summary).count
        let stats = summary.stats

        if stats.photoCount >= max(stats.dayCount, stats.journalCount), stats.photoCount > 0 {
            return MemoryStoryHeroMetric(
                kind: .photos,
                value: stats.photoCount,
                unit: "张照片",
                caption: "旅途中的照片",
                color: MemoryColors.accentAmber
            )
        }
        if stats.journalCount >= max(stats.dayCount, placeCount), stats.journalCount > 0 {
            return MemoryStoryHeroMetric(
                kind: .journals,
                value: stats.journalCount,
                unit: "篇日志",
                caption: "当时写下的记录",
                color: MemoryColors.accentPink
            )
        }
        return MemoryStoryHeroMetric(
            kind: .days,
            value: max(stats.dayCount, 1),
            unit: "天旅程",
            caption: "这段旅程的天数",
            color: MemoryColors.accentBlue
        )
    }

    static func visitedPlaces(from summary: TripSummaryResponse) -> [String] {
        let names = summary.dailyTimeline.flatMap { day in
            day.itineraries.compactMap { node in
                node.displayTitle
            }
        }
        return Array(Set(names)).sorted()
    }

    private static func statsNarrative(_ facts: Facts) -> String {
        if facts.isSparse {
            return "记录还不多，先看已经有的"
        }
        if facts.days <= 2 && facts.photos <= 3 && facts.journals <= 1 {
            return "天数不长，也留下了一些"
        }
        if facts.photos >= 30 || facts.journals >= 5 {
            return "记录比较多，可以慢慢看"
        }
        if facts.places >= 5 {
            return "\(facts.days) 天，去了 \(facts.places) 个地方"
        }
        if facts.journals >= 3 {
            return "\(facts.journals) 篇日志，走过 \(facts.days) 天"
        }
        if facts.photos >= 10 {
            return "\(facts.photos) 张照片，记录了这段路"
        }
        return "下面是这段旅程留下的"
    }

    private static func placesNarrative(_ facts: Facts) -> String {
        if facts.places == 0 {
            return "还没有记下具体地点"
        }
        if facts.places == 1 {
            return "主要都在这一处"
        }
        if facts.places >= 5 {
            return "一共去了 \(facts.places) 个地方"
        }
        return "这些是路上到过的地方"
    }

    private static func photosNarrative(_ facts: Facts) -> String {
        if facts.featuredPhotos == 0 {
            return "还没有点亮特别想留的照片"
        }
        if facts.featuredPhotos == 1 {
            return "有 1 张你特别标过的照片"
        }
        return "这些是你特别标过的画面"
    }

    private static func expensesNarrative(_ facts: Facts) -> String {
        if facts.totalExpense <= 0 {
            return "还没有记下花费"
        }
        if facts.expenseCount >= 20 {
            return "花费条目较多，可以按类别查看"
        }
        return "这些是路上的花费"
    }

    private static func memorableNarrative(_ facts: Facts) -> String {
        facts.hasMemorableLog
            ? "下面是你标过的重要时刻"
            : "还没有标过特别重要的日志"
    }

    private static func journalsNarrative(_ facts: Facts) -> String {
        if facts.journals == 0 {
            return "还没有写下日志"
        }
        if facts.journals == 1 {
            return "有 1 篇日志"
        }
        return "一共 \(facts.journals) 篇日志"
    }

    private static func endingSummary(_ facts: Facts) -> String {
        var parts: [String] = []
        if facts.days > 0 {
            parts.append("\(facts.days) 天")
        }
        if facts.places > 0 {
            parts.append("\(facts.places) 个地点")
        }
        if facts.photos > 0 {
            parts.append("\(facts.photos) 张照片")
        }
        if parts.isEmpty {
            return "这段旅程"
        }
        return parts.joined(separator: " · ")
    }

    private static func posterNarrative(_ facts: Facts) -> String {
        if facts.days <= 2 && facts.photos <= 3 && facts.journals <= 1 {
            return "天数不长 · 也留下了一些"
        }
        if facts.photos >= 30 {
            return "\(facts.photos) 张照片 · 可以回看"
        }
        if facts.places >= 5 {
            return "去了 \(facts.places) 个地方"
        }
        if facts.journals >= 3 {
            return "\(facts.journals) 篇日志"
        }
        if facts.photos >= 10 {
            return "\(facts.photos) 张照片"
        }
        return "这段旅程留下的"
    }

    private struct Facts {
        let days: Int
        let places: Int
        let photos: Int
        let featuredPhotos: Int
        let journals: Int
        let expenseCount: Int
        let totalExpense: Double
        let hasMemorableLog: Bool

        var isSparse: Bool {
            photos == 0 && journals == 0 && places == 0
        }

        init(summary: TripSummaryResponse) {
            days = summary.stats.dayCount
            places = MemoryStoryNarrativeBuilder.visitedPlaces(from: summary).count
            photos = summary.stats.photoCount
            featuredPhotos = summary.featuredPhotos.count
            journals = summary.stats.journalCount
            expenseCount = summary.stats.expenseCount
            totalExpense = summary.stats.totalExpenseValue
            hasMemorableLog = MemoryStoryPagePlanner.memorableLog(in: summary) != nil
        }
    }
}
