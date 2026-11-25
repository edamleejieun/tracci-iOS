import Foundation

// MARK: - Stats Footprint Analysis

struct StatsFootprintAnalysis: Decodable, Equatable {
    let destinationCount: Int
    let itineraryCount: Int
    let totalTravelDays: Int
    let insight: String?
    let cities: [StatsCityFootprint]
    let nodeTypes: [StatsNodeTypeStat]

    enum CodingKeys: String, CodingKey {
        case destinationCount
        case itineraryCount
        case totalTravelDays
        case insight
        case cities
        case nodeTypes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        destinationCount = try container.decodeIfPresent(Int.self, forKey: .destinationCount) ?? 0
        itineraryCount = try container.decodeIfPresent(Int.self, forKey: .itineraryCount) ?? 0
        totalTravelDays = try container.decodeIfPresent(Int.self, forKey: .totalTravelDays) ?? 0
        insight = try container.decodeIfPresent(String.self, forKey: .insight)
        cities = try container.decodeIfPresent([StatsCityFootprint].self, forKey: .cities) ?? []
        nodeTypes = try container.decodeIfPresent([StatsNodeTypeStat].self, forKey: .nodeTypes) ?? []
    }
}

struct StatsCityFootprint: Decodable, Equatable, Identifiable {
    let name: String
    let adcode: String?
    let cityCode: String?
    let provinceName: String?
    let latitude: String?
    let longitude: String?
    let tripCount: Int?
    let totalDays: Int?
    let itineraryCount: Int?
    let firstTripStartDate: String?

    /// Use `adcode` when available (guaranteed unique). Fallback to `name|province`
    /// to avoid collisions when multiple cities share the same name but no adcode.
    var id: String {
        if let adcode { return adcode }
        if let provinceName { return "\(name)|\(provinceName)" }
        return name
    }
}

struct StatsNodeTypeStat: Decodable, Equatable, Identifiable {
    let type: String
    let typeName: String?
    let count: Int

    var id: String { type }
}
