import Foundation

enum ExpenseFormatters {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        return formatter
    }()

    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let apiUTCDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()

    private static let apiUTCDateTimeWithFractionalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    private static let tripDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter
    }()

    // MARK: - Decimal / Money

    static func decimal(from string: String) -> Decimal? {
        decimalFormatter.number(from: string)?.decimalValue
    }

    static func money(_ value: Decimal, symbol: String = "") -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatted = moneyFormatter.string(from: number) ?? "\(number)"
        return "\(symbol)\(formatted)"
    }

    static func cny(_ value: Decimal) -> String {
        money(value, symbol: "¥")
    }

    // MARK: - API Date Parsing

    static func apiString(from date: Date) -> String {
        apiUTCDateTimeFormatter.string(from: date)
    }

    static func dateFromAPI(_ string: String) -> Date? {
        if let date = apiUTCDateTimeFormatter.date(from: string) {
            return date
        }
        if let date = apiUTCDateTimeWithFractionalFormatter.date(from: string) {
            return date
        }
        return tripDateFormatter.date(from: string)
    }

    static func tripDateRange(start: String, end: String) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let startDate = tripDateFormatter.date(from: start)
            ?? dateFromAPI(start)
            ?? Date.distantPast
        let rawEndDate = tripDateFormatter.date(from: end)
            ?? dateFromAPI(end)
            ?? Date.distantFuture

        let endDate: Date
        if rawEndDate != Date.distantFuture,
           let dayEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: rawEndDate)) {
            endDate = dayEnd
        } else {
            endDate = rawEndDate
        }

        return startDate...max(startDate, endDate)
    }

    static func displayTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(displayTimeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "昨天 \(displayTimeFormatter.string(from: date))"
        } else {
            return displayDateFormatter.string(from: date)
        }
    }

    static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter.string(from: date)
    }
}
