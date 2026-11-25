import XCTest
@testable import Tracci
import TracciNetworking
import TracciTestSupport

/// Characterizes Trip Detail form routing and collaboration state ownership
/// introduced in stages D/E — without rendering the full View tree.
@MainActor
final class TripDetailRouteStateTests: XCTestCase {
    func testFormRouterOwnsIndependentPresentationModes() {
        let router = TripDetailFormRouter()

        router.nodeFormMode = .create(defaultDayIndex: 2)
        router.expenseFormMode = .create(defaultDate: nil, itineraryLink: nil)
        router.journalFormMode = .create(defaultDate: nil)
        router.journalInitialSection = .photos

        XCTAssertNotNil(router.nodeFormMode)
        XCTAssertNotNil(router.expenseFormMode)
        XCTAssertNotNil(router.journalFormMode)
        XCTAssertEqual(router.journalInitialSection, .photos)

        router.nodeFormMode = nil
        XCTAssertNil(router.nodeFormMode)
        XCTAssertNotNil(router.expenseFormMode)
        XCTAssertNotNil(router.journalFormMode)
    }

    func testFormRouterCanSwitchJournalSectionIndependentlyOfMode() {
        let router = TripDetailFormRouter()
        router.journalFormMode = .create(defaultDate: nil)
        router.journalInitialSection = .content

        router.journalInitialSection = .photos
        XCTAssertEqual(router.journalInitialSection, .photos)
        XCTAssertNotNil(router.journalFormMode)

        router.journalFormMode = nil
        XCTAssertNil(router.journalFormMode)
        // Section value is independent state and is not auto-reset by dismissing the mode.
        XCTAssertEqual(router.journalInitialSection, .photos)
    }

    func testLiveInvitationUsesCollaborationServicePath() async throws {
        let stub = HTTPStub()
        stub.install()
        defer {
            stub.removeAllResponses()
            stub.resetRequestLog()
            stub.uninstall()
        }

        let client = stub.makeAPIClient()
        let trip = Trip(
            id: "trip-live",
            title: "Live",
            startDate: "2026-08-01",
            endDate: "2026-08-03",
            status: .planning,
            access: TripAccessContext(role: .owner, permissions: [.createInvitation])
        )

        let viewModel = TripDetailViewModel(
            trip: trip,
            tripService: TripService(apiClient: client, fileUploadService: FileUploadService(apiClient: client)),
            itineraryService: ItineraryService(apiClient: client),
            journalService: JournalService(apiClient: client, fileUploadService: FileUploadService(apiClient: client)),
            expenseService: ExpenseService(apiClient: client),
            collaborationService: CollaborationService(apiClient: client),
            routeProvider: TripRouteProviderStub()
        )

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-live/invitations",
            method: "POST",
            dataJSON: #"{"id":"inv-1","tripId":"trip-live","inviteCode":"ABCD12","roleToGrant":"editor","expiresAt":"2026-08-10T00:00:00Z","maxUses":null,"usedCount":0,"webInviteUrl":"https://tracci.cn/join/ABCD12","miniProgramPath":null,"appDeepLink":null,"shareText":null}"#
        )

        let invitation = await viewModel.createInvitationForSharing()
        XCTAssertEqual(invitation?.id, "inv-1")
        XCTAssertNil(viewModel.invitationErrorMessage)

        let request = try XCTUnwrap(stub.recordedRequests().first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/trips/trip-live/invitations")
        let body = try XCTUnwrap(stub.firstRequestBodyUTF8())
        XCTAssertTrue(body.contains("\"roleToGrant\":\"editor\""))
        XCTAssertTrue(body.contains("\"expiresInHours\":72"))
    }

    func testInvitationFailureCapturesRetryMessage() async {
        let stub = HTTPStub()
        stub.install()
        defer {
            stub.removeAllResponses()
            stub.resetRequestLog()
            stub.uninstall()
        }

        let client = stub.makeAPIClient()
        let trip = Trip(
            id: "trip-live",
            title: "Live",
            startDate: "2026-08-01",
            endDate: "2026-08-03",
            status: .planning
        )
        let viewModel = TripDetailViewModel(
            trip: trip,
            tripService: TripService(apiClient: client, fileUploadService: FileUploadService(apiClient: client)),
            itineraryService: ItineraryService(apiClient: client),
            journalService: JournalService(apiClient: client, fileUploadService: FileUploadService(apiClient: client)),
            expenseService: ExpenseService(apiClient: client),
            collaborationService: CollaborationService(apiClient: client),
            routeProvider: TripRouteProviderStub()
        )

        stub.stubAPIBusinessError(
            path: "/api/v1/trips/trip-live/invitations",
            method: "POST",
            code: 500,
            message: "fail"
        )

        let invitation = await viewModel.createInvitationForSharing()
        XCTAssertNil(invitation)
        XCTAssertEqual(viewModel.invitationErrorMessage, "邀请生成失败，请重试")
    }

    func testLoadMembersMapsCollaborationPath() async throws {
        let stub = HTTPStub()
        stub.install()
        defer {
            stub.removeAllResponses()
            stub.resetRequestLog()
            stub.uninstall()
        }

        let client = stub.makeAPIClient()
        let trip = Trip(
            id: "trip-live",
            title: "Live",
            startDate: "2026-08-01",
            endDate: "2026-08-03",
            status: .planning
        )
        let viewModel = TripDetailViewModel(
            trip: trip,
            tripService: TripService(apiClient: client, fileUploadService: FileUploadService(apiClient: client)),
            itineraryService: ItineraryService(apiClient: client),
            journalService: JournalService(apiClient: client, fileUploadService: FileUploadService(apiClient: client)),
            expenseService: ExpenseService(apiClient: client),
            collaborationService: CollaborationService(apiClient: client),
            routeProvider: TripRouteProviderStub()
        )

        stub.stubAPISuccess(
            path: "/api/v1/trips/trip-live/members",
            dataJSON: #"[{"id":"m1","tripId":"trip-live","userId":"u1","nickname":"旅人","role":"owner","status":"ACTIVE"}]"#
        )

        await viewModel.loadMembers()
        XCTAssertEqual(viewModel.members.count, 1)
        XCTAssertEqual(viewModel.members.first?.nickname, "旅人")
        XCTAssertEqual(stub.recordedRequests().first?.url?.path, "/api/v1/trips/trip-live/members")
    }
}
