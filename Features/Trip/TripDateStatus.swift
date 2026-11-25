import Foundation

/// Trip-domain status calculation stays in Features/Trip.
/// Calendar primitives live in Core (`TracciDateContext` / `TripDateFormatting`).
extension TracciDateContext {
    static func tripStatus(startDate: String?, endDate: String?, now: Date = Date()) -> TripStatus? {
        guard
            let start = TripDateFormatting.date(from: startDate),
            let end = TripDateFormatting.date(from: endDate)
        else {
            return nil
        }
        return tripStatus(startDate: start, endDate: end, now: now)
    }

    /// 基于 Date 的状态计算（与 String 版本算法一致），便于客户端预检直接复用
    static func tripStatus(startDate: Date, endDate: Date, now: Date = Date()) -> TripStatus {
        let today = startOfBusinessDay(for: now)
        let startDay = startOfBusinessDay(for: startDate)
        let endDay = startOfBusinessDay(for: endDate)

        if today < startDay { return .planning }
        if today > endDay { return .completed }
        return .ongoing
    }
}
