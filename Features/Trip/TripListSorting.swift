import Foundation

enum TripListSorting {
    static func sorted(_ trips: [Trip]) -> [Trip] {
        trips.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.effectiveStatus == .ongoing, rhs.element.effectiveStatus != .ongoing {
                    return true
                }

                if lhs.element.effectiveStatus != .ongoing, rhs.element.effectiveStatus == .ongoing {
                    return false
                }

                let lhsDate = sortDate(for: lhs.element)
                let rhsDate = sortDate(for: rhs.element)

                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                    return lhs.offset < rhs.offset
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func sortDate(for trip: Trip) -> Date? {
        tripDate(from: trip.startDate) ?? isoDate(from: trip.updatedAt) ?? isoDate(from: trip.createdAt)
    }

    private static func tripDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func isoDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
