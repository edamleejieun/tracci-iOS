import Foundation
import TracciNetworking

enum PlaceScope: String, Codable, Equatable, Sendable {
    case destination = "DESTINATION"
    case poi = "POI"

    var displayName: String {
        switch self {
        case .destination: "城市 / 地区"
        case .poi: "具体地点"
        }
    }
}
enum PlaceCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case city = "CITY", region = "REGION", attraction = "ATTRACTION", restaurant = "RESTAURANT", hotel = "HOTEL", shopping = "SHOPPING", transport = "TRANSPORT", other = "OTHER"

    var displayName: String {
        switch self {
        case .city: "城市"
        case .region: "地区"
        case .attraction: "景点"
        case .restaurant: "餐饮"
        case .hotel: "住宿"
        case .shopping: "购物"
        case .transport: "交通"
        case .other: "其他"
        }
    }

    static func allowed(for scope: PlaceScope) -> [PlaceCategory] {
        switch scope {
        case .destination: [.city, .region]
        case .poi: [.attraction, .restaurant, .hotel, .shopping, .transport, .other]
        }
    }
}
enum SupportedPlaceUsage: String, Codable, Equatable, Sendable { case tripDestination = "TRIP_DESTINATION"; case itineraryNode = "ITINERARY_NODE" }

struct SavedPlaceClassification: Equatable, Sendable {
    let scope: PlaceScope
    let category: PlaceCategory

    static let manual = SavedPlaceClassification(scope: .poi, category: .other)

    static func infer(
        name: String,
        mapCategory: String?,
        cityName: String?,
        provinceName: String?
    ) -> SavedPlaceClassification {
        let normalizedName = normalized(name)
        let city = cityName.map(normalized)
        let province = provinceName.map(normalized)
        let isAdministrativeResult = mapCategory == nil && [city, province]
            .compactMap { $0 }
            .contains(normalizedName)

        if isAdministrativeResult {
            return .init(scope: .destination, category: city == normalizedName ? .city : .region)
        }

        let category: PlaceCategory = switch mapCategory ?? "" {
        case "餐厅", "咖啡", "烘焙", "酒吧", "酒庄": .restaurant
        case "酒店": .hotel
        case "商店", "市场": .shopping
        case "机场", "公共交通", "租车", "码头", "停车", "加油站", "充电": .transport
        case "游乐园", "水族馆", "海滩", "图书馆", "影院", "博物馆", "公园", "体育场", "剧院", "大学", "动物园": .attraction
        default: .other
        }
        return .init(scope: .poi, category: category)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct PlaceSummary: Decodable, Equatable, Sendable {
    let name: String; let placeScope: PlaceScope; let category: PlaceCategory
    let address: String?; let cityName: String?; let country: String?; let latitude: Double?; let longitude: Double?
    let supportedUsages: [SupportedPlaceUsage]
}
struct PlaceUsageSummary: Decodable, Equatable, Sendable { let tripCount: Int; let lastUsedTripId: String? }
struct PlaceUserContext: Decodable, Equatable, Sendable {
    let isSaved: Bool; let savedPlaceId: String?; let note: String?; let usageSummary: PlaceUsageSummary?
}

/// 契约 §15.4：仅在存在 `status=PUBLISHED` 内容版本时返回，无内容时整块省略。
/// 逐字段 Optional —— 编辑可以只填其中几项，客户端按块隐藏，不补占位文案。
struct PlaceEditorialContent: Decodable, Equatable, Sendable {
    let version: Int?
    let introduction: String?
    let highlights: [String]?
    let recommendedDurationMinutes: Int?
    let visitTips: [String]?
    let bestVisitTime: String?
    let reservationTips: String?
    let notice: String?
}

/// 契约 §15.4：内容来源与审核说明。`label` 原文展示，`aiAssisted` 为真时必须可见。
struct PlaceContentMeta: Decodable, Equatable, Sendable {
    let aiAssisted: Bool?
    let label: String?
    let verifiedAt: String?
    let nextReviewAt: String?
    let reviewDue: Bool?
}

/// 契约 §15.4：仅返回 APPROVED 且授权未过期、已解析出展示 URL 的媒体。
struct PlaceMedia: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let url: String?
    let thumbnailUrl: String?
    let previewUrl: String?
    let width: Int?
    let height: Int?
    let altText: String?
    let attribution: String?

    /// Hero 照片带用大图；服务端已解析好 URL，客户端不做二次拼接。
    var heroURL: String? { previewUrl ?? url }
}

struct PlaceDetail: Decodable, Identifiable, Equatable, Sendable {
    let id: String; let name: String; let placeScope: PlaceScope; let category: PlaceCategory
    let address: String?; let cityName: String?; let country: String?; let latitude: Double?; let longitude: Double?
    let supportedUsages: [SupportedPlaceUsage]; let userContext: PlaceUserContext?
    let editorialContent: PlaceEditorialContent?
    let contentMeta: PlaceContentMeta?
    let media: [PlaceMedia]?

    var canAddToItinerary: Bool {
        guard placeScope == .poi else { return false }
        return supportedUsages.isEmpty || supportedUsages.contains(.itineraryNode)
    }

    func asSavedPlace() -> SavedPlace? {
        guard let savedPlaceId = userContext?.savedPlaceId else { return nil }
        return SavedPlace(
            id: savedPlaceId,
            placeId: id,
            place: PlaceSummary(
                name: name,
                placeScope: placeScope,
                category: category,
                address: address,
                cityName: cityName,
                country: country,
                latitude: latitude,
                longitude: longitude,
                supportedUsages: supportedUsages
            ),
            note: userContext?.note,
            usageSummary: userContext?.usageSummary,
            createdAt: "",
            updatedAt: nil
        )
    }
}
struct SavedPlace: Decodable, Identifiable, Equatable, Sendable {
    let id: String; let placeId: String; let place: PlaceSummary; let note: String?
    let usageSummary: PlaceUsageSummary?; let createdAt: String; let updatedAt: String?
}

extension SavedPlace {
    /// 列表 / Picker 共用的城市分组键。
    /// 目的地（城市/地区）以自身名称为键；POI 以 cityName 兜底「其他地点」。
    var groupingCityKey: String {
        if place.placeScope == .destination { return place.name }
        return place.cityName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankValue ?? "其他地点"
    }

    /// 是否可作为行程节点加入旅程。
    ///
    /// 契约：`DESTINATION` 只能作旅程目的地；`POI` 才能作 Itinerary node。
    /// `supportedUsages` 有值时再按能力字段收紧；为空时按 POI 默认可加入。
    var canAddToItinerary: Bool {
        guard place.placeScope == .poi else { return false }
        return place.supportedUsages.isEmpty
            || place.supportedUsages.contains(.itineraryNode)
    }
}

private extension String {
    /// 与 SavedPlacesView 的 `nilIfBlank` 同义，放在模型文件里避免跨文件依赖。
    var nilIfBlankValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct SavedPlaceLocationInput: Encodable, Equatable, Sendable {
    let name: String; let address: String?; let provider: String; let providerPlaceId: String?
    let country: String?; let provinceName: String?; let cityName: String?; let districtName: String?
    let latitude: Double?; let longitude: Double?; let adcode: String?; let cityCode: String?
}
struct CreateSavedPlaceRequest: Encodable, Equatable, Sendable {
    let placeId: String?; let placeScope: PlaceScope?; let category: PlaceCategory?; let location: SavedPlaceLocationInput?; let note: String?
    static func existingPlace(placeId: String, note: String?) -> Self { .init(placeId: placeId, placeScope: nil, category: nil, location: nil, note: note) }
    static func locationCandidate(scope: PlaceScope, category: PlaceCategory, location: SavedPlaceLocationInput, note: String?) -> Self { .init(placeId: nil, placeScope: scope, category: category, location: location, note: note) }
}
struct SavedPlaceListQuery: Equatable, Sendable {
    var usage: SupportedPlaceUsage? = nil; var tripId: String? = nil; var keyword: String? = nil
    var placeScope: PlaceScope? = nil; var category: PlaceCategory? = nil; var page: Int = 1; var pageSize: Int = 20
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let usage { items.append(.init(name: "usage", value: usage.rawValue)) }
        if let tripId, !tripId.isEmpty { items.append(.init(name: "tripId", value: tripId)) }
        if let keyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty { items.append(.init(name: "keyword", value: keyword)) }
        if let placeScope { items.append(.init(name: "placeScope", value: placeScope.rawValue)) }
        if let category { items.append(.init(name: "category", value: category.rawValue)) }
        items += [.init(name: "page", value: "\(max(1, page))"), .init(name: "pageSize", value: "\(min(100, max(1, pageSize)))")]
        return items
    }
}

/// 契约 §15.4.2 列表项封面：`sort_order` 最小的 APPROVED 且授权未过期媒体。
/// 无图或 COS 未接入时服务端整块省略，不返回占位 URL。
struct PublishedPlaceCover: Decodable, Equatable, Sendable {
    let id: String?
    let thumbnailUrl: String?
    let previewUrl: String?
    let url: String?
    let altText: String?
    let attribution: String?

    var displayURL: String? { thumbnailUrl ?? previewUrl ?? url }
}

/// 契约 §15.4.2 已发布地点列表项。探索首页画城市卡（`DESTINATION`），城市页画地点卡（`POI`）。
///
/// 列表**不返回** `editorialContent` / `media[]` / `contentMeta` / `userContext` / 地址；
/// `isSaved` 是唯一的用户态字段，仅供列表内快捷收藏的两态显示。
struct PublishedPlace: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let placeScope: PlaceScope
    let category: PlaceCategory
    let cityName: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let supportedUsages: [SupportedPlaceUsage]?
    /// 服务端派生的气质标签：`highlights[0]` 或 `introduction` 截 40 字。两者都空则省略，客户端不编造。
    let highlight: String?
    let publishedAt: String?
    let isSaved: Bool?
    let cover: PublishedPlaceCover?

    /// `publishedAt` 为 UTC `yyyy-MM-dd HH:mm:ss`（非 ISO-8601 带 Z），
    /// `TracciDateContext.dateTime` 的 UTC 格式表已覆盖该形态。
    var publishedDate: Date? { TracciDateContext.dateTime(from: publishedAt) }

    var isSavedLocally: Bool { isSaved ?? false }
}

/// 契约 §15.4.2 `GET /places` 查询参数。探索两层各自独立请求：
/// 首页 `placeScope=DESTINATION`，城市页 `placeScope=POI&cityName={城市名}`（精确匹配）。
struct PublishedPlacesQuery: Equatable, Sendable {
    var placeScope: PlaceScope? = nil
    var cityName: String? = nil
    var category: PlaceCategory? = nil
    var page: Int = 1
    var pageSize: Int = 20

    /// 本接口 `pageSize` 上限是 **50**（含封面，小于全局 100）。
    /// 契约规定非法分页**拒绝**并返回 `42201`，不做服务端夹紧，因此必须在客户端收口。
    static let pageSizeLimit = 50

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let placeScope { items.append(.init(name: "placeScope", value: placeScope.rawValue)) }
        if let cityName = cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !cityName.isEmpty {
            items.append(.init(name: "cityName", value: cityName))
        }
        if let category { items.append(.init(name: "category", value: category.rawValue)) }
        items += [
            .init(name: "page", value: "\(max(1, page))"),
            .init(name: "pageSize", value: "\(min(Self.pageSizeLimit, max(1, pageSize)))"),
        ]
        return items
    }
}

enum SavedPlaceErrorMessage {
    static func resolve(_ error: Error) -> String {
        guard case let APIError.business(code, message) = error else {
            return error.localizedDescription
        }
        switch code {
        case 40422: return "这个地点不存在或已不可用"
        case 40423: return "这条收藏已不可用，请刷新后重试"
        case 40901: return "这个地点已经收藏过了"
        case 42201: return "分页或筛选参数不正确"
        case 42242: return "这个收藏不支持当前操作"
        case 42243: return "这个地点与当前旅程目的地不匹配"
        case 42244: return "收藏方式或地点分类不正确"
        case 42245: return "地点信息不完整或暂时无法核验"
        default: return message
        }
    }

    static func businessCode(_ error: Error) -> Int? {
        guard case let APIError.business(code, _) = error else { return nil }
        return code
    }

    /// 契约决策 9：`40901` 重复收藏按幂等成功处理，用户不应看到「已经收藏过了」的失败感。
    /// 探索列表内 ♡ 与半层收藏按钮共用这一判定。
    static func isAlreadySaved(_ error: Error) -> Bool {
        businessCode(error) == 40901
    }
}
