import XCTest
@testable import Tracci
import TracciNetworking

final class SavedPlaceModelsTests: XCTestCase {
    func testCreateExistingPlaceEncodingIsMutuallyExclusive() throws {
        let data = try JSONEncoder().encode(CreateSavedPlaceRequest.existingPlace(placeId: "p1", note: "想去"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["placeId"] as? String, "p1"); XCTAssertNil(object["location"]); XCTAssertNil(object["placeScope"])
    }

    func testLocationCandidateEncodingIsMutuallyExclusive() throws {
        let location = SavedPlaceLocationInput(
            name: "清水寺",
            address: nil,
            provider: "MANUAL",
            providerPlaceId: nil,
            country: nil,
            provinceName: nil,
            cityName: "京都",
            districtName: nil,
            latitude: nil,
            longitude: nil,
            adcode: nil,
            cityCode: nil
        )
        let data = try JSONEncoder().encode(
            CreateSavedPlaceRequest.locationCandidate(
                scope: .poi,
                category: .attraction,
                location: location,
                note: nil
            )
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["placeId"])
        XCTAssertEqual(object["placeScope"] as? String, "POI")
        XCTAssertNotNil(object["location"])
    }
    func testQueryClampsPageSizeAndEncodesUsage() {
        let query = SavedPlaceListQuery(usage: .itineraryNode, tripId: "t1", page: 0, pageSize: 999)
        XCTAssertEqual(query.queryItems.map(\.name), ["usage", "tripId", "page", "pageSize"])
        XCTAssertEqual(query.queryItems.last?.value, "100")
    }
    func testResponsePlaceIdIsDecodedButLocationDoesNotEncodeIt() throws {
        let location = ItineraryLocation(provider: "APPLE", name: "清水寺", placeId: "p1")
        let data = try JSONEncoder().encode(location)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["placeId"])
        let decoded = try JSONDecoder().decode(ItineraryLocation.self, from: Data("{\"name\":\"清水寺\",\"placeId\":\"p1\"}".utf8))
        XCTAssertEqual(decoded.placeId, "p1")
    }

    func testTripCreationUsesSavedPlaceIdAsAuthority() throws {
        var state = TripFormState.empty
        state.title = "京都"
        state.destinationName = "京都"
        state.startDate = Date(timeIntervalSince1970: 0)
        state.endDate = Date(timeIntervalSince1970: 86_400)
        state.destinationSavedPlaceId = "saved-1"
        let data = try JSONEncoder().encode(CreateTripRequest(from: state))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["destinationSavedPlaceId"] as? String, "saved-1")
        XCTAssertNil(object["destination"])
    }

    func testNodeCreationUsesSavedPlaceIdAndDoesNotSendLocation() throws {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.locationName = "清水寺"
        form.savedPlaceId = "saved-2"
        let data = try JSONEncoder().encode(CreateItineraryNodeRequest(from: form))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["savedPlaceId"] as? String, "saved-2")
        XCTAssertNil(object["location"])
    }


    func testChangingNodeLocationClearsSavedPlaceAssociation() {
        var form = ItineraryNodeFormState.create(defaultDayIndex: 1)
        form.savedPlaceId = "saved-old"
        form.updateLocationText("新地点")
        XCTAssertNil(form.savedPlaceId)
        XCTAssertNil(form.selectedLocation)

        form.savedPlaceId = "saved-old"
        form.useSelectedLocation(ItineraryLocation(provider: "APPLE", name: "清水寺"))
        XCTAssertNil(form.savedPlaceId)
        XCTAssertEqual(form.selectedLocation?.name, "清水寺")

        form.savedPlaceId = "saved-old"
        form.useManualLocation("手动地点")
        XCTAssertNil(form.savedPlaceId)
        XCTAssertEqual(form.locationName, "手动地点")
    }

    func testPlaceCategoriesRespectScope() {
        XCTAssertEqual(PlaceCategory.allowed(for: .destination), [.city, .region])
        XCTAssertFalse(PlaceCategory.allowed(for: .poi).contains(.city))
        XCTAssertFalse(PlaceCategory.allowed(for: .poi).contains(.region))
    }

    func testSavedPlaceClassificationKeepsTechnicalFieldsOutOfTheUI() {
        XCTAssertEqual(
            SavedPlaceClassification.infer(
                name: "北京市",
                mapCategory: nil,
                cityName: "北京市",
                provinceName: "北京市"
            ),
            SavedPlaceClassification(scope: .destination, category: .city)
        )
        XCTAssertEqual(
            SavedPlaceClassification.infer(
                name: "故宫博物院",
                mapCategory: "博物馆",
                cityName: "北京市",
                provinceName: "北京市"
            ),
            SavedPlaceClassification(scope: .poi, category: .attraction)
        )
        XCTAssertEqual(SavedPlaceClassification.manual, .init(scope: .poi, category: .other))
    }

    func testSavedPlaceBusinessErrorsHaveStableFallbackCopy() {
        XCTAssertEqual(
            SavedPlaceErrorMessage.resolve(APIError.business(code: 42243, message: "raw")),
            "这个地点与当前旅程目的地不匹配"
        )
        XCTAssertEqual(
            SavedPlaceErrorMessage.resolve(APIError.business(code: 99999, message: "服务端说明")),
            "服务端说明"
        )
    }

    func testCanAddToItineraryRespectsPlaceScopeAndUsages() {
        let destination = makeSavedPlace(
            scope: .destination,
            category: .city,
            usages: [.tripDestination]
        )
        XCTAssertFalse(destination.canAddToItinerary)

        let poiWithNodeUsage = makeSavedPlace(
            scope: .poi,
            category: .attraction,
            usages: [.itineraryNode]
        )
        XCTAssertTrue(poiWithNodeUsage.canAddToItinerary)

        let poiWithoutNodeUsage = makeSavedPlace(
            scope: .poi,
            category: .attraction,
            usages: [.tripDestination]
        )
        XCTAssertFalse(poiWithoutNodeUsage.canAddToItinerary)

        let poiWithEmptyUsages = makeSavedPlace(
            scope: .poi,
            category: .attraction,
            usages: []
        )
        XCTAssertTrue(poiWithEmptyUsages.canAddToItinerary)
    }

    func testGroupingCityKeyUsesDestinationNameAndPOICityFallback() {
        let destination = makeSavedPlace(
            scope: .destination,
            category: .city,
            name: "京都",
            cityName: nil,
            usages: [.tripDestination]
        )
        XCTAssertEqual(destination.groupingCityKey, "京都")

        let poi = makeSavedPlace(
            scope: .poi,
            category: .attraction,
            name: "清水寺",
            cityName: "京都",
            usages: [.itineraryNode]
        )
        XCTAssertEqual(poi.groupingCityKey, "京都")

        let orphanPOI = makeSavedPlace(
            scope: .poi,
            category: .attraction,
            name: "某处",
            cityName: "   ",
            usages: [.itineraryNode]
        )
        XCTAssertEqual(orphanPOI.groupingCityKey, "其他地点")
    }

    @MainActor
    func testCreateEditorDoesNotSubmitOptionalNote() async throws {
        let service = SavedPlaceServiceStub()
        let viewModel = SavedPlaceEditorViewModel(service: service, mode: .create)
        viewModel.useManualName("故宫博物院")
        viewModel.note = String(repeating: "不", count: 501)

        let didSubmit = await viewModel.submit()
        XCTAssertTrue(didSubmit)

        let request = try XCTUnwrap(service.createdRequests.first)
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["note"])
    }

    @MainActor
    func testDebouncedSearchExecutesLatestKeywordWithoutCancellingItself() async throws {
        let service = SavedPlaceServiceStub()
        let viewModel = SavedPlacesViewModel(service: service)
        viewModel.keyword = "京"
        viewModel.scheduleSearch()
        viewModel.keyword = "京都"
        viewModel.scheduleSearch()

        try await Task.sleep(for: .milliseconds(450))

        XCTAssertEqual(service.queries.count, 1)
        XCTAssertEqual(service.queries.first?.keyword, "京都")
        XCTAssertNil(service.queries.first?.placeScope)
        XCTAssertNil(service.queries.first?.category)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testFailedLoadMoreRetriesSamePage() async {
        let service = SavedPlaceServiceStub(failPageTwoOnce: true)
        let viewModel = SavedPlacesViewModel(service: service)
        await viewModel.load()
        guard let first = viewModel.items.last else {
            return XCTFail("第一页应返回一条收藏")
        }

        await viewModel.loadMoreIfNeeded(after: first)
        await viewModel.loadMoreIfNeeded(after: first)

        XCTAssertEqual(service.queries.map(\.page), [1, 2, 2])
        XCTAssertEqual(viewModel.items.count, 2)
    }

    private func makeSavedPlace(
        scope: PlaceScope,
        category: PlaceCategory,
        name: String = "地点",
        cityName: String? = "京都",
        usages: [SupportedPlaceUsage]
    ) -> SavedPlace {
        SavedPlace(
            id: "saved-\(name)",
            placeId: "place-\(name)",
            place: PlaceSummary(
                name: name,
                placeScope: scope,
                category: category,
                address: nil,
                cityName: cityName,
                country: "日本",
                latitude: nil,
                longitude: nil,
                supportedUsages: usages
            ),
            note: nil,
            usageSummary: nil,
            createdAt: "2026-08-02T10:00:00Z",
            updatedAt: nil
        )
    }
}

private final class SavedPlaceServiceStub: SavedPlaceServicing {
    private(set) var queries: [SavedPlaceListQuery] = []
    private(set) var createdRequests: [CreateSavedPlaceRequest] = []
    private var shouldFailPageTwo: Bool

    init(failPageTwoOnce: Bool = false) {
        shouldFailPageTwo = failPageTwoOnce
    }

    func create(_ request: CreateSavedPlaceRequest) async throws -> SavedPlace {
        createdRequests.append(request)
        return Self.firstItem
    }

    func list(_ query: SavedPlaceListQuery) async throws -> PageResponse<SavedPlace> {
        queries.append(query)
        if query.page == 2, shouldFailPageTwo {
            shouldFailPageTwo = false
            throw APIError.underlying("分页失败")
        }
        let list = query.page == 1 ? [Self.firstItem] : [Self.secondItem]
        return PageResponse(list: list, total: 2, page: query.page, pageSize: query.pageSize)
    }

    func updateNote(savedPlaceId: String, note: String?) async throws -> SavedPlace { Self.firstItem }
    func delete(savedPlaceId: String) async throws {}
    func placeDetail(placeId: String) async throws -> PlaceDetail {
        PlaceDetail(
            id: placeId,
            name: "清水寺",
            placeScope: .poi,
            category: .attraction,
            address: nil,
            cityName: "京都",
            country: "日本",
            latitude: nil,
            longitude: nil,
            supportedUsages: [.itineraryNode],
            userContext: PlaceUserContext(isSaved: false, savedPlaceId: nil, note: nil, usageSummary: nil),
            editorialContent: nil,
            contentMeta: nil,
            media: nil
        )
    }
    func publishedPlaces(_ query: PublishedPlacesQuery) async throws -> PageResponse<PublishedPlace> {
        PageResponse(list: [], total: 0, page: query.page, pageSize: query.pageSize)
    }

    private static let place = PlaceSummary(
        name: "清水寺",
        placeScope: .poi,
        category: .attraction,
        address: nil,
        cityName: "京都",
        country: "日本",
        latitude: nil,
        longitude: nil,
        supportedUsages: [.itineraryNode]
    )

    private static let firstItem = SavedPlace(
        id: "saved-1",
        placeId: "place-1",
        place: place,
        note: nil,
        usageSummary: nil,
        createdAt: "2026-08-02T10:00:00Z",
        updatedAt: nil
    )

    private static let secondItem = SavedPlace(
        id: "saved-2",
        placeId: "place-2",
        place: place,
        note: nil,
        usageSummary: nil,
        createdAt: "2026-08-02T10:00:00Z",
        updatedAt: nil
    )
}
