import Foundation
import SwiftUI

// MARK: - Trip Member Role

enum TripMemberRole: String, Codable, Equatable, Identifiable {
    case owner
    case editor
    case viewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .owner: return "创建者"
        case .editor: return "可编辑"
        case .viewer: return "仅查看"
        }
    }

    var icon: String {
        switch self {
        case .owner: return "crown.fill"
        case .editor: return "pencil"
        case .viewer: return "eye"
        }
    }

}

enum TripPermission: String, Codable, Hashable {
    case read = "trip.read"
    case editContent = "trip.content.edit"
    case updateTrip = "trip.update"
    case deleteTrip = "trip.delete"
    case createInvitation = "trip.invitation.create"
    case manageMembers = "trip.members.manage"
    case transferOwnership = "trip.ownership.transfer"
    case manageShare = "trip.share.manage"
}

struct TripAccessContext: Equatable, Hashable {
    let role: TripMemberRole
    let permissions: Set<TripPermission>

    init(role: TripMemberRole, permissions: Set<TripPermission>) {
        self.role = role
        self.permissions = permissions
    }

    func allows(_ permission: TripPermission) -> Bool {
        permissions.contains(permission)
    }
}

extension TripAccessContext: Codable {
    private enum CodingKeys: String, CodingKey {
        case role
        case permissions
    }

    /// 忽略后端新增、客户端尚未识别的 permission 字符串，避免整段 Trip 解码失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(TripMemberRole.self, forKey: .role)
        let rawPermissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        permissions = Set(rawPermissions.compactMap(TripPermission.init(rawValue:)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(permissions.map(\.rawValue).sorted(), forKey: .permissions)
    }
}

// MARK: - Trip Member (API Response)

/// Backend response model for trip members.
/// Matches `GET /api/v1/trips/{tripId}/members` response.
struct TripMemberResp: Codable, Identifiable, Equatable {
    let id: String
    let tripId: String
    let userId: String
    let nickname: String
    let avatarUrl: String?
    let role: TripMemberRole
    let status: String
    let accountStatus: String?
    let joinedAt: String?

    init(
        id: String,
        tripId: String,
        userId: String,
        nickname: String,
        avatarUrl: String? = nil,
        role: TripMemberRole,
        status: String,
        accountStatus: String? = "active",
        joinedAt: String?
    ) {
        self.id = id
        self.tripId = tripId
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.role = role
        self.status = status
        self.accountStatus = accountStatus
        self.joinedAt = joinedAt
    }

    var isAccountDeleted: Bool { accountStatus?.uppercased() == "DELETED" }
    var isActive: Bool { status.uppercased() == "ACTIVE" && !isAccountDeleted }
}

// MARK: - UI Helpers

extension TripMemberResp {
    var roleLabel: String { role.label }
    var roleIcon: String { role.icon }
    var isOwner: Bool { role == .owner }

    var displayInitial: String {
        guard let first = nickname.first else { return "?" }
        return String(first)
    }

    var avatarURL: URL? {
        guard let avatarUrl else { return nil }
        let trimmed = avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    /// Stable identity color for this member, derived from userId.
    var memberColor: Color {
        MemberPalette.color(for: userId)
    }

    /// Background tint of the member's identity color.
    var memberColorBg: Color {
        MemberPalette.background(for: userId)
    }

    func updating(role: TripMemberRole) -> TripMemberResp {
        TripMemberResp(
            id: id,
            tripId: tripId,
            userId: userId,
            nickname: nickname,
            avatarUrl: avatarUrl,
            role: role,
            status: status,
            accountStatus: accountStatus,
            joinedAt: joinedAt
        )
    }
}
