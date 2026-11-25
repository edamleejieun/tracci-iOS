import UIKit
import XCTest
@testable import Tracci
import TracciTestSupport

@MainActor
final class StageDDependencyActionsTests: XCTestCase {
    func testTripListDeleteFailureIsCapturedOutsideView() async {
        let actions = TripListActions(
            operations: TripListActionOperations(
                deleteTrip: { _ in throw TestFailure.expected },
                createInvitation: { _, _ in throw TestFailure.expected },
                listMembers: { _ in [] }
            )
        )

        let succeeded = await actions.deleteTrip(id: "trip-1")
        XCTAssertFalse(succeeded)
        XCTAssertEqual(actions.errorMessage, TestFailure.expected.localizedDescription)
    }

    func testTripListDeleteCanRetryAfterFailure() async {
        var attempts = 0
        let actions = TripListActions(
            operations: TripListActionOperations(
                deleteTrip: { _ in
                    attempts += 1
                    if attempts == 1 { throw TestFailure.expected }
                },
                createInvitation: { _, _ in throw TestFailure.expected },
                listMembers: { _ in [] }
            )
        )

        let firstAttempt = await actions.deleteTrip(id: "trip-1")
        let secondAttempt = await actions.deleteTrip(id: "trip-1")
        XCTAssertFalse(firstAttempt)
        XCTAssertTrue(secondAttempt)
        XCTAssertNil(actions.errorMessage)
        XCTAssertEqual(attempts, 2)
    }

    func testTripListMembersDiscardStaleCompletion() async {
        let harness = MemberLoadHarness()
        let actions = TripListActions(
            operations: TripListActionOperations(
                deleteTrip: { _ in },
                createInvitation: { _, _ in throw TestFailure.expected },
                listMembers: { tripId in await harness.load(tripId: tripId) }
            )
        )
        let firstMember = makeMember(id: "member-1", tripId: "trip-1")
        let secondMember = makeMember(id: "member-2", tripId: "trip-2")

        let firstLoad = Task { await actions.loadShareMembers(tripId: "trip-1") }
        await harness.waitUntilPending(tripId: "trip-1")
        let secondLoad = Task { await actions.loadShareMembers(tripId: "trip-2") }
        await harness.waitUntilPending(tripId: "trip-2")

        await harness.resolve(tripId: "trip-2", members: [secondMember])
        await secondLoad.value
        await harness.resolve(tripId: "trip-1", members: [firstMember])
        await firstLoad.value

        XCTAssertEqual(actions.shareMembers, [secondMember])
    }

    func testTripListShareFailureKeepsCanonicalFallback() async {
        let actions = TripListActions(
            operations: TripListActionOperations(
                deleteTrip: { _ in },
                createInvitation: { _, _ in throw TestFailure.expected },
                listMembers: { _ in [] }
            )
        )

        let link = await actions.makeShareLink(tripId: "trip-1")
        XCTAssertEqual(link, "https://tracci.cn/join-trip")
    }

    func testTripDetailFormRouterOwnsIndependentRoutes() {
        let router = TripDetailFormRouter()

        router.nodeFormMode = .create(defaultDayIndex: 2)
        router.expenseFormMode = .create(defaultDate: nil, itineraryLink: nil)
        router.journalFormMode = .create(defaultDate: nil)
        router.journalInitialSection = .photos

        XCTAssertNotNil(router.nodeFormMode)
        XCTAssertNotNil(router.expenseFormMode)
        XCTAssertNotNil(router.journalFormMode)
        XCTAssertEqual(router.journalInitialSection, .photos)
    }

    func testUnavailablePhoneProviderStopsBeforeSDKPresentation() async {
        let provider = PhoneAuthProviderStub()
        provider.isConfigured = false
        let viewModel = AuthViewModel(phoneAuthProvider: provider)
        let session = AuthSession(tokenStore: KeychainTokenStore())

        let event = await viewModel.phoneOneTapLogin(
            authSession: session,
            presenting: UIViewController()
        )

        XCTAssertEqual(event, .showToast("号码认证服务暂不可用，请使用邮箱登录"))
        XCTAssertEqual(
            viewModel.phoneLoginPhase,
            .providerError("号码认证服务暂不可用，请使用邮箱登录。")
        )
        XCTAssertEqual(provider.requestCount, 0)
    }

    private func makeMember(id: String, tripId: String) -> TripMemberResp {
        TripMemberResp(
            id: id,
            tripId: tripId,
            userId: "user-\(id)",
            nickname: id,
            role: .editor,
            status: "ACTIVE",
            joinedAt: nil
        )
    }
}

private actor MemberLoadHarness {
    private var continuations: [String: CheckedContinuation<[TripMemberResp], Never>] = [:]

    func load(tripId: String) async -> [TripMemberResp] {
        await withCheckedContinuation { continuation in
            continuations[tripId] = continuation
        }
    }

    func waitUntilPending(tripId: String) async {
        while continuations[tripId] == nil {
            await Task.yield()
        }
    }

    func resolve(tripId: String, members: [TripMemberResp]) {
        continuations.removeValue(forKey: tripId)?.resume(returning: members)
    }
}

private enum TestFailure: LocalizedError {
    case expected

    var errorDescription: String? { "expected failure" }
}

// PhoneAuthProviderStub lives in TestSupport/CapabilityStubs.swift (Stage F).
