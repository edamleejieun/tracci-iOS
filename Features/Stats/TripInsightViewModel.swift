import Foundation
import Observation

@MainActor
@Observable
final class TripInsightViewModel {
    private(set) var overview: TripStageOverview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let tripId: String

    private let tripService: TripService
    private let defaults: UserDefaults
    private var userScope = "anonymous"
    private var suggestionRevision = 0

    init(
        tripId: String,
        tripService: TripService,
        defaults: UserDefaults = .standard
    ) {
        self.tripId = tripId
        self.tripService = tripService
        self.defaults = defaults
    }

    var phase: TripStagePhase? {
        guard overview?.phase != .noTrip else { return nil }
        return overview?.phase
    }

    var activeSuggestion: TripStageSuggestion? {
        _ = suggestionRevision
        guard let suggestion = overview?.ongoing?.suggestions.first else { return nil }
        let key = storageKey(for: suggestion.suggestionKey)
        if defaults.bool(forKey: key + ".dismissed") { return nil }
        if let snoozedUntil = defaults.object(forKey: key + ".snoozedUntil") as? Date,
           snoozedUntil > Date() {
            return nil
        }
        return suggestion
    }

    // MARK: - Header (single narrative layer)

    /// Stage label only — "出发前" / "今天" / "已结束".
    var companionEyebrow: String {
        switch phase {
        case .planning: return "出发前"
        case .ongoing: return "今天"
        case .completed: return "已结束"
        case .noTrip, .none: return "旅程概况"
        }
    }

    /// Destination · days under the stage label.
    var companionContext: String? {
        guard let trip = overview?.focusTrip else { return nil }
        let place = trip.destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let days = trip.totalDays
        if !place.isEmpty, days > 0 {
            return "\(place) · \(days) 天"
        }
        if !place.isEmpty { return place }
        if days > 0 { return "\(days) 天旅程" }
        return trip.title
    }

    /// Combined meta for the light header: "出发前 · 京都 · 5 天".
    var headerMetaLine: String {
        if let context = companionContext, !context.isEmpty {
            return "\(companionEyebrow) · \(context)"
        }
        return companionEyebrow
    }

    /// The only prose line in the sheet header — fact first, no second scene/insight stack.
    /// When a suggestion card will carry the journal CTA, avoid restating “补日志”.
    var companionConclusion: String? {
        switch phase {
        case .planning:
            guard let planning = overview?.planning else {
                return "目的地和日期已定，可以继续补充行程。"
            }
            let emptyDays = planning.unplannedDates.count
            if emptyDays > 0 {
                return emptyDays == 1
                    ? "还有 1 天没有安排，可以从这一天补上。"
                    : "还有 \(emptyDays) 天没有安排，可以先补最想去的一天。"
            }
            if planning.departureDays > 0, planning.departureDays <= 3 {
                return "还有 \(planning.departureDays) 天出发，各天都已有安排。"
            }
            if let densest = planning.dailyNodeCounts.max(by: { $0.nodeCount < $1.nodeCount }),
               densest.nodeCount > 0 {
                return "最满的一天有 \(densest.nodeCount) 站，需要时再微调即可。"
            }
            return "各天都已有安排，需要时再微调即可。"

        case .ongoing:
            guard let today = overview?.ongoing?.today else {
                return "今天的安排和记录会显示在这里。"
            }
            let nodes = today.itineraryCount
            let journals = today.journalCount
            let photos = today.photoCount
            let records = journals + photos
            // Suggestion card owns the “补日志” action — keep header factual only.
            if nodes == 0, records == 0 {
                return "今天还没有安排和记录。"
            }
            if nodes >= 5 {
                return "今天行程 \(nodes) 站，安排偏满。"
            }
            if nodes > 0, records == 0 {
                return "今天有 \(nodes) 站行程。"
            }
            if nodes == 0, records > 0 {
                return "今天没有固定行程，已有 \(records) 条记录。"
            }
            var parts: [String] = []
            if nodes > 0 { parts.append("\(nodes) 站行程") }
            if journals > 0 { parts.append("\(journals) 篇日志") }
            if photos > 0 { parts.append("\(photos) 张照片") }
            return parts.isEmpty ? nil : "今天已有" + parts.joined(separator: "、") + "。"

        case .completed:
            guard let completed = overview?.completed else {
                return "行程、记录和花费整理在这里。"
            }
            if let busiest = completed.pace.busiestDate,
               completed.pace.busiestDayNodeCount > 0 {
                let dayLabel = shortMonthDay(from: busiest) ?? busiest
                return "最忙的一天是 \(dayLabel)，共 \(completed.pace.busiestDayNodeCount) 个行程点。"
            }
            if let avg = ExpenseFormatters.decimal(from: completed.averageDailyExpense), avg > 0 {
                return "日均花费 \(ExpenseFormatters.cny(avg))。"
            }
            switch completed.pace.level {
            case "RELAXED": return "这趟行程不紧，空档也不少。"
            case "BUSY": return "这趟行程比较满，安排和记录都不少。"
            default: return "旅程已结束，可查看花费与记录。"
            }

        case .noTrip, .none:
            return nil
        }
    }

    /// Real weather signal only — no filler “可供参考” lines.
    var planningWeatherNote: String? {
        guard let weather = overview?.planning?.weather else { return nil }
        let message = weather.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !weather.available, !message.isEmpty {
            return message
        }
        return nil
    }

    var ongoingExpenseText: String? {
        guard let today = overview?.ongoing?.today,
              let amount = ExpenseFormatters.decimal(from: today.expenseAmount),
              amount > 0
        else { return nil }
        return ExpenseFormatters.cny(amount)
    }

    // MARK: - Compact entry (detail workspace title)

    var entryTitle: String {
        if isLoading, overview == nil { return "旅程概况" }
        if errorMessage != nil, overview == nil { return "旅程概况" }
        switch phase {
        case .planning: return "出发前"
        case .ongoing: return "今天"
        case .completed: return "旅程回顾"
        case .noTrip, .none: return "旅程概况"
        }
    }

    var entrySubtitle: String {
        if isLoading, overview == nil { return "正在加载…" }
        if let errorMessage, overview == nil { return errorMessage }
        switch phase {
        case .planning:
            if let unplanned = overview?.planning?.unplannedDates, !unplanned.isEmpty {
                return "还有 \(unplanned.count) 天未安排"
            }
            if let days = overview?.planning?.departureDays {
                return days <= 0 ? "可以开始安排第一天" : "还有 \(max(days, 0)) 天出发"
            }
            return "查看出发前安排"
        case .ongoing:
            if activeSuggestion != nil {
                return "可以补一条日志"
            }
            if let today = overview?.ongoing?.today {
                let parts: [String] = [
                    today.itineraryCount > 0 ? "\(today.itineraryCount) 站" : nil,
                    today.journalCount > 0 ? "\(today.journalCount) 日志" : nil,
                    today.photoCount > 0 ? "\(today.photoCount) 照片" : nil
                ].compactMap { $0 }
                if !parts.isEmpty { return parts.joined(separator: " · ") }
            }
            return "今日概况"
        case .completed:
            return "花费与记录"
        case .noTrip, .none:
            return "查看这趟旅程"
        }
    }

    var entrySystemImage: String {
        switch phase {
        case .planning: return "calendar"
        case .ongoing: return "sun.max"
        case .completed: return "book.closed"
        case .noTrip, .none: return "text.book.closed"
        }
    }

    var entryShowsSoftDot: Bool {
        activeSuggestion != nil
    }

    var showsDetailEntry: Bool {
        true
    }

    // MARK: - Actions

    func setUserScope(_ userId: String?) {
        userScope = userId.flatMap { $0.isEmpty ? nil : $0 } ?? "anonymous"
    }

    private var isDemoMode = false

    func loadIfNeeded() async {
        guard !isDemoMode else { return }
        guard overview == nil, !isLoading else { return }
        await load()
    }

    func refresh() async {
        guard !isDemoMode else { return }
        await load()
    }

    /// Demo Journey: hydrate stage overview without network or UserDefaults writes.
    func applyDemoOverview(_ overview: TripStageOverview) {
        isDemoMode = true
        self.overview = overview
        isLoading = false
        errorMessage = nil
    }

    func dismissSuggestion(_ suggestion: TripStageSuggestion) {
        guard !isDemoMode else { return }
        defaults.set(true, forKey: storageKey(for: suggestion.suggestionKey) + ".dismissed")
        suggestionRevision += 1
    }

    func snoozeSuggestion(_ suggestion: TripStageSuggestion) {
        guard !isDemoMode else { return }
        let calendar = Calendar.current
        let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) ?? Date().addingTimeInterval(21_600)
        defaults.set(nextDay, forKey: storageKey(for: suggestion.suggestionKey) + ".snoozedUntil")
        suggestionRevision += 1
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await tripService.stageOverview(tripId: tripId)
            guard response.phase != .noTrip, response.focusTrip?.id == tripId else {
                overview = nil
                errorMessage = "暂时无法加载这趟旅程的概况"
                return
            }
            overview = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func storageKey(for suggestionKey: String) -> String {
        "insight.suggestion.\(userScope).\(suggestionKey)"
    }

    private func shortMonthDay(from dateString: String) -> String? {
        guard let date = TripDateFormatting.date(from: dateString) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    #if DEBUG
    func configureForPreview(isLoading: Bool) {
        self.isLoading = isLoading
    }
    #endif
}
