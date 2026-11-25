import Foundation
import Observation
import TracciNetworking

@MainActor
@Observable
final class JoinTripViewModel {
    private let collaborationService: CollaborationService

    var inviteCode: String = ""
    private(set) var isJoining = false
    private(set) var errorMessage: String?
    private(set) var joinResult: JoinInvitationResponse?

    init(collaborationService: CollaborationService, initialCode: String = "") {
        self.collaborationService = collaborationService
        self.inviteCode = TripInviteCode.sanitizedInput(initialCode)
    }

    var canJoin: Bool {
        TripInviteCode.isSubmittable(inviteCode) && !isJoining
    }

    func updateInviteCode(_ raw: String) {
        inviteCode = TripInviteCode.sanitizedInput(raw)
        if errorMessage != nil {
            errorMessage = nil
        }
    }

    func join() async -> JoinInvitationResponse? {
        let normalized = TripInviteCode.normalize(inviteCode)
        guard TripInviteCode.isSubmittable(normalized) else {
            errorMessage = "请输入 \(TripInviteCode.codeLength) 位邀请码"
            return nil
        }

        isJoining = true
        errorMessage = nil
        joinResult = nil
        defer { isJoining = false }

        do {
            let result = try await collaborationService.joinByInvitation(inviteCode: normalized)
            joinResult = result
            return result
        } catch let apiError as APIError {
            errorMessage = JoinTripError.from(apiError: apiError).errorDescription
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
