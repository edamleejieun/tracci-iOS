import Foundation

enum ExportFormatting {
    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private static let shortMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static func dateRangeText(startDate: String, endDate: String) -> String {
        guard
            let start = apiDateFormatter.date(from: startDate),
            let end = apiDateFormatter.date(from: endDate)
        else {
            return "\(startDate) - \(endDate)"
        }

        let startText = displayDateFormatter.string(from: start)
        let endText = shortMonthDayFormatter.string(from: end)
        return "\(startText) - \(endText)"
    }

    static func currencyText(amount: Double, currency: String) -> String {
        let symbol = currency == "CNY" ? "¥" : currency + " "
        if amount.rounded() == amount {
            return "\(symbol)\(Int(amount))"
        }
        return String(format: "\(symbol)%.2f", amount)
    }

    static func copyText(
        style: ExportCopyStyle,
        trip: ExportTripInfo,
        stats: ExportStats
    ) -> String {
        switch style {
        case .none:
            return ""
        case .concise:
            return "\(trip.totalDays)天，\(stats.journalCount)篇日志，记录了这趟旅行的美好。"
        case .mood:
            return "在\(trip.destination)的风里，忘记时间的存在。"
        }
    }

    static func itineraryPlainText(
        trip: ItineraryExportTripInfo,
        days: [ItineraryExportDay],
        selectedDates: Set<String>
    ) -> String {
        let filteredDays = days.filter { selectedDates.contains($0.date) }
        var lines: [String] = []
        lines.append("\(trip.title) 行程单")
        lines.append(dateRangeText(startDate: trip.startDate, endDate: trip.endDate))
        lines.append("")

        for day in filteredDays {
            let weekday = weekdayLabel(for: day.date)
            lines.append("第 \(day.dayIndex) 天 · \(shortDateLabel(day.date)) \(weekday)")
            if day.nodes.isEmpty {
                lines.append("  （暂无行程节点）")
            } else {
                for node in day.nodes {
                    var line = "  "
                    if let time = node.timeText {
                        line += "\(time) "
                    }
                    line += node.displayTitle
                    if let location = node.locationText {
                        line += " @ \(location)"
                    }
                    lines.append(line)
                }
            }
            lines.append("")
        }

        lines.append("— 由趣溪生成")
        return lines.joined(separator: "\n")
    }

    static func shareCopy(from summary: TripSummaryResponse) -> ShareCopyResult {
        var bodyLines: [String] = []
        let destination = summary.trip.destination.isEmpty ? summary.trip.title : summary.trip.destination

        if summary.trip.dayCount > 0 {
            bodyLines.append("在\(destination)的\(summary.trip.dayCount)天，被我认真地存进了趣溪。")
        } else {
            bodyLines.append("这趟\(destination)之旅，被我认真地存进了趣溪。")
        }

        if summary.stats.itineraryCount > 0 {
            bodyLines.append("这趟旅行一共记录了\(summary.stats.itineraryCount)个行程点。")
        }
        if summary.stats.journalCount > 0 {
            bodyLines.append("还留下了\(summary.stats.journalCount)段当时的心情。")
        }
        if summary.stats.photoCount > 0 {
            bodyLines.append("相册里有\(summary.stats.photoCount)张照片，替我记住了路上的光。")
        }
        if summary.stats.totalExpenseValue > 0 {
            bodyLines.append("总花费约 \(currencyText(amount: summary.stats.totalExpenseValue, currency: summary.stats.currency))，也算是给这段旅程做了一个小小的注脚。")
        }

        bodyLines.append("来自趣溪 App")

        var tags = ["#趣溪", "#Tracci"]
        if !destination.isEmpty {
            tags.append("#\(destination.replacingOccurrences(of: " ", with: ""))")
        }

        return ShareCopyResult(
            title: "\(destination)旅程回顾",
            body: bodyLines.joined(separator: "\n"),
            hashtags: tags
        )
    }

    static func fallbackTripShareText(trip: Trip) -> String {
        var lines: [String] = []
        let destination = trip.destinationName ?? trip.title
        if let totalDays = trip.totalDays, totalDays > 0 {
            lines.append("在\(destination)的\(totalDays)天，被我认真地存进了趣溪。")
        } else {
            lines.append("这趟\(destination)之旅，被我认真地存进了趣溪。")
        }
        if let nodeCount = trip.nodeCount, nodeCount > 0 {
            lines.append("这趟旅行一共记录了\(nodeCount)个行程点。")
        }
        if let journalCount = trip.journalCount, journalCount > 0 {
            lines.append("还留下了\(journalCount)段当时的心情。")
        }
        if let totalCnyString = trip.totalCny, let totalCny = Double(totalCnyString), totalCny > 0 {
            lines.append("总花费约 \(currencyText(amount: totalCny, currency: trip.baseCurrency ?? "CNY"))。")
        }
        lines.append("来自趣溪 App")
        return lines.joined(separator: "\n")
    }

    private static func shortDateLabel(_ dateString: String) -> String {
        guard let date = apiDateFormatter.date(from: dateString) else {
            return dateString
        }
        return shortMonthDayFormatter.string(from: date)
    }

    private static func weekdayLabel(for dateString: String) -> String {
        guard let date = apiDateFormatter.date(from: dateString) else {
            return ""
        }
        return weekdayFormatter.string(from: date)
    }
}
