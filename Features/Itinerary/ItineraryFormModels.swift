import Foundation

struct ItineraryNodeFormState: Equatable {
    var savedPlaceId: String?
    var dayIndex: Int
    var title: String
    var type: ItineraryNodeType
    var locationName: String
    var selectedLocation: ItineraryLocation?
    var startTime: String
    var endTime: String
    var note: String

    // Transport details
    var transportMode: TransportMode?
    var flightNo: String
    var airline: String
    var trainNo: String
    var busNo: String
    var departureName: String
    var arrivalName: String
    var seatInfo: String

    // Hotel details (Phase 1 + Phase 2)
    var confirmationCode: String
    var hotelCheckInTime: String
    var hotelCheckOutTime: String
    /// 离店日期 yyyy-MM-dd；有值时后端物化跨天 stay group
    var hotelCheckOutDate: String

    var trimmedLocationName: String {
        locationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 有效地点：已选结构化地点，或手动输入了非空地点名称。
    var hasValidLocation: Bool {
        selectedLocation != nil || !trimmedLocationName.isEmpty
    }

    mutating func useSelectedLocation(_ location: ItineraryLocation, fallbackName: String? = nil) {
        savedPlaceId = nil
        selectedLocation = location
        locationName = location.name ?? fallbackName ?? ""
    }

    mutating func useManualLocation(_ name: String) {
        savedPlaceId = nil
        selectedLocation = nil
        locationName = name
    }

    mutating func useSavedPlace(_ savedPlace: SavedPlace) {
        let place = savedPlace.place
        savedPlaceId = savedPlace.id
        selectedLocation = ItineraryLocation(
            provider: nil,
            country: place.country,
            name: place.name,
            address: place.address,
            latitude: place.latitude,
            longitude: place.longitude,
            cityName: place.cityName
        )
        locationName = place.name
        type = ItineraryNodeSuggestion.nodeType(for: place.category)
    }

    mutating func updateLocationText(_ value: String) {
        savedPlaceId = nil
        selectedLocation = nil
        locationName = value
    }

    mutating func applyType(_ type: ItineraryNodeType) {
        self.type = type
        normalizeTypeSpecificState()
    }

    mutating func normalizeTypeSpecificState() {
        if type == .transport {
            transportMode = transportMode ?? .flight
            title = ""
        }

        if type == .hotel {
            endTime = ""
            if hotelCheckInTime.isEmpty, !startTime.isEmpty {
                hotelCheckInTime = startTime
            } else if !hotelCheckInTime.isEmpty {
                startTime = hotelCheckInTime
            }
        }
    }

    var normalizedStartTime: String? {
        Self.normalizedTime(from: startTime)
    }

    var normalizedEndTime: String? {
        Self.normalizedTime(from: endTime)
    }

    var normalizedHotelCheckInTime: String? {
        Self.normalizedTime(from: hotelCheckInTime)
    }

    var normalizedHotelCheckOutTime: String? {
        Self.normalizedTime(from: hotelCheckOutTime)
    }

    func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func create(defaultDayIndex: Int) -> ItineraryNodeFormState {
        ItineraryNodeFormState(
            savedPlaceId: nil,
            dayIndex: defaultDayIndex,
            title: "",
            type: .other,
            locationName: "",
            selectedLocation: nil,
            startTime: "",
            endTime: "",
            note: "",
            transportMode: nil,
            flightNo: "",
            airline: "",
            trainNo: "",
            busNo: "",
            departureName: "",
            arrivalName: "",
            seatInfo: "",
            confirmationCode: "",
            hotelCheckInTime: "",
            hotelCheckOutTime: "",
            hotelCheckOutDate: ""
        )
    }

    static func from(node: ItineraryNodeItem) -> ItineraryNodeFormState {
        let d = node.details
        // 住宿：入住时间优先 details，否则回落节点 startTime（兼容旧数据）
        let hotelIn = {
            let fromDetails = d?.checkInTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fromDetails.isEmpty { return fromDetails }
            return node.startTime ?? ""
        }()
        return ItineraryNodeFormState(
            savedPlaceId: nil,
            dayIndex: node.dayIndex,
            title: node.title,
            type: node.type,
            locationName: node.locationName ?? "",
            selectedLocation: node.location,
            startTime: node.type == .hotel ? hotelIn : (node.startTime ?? ""),
            endTime: node.type == .hotel ? "" : (node.endTime ?? ""),
            note: node.note ?? "",
            transportMode: d?.transportMode ?? (node.type == .transport ? .flight : nil),
            flightNo: d?.flightNo ?? "",
            airline: d?.airline ?? "",
            trainNo: d?.trainNo ?? "",
            busNo: d?.busNo ?? "",
            departureName: d?.departureName ?? "",
            arrivalName: d?.arrivalName ?? "",
            seatInfo: d?.seatInfo ?? "",
            confirmationCode: d?.confirmationCode ?? "",
            hotelCheckInTime: hotelIn,
            hotelCheckOutTime: d?.checkOutTime ?? "",
            hotelCheckOutDate: d?.checkOutDate ?? ""
        )
    }

    private static func normalizedTime(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ItineraryNodeTimeField: Hashable {
    case start
    case end
    case hotelCheckIn
    case hotelCheckOut

    var pickerTitle: String {
        switch self {
        case .start: "开始时间"
        case .end: "结束时间"
        case .hotelCheckIn: "入住时间"
        case .hotelCheckOut: "退房时间"
        }
    }
}

extension ItineraryNodeFormState {
    func timeValue(for field: ItineraryNodeTimeField) -> String {
        switch field {
        case .start: startTime
        case .end: endTime
        case .hotelCheckIn: hotelCheckInTime
        case .hotelCheckOut: hotelCheckOutTime
        }
    }

    func initialTimeDate(for field: ItineraryNodeTimeField, now: Date = Date()) -> Date {
        if let selected = ItineraryTimeFormatting.date(fromTime: timeValue(for: field)) {
            return selected
        }

        if field == .end,
           let start = ItineraryTimeFormatting.date(fromTime: startTime),
           let oneHourLater = TracciDateContext.calendar.date(byAdding: .hour, value: 1, to: start) {
            return oneHourLater
        }

        return now
    }

    mutating func applyTime(_ date: Date, for field: ItineraryNodeTimeField) {
        let value = ItineraryTimeFormatting.apiTime(from: date)

        switch field {
        case .hotelCheckIn:
            hotelCheckInTime = value
            // Hotel check-in remains the node start time so the itinerary timeline can render it.
            startTime = value
        case .hotelCheckOut:
            hotelCheckOutTime = value
            // Check-out is a hotel detail, not the end of the check-in day's node.
            endTime = ""
        case .start:
            startTime = value
            guard let oneHourLater = TracciDateContext.calendar.date(byAdding: .hour, value: 1, to: date) else {
                return
            }
            let trimmedEnd = endTime.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedEnd.isEmpty {
                endTime = ItineraryTimeFormatting.apiTime(from: oneHourLater)
            } else if shouldReplaceEndTime(existingEnd: trimmedEnd, start: date) {
                endTime = ItineraryTimeFormatting.apiTime(from: oneHourLater)
            }
        case .end:
            endTime = value
        }
    }

    mutating func clearTime(_ field: ItineraryNodeTimeField) {
        switch field {
        case .start:
            startTime = ""
        case .end:
            endTime = ""
        case .hotelCheckIn:
            hotelCheckInTime = ""
            startTime = ""
        case .hotelCheckOut:
            hotelCheckOutTime = ""
            endTime = ""
        }
    }

    /// Compare clock times only. Parsed `HH:mm` sits on the formatter reference
    /// day, while a live picker may confirm `Date()` today — a raw `Date <=`
    /// would treat any existing end as earlier and overwrite it.
    private func shouldReplaceEndTime(existingEnd: String, start: Date) -> Bool {
        guard
            let startMinutes = ItineraryTimeFormatting.minutes(from: start),
            let endMinutes = ItineraryTimeFormatting.minutes(from: existingEnd)
        else {
            return false
        }
        return endMinutes <= startMinutes
    }
}

enum ItineraryNodeSuggestion {
    static func nodeType(for category: PlaceCategory) -> ItineraryNodeType {
        switch category {
        case .restaurant: .restaurant
        case .hotel: .hotel
        case .transport: .transport
        case .shopping: .shopping
        case .attraction: .attraction
        default: .other
        }
    }

    static func nodeType(for result: TracciPlaceSearchResult) -> ItineraryNodeType {
        let classification = SavedPlaceClassification.infer(
            name: result.name,
            mapCategory: result.category,
            cityName: result.cityName,
            provinceName: result.provinceName
        )
        return nodeType(for: classification.category)
    }
}

enum ItineraryFormFieldKey: Hashable {
    case dayIndex
    case title
    case location
    case startTime
    case endTime
    case note
}

/// Trip 详情添加/编辑节点的路由 mode；由 `TripDetailFormRouter` 持有，
/// Create 与 Edit 页面各自决定从 mode 读取哪些上下文。
enum ItineraryNodeFormMode: Equatable, Hashable {
    case create(defaultDayIndex: Int)
    case edit(ItineraryNodeItem)
    /// 仅编辑备注：已结束旅程的节点不允许修改结构与时间，只允许修改备注。
    case editNote(ItineraryNodeItem)
}

extension ItineraryNodeFormMode: Identifiable {
    var id: String {
        switch self {
        case let .create(dayIndex):
            return "create-\(dayIndex)"
        case let .edit(node):
            return "edit-\(node.id)"
        case let .editNote(node):
            return "editNote-\(node.id)"
        }
    }
}

enum ItineraryTimeFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func displayRange(start: String?, end: String?) -> String? {
        switch (start?.trimmingCharacters(in: .whitespacesAndNewlines),
                end?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (start?, end?) where !start.isEmpty && !end.isEmpty:
            return "\(start) - \(end)"
        case let (start?, _) where !start.isEmpty:
            return start
        case let (_, end?) where !end.isEmpty:
            return end
        default:
            return nil
        }
    }

    static func isValidTimeFormat(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return parse(trimmed) != nil
    }

    static func date(fromTime value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parse(trimmed)
    }

    static func apiTime(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func isStartBeforeOrEqualEnd(start: String, end: String) -> Bool {
        let trimmedStart = start.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnd = end.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedStart.isEmpty, !trimmedEnd.isEmpty else { return true }
        guard let startDate = parse(trimmedStart), let endDate = parse(trimmedEnd) else { return true }
        return startDate <= endDate
    }

    static func displayDate(_ apiDate: String) -> String {
        guard let date = TripDateFormatting.date(from: apiDate) else {
            return apiDate
        }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "MM.dd"
        return formatter.string(from: date)
    }

    static func weekday(_ apiDate: String) -> String {
        guard let date = TripDateFormatting.date(from: apiDate) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func isToday(_ apiDate: String) -> Bool {
        guard let date = TripDateFormatting.date(from: apiDate) else {
            return false
        }

        return TracciDateContext.calendar.isDate(date, inSameDayAs: Date())
    }

    static func displayStatus(for node: ItineraryNodeItem, dayDate: String, now: Date = Date()) -> ItineraryNodeDisplayStatus {
        guard let date = TripDateFormatting.date(from: dayDate) else {
            return .upcoming
        }

        let calendar = TracciDateContext.calendar
        let day = calendar.startOfDay(for: date)
        let today = TracciDateContext.today()

        if day < today { return .completed }
        if day > today { return .upcoming }

        guard let nowMinutes = minutes(from: now) else {
            return .today
        }

        let startMinutes = minutes(from: node.startTime)
        let endMinutes = minutes(from: node.endTime)

        switch (startMinutes, endMinutes) {
        case let (start?, end?):
            if nowMinutes < start { return .upcoming }
            if nowMinutes > end { return .completed }
            return .current
        case let (start?, nil):
            return nowMinutes < start ? .upcoming : .current
        case let (nil, end?):
            return nowMinutes > end ? .completed : .current
        default:
            return .today
        }
    }

    private static func parse(_ value: String) -> Date? {
        timeFormatter.date(from: value)
    }

    static func minutes(from value: String?) -> Int? {
        guard
            let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            let date = parse(value)
        else {
            return nil
        }

        let components = TracciDateContext.calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return hour * 60 + minute
    }

    static func minutes(from date: Date) -> Int? {
        let components = TracciDateContext.calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return hour * 60 + minute
    }
}

extension KeyedDecodingContainer {
    func decodeItineraryFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }

        return nil
    }

    func decodeItineraryFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }

        return nil
    }
}
