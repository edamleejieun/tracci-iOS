import XCTest
@testable import Tracci
import TracciNetworking

/// Closeout coverage for the full iOS Demo Journey plan (home matrix, scene switch, gates).
final class DemoJourneyCloseoutTests: XCTestCase {

    private var fixtureData: Data!

    private func makeTripService() -> TripService {
        let apiClient = APIClient(config: .development)
        return TripService(
            apiClient: apiClient,
            fileUploadService: FileUploadService(apiClient: apiClient)
        )
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Fixture lives at <test-target-root>/Fixtures/demo-journey-v1.json.
        // Derived from this file's location so the test survives moves within the same target.
        let testTargetDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // .../TracciTests/
            .deletingLastPathComponent() // test target root
        let url = testTargetDir
            .appendingPathComponent("TracciTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("demo-journey-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "DemoJourneyCloseoutTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Fixture not found at \(url.path)"]
            )
        }
        fixtureData = try Data(contentsOf: url)
    }

    // MARK: - Home display matrix (P1 + P5)

    @MainActor
    func testHomeDemoDisplayMatrix() {
        // Only real empty + non-search + available displayable bundle.
        XCTAssertTrue(
            HomeViewModel.shouldDisplayDemo(
                viewState: .empty,
                isSearching: false,
                demoLoadState: .available,
                bundleIsDisplayable: true
            )
        )

        let negatives: [(HomeViewModel.ViewState, Bool, HomeViewModel.DemoLoadState, Bool, Bool)] = [
            (.loaded, false, .available, true, false),
            (.loading, false, .available, true, false),
            (.idle, false, .available, true, false),
            (.error("x"), false, .available, true, false),
            (.empty, true, .available, true, false), // searching
            (.empty, false, .unavailable, true, false),
            (.empty, false, .loading, true, false),
            (.empty, false, .idle, true, false),
            (.empty, false, .available, false, false), // not displayable
            (.empty, false, .available, true, true), // graduated — permanent one-time gate
        ]

        for (state, searching, demo, displayable, graduated) in negatives {
            XCTAssertFalse(
                HomeViewModel.shouldDisplayDemo(
                    viewState: state,
                    isSearching: searching,
                    demoLoadState: demo,
                    bundleIsDisplayable: displayable,
                    hasGraduated: graduated
                ),
                "Unexpected show for state=\(state) searching=\(searching) demo=\(demo) displayable=\(displayable) graduated=\(graduated)"
            )
        }
    }

    /// 一次性资格：真实旅程出现过一次后，即便全部删除回到空列表，示例也不得复现。
    @MainActor
    func testDemoDoesNotReturnAfterTripCreatedThenDeleted() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let home = HomeViewModel(
            tripService: makeTripService(),
            demoJourneyService: nil
        )
        // Unique key per run so the test never reads a stale graduation marker.
        home.currentUserId = "test-graduate-\(UUID().uuidString)"

        // Fresh empty account: demo shows.
        home.applyTripsStateForTesting(trips: [], total: 0, state: .empty)
        home.applyDemoLoadResultForTesting(.displayable(bundle))
        XCTAssertTrue(home.showsDemoJourney)
        XCTAssertNotNil(home.displayableEmptyStateDemoBundle)

        // Create a real trip: demo hides and the account is permanently graduated.
        let trip = try XCTUnwrap(bundle.scene(.ongoing)?.trip)
        home.applyTripsStateForTesting(trips: [trip], total: 1, state: .loaded)
        XCTAssertFalse(home.showsDemoJourney)
        XCTAssertNil(home.displayableEmptyStateDemoBundle)
        XCTAssertTrue(home.hasGraduatedFromDemo)

        // Delete the last trip: list is empty again, bundle still available,
        // but the demo must NOT come back.
        home.applyTripsStateForTesting(trips: [], total: 0, state: .empty)
        home.applyDemoLoadResultForTesting(.displayable(bundle))
        XCTAssertTrue(home.hasGraduatedFromDemo)
        XCTAssertFalse(home.showsDemoJourney)
        XCTAssertNil(home.displayableEmptyStateDemoBundle)
    }

    @MainActor
    func testHomeClearsDemoWhenTripsAppear() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let home = HomeViewModel(
            tripService: makeTripService(),
            demoJourneyService: nil
        )
        home.applyDemoLoadResultForTesting(.displayable(bundle))
        home.applyTripsStateForTesting(trips: [], total: 0, state: .empty)
        // Manually re-apply demo after empty (applyTrips empty does not auto-load without service).
        home.applyDemoLoadResultForTesting(.displayable(bundle))
        XCTAssertEqual(home.demoLoadState, .available)
        XCTAssertTrue(home.showsDemoJourney)
        XCTAssertNotNil(home.displayableEmptyStateDemoBundle)

        let trip = try XCTUnwrap(bundle.scene(.ongoing)?.trip)
        home.applyTripsStateForTesting(trips: [trip], total: 1, state: .loaded)
        XCTAssertEqual(home.demoLoadState, .unavailable)
        XCTAssertNil(home.demoBundle)
        XCTAssertFalse(home.showsDemoJourney)
        XCTAssertNil(home.displayableEmptyStateDemoBundle)
    }

    @MainActor
    func testHomeHidesDemoWhileSearchingEvenIfBundlePresent() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let home = HomeViewModel(
            tripService: makeTripService(),
            demoJourneyService: nil
        )
        home.applyTripsStateForTesting(trips: [], total: 0, state: .empty)
        home.applyDemoLoadResultForTesting(.displayable(bundle))
        XCTAssertTrue(home.showsDemoJourney)

        home.searchQuery = "上海"
        XCTAssertTrue(home.isSearching)
        XCTAssertFalse(home.showsDemoJourney)
        // Bundle kept in memory; only presentation is suppressed.
        XCTAssertNotNil(home.demoBundle)
    }

    // MARK: - Home refresh continuity

    @MainActor
    func testPullToRefreshRetainsDisplayedDemoWhenDemoRequestFails() async throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let tripLoader = TripPageLoaderStub(results: [
            .success(Self.emptyTripPage),
            .success(Self.emptyTripPage),
        ])
        let demoLoader = DemoJourneyLoaderStub(results: [
            .displayable(bundle),
            .failure(message: "offline"),
        ])
        let home = makeRefreshHome(tripLoader: tripLoader, demoLoader: demoLoader)

        await home.loadTrips()
        XCTAssertTrue(home.showsDemoJourney)

        await home.refreshTrips()

        XCTAssertEqual(home.state, .empty)
        XCTAssertEqual(home.demoLoadState, .available)
        XCTAssertEqual(home.demoBundle?.contentVersion, bundle.contentVersion)
        XCTAssertTrue(home.showsDemoJourney)
        XCTAssertFalse(home.hasGraduatedFromDemo)
    }

    @MainActor
    func testPullToRefreshRetainsDisplayedDemoWhenRealTripListFails() async throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let tripLoader = TripPageLoaderStub(results: [
            .success(Self.emptyTripPage),
            .failure,
        ])
        let demoLoader = DemoJourneyLoaderStub(results: [.displayable(bundle)])
        let home = makeRefreshHome(tripLoader: tripLoader, demoLoader: demoLoader)

        await home.loadTrips()
        XCTAssertTrue(home.showsDemoJourney)

        await home.refreshTrips()

        XCTAssertEqual(home.state, .empty)
        XCTAssertEqual(home.demoLoadState, .available)
        XCTAssertTrue(home.showsDemoJourney)
        XCTAssertEqual(demoLoader.loadCount, 1, "Demo should not revalidate when the real list failed")
    }

    @MainActor
    func testPullToRefreshClearsDisplayedDemoWhenServerExplicitlyDisablesIt() async throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let tripLoader = TripPageLoaderStub(results: [
            .success(Self.emptyTripPage),
            .success(Self.emptyTripPage),
        ])
        let demoLoader = DemoJourneyLoaderStub(results: [
            .displayable(bundle),
            .featureOff,
        ])
        let home = makeRefreshHome(tripLoader: tripLoader, demoLoader: demoLoader)

        await home.loadTrips()
        XCTAssertTrue(home.showsDemoJourney)

        await home.refreshTrips()

        XCTAssertEqual(home.state, .empty)
        XCTAssertEqual(home.demoLoadState, .unavailable)
        XCTAssertNil(home.demoBundle)
        XCTAssertFalse(home.showsDemoJourney)
    }

    @MainActor
    func testPullToRefreshGraduatesDemoWhenFirstRealTripAppears() async throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let firstTrip = try XCTUnwrap(bundle.scene(.ongoing)?.trip)
        let tripLoader = TripPageLoaderStub(results: [
            .success(Self.emptyTripPage),
            .success(PageResponse(list: [firstTrip], total: 1, page: 1, pageSize: 20)),
        ])
        let demoLoader = DemoJourneyLoaderStub(results: [.displayable(bundle)])
        let home = makeRefreshHome(tripLoader: tripLoader, demoLoader: demoLoader)

        await home.loadTrips()
        XCTAssertTrue(home.showsDemoJourney)

        await home.refreshTrips()

        XCTAssertEqual(home.state, .loaded)
        XCTAssertEqual(home.trips.map(\.id), [firstTrip.id])
        XCTAssertTrue(home.hasGraduatedFromDemo)
        XCTAssertNil(home.demoBundle)
        XCTAssertFalse(home.showsDemoJourney)
    }

    @MainActor
    private func makeRefreshHome(
        tripLoader: TripPageLoaderStub,
        demoLoader: DemoJourneyLoaderStub
    ) -> HomeViewModel {
        let home = HomeViewModel(
            tripService: makeTripService(),
            demoJourneyService: demoLoader,
            tripPageLoader: { page, pageSize in
                try await tripLoader.load(page: page, pageSize: pageSize)
            }
        )
        home.currentUserId = "test-refresh-\(UUID().uuidString)"
        return home
    }

    private static var emptyTripPage: PageResponse<Trip> {
        PageResponse(list: [], total: 0, page: 1, pageSize: 20)
    }

    // MARK: - Scene switch (P2/P4)

    @MainActor
    func testSwitchDemoSceneRehydratesWithoutLiveTripIdConfusion() async throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let ongoing = try XCTUnwrap(bundle.scene(.ongoing))
        let client = APIClient(config: .development)
        let fileUploadService = FileUploadService(apiClient: client)
        let vm = TripDetailViewModel(
            trip: ongoing.trip,
            tripService: TripService(apiClient: client, fileUploadService: fileUploadService),
            itineraryService: ItineraryService(apiClient: client),
            journalService: JournalService(apiClient: client, fileUploadService: fileUploadService),
            expenseService: ExpenseService(apiClient: client),
            collaborationService: CollaborationService(apiClient: client),
            routeProvider: RouteCacheService(),
            journeyContext: .demo(bundle: bundle, scene: .ongoing)
        )
        await vm.bootstrapDemoIfNeeded()
        XCTAssertEqual(vm.trip.status, .ongoing)
        XCTAssertFalse(vm.journalViewModel.entries.isEmpty)

        let switched = await vm.switchDemoScene(to: .planning)
        XCTAssertTrue(switched)
        XCTAssertEqual(vm.demoSceneKind, .planning)
        XCTAssertEqual(vm.trip.status, .planning)
        XCTAssertTrue(vm.journalViewModel.entries.isEmpty) // planning has no journals
        XCTAssertEqual(vm.insightViewModel.phase, .planning)

        let toCompleted = await vm.switchDemoScene(to: .completed)
        XCTAssertTrue(toCompleted)
        XCTAssertEqual(vm.trip.status, .completed)
        XCTAssertFalse(vm.journalViewModel.entries.isEmpty)
        XCTAssertNotNil(vm.demoSummary)
        XCTAssertFalse(vm.demoActivityLogs.isEmpty)
    }

    // MARK: - Capability / mutation (P3)

    func testCapabilitiesDenyAllWrites() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let caps = bundle.capabilities
        XCTAssertTrue(caps.deniesAllMutations)
        let ctx = JourneyContext.demo(bundle: bundle, scene: .ongoing)
        for key in [
            DemoMutationGuard.DemoCapabilityKey.editTrip,
            .addNode,
            .editJournal,
            .manageExpense,
            .manageMembers,
            .invite,
            .delete,
            .share,
            .export,
            .applyAiChanges,
        ] {
            XCTAssertFalse(DemoMutationGuard.allows(key, in: ctx), "Expected false for \(key)")
        }
        XCTAssertFalse(DemoMutationGuard.allowsMutation(ctx))
    }

    // MARK: - Schema / disable (P0 + P5)

    func testFeatureOffAndUnsupportedSchemaAreNotDisplayable() throws {
        var off = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        // Rebuild disabled via JSON
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        json["enabled"] = false
        json["scenes"] = nil
        let offData = try JSONSerialization.data(withJSONObject: json)
        off = try JSONDecoder().decode(DemoJourneyBundle.self, from: offData)
        XCTAssertFalse(off.isDisplayable)
        XCTAssertEqual(DemoJourneyService.validateResult(for: off), .featureOff)

        json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        json["schemaVersion"] = 99
        let badSchema = try JSONDecoder().decode(
            DemoJourneyBundle.self,
            from: try JSONSerialization.data(withJSONObject: json)
        )
        if case .undisplayable = DemoJourneyService.validateResult(for: badSchema) {
            // ok
        } else {
            XCTFail("Expected undisplayable for unknown schema")
        }
        XCTAssertFalse(badSchema.isDisplayable)
    }

    // MARK: - Navigation semantics

    func testDemoNavigationRouteIsNotLiveTripDetail() throws {
        let route = HomeNavigationRoute.demoJourney(scene: .ongoing)
        switch route {
        case .demoJourney(let scene):
            XCTAssertEqual(scene, .ongoing)
        default:
            XCTFail("Demo must use dedicated route, not tripDetail")
        }
    }

    @MainActor
    func testCompletedDemoUsesBundleCoverAsStoryCover() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let completed = try XCTUnwrap(bundle.scene(.completed))
        let cover = try XCTUnwrap(
            MemoryPageViewModel.preferredDemoStoryCoverPhoto(in: completed.summary)
        )

        XCTAssertEqual(cover.fileId, "demo-v1-asset-cover")
    }
}

private enum TripPageLoaderResult {
    case success(PageResponse<Trip>)
    case failure
}

private enum TripPageLoaderError: Error {
    case offline
}

private final class TripPageLoaderStub {
    private var results: [TripPageLoaderResult]

    init(results: [TripPageLoaderResult]) {
        self.results = results
    }

    func load(page: Int, pageSize: Int) async throws -> PageResponse<Trip> {
        guard !results.isEmpty else { throw TripPageLoaderError.offline }
        switch results.removeFirst() {
        case let .success(response):
            return response
        case .failure:
            throw TripPageLoaderError.offline
        }
    }
}

private final class DemoJourneyLoaderStub: DemoJourneyLoading {
    private var results: [DemoJourneyService.LoadResult]
    private(set) var loadCount = 0

    init(results: [DemoJourneyService.LoadResult]) {
        self.results = results
    }

    func loadDisplayableBundle() async -> DemoJourneyService.LoadResult {
        loadCount += 1
        guard !results.isEmpty else { return .failure(message: "No stubbed Demo result") }
        return results.removeFirst()
    }
}

// MARK: - LoadResult Equatable helper for tests

extension DemoJourneyService.LoadResult: Equatable {
    public static func == (lhs: DemoJourneyService.LoadResult, rhs: DemoJourneyService.LoadResult) -> Bool {
        switch (lhs, rhs) {
        case (.featureOff, .featureOff):
            return true
        case let (.undisplayable(a), .undisplayable(b)):
            return a == b
        case let (.failure(a), .failure(b)):
            return a == b
        case let (.displayable(a), .displayable(b)):
            return a.schemaVersion == b.schemaVersion
                && a.contentVersion == b.contentVersion
                && a.enabled == b.enabled
        default:
            return false
        }
    }
}
