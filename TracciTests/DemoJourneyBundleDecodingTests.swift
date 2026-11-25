import CryptoKit
import XCTest
@testable import Tracci
import TracciNetworking

final class DemoJourneyBundleDecodingTests: XCTestCase {

    private var fixtureData: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureData = try Self.loadFixtureData()
    }

    // MARK: - Golden Snapshot

    func testGoldenSnapshotDecodesWithProductionModels() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)

        XCTAssertEqual(bundle.schemaVersion, 1)
        XCTAssertEqual(bundle.contentVersion, "2026.07.31.4")
        XCTAssertEqual(bundle.referenceDate, "2026-07-30")
        XCTAssertTrue(bundle.enabled)
        XCTAssertEqual(bundle.defaultScene, "ONGOING")
        XCTAssertEqual(bundle.validDefaultScene, .ongoing)
        XCTAssertTrue(bundle.isDisplayable)
        XCTAssertTrue(bundle.capabilities.deniesAllMutations)
        XCTAssertTrue(bundle.capabilities.readOnly)

        let scenes = try XCTUnwrap(bundle.scenes)
        XCTAssertEqual(scenes.planning.trip.status, .planning)
        XCTAssertEqual(scenes.ongoing.trip.status, .ongoing)
        XCTAssertEqual(scenes.completed.trip.status, .completed)

        for kind in DemoJourneySceneKind.allCases {
            let scene = scenes[kind]
            XCTAssertEqual(scene.trip.access?.role, .viewer)
            XCTAssertTrue(scene.trip.access?.allows(.read) == true)
            XCTAssertFalse(scene.trip.access?.allows(.editContent) == true)
            XCTAssertFalse(scene.itinerary.days.isEmpty)
            XCTAssertEqual(scene.stats.overview.overview.tripCount, 1)
            XCTAssertGreaterThanOrEqual(scene.stats.recordsAnalysis.itineraryCount, 0)
            XCTAssertFalse(scene.stats.footprintAnalysis.cities.isEmpty)
            XCTAssertEqual(scene.stageOverview.permissions?.canAddJournal, false)
            XCTAssertEqual(scene.stageOverview.permissions?.canFeaturePhoto, false)
        }

        // Spend categories are present once the scene has actual expenses (not planning).
        XCTAssertFalse(scenes.ongoing.stats.spendAnalysis.categoryStats.isEmpty)
        XCTAssertFalse(scenes.completed.stats.spendAnalysis.categoryStats.isEmpty)
        XCTAssertTrue(scenes.planning.stats.spendAnalysis.categoryStats.isEmpty)
    }

    func testDefaultSceneIsOngoingWithContent() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let scene = try XCTUnwrap(bundle.defaultScenePayload())

        XCTAssertEqual(scene.trip.id, "demo-v1-ongoing-trip")
        XCTAssertEqual(scene.trip.title, "魔都五日 · 浦西浦东")
        XCTAssertEqual(scene.trip.destinationName, "上海")
        XCTAssertEqual(scene.itinerary.days.count, 5)
        XCTAssertEqual(scene.itinerary.days.flatMap(\.nodes).count, 22)
        XCTAssertEqual(scene.journals.total, 9)
        XCTAssertEqual(scene.journals.list.flatMap(\.photos).count, 9)
        XCTAssertEqual(scene.expenses.total, 14)
        XCTAssertEqual(scene.members.count, 3)
        XCTAssertTrue(scene.weather.available)
        XCTAssertEqual(scene.weather.updatedAt, "2026-07-30")
        XCTAssertEqual(scene.stageOverview.phase, .ongoing)
        XCTAssertFalse(scene.summary.recommendedPhotos.isEmpty)
        XCTAssertFalse(scene.exportAssets.photos.isEmpty)
        XCTAssertFalse(scene.itineraryExportAssets.days.isEmpty)
        let itineraryText = scene.itinerary.days
            .flatMap(\.nodes)
            .map(\.title)
            .joined(separator: " ")
        for landmark in [
            "南京路", "外滩", "豫园", "武康路", "田子坊",
            "新天地", "陆家嘴", "上海中心", "迪士尼",
        ] {
            XCTAssertTrue(itineraryText.contains(landmark), "Missing Shanghai landmark: \(landmark)")
        }
    }

    func testPlanningSceneHasNoFutureJournalsOrExpenses() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let planning = try XCTUnwrap(bundle.scene(.planning))

        XCTAssertEqual(planning.journals.total, 0)
        XCTAssertTrue(planning.journals.list.isEmpty)
        XCTAssertEqual(planning.expenses.total, 0)
        XCTAssertTrue(planning.expenses.list.isEmpty)
        XCTAssertEqual(planning.stageOverview.phase, .planning)
    }

    func testExpenseEnumsDecodeUppercaseBackendValues() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let expense = try XCTUnwrap(bundle.scene(.ongoing)?.expenses.list.first)

        XCTAssertEqual(expense.expenseScope, .group)
        XCTAssertEqual(expense.splitMethod, .equal)
        XCTAssertEqual(expense.category, .transport)
        XCTAssertTrue(
            bundle.scene(.ongoing)?.expenses.list.contains { $0.category == .food } == true
        )
    }

    func testFixtureSHA256MatchesFrozenContract() throws {
        let digest = SHA256.hex(of: fixtureData)
        XCTAssertEqual(
            digest,
            "d2dec50267e20646b4a62efdd865e50881234470d48f5b072dfc9d5bc29d41c1"
        )
    }

    // MARK: - Schema / display rules

    func testUnknownSchemaIsNotDisplayable() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        json["schemaVersion"] = 99
        let data = try JSONSerialization.data(withJSONObject: json)
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: data)

        XCTAssertFalse(DemoJourneySchema.isSupported(bundle.schemaVersion))
        XCTAssertFalse(bundle.isDisplayable)
    }

    func testDisabledBundleIsNotDisplayable() throws {
        let json = """
        {
          "schemaVersion": 1,
          "contentVersion": "2026.07.31.4",
          "referenceDate": "2026-07-30",
          "enabled": false,
          "defaultScene": "ONGOING",
          "capabilities": {
            "readOnly": true,
            "canEditTrip": false,
            "canAddNode": false,
            "canEditJournal": false,
            "canManageExpense": false,
            "canManageMembers": false,
            "canInvite": false,
            "canDelete": false,
            "canShare": false,
            "canExport": false,
            "canApplyAiChanges": false
          }
        }
        """.data(using: .utf8)!

        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: json)
        XCTAssertFalse(bundle.enabled)
        XCTAssertNil(bundle.scenes)
        XCTAssertFalse(bundle.isDisplayable)
    }

    func testMissingFieldFailsDecodingSafely() {
        let json = """
        { "schemaVersion": 1, "enabled": true }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(DemoJourneyBundle.self, from: json))
    }

    // MARK: - Cache

    func testCacheStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo-journey-cache-\(UUID().uuidString)", isDirectory: true)
        let store = DemoJourneyCacheStore(directoryURL: directory)
        defer { store.clear() }

        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        // Cache stores full ApiResponse body.
        let responseBody = try makeAPIResponseBody(from: fixtureData)
        try store.save(responseBody: responseBody, etag: "W/\"demo-test\"", bundle: bundle)

        let cached = try XCTUnwrap(store.load())
        XCTAssertEqual(cached.etag, "W/\"demo-test\"")
        XCTAssertEqual(cached.contentVersion, "2026.07.31.4")

        let service = DemoJourneyService(apiClient: APIClient())
        let restored = try service.decodeBundle(from: cached.responseBody)
        XCTAssertEqual(restored.contentVersion, bundle.contentVersion)
        XCTAssertTrue(restored.isDisplayable)

        // Clearing twice must remain safe (no throw on missing dir).
        store.clear()
        store.clear()
        XCTAssertNil(store.load())
    }

    func testMutationGuardBlocksDemo() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let demo = JourneyContext.demo(bundle: bundle, scene: .ongoing)
        let live = JourneyContext.live(tripID: "trip-1")

        XCTAssertFalse(DemoMutationGuard.allowsMutation(demo))
        XCTAssertTrue(DemoMutationGuard.allowsMutation(live))
        XCTAssertFalse(DemoMutationGuard.allows(.share, in: demo))
        XCTAssertFalse(DemoMutationGuard.allows(.export, in: demo))
        XCTAssertTrue(DemoMutationGuard.allows(.share, in: live))
    }

    @MainActor
    func testChildViewModelsRejectDemoMutationsAndNetwork() async throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let scene = try XCTUnwrap(bundle.scene(.ongoing))
        let client = APIClient(config: .development, tokenProvider: nil)

        let itineraryVM = ItineraryViewModel(
            tripId: scene.trip.id,
            trip: scene.trip,
            itineraryService: ItineraryService(apiClient: client),
            routeProvider: RouteCacheService()
        )
        itineraryVM.applyDemoPayload(scene.itinerary, preferredDayIndex: 2)
        XCTAssertEqual(itineraryVM.selectedDayIndex, 2)
        let created = await itineraryVM.createNode(form: .create(defaultDayIndex: 1))
        XCTAssertNil(created)
        XCTAssertEqual(itineraryVM.errorMessage, DemoReadOnlyCopy.toast)

        let journalVM = JournalViewModel(
            tripId: scene.trip.id,
            tripStartDate: scene.trip.startDate,
            tripEndDate: scene.trip.endDate,
            journalService: JournalService(
                apiClient: client,
                fileUploadService: FileUploadService(apiClient: client)
            )
        )
        journalVM.applyDemoEntries(scene.journals.list)
        XCTAssertEqual(journalVM.entries.count, scene.journals.list.count)
        let journalOk = await journalVM.createEntry(form: JournalFormState.empty(defaultOccurredDate: Date()))
        XCTAssertFalse(journalOk)
        XCTAssertEqual(journalVM.errorMessage, DemoReadOnlyCopy.toast)

        let expenseVM = ExpenseViewModel(
            tripId: scene.trip.id,
            tripStartDate: scene.trip.startDate,
            tripEndDate: scene.trip.endDate,
            baseCurrency: "CNY",
            expenseService: ExpenseService(apiClient: client)
        )
        expenseVM.applyDemo(expenses: scene.expenses.list, summary: scene.expenseSummary)
        XCTAssertEqual(expenseVM.expenses.count, scene.expenses.list.count)
        let expenseOk = await expenseVM.createExpense(
            CreateExpenseRequest(
                amountInput: "1.00",
                currency: "CNY",
                category: "food",
                note: nil,
                spentAt: "2026-07-29T10:00:00Z",
                expenseScope: nil,
                payerMemberId: nil,
                participantMemberIds: nil,
                splitMethod: nil
            )
        )
        XCTAssertFalse(expenseOk)
        XCTAssertEqual(expenseVM.submitError, DemoReadOnlyCopy.toast)

        let settlementVM = SettlementViewModel(
            tripId: scene.trip.id,
            expenseService: ExpenseService(apiClient: client)
        )
        settlementVM.applyDemoSettlement(scene.expenseSettlement)
        XCTAssertEqual(settlementVM.settlement?.tripId, scene.expenseSettlement.tripId)
        await settlementVM.loadSettlement() // no-op in demo; must not clear data
        XCTAssertEqual(settlementVM.settlement?.tripId, scene.expenseSettlement.tripId)

        let activityVM = ActivityLogViewModel(
            tripId: scene.trip.id,
            collaborationService: CollaborationService(apiClient: client)
        )
        activityVM.applyDemoLogs(scene.activityLogs.list)
        XCTAssertFalse(activityVM.logs.isEmpty)
        await activityVM.loadLogs()
        XCTAssertFalse(activityVM.logs.isEmpty)

        let completed = try XCTUnwrap(bundle.scene(.completed))
        let storyVM = MemoryStoryViewModel(
            tripId: completed.trip.id,
            tripTitle: completed.trip.title,
            exportService: ExportService(apiClient: client)
        )
        await storyVM.applyDemoSummary(completed.summary)
        XCTAssertTrue(storyVM.isDemo)
        XCTAssertNotNil(storyVM.summary)
        let saveOk = await storyVM.saveReportImage()
        XCTAssertFalse(saveOk)
        XCTAssertEqual(storyVM.errorMessage, DemoReadOnlyCopy.exportUnavailable)
    }

    // MARK: - LoadResult

    func testLoadResultFeatureOffBundle() throws {
        let json = """
        {
          "schemaVersion": 1,
          "contentVersion": "2026.07.31.4",
          "referenceDate": "2026-07-30",
          "enabled": false,
          "defaultScene": "ONGOING",
          "capabilities": {
            "readOnly": true,
            "canEditTrip": false,
            "canAddNode": false,
            "canEditJournal": false,
            "canManageExpense": false,
            "canManageMembers": false,
            "canInvite": false,
            "canDelete": false,
            "canShare": false,
            "canExport": false,
            "canApplyAiChanges": false
          }
        }
        """.data(using: .utf8)!

        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: json)
        let result = DemoJourneyService.validateResult(for: bundle)
        if case .featureOff = result {
            // expected
        } else {
            XCTFail("Expected .featureOff, got \(result)")
        }
        XCTAssertFalse(result.isDisplayable)
        XCTAssertNil(result.bundle)
    }

    func testLoadResultUnsupportedSchema() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        json["schemaVersion"] = 99
        json["enabled"] = true
        let data = try JSONSerialization.data(withJSONObject: json)
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: data)

        let result = DemoJourneyService.validateResult(for: bundle)
        if case .undisplayable(let reason) = result {
            XCTAssertTrue(reason.contains("schema version"))
        } else {
            XCTFail("Expected undisplayable, got \(result)")
        }
        XCTAssertFalse(result.isDisplayable)
        XCTAssertNil(result.bundle)
    }

    func testLoadResultMissingScenes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "contentVersion": "2026.07.31.4",
          "referenceDate": "2026-07-30",
          "enabled": true,
          "defaultScene": "ONGOING",
          "capabilities": {
            "readOnly": true,
            "canEditTrip": false,
            "canAddNode": false,
            "canEditJournal": false,
            "canManageExpense": false,
            "canManageMembers": false,
            "canInvite": false,
            "canDelete": false,
            "canShare": false,
            "canExport": false,
            "canApplyAiChanges": false
          }
        }
        """.data(using: .utf8)!

        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: json)
        let result = DemoJourneyService.validateResult(for: bundle)
        if case .undisplayable(let reason) = result {
            XCTAssertTrue(reason.contains("scenes"))
        } else {
            XCTFail("Expected undisplayable, got \(result)")
        }
    }

    func testLoadResultDisplayable() throws {
        let bundle = try JSONDecoder().decode(DemoJourneyBundle.self, from: fixtureData)
        let result = DemoJourneyService.validateResult(for: bundle)
        XCTAssertTrue(result.isDisplayable)
        XCTAssertNotNil(result.bundle)
        if case .displayable(let b) = result {
            XCTAssertEqual(b.schemaVersion, 1)
            XCTAssertTrue(b.scenes != nil)
        }
    }

    // MARK: - Helpers

    private static func loadFixtureData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/demo-journey-v1.json")
        return try Data(contentsOf: url)
    }

    private func makeAPIResponseBody(from unwrapped: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: unwrapped)
        let envelope: [String: Any] = [
            "code": 0,
            "message": "ok",
            "data": object
        ]
        return try JSONSerialization.data(withJSONObject: envelope)
    }
}

private enum SHA256 {
    static func hex(of data: Data) -> String {
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
