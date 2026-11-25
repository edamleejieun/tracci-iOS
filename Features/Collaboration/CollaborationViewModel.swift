import Foundation
import Observation
import TracciNetworking

@MainActor
@Observable
final class CollaborationViewModel {
    let tripId: String
    let tripTitle: String
    private let collaborationService: CollaborationService
    private let currentUserId: String?
    private(set) var currentUserAccess: TripAccessContext?

    // Members
    private(set) var members: [TripMemberResp] = []
    private(set) var isLoadingMembers = false
    private(set) var membersError: String?
    /// Demo Journey hydrate — no network, no mutations.
    private(set) var isDemoMode = false

    // Current user's membership
    var currentUserMember: TripMemberResp? {
        guard let currentUserId else { return nil }
        return members.first { $0.userId == currentUserId && $0.isActive }
    }

    // Permissions
    var canEdit: Bool {
        guard !isDemoMode else { return false }
        return currentUserAccess?.allows(.editContent) ?? false
    }
    var canInvite: Bool {
        guard !isDemoMode else { return false }
        return currentUserAccess?.allows(.createInvitation) ?? false
    }
    var canManageMembers: Bool {
        guard !isDemoMode else { return false }
        return currentUserAccess?.allows(.manageMembers) ?? false
    }
    var canTransferOwnership: Bool {
        guard !isDemoMode else { return false }
        return currentUserAccess?.allows(.transferOwnership) ?? false
    }
    var canUpdateTrip: Bool {
        guard !isDemoMode else { return false }
        return currentUserAccess?.allows(.updateTrip) ?? false
    }

    // Invitation creation
    private(set) var isCreatingInvitation = false
    private(set) var createdInvitation: TripInvitationResp?
    private(set) var invitationError: String?

    var invitationSheetState: TracciDialogMetrics.InvitationSheetState {
        if createdInvitation != nil {
            return .result
        }
        if invitationError != nil {
            return .error
        }
        return .create
    }

    // Member operations
    private(set) var operatingMemberId: String?
    private(set) var memberOperationError: String?

    init(
        tripId: String,
        tripTitle: String,
        collaborationService: CollaborationService,
        currentUserId: String?,
        currentUserAccess: TripAccessContext? = nil
    ) {
        self.tripId = tripId
        self.tripTitle = tripTitle
        self.collaborationService = collaborationService
        self.currentUserId = currentUserId
        self.currentUserAccess = currentUserAccess
    }

    // MARK: - Load Members

    func loadMembers() async {
        guard !isDemoMode else { return }
        isLoadingMembers = true
        membersError = nil
        defer { isLoadingMembers = false }

        do {
            members = try await collaborationService.listMembers(tripId: tripId)
        } catch {
            membersError = error.localizedDescription
        }
    }

    /// Hydrate from Demo Bundle members — fully read-only, no network.
    func applyDemoMembers(_ demoMembers: [TripMemberResp]) {
        isDemoMode = true
        members = demoMembers
        isLoadingMembers = false
        membersError = nil
    }

    // MARK: - Update Member Role

    func updateMemberRole(memberId: String, newRole: TripMemberRole) async -> Bool {
        guard !isDemoMode else {
            memberOperationError = DemoReadOnlyCopy.toast
            return false
        }
        operatingMemberId = memberId
        memberOperationError = nil
        defer { operatingMemberId = nil }

        do {
            let updated = try await collaborationService.updateMemberRole(
                tripId: tripId,
                memberId: memberId,
                role: newRole
            )
            if let index = members.firstIndex(where: { $0.id == memberId }) {
                members[index] = updated
            }
            return true
        } catch let apiError as APIError {
            memberOperationError = CollaborationPermissionError.from(apiError: apiError).errorDescription
            return false
        } catch {
            memberOperationError = error.localizedDescription
            return false
        }
    }

    // MARK: - Remove Member

    func removeMember(memberId: String) async -> Bool {
        guard !isDemoMode else {
            memberOperationError = DemoReadOnlyCopy.toast
            return false
        }
        operatingMemberId = memberId
        memberOperationError = nil
        defer { operatingMemberId = nil }

        do {
            try await collaborationService.removeMember(tripId: tripId, memberId: memberId)
            members.removeAll { $0.id == memberId }
            return true
        } catch let apiError as APIError {
            memberOperationError = CollaborationPermissionError.from(apiError: apiError).errorDescription
            return false
        } catch {
            memberOperationError = error.localizedDescription
            return false
        }
    }

    // MARK: - Transfer Ownership

    func transferOwnership(to memberId: String) async -> Bool {
        guard !isDemoMode else {
            memberOperationError = DemoReadOnlyCopy.toast
            return false
        }
        operatingMemberId = memberId
        memberOperationError = nil
        defer { operatingMemberId = nil }

        do {
            let response = try await collaborationService.transferOwnership(
                tripId: tripId,
                memberId: memberId
            )
            members = members.map { member in
                if member.id == response.previousOwnerMemberId {
                    return member.updating(role: .editor)
                }
                if member.id == response.newOwnerMemberId {
                    return member.updating(role: .owner)
                }
                return member
            }
            currentUserAccess = response.access
            return true
        } catch let apiError as APIError {
            memberOperationError = CollaborationPermissionError.from(apiError: apiError).errorDescription
            return false
        } catch {
            memberOperationError = error.localizedDescription
            return false
        }
    }

    // MARK: - Create Invitation

    func createInvitation(roleToGrant: TripMemberRole = .editor) async -> TripInvitationResp? {
        guard !isDemoMode else {
            invitationError = DemoReadOnlyCopy.membersInviteUnavailable
            return nil
        }
        isCreatingInvitation = true
        invitationError = nil
        createdInvitation = nil
        defer { isCreatingInvitation = false }

        do {
            let request = CreateInvitationRequest(
                roleToGrant: roleToGrant.rawValue,
                expiresInHours: 168,
                maxUses: 10
            )
            let invitation = try await collaborationService.createInvitation(
                tripId: tripId,
                request: request
            )
            createdInvitation = invitation
            return invitation
        } catch {
            invitationError = error.localizedDescription
            return nil
        }
    }

    func clearInvitationError() {
        invitationError = nil
    }

    func clearMemberOperationError() {
        memberOperationError = nil
    }

    func clearCreatedInvitation() {
        createdInvitation = nil
    }
}
