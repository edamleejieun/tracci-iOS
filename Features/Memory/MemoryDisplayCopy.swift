import Foundation

enum MemoryDisplayCopy {
    static func isSparse(stats: TripSummaryStats) -> Bool {
        stats.itineraryCount == 0
            && stats.journalCount == 0
            && stats.photoCount == 0
            && stats.expenseCount == 0
    }

    static func isSparse(trip: Trip) -> Bool {
        (trip.nodeCount ?? 0) == 0
            && (trip.journalCount ?? 0) == 0
            && (trip.expenseCount ?? 0) == 0
    }

    static func launcherHeadline(isSparse: Bool, isRevisit: Bool = false) -> String {
        if isRevisit {
            return isSparse ? "再看一遍也可以" : "再看这段旅程？"
        }
        return isSparse
            ? "记录还不多"
            : "打开这段旅程？"
    }

    static func launcherSubtitle(isSparse: Bool, isRevisit: Bool = false) -> String {
        if isRevisit {
            return isSparse
                ? "内容还不多，也可以先回看基础信息。"
                : "照片、行程和日志还在这里。"
        }
        return isSparse
            ? "会先展示日期和地点。之后补了照片和日志，内容会更完整。"
            : "照片、行程和日志都在这里。"
    }

    static func launcherStartTitle(isRevisit: Bool) -> String {
        isRevisit ? "再看一遍" : "开始回顾"
    }

    static func isStoryWellRounded(trip: Trip) -> Bool {
        !isSparse(trip: trip)
    }

    /// Day count is already on the cover page — keep sparse copy qualitative.
    static func storySparseStatsNarrative(dayCount: Int) -> String {
        if dayCount > 0 {
            return "记录还不多。以后补一点，再回来看也可以。"
        }
        return "还没什么记录，先从基础信息看起。"
    }
}
