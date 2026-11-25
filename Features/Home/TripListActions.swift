import Foundation
import Observation

struct TripListActionOperations {
    let deleteTrip: (String) async throws -> Void
    let createInvitation: (String, CreateInvitationRequest) async throws -> TripInvitationResp
    let listMembers: (String) async throws -> [TripMemberResp]
}

/// Shared Home/All Trips business actions. Views keep only presentation state
/// and forward successful mutations to their owning scene via callbacks.
@MainActor
@Observable
final class TripListActions {
    private(set) var shareMembers: [TripMemberResp] = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let operations: TripListActionOperations
    @ObservationIgnored private var memberLoadGeneration = 0

    init(operations: TripListActionOperations) {
        self.operations = operations
    }

    convenience init(
        tripService: TripService,
        collaborationService: CollaborationService
    ) {
        self.init(
            operations: TripListActionOperations(
                deleteTrip: { tripId in
                    try await tripService.deleteTrip(id: tripId)
                },
                createInvitation: { tripId, request in
                    try await collaborationService.createInvitation(
                        tripId: tripId,
                        request: request
                    )
                },
                listMembers: { tripId in
                    try await collaborationService.listMembers(tripId: tripId)
                }
            )
        )
    }

    func deleteTrip(id: String) async -> Bool {
        errorMessage = nil
        do {
            try await operations.deleteTrip(id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func makeShareLink(tripId: String) async -> String {
        do {
            let invitation = try await operations.createInvitation(
                tripId,
                CreateInvitationRequest(
                    roleToGrant: "editor",
                    expiresInHours: 72,
                    maxUses: nil
                )
            )
            return invitation.webInviteUrl
                ?? invitation.appDeepLink
                ?? "https://tracci.cn/co-editor?id=\(invitation.tripId)&code=\(invitation.inviteCode)"
        } catch {
            return "https://tracci.cn/join-trip"
        }
    }

    func loadShareMembers(tripId: String) async {
        memberLoadGeneration += 1
        let generation = memberLoadGeneration
        do {
            let members = try await operations.listMembers(tripId)
            guard generation == memberLoadGeneration else { return }
            shareMembers = members
        } catch {
            guard generation == memberLoadGeneration else { return }
            shareMembers = []
        }
    }

    func clearShareMembers() {
        memberLoadGeneration += 1
        shareMembers = []
    }
}
