import Foundation

enum MemoryMode: String, CaseIterable, Identifiable {
    case tripReview
    case yearlyReport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tripReview: "旅程回顾"
        case .yearlyReport: "年度报告"
        }
    }

    var systemImage: String {
        switch self {
        case .tripReview: "book.pages"
        case .yearlyReport: "star"
        }
    }
}

struct YearlyMemoryReport: Identifiable, Equatable {
    let year: Int
    let trips: Int
    let days: Int
    let places: Int
    let coverURLs: [URL]

    var id: Int { year }
}

struct MemoryNavigationRequest: Equatable {
    let tripId: String
}

enum StoryPageKind: CaseIterable, Equatable {
    case cover
    case stats
    case places
    case photos
    case expenses
    case memorable
    case journals
    case ending
}
