import Foundation

struct TripCoverPhoto: Codable, Equatable {
    let fileId: String?
    let url: String?
    let thumbnailUrl: String?
    let previewUrl: String?
    let exportUrl: String?
    let storyPortraitUrl: String?
    let storyCardUrl: String?
    let squareUrl: String?
    let watermarkedUrl: String?
    let width: Int?
    let height: Int?

    /// 后端约定：`fileId == null` 表示系统按目的地推荐的封面。
    var isSystemProvided: Bool {
        fileId == nil
    }

    /// 用户明确上传并绑定到旅程的封面。
    var isUserProvided: Bool {
        fileId != nil
    }
}

struct TripWeatherResponse: Decodable, Equatable {
    let available: Bool
    let status: String
    let source: String?
    let forecastType: String?
    let message: String?
    let updatedAt: String?
    let locationName: String?
    let forecastLimitDays: Int?
    let items: [TripWeatherItem]
    let location: TripWeatherLocation?

    enum CodingKeys: String, CodingKey {
        case available
        case status
        case source
        case forecastType
        case message
        case updatedAt
        case locationName
        case forecastLimitDays
        case items
        case location
    }

    init(
        available: Bool,
        status: String,
        source: String? = nil,
        forecastType: String? = nil,
        message: String? = nil,
        updatedAt: String? = nil,
        locationName: String? = nil,
        forecastLimitDays: Int? = nil,
        items: [TripWeatherItem] = [],
        location: TripWeatherLocation? = nil
    ) {
        self.available = available
        self.status = status
        self.source = source
        self.forecastType = forecastType
        self.message = message
        self.updatedAt = updatedAt
        self.locationName = locationName
        self.forecastLimitDays = forecastLimitDays
        self.items = items
        self.location = location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "UNAVAILABLE"
        source = try container.decodeIfPresent(String.self, forKey: .source)
        forecastType = try container.decodeIfPresent(String.self, forKey: .forecastType)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        // Jackson may emit LocalDate as ISO string or as `[year, month, day]`.
        updatedAt = try container.decodeTripFlexibleDateStringIfPresent(forKey: .updatedAt)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        forecastLimitDays = try container.decodeTripFlexibleIntIfPresent(forKey: .forecastLimitDays)
        items = try container.decodeIfPresent([TripWeatherItem].self, forKey: .items) ?? []
        location = try container.decodeIfPresent(TripWeatherLocation.self, forKey: .location)
    }
}

struct TripWeatherItem: Decodable, Identifiable, Equatable {
    var id: String { date }

    let date: String
    let weekday: String?
    let weather: String
    let tempMin: Double?
    let tempMax: Double?
    let wind: String?
    let icon: String?
    let pop: Double?
    let tip: String?

    enum CodingKeys: String, CodingKey {
        case date
        case weekday
        case weather
        case tempMin
        case tempMax
        case wind
        case icon
        case pop
        case tip
    }

    init(
        date: String,
        weekday: String?,
        weather: String,
        tempMin: Double?,
        tempMax: Double?,
        wind: String?,
        icon: String?,
        pop: Double?,
        tip: String?
    ) {
        self.date = date
        self.weekday = weekday
        self.weather = weather
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.wind = wind
        self.icon = icon
        self.pop = pop
        self.tip = tip
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Jackson may emit LocalDate as ISO string or as `[year, month, day]`.
        date = try container.decodeTripFlexibleDateStringIfPresent(forKey: .date) ?? ""
        weekday = try container.decodeIfPresent(String.self, forKey: .weekday)
        weather = try container.decodeIfPresent(String.self, forKey: .weather) ?? "unknown"
        tempMin = try container.decodeTripFlexibleDoubleIfPresent(forKey: .tempMin)
        tempMax = try container.decodeTripFlexibleDoubleIfPresent(forKey: .tempMax)
        wind = try container.decodeIfPresent(String.self, forKey: .wind)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        pop = try container.decodeTripFlexibleDoubleIfPresent(forKey: .pop)
        tip = try container.decodeIfPresent(String.self, forKey: .tip)
    }
}

struct TripWeatherLocation: Decodable, Equatable {
    let city: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case city
        case country
        case latitude
        case longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        latitude = try container.decodeTripFlexibleDoubleIfPresent(forKey: .latitude)
        longitude = try container.decodeTripFlexibleDoubleIfPresent(forKey: .longitude)
    }
}

extension KeyedDecodingContainer {
    func decodeTripFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
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

    func decodeTripFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
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

    func decodeTripFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        return nil
    }

    /// Accepts ISO date/time strings or Jackson-style LocalDate arrays `[y, m, d]`.
    func decodeTripFlexibleDateStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try decodeTripFlexibleStringIfPresent(forKey: key) {
            return value
        }

        if let parts = try? decodeIfPresent([Int].self, forKey: key), parts.count >= 3 {
            let (year, month, day) = (parts[0], parts[1], parts[2])
            if isValidDate(year: year, month: month, day: day) {
                return String(format: "%04d-%02d-%02d", year, month, day)
            }
        }

        return nil
    }

    private func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        guard day > 0 else { return false }

        let maxDay: Int
        switch month {
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
            maxDay = isLeap ? 29 : 28
        case 4, 6, 9, 11:
            maxDay = 30
        default:
            maxDay = 31
        }

        return day <= maxDay
    }

    func decodeTripFlexibleDestinationIfPresent(forKey key: Key) throws -> TripDestination? {
        if let destination = try? decodeIfPresent(TripDestination.self, forKey: key) {
            return destination
        }

        if let name = try decodeTripLossyStringIfPresent(forKey: key), !name.isEmpty {
            return TripDestination(name: name)
        }

        return nil
    }

    func decodeTripLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }

        return nil
    }
}
