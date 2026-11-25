import XCTest
@testable import Tracci
import TracciNetworking

@MainActor
final class SavedPlaceAddToTripViewModelTests: XCTestCase {
    func testLoadSortsMatchingDestinationTripsFirst() async {
        let place = makePOI(cityName: "京都")
        let provider = TripProviderStub(trips: [
            makeTrip(id: "tokyo", destination: "东京", startDate: "2026-09-01"),
            makeTrip(id: "kyoto", destination: "京都", startDate: "2026-10-01"),
            makeTrip(id: "osaka", destination: "大阪", startDate: "2026-08-01")
        ])
        let model = SavedPlaceAddToTripViewModel(place: place, provider: provider)

        await model.load()

        XCTAssertEqual(model.trips.map(\.id), ["kyoto", "osaka", "tokyo"])
    }

    func testSelectTripGenerationDropsStaleDays() async {
        let place = makePOI(cityName: "京都")
        let provider = TripProviderStub(
            trips: [
                makeTrip(id: "slow", destination: "京都", startDate: "2026-09-01"),
                makeTrip(id: "fast", destination: "京都", startDate: "2026-10-01")
            ],
            daysByTripId: [
                "slow": [makeDay(id: "slow-day", dayIndex: 1)],
                "fast": [makeDay(id: "fast-day", dayIndex: 1)]
            ],
            delayNanosecondsByTripId: ["slow": 120_000_000]
        )
        let model = SavedPlaceAddToTripViewModel(place: place, provider: provider)
        await model.load()

        model.selectTrip(provider.trips[0]) // slow
        model.selectTrip(provider.trips[1]) // fast, should win

        try? await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(model.selectedTripId, "fast")
        XCTAssertEqual(model.days.map(\.id), ["fast-day"])
        XCTAssertFalse(model.isLoadingDays)
    }

    func testDestinationLikelyMatchesUsesCityContainment() {
        let place = makePOI(cityName: "京都市")
        let matching = makeTrip(id: "1", destination: "京都", startDate: "2026-10-01")
        let mismatch = makeTrip(id: "2", destination: "东京", startDate: "2026-10-01")

        XCTAssertTrue(
            SavedPlaceAddToTripViewModel.destinationLikelyMatches(place: place, trip: matching)
        )
        XCTAssertFalse(
            SavedPlaceAddToTripViewModel.destinationLikelyMatches(place: place, trip: mismatch)
        )
    }

    func testDisplayGroupsKeepsDestinationsWideAndAggregatesPOIByCity() async {
        let service = DisplayGroupServiceStub(items: [
            makeSavedPlace(id: "d1", scope: .destination, name: "京都", cityName: nil),
            makeSavedPlace(id: "p1", scope: .poi, name: "清水寺", cityName: "京都"),
            makeSavedPlace(id: "p2", scope: .poi, name: "金阁寺", cityName: "京都"),
            makeSavedPlace(id: "p3", scope: .poi, name: "某处", cityName: nil)
        ])
        let model = SavedPlacesViewModel(service: service)
        await model.load()

        let groups = model.displayGroups
        XCTAssertEqual(groups.map(\.label), ["目的地", "京都", "其他地点"])
        XCTAssertEqual(groups.map(\.count), [1, 2, 1])
    }

    // MARK: - Fixtures

    private func makePOI(cityName: String) -> SavedPlace {
        makeSavedPlace(id: "saved-poi", scope: .poi, name: "清水寺", cityName: cityName)
    }

    private func makeSavedPlace(
        id: String,
        scope: PlaceScope,
        name: String,
        cityName: String?
    ) -> SavedPlace {
        SavedPlace(
            id: id,
            placeId: "place-\(id)",
            place: PlaceSummary(
                name: name,
                placeScope: scope,
                category: scope == .destination ? .city : .attraction,
                address: nil,
                cityName: cityName,
                country: "日本",
                latitude: nil,
                longitude: nil,
                supportedUsages: scope == .destination ? [.tripDestination] : [.itineraryNode]
            ),
            note: nil,
            usageSummary: nil,
            createdAt: "2026-08-02T10:00:00Z",
            updatedAt: nil
        )
    }

    private func makeTrip(
        id: String,
        destination: String,
        startDate: String
    ) -> SavedPlaceTripSummary {
        SavedPlaceTripSummary(
            trip: Trip(
                id: id,
                title: "\(destination)之旅",
                startDate: startDate,
                endDate: startDate,
                status: .planning,
                totalDays: 3,
                destination: TripDestination(name: destination, country: "日本", cityName: destination),
                nodeCount: 0
            )
        )
    }

    private func makeDay(id: String, dayIndex: Int) -> SavedPlaceTripDay {
        SavedPlaceTripDay(
            day: ItineraryDay(
                id: id,
                dayIndex: dayIndex,
                date: "2026-10-15",
                nodes: []
            )
        )
    }
}

// MARK: - Stubs

@MainActor
private final class TripProviderStub: SavedPlaceTripProviding {
    let trips: [SavedPlaceTripSummary]
    private let daysByTripId: [String: [SavedPlaceTripDay]]
    private let delayNanosecondsByTripId: [String: UInt64]

    init(
        trips: [SavedPlaceTripSummary],
        daysByTripId: [String: [SavedPlaceTripDay]] = [:],
        delayNanosecondsByTripId: [String: UInt64] = [:]
    ) {
        self.trips = trips
        self.daysByTripId = daysByTripId
        self.delayNanosecondsByTripId = delayNanosecondsByTripId
    }

    func loadActiveTrips() async throws -> [SavedPlaceTripSummary] { trips }

    func loadTripDays(tripId: String) async throws -> [SavedPlaceTripDay] {
        if let delay = delayNanosecondsByTripId[tripId] {
            try await Task.sleep(nanoseconds: delay)
        }
        return daysByTripId[tripId] ?? []
    }

    func addSavedPlace(
        _ place: SavedPlace,
        toTripId tripId: String,
        dayId: String
    ) async throws -> String {
        "node-1"
    }
}

@MainActor
private final class DisplayGroupServiceStub: SavedPlaceServicing {
    let items: [SavedPlace]

    init(items: [SavedPlace]) {
        self.items = items
    }

    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace { items[0] }
    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> {
        PageResponse(list: items, total: items.count, page: 1, pageSize: 20)
    }
    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace { items[0] }
    func delete(savedPlaceId: String) async throws {}
    func placeDetail(placeId: String) async throws -> PlaceDetail {
        PlaceDetail(
            id: placeId,
            name: "详情",
            placeScope: .poi,
            category: .attraction,
            address: nil,
            cityName: nil,
            country: nil,
            latitude: nil,
            longitude: nil,
            supportedUsages: [.itineraryNode],
            userContext: nil,
            editorialContent: nil,
            contentMeta: nil,
            media: nil
        )
    }
    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> {
        PageResponse(list: [], total: 0, page: query.page, pageSize: query.pageSize)
    }
}
