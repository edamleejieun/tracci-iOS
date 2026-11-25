import MapKit
import Observation
import SwiftUI
import TracciNetworking

// MARK: - Preview

private struct PreviewSavedPlaceService: SavedPlaceServicing {
    let items: [SavedPlace]
    let detail: PlaceDetail

    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace { items[0] }
    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> {
        PageResponse(list: items, total: items.count, page: 1, pageSize: 20)
    }
    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace { items[0] }
    func delete(savedPlaceId: String) async throws {}
    func placeDetail(placeId: String) async throws -> PlaceDetail { detail }
    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> {
        PageResponse(list: [], total: 0, page: query.page, pageSize: query.pageSize)
    }
}

private let previewPlaceSummary = PlaceSummary(
    name: "清水寺",
    placeScope: .poi,
    category: .attraction,
    address: "京都府京都市东山区清水 1-294",
    cityName: "京都",
    country: "日本",
    latitude: 34.9949,
    longitude: 135.785,
    supportedUsages: [.itineraryNode]
)

private let previewSavedPlace = SavedPlace(
    id: "saved-preview",
    placeId: "place-preview",
    place: previewPlaceSummary,
    note: "早上开门后去，人相对少一些",
    usageSummary: PlaceUsageSummary(tripCount: 1, lastUsedTripId: "trip-preview"),
    createdAt: "2026-08-02T10:00:00Z",
    updatedAt: "2026-08-02T10:00:00Z"
)

private let previewPlaceDetail = PlaceDetail(
    id: "place-preview",
    name: previewPlaceSummary.name,
    placeScope: previewPlaceSummary.placeScope,
    category: previewPlaceSummary.category,
    address: previewPlaceSummary.address,
    cityName: previewPlaceSummary.cityName,
    country: previewPlaceSummary.country,
    latitude: previewPlaceSummary.latitude,
    longitude: previewPlaceSummary.longitude,
    supportedUsages: previewPlaceSummary.supportedUsages,
    userContext: PlaceUserContext(
        isSaved: true,
        savedPlaceId: "saved-preview",
        note: previewSavedPlace.note,
        usageSummary: previewSavedPlace.usageSummary
    ),
    editorialContent: nil,
    contentMeta: nil,
    media: nil
)

private let previewSavedPlaceService = PreviewSavedPlaceService(
    items: [previewSavedPlace],
    detail: previewPlaceDetail
)

#Preview("想去的地点 · 内容") {
    NavigationStack {
        SavedPlacesView(service: previewSavedPlaceService, onOpenDetail: { _ in })
    }
}

// MARK: - Trip Capability (Preview)

/// 预览用的行程能力 mock：返回固定旅程与日期，addSavedPlace 直接返回固定 id。
private final class PreviewSavedPlaceTripProvider: SavedPlaceTripProviding {
    func loadActiveTrips() async throws -> [SavedPlaceTripSummary] {
        let trip = Trip(
            id: "trip-preview",
            title: "秋日京都 5 日游",
            startDate: "2026-10-15",
            endDate: "2026-10-19",
            status: .planning,
            totalDays: 5,
            destination: TripDestination(name: "京都", country: "日本", cityName: "京都"),
            nodeCount: 3
        )
        return [SavedPlaceTripSummary(trip: trip)]
    }

    func loadTripDays(tripId: String) async throws -> [SavedPlaceTripDay] {
        // dayIndex 与 API 一致，从 1 开始。
        let days = (1...5).map { dayIndex in
            ItineraryDay(
                id: "day-preview-\(dayIndex)",
                dayIndex: dayIndex,
                date: "2026-10-\(14 + dayIndex)",
                nodes: []
            )
        }
        return days.map(SavedPlaceTripDay.init)
    }

    func addSavedPlace(_ place: SavedPlace, toTripId tripId: String, dayId: String) async throws -> String {
        "node-preview"
    }
}

#Preview("想去的地点 · 加入行程") {
    NavigationStack {
        PlaceDetailView(
            service: previewSavedPlaceService,
            placeId: "place-preview",
            tripProvider: PreviewSavedPlaceTripProvider()
        )
    }
}

#Preview("收藏地点") {
    SavedPlaceEditorView(service: previewSavedPlaceService, mode: .create, onSuccess: {})
}

#Preview("地点详情") {
    NavigationStack {
        PlaceDetailView(service: previewSavedPlaceService, placeId: "place-preview")
    }
}

#Preview("选择收藏地点") {
    SavedPlacePickerView(
        service: previewSavedPlaceService,
        query: SavedPlaceListQuery(usage: .itineraryNode, tripId: "trip-preview"),
        onSelect: { _ in }
    )
}


