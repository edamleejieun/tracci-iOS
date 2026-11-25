import Foundation

// MARK: - Itinerary Export

enum ItineraryExportFormat: String, CaseIterable, Identifiable {
    case image
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: "保存图片"
        case .text: "复制文字"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo"
        case .text: "doc.text"
        }
    }
}

struct ItineraryExportAssetsResponse: Decodable, Equatable {
    let trip: ItineraryExportTripInfo
    let days: [ItineraryExportDay]
    let meta: ItineraryExportMeta
    let watermark: ExportWatermark
}

struct ItineraryExportTripInfo: Decodable, Equatable {
    let id: String
    let title: String
    let destination: String
    let startDate: String
    let endDate: String
    let totalDays: Int
}

struct ItineraryExportDay: Decodable, Equatable, Identifiable {
    let id: String
    let dayIndex: Int
    let date: String
    let nodeCount: Int
    let nodes: [ItineraryExportNode]

    var hasNodes: Bool { nodeCount > 0 && !nodes.isEmpty }
}

struct ItineraryExportNode: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let type: String
    let typeName: String
    let startTime: String?
    let endTime: String?
    let locationName: String?
    let locationAddress: String?
    let note: String?
    let sortOrder: Int?

    var timeText: String? {
        switch (startTime, endTime) {
        case let (start?, end?):
            return "\(start) - \(end)"
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        default:
            return nil
        }
    }

    var locationText: String? {
        if let address = locationAddress, !address.isEmpty {
            return address
        }
        if let name = locationName, !name.isEmpty {
            return name
        }
        return nil
    }

    /// 展示用标题：优先展示地点名称（locationName → locationAddress），title 为空时兜底。
    var displayTitle: String {
        if let name = locationName, !name.isEmpty {
            return name
        }
        if let address = locationAddress, !address.isEmpty {
            return address
        }
        if !title.isEmpty {
            return title
        }
        return "未命名行程"
    }
}

struct ItineraryExportMeta: Decodable, Equatable {
    let totalDayCount: Int
    let totalNodeCount: Int
    let selectedDayCount: Int
    let selectedNodeCount: Int
}

