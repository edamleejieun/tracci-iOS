import Foundation

enum MemoryStoryPagePlanner {
    static func pages(for summary: TripSummaryResponse, visitedPlaceCount: Int) -> [StoryPageKind] {
        var pages: [StoryPageKind] = [.cover, .stats]

        let hasRichMaterial = summary.stats.photoCount >= 3
            || (summary.stats.journalCount >= 2 && summary.stats.photoCount >= 1)
        guard hasRichMaterial else {
            return pages + [.ending]
        }

        if visitedPlaceCount > 0 {
            pages.append(.places)
        }

        if summary.stats.photoCount > 0 || !summary.featuredPhotos.isEmpty {
            pages.append(.photos)
        }

        let hasExpenses = summary.stats.totalExpenseValue > 0
            || !(summary.expenseSummary?.categoryStats.filter { $0.amountValue > 0 }.isEmpty ?? true)
        if hasExpenses {
            pages.append(.expenses)
        }

        if let memorable = memorableLog(in: summary) {
            pages.append(.memorable)
            if let latest = latestJournalLog(in: summary), latest.id != memorable.id {
                pages.append(.journals)
            }
        }

        pages.append(.ending)
        return pages
    }

    static func memorableLog(in summary: TripSummaryResponse) -> TripSummaryLog? {
        let highlighted = summary.highlightLogs
            .filter { ($0.content ?? "").count >= 10 }
            .sorted { ($0.content ?? "").count > ($1.content ?? "").count }
            .first
        return highlighted ?? latestJournalLog(in: summary)
    }

    static func latestJournalLog(in summary: TripSummaryResponse) -> TripSummaryLog? {
        summary.dailyTimeline
            .flatMap(\.logs)
            .filter { ($0.content ?? "").count >= 10 }
            .sorted {
                let t0 = $0.logTime ?? ""
                let t1 = $1.logTime ?? ""
                if !t0.isEmpty || !t1.isEmpty { return t0 > t1 }
                return ($0.content ?? "").count > ($1.content ?? "").count
            }
            .first
    }
}
