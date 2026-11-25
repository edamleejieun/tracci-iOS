import Foundation

/// Pure trip display formatting shared by list and detail surfaces.
enum TripPresentation {
    static func dateRangeText(for trip: Trip) -> String {
        let start = displayDate(from: trip.startDate)
        let end = displayDate(from: trip.endDate)
        switch (start.isEmpty, end.isEmpty) {
        case (false, false): return "\(start) - \(end)"
        case (false, true): return start
        case (true, false): return end
        case (true, true): return "日期待定"
        }
    }

    static func totalDaysText(for trip: Trip) -> String {
        if let totalDays = trip.totalDays, totalDays > 0 { return "\(totalDays) 天" }
        guard let start = tripDate(from: trip.startDate),
              let end = tripDate(from: trip.endDate),
              let days = TracciDateContext.inclusiveDayCount(start: start, end: end)
        else { return "天数待定" }
        return "\(days) 天"
    }

    static func expenseText(for trip: Trip) -> String {
        guard let raw = trip.totalCny, !raw.isEmpty else { return "¥0" }
        let value = Double(raw) ?? 0
        guard value > 0 else { return "¥0" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "¥\(Int(value))"
    }

    static func destinationText(for trip: Trip) -> String {
        guard let destination = trip.destinationName, !destination.isEmpty else {
            return "未设置目的地"
        }
        return destination
    }

    static func currentDayText(for trip: Trip) -> String? {
        guard let pair = currentDayPair(for: trip) else { return nil }
        return "第 \(pair.current) / \(pair.total) 天"
    }

    static func phaseSubtitleText(for trip: Trip) -> String {
        switch trip.effectiveStatus {
        case .ongoing:
            let place = compactPlaceName(trip.destinationName) ?? trip.title
            if let pair = currentDayPair(for: trip) {
                return "今日第 \(pair.current) 天 · \(place)"
            }
            return "第 1 天 · \(place)"
        case .planning:
            if let days = daysUntilDeparture(for: trip), days > 0 { return "还有 \(days) 天出发" }
            if let days = daysUntilDeparture(for: trip), days == 0 { return "今天出发" }
            return "出发时间 待定"
        case .completed:
            return archiveSummaryText(for: trip)
        case .unknown:
            return "\(destinationText(for: trip)) · \(dateRangeText(for: trip))"
        }
    }

    static func phaseMetaTexts(for trip: Trip) -> [String] {
        switch trip.effectiveStatus {
        case .ongoing:
            var items: [String] = []
            if let count = trip.nodeCount, count > 0 { items.append("\(count) 个行程") }
            if let count = trip.journalCount, count > 0 { items.append("\(count) 条日志") }
            return items
        case .planning:
            guard let count = trip.nodeCount, count > 0 else { return [] }
            return ["\(count) 个行程"]
        case .completed:
            return []
        case .unknown:
            var items = [totalDaysText(for: trip)]
            if let count = trip.nodeCount, count > 0 { items.append("\(count) 个行程") }
            if let count = trip.journalCount, count > 0 { items.append("\(count) 条日志") }
            return items
        }
    }

    private static func archiveSummaryText(for trip: Trip) -> String {
        var parts: [String] = []
        let days = totalDaysText(for: trip)
        if days != "天数待定" { parts.append(days) }
        if let count = trip.journalCount, count > 0 { parts.append("\(count) 篇日志") }
        return parts.isEmpty ? dateRangeText(for: trip) : parts.joined(separator: " · ")
    }

    private static func daysUntilDeparture(for trip: Trip) -> Int? {
        guard let start = tripDate(from: trip.startDate) else { return nil }
        return TracciDateContext.calendar.dateComponents(
            [.day], from: TracciDateContext.today(), to: start
        ).day
    }

    private static func currentDayPair(for trip: Trip) -> (current: Int, total: Int)? {
        guard trip.effectiveStatus == .ongoing,
              let start = tripDate(from: trip.startDate),
              let total = trip.totalDays ?? inferredTotalDays(for: trip),
              total > 0
        else { return nil }
        let offset = TracciDateContext.calendar.dateComponents(
            [.day], from: start, to: TracciDateContext.today()
        ).day ?? 0
        return (min(max(offset + 1, 1), total), total)
    }

    private static func inferredTotalDays(for trip: Trip) -> Int? {
        guard let start = tripDate(from: trip.startDate),
              let end = tripDate(from: trip.endDate)
        else { return nil }
        return TracciDateContext.inclusiveDayCount(start: start, end: end)
    }

    private static func tripDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return TripDateFormatting.date(from: value)
    }

    private static func displayDate(from value: String?) -> String {
        guard let date = tripDate(from: value) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func compactPlaceName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
