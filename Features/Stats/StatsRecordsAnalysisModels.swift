import Foundation

// MARK: - Stats Records Analysis

struct StatsRecordsAnalysis: Decodable, Equatable {
    let journalCount: Int
    let photoCount: Int
    let itineraryCount: Int
    let tripRecords: [StatsTripRecords]

    enum CodingKeys: String, CodingKey {
        case journalCount
        case photoCount
        case itineraryCount
        case tripRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        journalCount = try container.decodeIfPresent(Int.self, forKey: .journalCount) ?? 0
        photoCount = try container.decodeIfPresent(Int.self, forKey: .photoCount) ?? 0
        itineraryCount = try container.decodeIfPresent(Int.self, forKey: .itineraryCount) ?? 0
        tripRecords = try container.decodeIfPresent([StatsTripRecords].self, forKey: .tripRecords) ?? []
    }
}

struct StatsTripRecords: Decodable, Equatable, Identifiable {
    let tripId: String
    let title: String?
    let destinationName: String?
    let itineraryCount: Int?
    let journalCount: Int?
    let photoCount: Int?
    let expenseCount: Int?

    var id: String { tripId }
}
