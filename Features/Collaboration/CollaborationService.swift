import Foundation
import TracciNetworking

struct CollaborationService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Members

    func listMembers(tripId: String) async throws -> [TripMemberResp] {
        try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/members"),
            as: [TripMemberResp].self
        )
    }

    func updateMemberRole(tripId: String, memberId: String, role: TripMemberRole) async throws -> TripMemberResp {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/members/\(memberId)",
                method: .put,
                body: UpdateMemberRequest(role: role.rawValue)
            ),
            as: TripMemberResp.self
        )
    }

    func removeMember(tripId: String, memberId: String) async throws {
        _ = try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/members/\(memberId)",
                method: .delete
            ),
            as: EmptyResponse.self
        )
    }

    func transferOwnership(tripId: String, memberId: String) async throws -> TransferTripOwnershipResponse {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/owner",
                method: .put,
                body: TransferTripOwnershipRequest(memberId: memberId)
            ),
            as: TransferTripOwnershipResponse.self
        )
    }

    // MARK: - Invitations

    func createInvitation(tripId: String, request: CreateInvitationRequest) async throws -> TripInvitationResp {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/invitations",
                method: .post,
                body: request
            ),
            as: TripInvitationResp.self
        )
    }

    func joinByInvitation(inviteCode: String) async throws -> JoinInvitationResponse {
        try await apiClient.request(
            APIEndpoint(
                path: "trip-invitations/join",
                method: .post,
                body: JoinInvitationRequest(
                    inviteCode: TripInviteCode.normalize(inviteCode)
                )
            ),
            as: JoinInvitationResponse.self
        )
    }

    // MARK: - Activity Logs (§16.7)

    func listActivityLogs(tripId: String, page: Int = 1, pageSize: Int = 50) async throws -> PageResponse<ActivityLogResp> {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/activity-logs",
                queryItems: [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "pageSize", value: "\(pageSize)")
                ]
            ),
            as: PageResponse<ActivityLogResp>.self
        )
    }
}
