import Foundation

/// App-wide business calendar (Asia/Shanghai).
/// Lives in Core so DesignSystem pickers do not reverse-depend on Features/Trip.
enum TracciDateContext {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        return calendar
    }

    static func startOfBusinessDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func today() -> Date {
        startOfBusinessDay(for: Date())
    }

    static func inclusiveDayCount(start: Date, end: Date) -> Int? {
        let startDay = startOfBusinessDay(for: start)
        let endDay = startOfBusinessDay(for: end)
        guard let days = calendar.dateComponents([.day], from: startDay, to: endDay).day, days >= 0 else {
            return nil
        }
        return days + 1
    }

    static func dayIndex(for date: Date, startDate: Date) -> Int? {
        let startDay = startOfBusinessDay(for: startDate)
        let targetDay = startOfBusinessDay(for: date)
        guard let offset = calendar.dateComponents([.day], from: startDay, to: targetDay).day else {
            return nil
        }
        return offset + 1
    }

    static func dateTime(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let utcFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        for format in utcFormats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return TripDateFormatting.date(from: value)
    }
}

/// Shared date string formatting for API payloads and UI display.
enum TripDateFormatting {
    private static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func apiString(from date: Date?) -> String {
        guard let date else { return "" }
        return apiFormatter.string(from: date)
    }

    static func date(from apiString: String?) -> Date? {
        guard let apiString, !apiString.isEmpty else { return nil }
        return apiFormatter.date(from: apiString)
    }

    static func displayString(from date: Date?) -> String {
        guard let date else { return "选择日期" }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}
