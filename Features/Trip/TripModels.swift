import Foundation
import SwiftUI

struct Trip: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: String
    let endDate: String
    let status: TripStatus
    let totalDays: Int?
    let destination: TripDestination?
    let coverPhoto: TripCoverPhoto?
    let baseCurrency: String?
    let totalCny: String?
    let nodeCount: Int?
    let journalCount: Int?
    let expenseCount: Int?
    let access: TripAccessContext?
    let createdAt: String?
    let updatedAt: String?

    var destinationName: String? {
        destination?.name
    }

    var coverThumbnailURL: URL? {
        urlCandidates([coverPhoto?.thumbnailUrl, coverPhoto?.url, coverPhoto?.previewUrl])
    }

    var coverPreviewURL: URL? {
        urlCandidates([coverPhoto?.previewUrl, coverPhoto?.url, coverPhoto?.thumbnailUrl])
    }

    /// 列表/卡片优先缩略图，系统封面加载更快。
    var coverCardURL: URL? {
        if coverPhoto?.isSystemProvided == true {
            return coverThumbnailURL ?? coverPreviewURL
        }
        return coverPreviewURL ?? coverThumbnailURL
    }

    /// 详情 Hero 优先预览图，系统封面可回退缩略图。
    var coverHeroURL: URL? {
        coverPreviewURL ?? coverThumbnailURL
    }

    /// 首页最高权重的 Featured Surface 只使用用户明确上传的封面。
    /// 系统目的地图仍可用于普通列表缩略图、详情、分享和回忆，但不会被放大为 Media Hero。
    var homeFeaturedCoverURL: URL? {
        guard coverPhoto?.isUserProvided == true else { return nil }
        return coverHeroURL ?? coverCardURL ?? coverThumbnailURL
    }

    var homeFeaturedCoverFallbackURL: URL? {
        guard coverPhoto?.isUserProvided == true else { return nil }
        let primary = homeFeaturedCoverURL
        return [coverCardURL, coverThumbnailURL, coverPreviewURL]
            .compactMap { $0 }
            .first { $0 != primary }
    }

    var coverHeroFallbackURL: URL? {
        guard coverPhoto?.isSystemProvided == true else { return nil }
        return coverThumbnailURL
    }

    /// 全屏封面预览优先使用原图，并按预览图、缩略图顺序回退。
    var coverFullSizeURLs: [URL] {
        var seen = Set<String>()
        return [coverPhoto?.url, coverPhoto?.previewUrl, coverPhoto?.thumbnailUrl]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .filter { seen.insert($0.absoluteString).inserted }
    }

    private func urlCandidates(_ values: [String?]) -> URL? {
        values
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }

    var coverStoryCardURL: URL? {
        [coverPhoto?.storyCardUrl, coverPhoto?.previewUrl, coverPhoto?.url, coverPhoto?.thumbnailUrl]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }

    var coverStoryPortraitURL: URL? {
        [coverPhoto?.storyPortraitUrl, coverPhoto?.storyCardUrl, coverPhoto?.previewUrl, coverPhoto?.url, coverPhoto?.thumbnailUrl]
            .compactMap { $0 }
            .first
            .flatMap(URL.init(string:))
    }

    var effectiveStatus: TripStatus {
        TracciDateContext.tripStatus(startDate: startDate, endDate: endDate) ?? status
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case startDate
        case endDate
        case status
        case totalDays
        case destination
        case coverPhoto
        case coverUrl
        case coverPhotoUrl
        case baseCurrency
        case totalCny
        case totalExpense
        case nodeCount
        case itineraryCount
        case journalCount
        case expenseCount
        case access
        case createdAt
        case updatedAt
    }

    init(
        id: String,
        title: String,
        startDate: String,
        endDate: String,
        status: TripStatus,
        totalDays: Int? = nil,
        destination: TripDestination? = nil,
        coverPhoto: TripCoverPhoto? = nil,
        baseCurrency: String? = nil,
        totalCny: String? = nil,
        nodeCount: Int? = nil,
        journalCount: Int? = nil,
        expenseCount: Int? = nil,
        access: TripAccessContext? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.totalDays = totalDays
        self.destination = destination
        self.coverPhoto = coverPhoto
        self.baseCurrency = baseCurrency
        self.totalCny = totalCny
        self.nodeCount = nodeCount
        self.journalCount = journalCount
        self.expenseCount = expenseCount
        self.access = access
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? "未命名旅程"
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        status = try container.decodeIfPresent(TripStatus.self, forKey: .status) ?? .planning
        totalDays = try container.decodeTripFlexibleIntIfPresent(forKey: .totalDays)
        destination = try container.decodeTripFlexibleDestinationIfPresent(forKey: .destination)

        if let coverPhoto = try? container.decodeIfPresent(TripCoverPhoto.self, forKey: .coverPhoto) {
            self.coverPhoto = coverPhoto
        } else {
            let fallbackURL = try container.decodeIfPresent(String.self, forKey: .coverUrl)
                ?? container.decodeIfPresent(String.self, forKey: .coverPhotoUrl)
                ?? container.decodeTripLossyStringIfPresent(forKey: .coverPhoto)
            self.coverPhoto = fallbackURL.map {
                TripCoverPhoto(
                    fileId: nil,
                    url: $0,
                    thumbnailUrl: $0,
                    previewUrl: $0,
                    exportUrl: nil,
                    storyPortraitUrl: nil,
                    storyCardUrl: nil,
                    squareUrl: nil,
                    watermarkedUrl: nil,
                    width: nil,
                    height: nil
                )
            }
        }

        baseCurrency = try container.decodeIfPresent(String.self, forKey: .baseCurrency)
        totalCny = try container.decodeTripFlexibleStringIfPresent(forKey: .totalCny)
            ?? container.decodeTripFlexibleStringIfPresent(forKey: .totalExpense)
        nodeCount = try container.decodeTripFlexibleIntIfPresent(forKey: .nodeCount)
            ?? container.decodeTripFlexibleIntIfPresent(forKey: .itineraryCount)
        journalCount = try container.decodeTripFlexibleIntIfPresent(forKey: .journalCount)
        expenseCount = try container.decodeTripFlexibleIntIfPresent(forKey: .expenseCount)
        access = try container.decodeIfPresent(TripAccessContext.self, forKey: .access)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}
enum TripStatus: String, Decodable, Equatable {
    case planning
    case ongoing
    case completed
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue.lowercased() {
        case "planned", "planning":
            self = .planning
        case "ongoing":
            self = .ongoing
        case "completed":
            self = .completed
        default:
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .planning:
            return "计划中"
        case .ongoing:
            return "进行中"
        case .completed:
            return "已完成"
        case .unknown:
            return "旅程"
        }
    }

    /// v0 对齐：状态徽章颜色 — planning=品牌蓝, ongoing=阶段进行色(品牌蓝,与 featured stage 一致,避免绿色交通灯感), completed=中性灰
    var statusColor: Color {
        switch self {
        case .planning: AppColors.brandPrimary
        case .ongoing: AppColors.stageOngoing
        case .completed: AppColors.textMuted
        case .unknown: AppColors.textMuted
        }
    }
}

/// 探索城市页「用这里创建旅程」带来的目的地（规格 §7.3）。
///
/// 契约 §15.7 这条路径只认 `destinationSavedPlaceId`：带上它就不再发 `destination`
/// （见 `CreateTripRequest`），所以种子只需要 id；`destinationName` 只用于表单回显与标题建议。
struct TripCreateSeed: Equatable {
    let destinationSavedPlaceId: String
    let destinationName: String
}

struct TripFormState: Equatable {
    var title: String
    var destinationName: String
    var selectedDestination: TripDestination?
    var startDate: Date?
    var endDate: Date?
    var coverFileId: String?
    var coverPreviewURL: URL?
    var destinationSavedPlaceId: String?

    var trimmedDestinationName: String {
        destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var empty: TripFormState {
        let calendar = TracciDateContext.calendar
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 2, to: start)
        return TripFormState(
            title: "",
            destinationName: "",
            selectedDestination: nil,
            startDate: start,
            endDate: end,
            coverFileId: nil,
            coverPreviewURL: nil,
            destinationSavedPlaceId: nil
        )
    }

    static func from(trip: Trip) -> TripFormState {
        TripFormState(
            title: trip.title,
            destinationName: trip.destinationName ?? "",
            selectedDestination: trip.destination,
            startDate: TripDateFormatting.date(from: trip.startDate),
            endDate: TripDateFormatting.date(from: trip.endDate),
            coverFileId: trip.coverPhoto?.fileId,
            coverPreviewURL: trip.coverPreviewURL,
            destinationSavedPlaceId: nil
        )
    }
}

struct TripDestination: Codable, Equatable {
    let placeId: String?
    let name: String?
    let provider: String?
    let providerPlaceId: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let adcode: String?
    let cityCode: String?
    let provinceName: String?
    let cityName: String?
    let districtName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case provider
        case providerPlaceId
        case country
        case latitude
        case longitude
        case adcode
        case cityCode
        case provinceName
        case cityName
        case districtName
        case placeId
    }

    init(
        name: String?,
        provider: String? = nil,
        providerPlaceId: String? = nil,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        adcode: String? = nil,
        cityCode: String? = nil,
        provinceName: String? = nil,
        cityName: String? = nil,
        districtName: String? = nil,
        placeId: String? = nil
    ) {
        self.name = name
        self.provider = provider
        self.providerPlaceId = providerPlaceId
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.adcode = adcode
        self.cityCode = cityCode
        self.provinceName = provinceName
        self.cityName = cityName
        self.districtName = districtName
        self.placeId = placeId
    }

    init(placeSearchResult result: TracciPlaceSearchResult) {
        self.init(
            name: result.name,
            provider: "APPLE",
            providerPlaceId: result.providerPlaceId,
            country: result.country,
            latitude: result.latitude,
            longitude: result.longitude,
            provinceName: result.provinceName,
            cityName: result.cityName,
            districtName: result.districtName
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        providerPlaceId = try container.decodeIfPresent(String.self, forKey: .providerPlaceId)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        latitude = try container.decodeTripFlexibleDoubleIfPresent(forKey: .latitude)
        longitude = try container.decodeTripFlexibleDoubleIfPresent(forKey: .longitude)
        adcode = try container.decodeIfPresent(String.self, forKey: .adcode)
        cityCode = try container.decodeIfPresent(String.self, forKey: .cityCode)
        provinceName = try container.decodeIfPresent(String.self, forKey: .provinceName)
        cityName = try container.decodeIfPresent(String.self, forKey: .cityName)
        districtName = try container.decodeIfPresent(String.self, forKey: .districtName)
        placeId = try container.decodeIfPresent(String.self, forKey: .placeId)
    }
}

struct TripDestinationInput: Encodable, Equatable {
    let name: String
    let provider: String?
    let providerPlaceId: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let adcode: String?
    let cityCode: String?
    let provinceName: String?
    let cityName: String?
    let districtName: String?

    init(name: String) {
        self.name = name
        self.provider = "MANUAL"
        self.providerPlaceId = nil
        self.country = nil
        self.latitude = nil
        self.longitude = nil
        self.adcode = nil
        self.cityCode = nil
        self.provinceName = nil
        self.cityName = nil
        self.districtName = nil
    }

    init(destination: TripDestination) {
        name = destination.name ?? ""
        provider = destination.provider
        providerPlaceId = destination.providerPlaceId
        country = destination.country
        latitude = destination.latitude
        longitude = destination.longitude
        adcode = destination.adcode
        cityCode = destination.cityCode
        provinceName = destination.provinceName
        cityName = destination.cityName
        districtName = destination.districtName
    }
}

struct CreateTripRequest: Encodable {
    let title: String
    let startDate: String
    let endDate: String
    let coverFileId: String?
    let destination: TripDestinationInput?
    let baseCurrency: String?
    let destinationSavedPlaceId: String?

    init(from state: TripFormState, baseCurrency: String? = nil) {
        title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        startDate = TripDateFormatting.apiString(from: state.startDate)
        endDate = TripDateFormatting.apiString(from: state.endDate)
        coverFileId = state.coverFileId
        self.baseCurrency = baseCurrency
        destinationSavedPlaceId = state.destinationSavedPlaceId

        if let selectedDestination = state.selectedDestination,
           let name = selectedDestination.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            destination = state.destinationSavedPlaceId == nil ? TripDestinationInput(destination: selectedDestination) : nil
        } else {
            destination = state.destinationSavedPlaceId == nil && !state.trimmedDestinationName.isEmpty ? TripDestinationInput(name: state.trimmedDestinationName) : nil
        }
    }
}

struct UpdateTripRequest: Encodable {
    let title: String
    let startDate: String
    let endDate: String
    let coverFileId: String?
    let destination: TripDestinationInput?
    let baseCurrency: String?
    /// 客户端已就「修改日期会改变旅程状态」获得用户确认（对应 `TripAPIBusinessCode.statusChangeRequiresConfirm`）
    let statusChangeConfirmed: Bool

    init(from state: TripFormState, baseCurrency: String? = nil, statusChangeConfirmed: Bool = false) {
        title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        startDate = TripDateFormatting.apiString(from: state.startDate)
        endDate = TripDateFormatting.apiString(from: state.endDate)
        coverFileId = state.coverFileId
        self.baseCurrency = baseCurrency
        self.statusChangeConfirmed = statusChangeConfirmed

        if let selectedDestination = state.selectedDestination,
           let name = selectedDestination.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            destination = TripDestinationInput(destination: selectedDestination)
        } else {
            destination = state.trimmedDestinationName.isEmpty ? nil : TripDestinationInput(name: state.trimmedDestinationName)
        }
    }
}

// TripDateFormatting + TracciDateContext primitives: Core/Utils/TracciDateContext.swift
// tripStatus(…): Features/Trip/TripDateStatus.swift
