import Foundation
import XCTest

final class DependencyInjectionArchitectureTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRootViewsDoNotExpandConcreteServiceParameters() throws {
        let app = try source(at: "App/TracciApp.swift")
        let root = try source(at: "App/AppRootView.swift")
        let main = try source(at: "App/MainTabView.swift")

        let concreteDependencyDeclaration = #"\b(?:private\s+)?let\s+\w+(?:Service|Client)\s*:"#
        XCTAssertEqual(matchCount(in: app, pattern: concreteDependencyDeclaration), 0)
        XCTAssertTrue(app.contains("private let dependencies: AppDependencies"))

        XCTAssertEqual(matchCount(in: root, pattern: concreteDependencyDeclaration), 0)
        XCTAssertTrue(root.contains("let dependencies: AppDependencies"))

        XCTAssertFalse(main.contains("init(\n        authService:"))
        XCTAssertTrue(main.contains("init(dependencies: MainSceneDependencies)"))
    }

    func testServicesDoNotConstructTheirOwnExternalDependencies() throws {
        let tripService = try source(at: "Features/Trip/TripService.swift")
        let journalService = try source(at: "Features/Journal/JournalService.swift")

        for source in [tripService, journalService] {
            XCTAssertFalse(source.contains("FileUploadService(apiClient:"))
            XCTAssertFalse(source.contains("LocationService("))
        }

        // Stage G: FileUpload implementation lives in TracciNetworking, not App Core.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent("Core/Network/FileUploadService.swift").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent("Packages/TracciNetworking/Sources/TracciNetworking/FileUploadService.swift")
                    .path
            )
        )
    }

    func testMainTabRoutingStateStaysInPureCoordinator() throws {
        let main = try source(at: "App/MainTabView.swift")
        let coordinator = try source(at: "App/Navigation/MainTabCoordinator.swift")
        let routedStateNames = [
            "selectedTab",
            "showingCreateTrip",
            "showingJoinTrip",
            "showingCreateOptions",
            "homeNavigationPath",
            "exploreNavigationPath",
            "profileNavigationPath",
            "tripDetailNavigationRequest",
            "memoryNavigationRequest",
        ]

        for name in routedStateNames {
            XCTAssertFalse(main.contains("@State private var \(name)"))
            XCTAssertTrue(coordinator.contains("var \(name)"))
        }

        XCTAssertTrue(main.contains("@State private var coordinator: MainTabCoordinator"))
        XCTAssertFalse(coordinator.contains("Service"))
        XCTAssertFalse(coordinator.contains("try await"))
    }

    func testMainSceneDataFlowStaysInSceneViewModelAndFactory() throws {
        let main = try source(at: "App/MainTabView.swift")
        let sceneViewModel = try source(at: "App/Scene/MainSceneViewModel.swift")
        let sceneFactory = try source(at: "App/Composition/MainSceneFactory.swift")
        let migratedStateNames = [
            "tripDataRevision",
            "lastDeletedTripId",
            "homeViewModel",
            "memoryPageViewModel",
        ]

        for name in migratedStateNames {
            XCTAssertFalse(main.contains("@State private var \(name)"))
            XCTAssertTrue(sceneViewModel.contains(name))
        }

        XCTAssertTrue(main.contains("@State private var sceneViewModel: MainSceneViewModel"))
        XCTAssertTrue(main.contains("MainSceneFactory(dependencies: dependencies).make()"))
        XCTAssertFalse(main.contains("try await tripService."))
        XCTAssertTrue(sceneFactory.contains("HomeViewModel("))
        XCTAssertTrue(sceneFactory.contains("MemoryPageViewModel("))
        XCTAssertTrue(sceneFactory.contains("ProfileViewModel("))
    }

    /// Phase 0 冻结基线（2026-08-09）：View 层业务 Service 调用集合 = []（零调用）。
    /// 后续拆分阶段不得放宽——任何 View.swift 出现直接 Service 调用都须显式注册并说明。
    func testViewBusinessServiceCallsMatchRegisteredBaseline() throws {
        let pattern = #"(?:try\s+)?await\s+((?:[a-z][A-Za-z0-9_]*Service)|(?:RouteCacheService\.shared))\s*\."#
        let actual = try matches(
            inDirectories: ["App", "Features"],
            fileFilter: { $0.lastPathComponent.hasSuffix("View.swift") },
            pattern: pattern,
            captureGroup: 1
        )

        let expected: [String] = []

        XCTAssertEqual(actual, expected, "Register or remove View-side business calls explicitly")
    }

    /// Phase 2.1: Create Trip has one modal host. Destination/date transitions stay
    /// inside its NavigationStack, and MapKit lifecycle state belongs to a model.
    /// Presented as a full-screen cover for brand immersion (Creek Editorial Immersion).
    func testTripCreatePresentationKeepsSingleHostAndModelOwnedSearch() throws {
        let presentation = try source(at: "App/CreateFlow/MainScenePresentationModifier.swift")
        let create = try source(at: "Features/Trip/TripCreateView.swift")
        let destination = try source(at: "Features/Trip/TripCreateDestinationView.swift")
        let itineraryCreate = try source(at: "Features/Itinerary/ItineraryNodeCreateSheet.swift")

        XCTAssertEqual(matchCount(in: presentation, pattern: #"\.fullScreenCover\s*\("#), 1)
        XCTAssertTrue(presentation.contains("case .createTrip:"))
        XCTAssertTrue(presentation.contains("TripCreateView("))
        XCTAssertFalse(presentation.contains(".fullScreenCover(isPresented:"))

        XCTAssertEqual(matchCount(in: create, pattern: #"\bNavigationStack\s*\("#), 1)
        XCTAssertFalse(create.contains(".sheet("))
        XCTAssertFalse(create.contains(".fullScreenCover("))
        XCTAssertFalse(create.contains(".tracciBottomSheet("))
        XCTAssertTrue(create.contains("case destinationPicker"))
        XCTAssertTrue(create.contains("case datePicker"))
        XCTAssertTrue(create.contains("onCancel: cancelDestinationEdit"))

        XCTAssertEqual(matchCount(in: destination, pattern: #"\bNavigationStack\s*\("#), 0)
        XCTAssertFalse(destination.contains(".sheet("))
        XCTAssertFalse(destination.contains(".fullScreenCover("))
        XCTAssertTrue(destination.contains("final class TripCreateDestinationSearchModel"))

        let viewSource = try XCTUnwrap(
            destination.components(separatedBy: "struct TripCreateDestinationSearchView: View").last
        )
        XCTAssertFalse(viewSource.contains("TracciPlaceSearchEngine.search"))
        XCTAssertFalse(viewSource.contains("Task.sleep(for: .milliseconds(360))"))

        // Product boundary: Saved Places are a source for Add Itinerary Node only.
        // Create Trip must remain MapKit/manual and must not regain hidden Saved Place wiring.
        XCTAssertFalse(create.contains("savedPlaceService"))
        XCTAssertFalse(create.contains("savedPlaceId"))
        XCTAssertFalse(destination.contains("SavedPlacePicker"))
        XCTAssertFalse(destination.contains("savedPlace"))
        XCTAssertFalse(destination.contains("想去的地点"))
        XCTAssertTrue(itineraryCreate.contains("loadMatchingSavedPlaces"))
    }

    /// Phase 3 interaction simplification: simple title and cover edits stay on the
    /// Settings page; destination search is the only local sheet and commits on selection.
    func testTripEditPresentationAvoidsRedundantEditorLayers() throws {
        let edit = try source(at: "Features/Trip/TripEditView.swift")
        let destination = try source(at: "Features/Trip/TripDestinationSelectionSheet.swift")

        XCTAssertTrue(edit.contains("private var inlineTitleEditor"))
        XCTAssertTrue(edit.contains("PhotosPicker(selection: $selectedCoverItem"))
        XCTAssertFalse(edit.contains("TripNameEditorSheet"))
        XCTAssertFalse(edit.contains("TripCoverEditorView"))
        XCTAssertEqual(matchCount(in: edit, pattern: #"\.sheet\s*\("#), 1)

        XCTAssertTrue(destination.contains("showsSaveButton: false"))
        XCTAssertTrue(destination.contains("onSelect(destination, nil)"))
        XCTAssertFalse(destination.contains("showDiscardConfirmation"))
    }

    /// Phase 4: Add Itinerary uses one Trip Detail sheet host. Its root is place-first;
    /// simple fields stay inline, and only transport/hotel details are pushed internally.
    func testItineraryCreatePresentationKeepsSingleTaskHost() throws {
        let detail = try source(at: "Features/Trip/TripDetailView.swift")
        let create = try source(at: "Features/Itinerary/ItineraryNodeCreateSheet.swift")
        let place = try source(at: "Features/Itinerary/ItineraryNodePlaceSearchView.swift")
        let details = try source(at: "Features/Itinerary/ItineraryNodeOptionalDetailsView.swift")

        XCTAssertTrue(detail.contains("case let .create(defaultDayIndex)"))
        XCTAssertTrue(detail.contains("ItineraryNodeCreateSheet("))
        XCTAssertTrue(detail.contains("case .edit, .editNote:"))
        XCTAssertTrue(detail.contains("ItineraryNodeEditView("))
        XCTAssertFalse(detail.contains("ItineraryNodeFormView("))

        XCTAssertEqual(matchCount(in: create, pattern: #"\bNavigationStack\s*\("#), 1)
        XCTAssertFalse(create.contains(".sheet("))
        XCTAssertFalse(create.contains(".fullScreenCover("))
        XCTAssertTrue(create.contains("TracciTimePickerSheet"))
        XCTAssertTrue(create.contains("case timePicker(ItineraryNodeTimeField)"))
        XCTAssertTrue(create.contains("presentation: .pushed"))
        XCTAssertFalse(create.contains("TextField(\"HH:mm\""))
        XCTAssertFalse(create.contains("private func inlineTimeField"))
        XCTAssertFalse(create.contains("showingDayPicker"))
        XCTAssertTrue(create.contains("ItineraryNodePlaceSearchView("))
        XCTAssertTrue(create.contains("case transportDetails"))
        XCTAssertTrue(create.contains("case hotelDetails"))
        XCTAssertTrue(create.contains("model.resetLocation()"))
        XCTAssertTrue(create.contains("viewModel.loadMatchingSavedPlaces()"))

        XCTAssertFalse(place.contains(".sheet("))
        XCTAssertFalse(place.contains("NavigationStack("))
        XCTAssertTrue(place.contains("onOpenSavedPlaces"))
        XCTAssertTrue(place.contains("onSearchSavedPlaces"))
        XCTAssertFalse(place.contains("SavedPlacePickerView"))
        // Saved places collapse into one entry row that pushes the shared picker page.
        XCTAssertTrue(place.contains("从想去的地点选择"))
        XCTAssertTrue(create.contains("case savedPlacePicker"))

        XCTAssertFalse(details.contains(".sheet("))
        XCTAssertFalse(details.contains("TracciTimePickerSheet"))
        XCTAssertTrue(details.contains("onSelectTime"))
        XCTAssertFalse(details.contains("TextField(\"HH:mm\""))
        XCTAssertFalse(details.contains("private func inlineTimeField"))
        XCTAssertFalse(details.contains(".tracciChoiceSheet("))
        XCTAssertTrue(details.contains("showsSaveButton: false"))

        // Interaction simplification must not remove existing create capabilities.
        for field in [
            "flightNo", "airline", "trainNo", "busNo",
            "departureName", "arrivalName", "seatInfo", "confirmationCode",
        ] {
            XCTAssertTrue(details.contains("$form.\(field)"), "Missing advanced field: \(field)")
        }
        XCTAssertTrue(details.contains("form.hotelCheckOutDate"))
        XCTAssertTrue(details.contains(".hotelCheckIn"))
        XCTAssertTrue(details.contains(".hotelCheckOut"))
        XCTAssertTrue(create.contains("TracciFocusableFormField("))
        XCTAssertTrue(create.contains("TracciFormTextArea("))
        XCTAssertTrue(place.contains("onOpenSavedPlaces"))
        XCTAssertTrue(place.contains("onUseManual"))
        XCTAssertTrue(place.contains("没有匹配的想去地点，仍可直接搜索或手动填写"))
    }

    /// Phase 5: Edit Itinerary is a Settings page. It starts from current values,
    /// submits each field independently, and only searches place when the user asks.
    func testItineraryEditPresentationUsesSettingsWithoutAddFlow() throws {
        let edit = try source(at: "Features/Itinerary/ItineraryNodeEditView.swift")
        let details = try source(at: "Features/Itinerary/ItineraryNodeOptionalDetailsView.swift")

        XCTAssertEqual(matchCount(in: edit, pattern: #"\bNavigationStack\s*\("#), 1)
        XCTAssertFalse(edit.contains(".sheet("))
        XCTAssertFalse(edit.contains(".fullScreenCover("))
        XCTAssertFalse(edit.contains("TextField(\"HH:mm\""))
        XCTAssertFalse(edit.contains("private func inlineTimeField"))
        XCTAssertTrue(edit.contains("TracciTimePickerSheet"))
        XCTAssertTrue(edit.contains("presentation: .pushed"))
        XCTAssertTrue(edit.contains("ItineraryNodePlaceSearchView("))
        XCTAssertTrue(edit.contains("case placeSearch"))
        XCTAssertTrue(edit.contains("case transportDetails"))
        XCTAssertTrue(edit.contains("case hotelDetails"))
        XCTAssertTrue(edit.contains("showsSaveButton: false"))
        XCTAssertTrue(edit.contains("if model.isNoteOnly"))
        XCTAssertTrue(edit.contains("旅程已结束，行程内容已锁定，只能改备注。"))
        XCTAssertTrue(edit.contains("daySection"))
        XCTAssertTrue(edit.contains("placeSection"))
        XCTAssertTrue(edit.contains("detailsEntry"))
        XCTAssertFalse(edit.contains("记账"))
        XCTAssertFalse(edit.contains("复制节点"))
        XCTAssertFalse(edit.contains("轨迹"))
        XCTAssertTrue(details.contains("onSelectTime"))
    }

    /// Node cards use the whole card as the place-detail entry. The timeline dot
    /// remains the explicit map-link control, so simplifying the card does not
    /// remove map linkage or the independent edit/delete action menu.
    func testItineraryNodeCardUsesWholeCardForPlaceDetail() throws {
        let card = try source(at: "Features/Itinerary/ItineraryNodeCard.swift")
        let feed = try source(at: "Features/Trip/TripUnifiedCreekFeed.swift")

        XCTAssertTrue(card.contains("if let onOpenPlaceDetail"))
        XCTAssertTrue(card.contains("onOpenPlaceDetail()"))
        XCTAssertTrue(card.contains("accessibilityHint(\"轻点查看地点详情\")"))
        XCTAssertFalse(card.contains("Text(\"查看地点详情\")"))
        XCTAssertFalse(card.contains("var onSelect: (() -> Void)?"))

        XCTAssertTrue(feed.contains("timelineDot("))
        XCTAssertTrue(feed.contains("linkToNode(id: node.id, scroll: false)"))
        XCTAssertTrue(feed.contains("onOpenPlaceDetail: node.location?.placeId == nil ? nil"))
        XCTAssertTrue(card.contains("TracciActionMenuButton(actions: nodeActions)"))
    }

    func testCustomSharedDependenciesMatchRegisteredBaseline() throws {
        let allSharedUses = try matches(
            inDirectories: ["App", "Core", "Features"],
            fileFilter: { $0.pathExtension == "swift" },
            pattern: #"\b([A-Z][A-Za-z0-9_]+)\.shared\b"#,
            captureGroup: 1
        )
        let systemTypes = ["PHPhotoLibrary", "UIApplication", "URLSession"]
        let actual = allSharedUses.filter { match in
            !systemTypes.contains { match.hasSuffix("|\($0)") }
        }

        let expected = [
            "App/AppDelegate.swift|PhoneAuthManager",
            "Features/Trip/TripDetailViewModel.swift|WeatherService",
        ].sorted()

        XCTAssertEqual(actual, expected, "New custom shared dependencies require explicit review")
    }

    func testTripDetailUsesCallbacksAndInjectedCapabilitiesInsteadOfRootViewModel() throws {
        let detail = try source(at: "Features/Trip/TripDetailView.swift")
        let factory = try source(at: "Features/Trip/TripDetailSceneFactory.swift")
        let map = try source(at: "Features/Trip/Components/TripHeroMapView.swift")
        let routeLoader = try source(at: "Features/Trip/Components/TripHeroRouteLoader.swift")
        let auth = try source(at: "Features/Auth/AuthLandingView.swift")

        XCTAssertFalse(detail.contains("HomeViewModel"))
        XCTAssertTrue(detail.contains("let onTripUpdated: (Trip) -> Void"))
        XCTAssertTrue(detail.contains("let sceneFactory: TripDetailSceneFactory"))
        XCTAssertFalse(detail.contains("Service"))
        XCTAssertTrue(factory.contains("func makeViewModel("))
        XCTAssertFalse(map.contains("RouteCacheService.shared"))
        XCTAssertFalse(map.contains("routeProvider.route("))
        XCTAssertTrue(map.contains("let routeLoader: TripHeroRouteLoader"))
        XCTAssertTrue(routeLoader.contains("routeProvider.route("))
        XCTAssertFalse(auth.contains("PhoneAuthManager"))
    }

    /// Phase 0 冻结基线（2026-08-09）：Stage E 文件行数上限快照。
    /// 实测：TripModels.swift=485（上限 700）、ItineraryModels.swift=611（上限 700）。
    /// 后续拆分阶段不得放宽这些上限。
    func testStageEFileBoundariesStaySplit() throws {
        // Hard ceilings from Stage E splits (must not re-merge).
        let limits = [
            "App/MainTabView.swift": 350,
            "Features/SavedPlaces/SavedPlacesView.swift": 800,
            "Features/Trip/TripUnifiedCreekFeed.swift": 1_500,
            "Features/Trip/TripModels.swift": 700,
            "Features/Itinerary/ItineraryModels.swift": 700,
            "Features/Export/ExportModels.swift": 700,
        ]

        for (path, maximum) in limits {
            let lineCount = try source(at: path).split(separator: "\n", omittingEmptySubsequences: false).count
            XCTAssertLessThanOrEqual(lineCount, maximum, "\(path) exceeded its Stage E boundary")
        }

        // Growth monitors for still-large owners: ~current size + modest headroom.
        // Failing means "stop and split by ownership" — not silent re-accumulation.
        let growthMonitors = [
            "Features/Trip/TripDetailView.swift": 2_400,
            "Features/Memory/MemoryStoryExperienceViews.swift": 2_300,
            "Features/Home/HomeView.swift": 1_600,
            "Core/Auth/PhoneAuthManager.swift": 1_450,
            "Features/Trip/Components/TripHeroMapView.swift": 1_300,
        ]

        for (path, maximum) in growthMonitors {
            let lineCount = try source(at: path).split(separator: "\n", omittingEmptySubsequences: false).count
            XCTAssertLessThanOrEqual(
                lineCount,
                maximum,
                "\(path) is \(lineCount) lines (max \(maximum)). Split by ownership before adding more."
            )
        }

        let requiredFiles = [
            "App/CreateFlow/MainScenePresentationModifier.swift",
            "App/Navigation/MainTabRouterView.swift",
            "App/Navigation/MainTabChromeView.swift",
            "Features/SavedPlaces/SavedPlaceEditorView.swift",
            "Features/SavedPlaces/PlaceDetailView.swift",
            "Features/SavedPlaces/SavedPlacePickerView.swift",
            "Features/Trip/TripDetailSceneFactory.swift",
            "Features/Trip/Components/TripCreekContentSections.swift",
            "Features/Trip/Components/TripDayMapSection.swift",
            "Features/Trip/Components/TripDetailDemoBanner.swift",
            "Features/Trip/Components/TripHeroRouteLoader.swift",
            "Features/Trip/TripWeatherModels.swift",
            "Features/Itinerary/ItineraryMutationModels.swift",
            "Features/Itinerary/ItineraryNodeCreateSheet.swift",
            "Features/Itinerary/ItineraryNodeCreateViewModel.swift",
            "Features/Itinerary/ItineraryNodeEditView.swift",
            "Features/Itinerary/ItineraryNodeEditViewModel.swift",
            "Features/Itinerary/ItineraryNodeOptionalDetailsView.swift",
            "Features/Itinerary/ItineraryNodePlaceSearchView.swift",
            "Features/Export/TripSummaryModels.swift",
            "Packages/TracciNetworking/Sources/TracciNetworking/FileUploadService.swift",
            "Features/Trip/Components/TripDetailLayout.swift",
            "Features/Stats/StatsRadarDecoration.swift",
            "Features/SavedPlaces/PlaceCategoryGlyph.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path),
                "Missing Stage E file: \(path)"
            )
        }
    }

    /// Stage F/G: TestSupport tools live in TracciTestSupport package; Feature stubs stay in TracciTests.
    /// Architecture baselines above are the local/CI gate for View Service calls and unregistered `.shared`.
    func testStageFTestSupportAndTargetedSuitesExist() throws {
        let requiredFiles = [
            "Packages/TracciTestSupport/Sources/TracciTestSupport/HTTPStub.swift",
            "Packages/TracciTestSupport/Sources/TracciTestSupport/ResultQueue.swift",
            "Packages/TracciTestSupport/Sources/TracciTestSupport/CallRecorder.swift",
            "TracciTests/TestSupport/CapabilityStubs.swift",
            "TracciTests/HTTPStubSmokeTests.swift",
            "TracciTests/TripServiceHTTPStubTests.swift",
            "TracciTests/ServiceMappingHTTPStubTests.swift",
            "TracciTests/SavedPlacePickerViewModelTests.swift",
            "TracciTests/TripCreateViewModelTests.swift",
            "TracciTests/TripDetailRouteStateTests.swift",
            "TracciTests/MainTabCoordinatorTests.swift",
            "TracciTests/StageDDependencyActionsTests.swift",
            "TracciTests/DependencyInjectionArchitectureTests.swift",
        ]

        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path),
                "Missing Stage F file: \(path)"
            )
        }

        let httpStub = try source(at: "Packages/TracciTestSupport/Sources/TracciTestSupport/HTTPStub.swift")
        XCTAssertTrue(httpStub.contains("func install()"))
        XCTAssertTrue(httpStub.contains("class StubURLProtocol"))
        XCTAssertTrue(httpStub.contains("func makeAPIClient"))

        let capabilityStubs = try source(at: "TracciTests/TestSupport/CapabilityStubs.swift")
        XCTAssertTrue(capabilityStubs.contains("SavedPlaceServicingStub"))
        XCTAssertTrue(capabilityStubs.contains("TripRouteProviderStub"))
        XCTAssertTrue(capabilityStubs.contains("PhoneAuthProviderStub"))
    }

    /// Stage G package gates: Networking/TestSupport packages exist, no cycles, App does not compile Network sources inline.
    func testStageGPackageBoundaries() throws {
        let requiredPackageFiles = [
            "Packages/TracciNetworking/Package.swift",
            "Packages/TracciNetworking/Sources/TracciNetworking/APIClient.swift",
            "Packages/TracciNetworking/Sources/TracciNetworking/FileUploadModels.swift",
            "Packages/TracciTestSupport/Package.swift",
            "Packages/TracciTestSupport/Sources/TracciTestSupport/HTTPStub.swift",
            "Core/Utils/TracciDateContext.swift",
            "Features/Trip/TripDateStatus.swift",
            "Core/Network/README.md",
        ]
        for path in requiredPackageFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path),
                "Missing Stage G file: \(path)"
            )
        }

        // DesignSystem must not reverse-depend on Trip feature path or Export helpers.
        let picker = try source(at: "Core/DesignSystem/TracciPickerSupport.swift")
        XCTAssertTrue(picker.contains("TripDateFormatting.displayString"))
        XCTAssertFalse(picker.contains("Features/Trip"))

        let brandRenderChecks = try source(at: "Core/DesignSystem/Brand/BrandRenderChecks.swift")
        // Call-site form only — comments mentioning the type name must not trip the gate.
        XCTAssertFalse(
            brandRenderChecks.contains("ExportShareHelper."),
            "DesignSystem must not call Export Feature helpers"
        )
        XCTAssertFalse(brandRenderChecks.contains("Features/Export"))
        XCTAssertTrue(brandRenderChecks.contains("ImageRenderer"))

        // Networking package depends only on Foundation (Package.swift has no extra deps).
        let networkingPackage = try source(at: "Packages/TracciNetworking/Package.swift")
        XCTAssertFalse(networkingPackage.contains(".package(url:"))
        XCTAssertTrue(networkingPackage.contains("TracciNetworking"))

        // TestSupport depends on Networking only.
        let testSupportPackage = try source(at: "Packages/TracciTestSupport/Package.swift")
        XCTAssertTrue(testSupportPackage.contains("../TracciNetworking"))
        XCTAssertFalse(testSupportPackage.contains("TracciDesignSystem"))

        // App target must not still compile deleted Core/Network sources.
        for name in [
            "APIClient.swift",
            "APIEndpoint.swift",
            "APIError.swift",
            "APIResponse.swift",
            "HTTPMethod.swift",
            "NetworkConfig.swift",
            "FileUploadService.swift",
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: repositoryRoot.appendingPathComponent("Core/Network/\(name)").path
                ),
                "Core/Network/\(name) should live in TracciNetworking package"
            )
        }

        // File upload models moved out of Journal feature.
        let journalModels = try source(at: "Features/Journal/JournalModels.swift")
        XCTAssertFalse(journalModels.contains("struct FileUploadCredentials"))
        XCTAssertFalse(journalModels.contains("struct FileConfirmResponse"))
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func matchCount(in source: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("Invalid architecture pattern: \(pattern)")
            return 0
        }
        return regex.numberOfMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    private func matches(
        inDirectories directories: [String],
        fileFilter: (URL) -> Bool,
        pattern: String,
        captureGroup: Int
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        var results: [String] = []

        for directory in directories {
            let directoryURL = repositoryRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else {
                XCTFail("Cannot enumerate \(directory)")
                continue
            }

            for case let fileURL as URL in enumerator where fileFilter(fileURL) {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let range = NSRange(content.startIndex..., in: content)
                for match in regex.matches(in: content, range: range) {
                    guard let valueRange = Range(match.range(at: captureGroup), in: content) else {
                        continue
                    }
                    let relativePath = fileURL.path
                        .replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                    results.append("\(relativePath)|\(content[valueRange])")
                }
            }
        }

        return results.sorted()
    }
}
