import Foundation
@testable import Tracci

/// Phase 0（Create / Edit / Sheet V2 专项）characterization-test fixtures。
///
/// 只提供测试数据构造，不包含任何生产行为。日期以当前日期为基准相对构造
/// （`TracciDateContext.today()` 不可注入），状态边界保留 ≥20 天余量。
enum ItineraryFixtures {

    // MARK: - Node DTO JSON

    /// 构造可被 `ItineraryNodeDTO` 解码的节点 JSON。除 `id` 外全部可选。
    static func nodeDTOJSON(
        id: String = "node-1",
        title: String? = "测试节点",
        type: String? = "attraction",
        startTime: String? = nil,
        endTime: String? = nil,
        address: String? = nil,
        locationJSON: String? = nil,
        note: String? = nil,
        detailsJSON: String? = nil,
        sortOrder: Int? = 0,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) -> String {
        var fields: [String] = ["\"id\":\"\(id)\""]
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let type { fields.append("\"type\":\"\(type)\"") }
        if let startTime { fields.append("\"startTime\":\"\(startTime)\"") }
        if let endTime { fields.append("\"endTime\":\"\(endTime)\"") }
        if let address { fields.append("\"address\":\"\(address)\"") }
        if let locationJSON { fields.append("\"location\":\(locationJSON)") }
        if let note { fields.append("\"note\":\"\(note)\"") }
        if let detailsJSON { fields.append("\"details\":\(detailsJSON)") }
        if let sortOrder { fields.append("\"sortOrder\":\(sortOrder)") }
        if let createdAt { fields.append("\"createdAt\":\"\(createdAt)\"") }
        if let updatedAt { fields.append("\"updatedAt\":\"\(updatedAt)\"") }
        return "{\(fields.joined(separator: ","))}"
    }

    static func dayJSON(
        id: String = "day-1",
        dayIndex: Int = 1,
        date: String = "2026-08-01",
        nodesJSON: [String] = []
    ) -> String {
        """
        {"id":"\(id)","dayIndex":\(dayIndex),"date":"\(date)","nodes":[\(nodesJSON.joined(separator: ","))]}
        """
    }

    static func itineraryResponseJSON(tripId: String = "trip-1", daysJSON: [String] = []) -> String {
        """
        {"tripId":"\(tripId)","days":[\(daysJSON.joined(separator: ","))]}
        """
    }

    /// 两日行程默认载荷：day-1 / day-2，可选携带节点。
    static func twoDayResponseJSON(
        tripId: String = "trip-1",
        day1NodesJSON: [String] = [],
        day2NodesJSON: [String] = []
    ) -> String {
        itineraryResponseJSON(
            tripId: tripId,
            daysJSON: [
                dayJSON(id: "day-1", dayIndex: 1, nodesJSON: day1NodesJSON),
                dayJSON(id: "day-2", dayIndex: 2, nodesJSON: day2NodesJSON),
            ]
        )
    }

    // MARK: - Decoding helpers

    static func decodeNodeDTO(_ json: String) -> ItineraryNodeDTO {
        do {
            return try JSONDecoder().decode(ItineraryNodeDTO.self, from: Data(json.utf8))
        } catch {
            fatalError("ItineraryFixtures: invalid node DTO JSON: \(error)")
        }
    }

    static func decodeItineraryResponse(_ json: String) -> ItineraryResponse {
        do {
            return try JSONDecoder().decode(ItineraryResponse.self, from: Data(json.utf8))
        } catch {
            fatalError("ItineraryFixtures: invalid itinerary response JSON: \(error)")
        }
    }

    // MARK: - Domain objects

    /// 直接构造 `ItineraryNodeItem`（经 DTO 解码，与生产 hydrate 路径一致）。
    static func makeNodeItem(
        id: String = "node-1",
        tripId: String = "trip-1",
        dayId: String = "day-1",
        dayIndex: Int = 1,
        title: String? = "测试节点",
        type: String? = "attraction",
        startTime: String? = nil,
        endTime: String? = nil,
        address: String? = nil,
        locationJSON: String? = nil,
        note: String? = nil,
        detailsJSON: String? = nil,
        sortOrder: Int? = 0
    ) -> ItineraryNodeItem {
        let dto = decodeNodeDTO(nodeDTOJSON(
            id: id,
            title: title,
            type: type,
            startTime: startTime,
            endTime: endTime,
            address: address,
            locationJSON: locationJSON,
            note: note,
            detailsJSON: detailsJSON,
            sortOrder: sortOrder
        ))
        return ItineraryNodeItem(dto: dto, tripId: tripId, dayId: dayId, dayIndex: dayIndex)
    }

    /// 按状态构造 Trip。日期相对当前日期构造，边界余量 ≥20 天。
    static func makeTrip(
        id: String = "trip-1",
        title: String = "测试旅程",
        status: TripStatus = .planning,
        totalDays: Int? = nil,
        destination: TripDestination? = nil,
        access: TripAccessContext? = nil
    ) -> Trip {
        let calendar = TracciDateContext.calendar
        let today = TracciDateContext.today()

        func day(_ offset: Int) -> String {
            TripDateFormatting.apiString(from: calendar.date(byAdding: .day, value: offset, to: today)!)
        }

        let (startOffset, endOffset): (Int, Int)
        switch status {
        case .completed:
            // 全部落在过去（余量 25 天）
            (startOffset, endOffset) = (-30, -25)
        case .ongoing:
            (startOffset, endOffset) = (-1, 3)
        case .planning, .unknown:
            // 全部落在未来（余量 10 天）
            (startOffset, endOffset) = (10, 14)
        }

        return Trip(
            id: id,
            title: title,
            startDate: day(startOffset),
            endDate: day(endOffset),
            status: status == .unknown ? .planning : status,
            totalDays: totalDays,
            destination: destination,
            access: access
        )
    }

    // MARK: - Saved places

    static func savedPlace(
        id: String = "saved-1",
        placeId: String = "place-1",
        name: String = "收藏地点",
        category: PlaceCategory = .attraction,
        cityName: String? = "京都",
        country: String? = "日本"
    ) -> SavedPlace {
        SavedPlace(
            id: id,
            placeId: placeId,
            place: PlaceSummary(
                name: name,
                placeScope: .poi,
                category: category,
                address: "\(name)地址",
                cityName: cityName,
                country: country,
                latitude: 35.0,
                longitude: 135.0,
                supportedUsages: [.itineraryNode]
            ),
            note: nil,
            usageSummary: nil,
            createdAt: "2026-08-01T00:00:00Z",
            updatedAt: nil
        )
    }

    // MARK: - Access

    static func ownerAccess() -> TripAccessContext {
        TripAccessContext(role: .owner, permissions: [.read, .editContent, .updateTrip, .deleteTrip])
    }

    static func viewerAccess() -> TripAccessContext {
        TripAccessContext(role: .viewer, permissions: [.read])
    }
}
