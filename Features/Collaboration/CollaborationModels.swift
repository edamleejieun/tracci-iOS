import Foundation
import TracciNetworking

// MARK: - Invite Code

/// Collaboration invite code rules aligned with backend `TripCollaborationServiceImpl`.
enum TripInviteCode {
    static let codeLength = 4
    static let allowedCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private static let allowedCharacterSet = CharacterSet(charactersIn: allowedCharacters)

    /// Matches backend `normalizeCode`: trim whitespace and uppercase.
    static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Filters user input to the backend charset and caps length.
    static func sanitizedInput(_ raw: String) -> String {
        let uppercased = raw.uppercased()
        let filtered = uppercased.unicodeScalars.filter { allowedCharacterSet.contains($0) }
        return String(String.UnicodeScalarView(filtered.prefix(codeLength)))
    }

    /// Client-side guard for submit affordance; final validation remains on the backend hash lookup.
    static func isSubmittable(_ code: String) -> Bool {
        normalize(code).count == codeLength
    }
}

// MARK: - Invitation

struct CreateInvitationRequest: Encodable {
    let roleToGrant: String?
    let expiresInHours: Int?
    let maxUses: Int?
}

/// Matches §16.2 POST /api/v1/trips/{tripId}/invitations response.
struct TripInvitationResp: Codable, Identifiable, Equatable {
    let id: String
    let tripId: String
    let inviteCode: String
    let roleToGrant: String
    let expiresAt: String?
    let maxUses: Int?
    let usedCount: Int?
    let webInviteUrl: String?
    let miniProgramPath: String?
    let appDeepLink: String?
    let shareText: String?
}

extension TripInvitationResp {
    /// Web invite link per API §16.2; falls back to canonical co-editor URL.
    var inviteURL: String {
        if let webInviteUrl, !webInviteUrl.isEmpty {
            return webInviteUrl
        }
        if let appDeepLink, !appDeepLink.isEmpty {
            return appDeepLink
        }
        return "https://tracci.cn/co-editor?id=\(tripId)&code=\(inviteCode)"
    }
}

// MARK: - Join

struct JoinInvitationRequest: Encodable {
    let inviteCode: String
}

struct JoinInvitationResponse: Codable, Equatable {
    let tripId: String
    let memberId: String
    let role: String
    let status: String
    let joinedAt: String?
}

// MARK: - Update Member

struct UpdateMemberRequest: Encodable {
    let role: String
}

// MARK: - Transfer Ownership

struct TransferTripOwnershipRequest: Encodable {
    let memberId: String
}

struct TransferTripOwnershipResponse: Codable, Equatable {
    let tripId: String
    let previousOwnerMemberId: String
    let newOwnerMemberId: String
    let newOwnerUserId: String
    let access: TripAccessContext
}

// MARK: - Activity Logs

struct ActivityLogResp: Codable, Identifiable, Equatable {
    let id: String
    let tripId: String
    let actor: ActivityActor
    let action: String
    let targetType: String?
    let targetId: String?
    let summary: String
    let fieldChanges: [FieldChange]
    let createdAt: String?
}

struct ActivityActor: Codable, Equatable {
    let userId: String
    let memberId: String
    let nickname: String
}

struct FieldChange: Codable, Equatable {
    let field: String
    let oldValue: String?
    let newValue: String?

    /// User-facing presentation for journey history.
    ///
    /// Activity-log payloads intentionally use stable backend field keys. The UI
    /// must never expose those keys, file/member IDs, or serialized JSON directly.
    /// Unknown fields are omitted while the activity summary remains visible.
    var activityPresentation: ActivityFieldChangePresentation? {
        switch field {
        case "coverFileId":
            if Self.isEmpty(oldValue) {
                return .message("添加了旅程封面")
            }
            if Self.isEmpty(newValue) {
                return .message("移除了旅程封面")
            }
            return .message("更换了旅程封面")
        case "details":
            return .message("更新了详细信息")
        case "stayGroupId":
            return .message("更新了住宿安排")
        case "nodeIds":
            return .message("调整了行程顺序")
        case "statusChangeConfirmed":
            return nil
        case "title":
            return transition(label: "名称")
        case "baseCurrency":
            return transition(label: "默认币种")
        case "startDate":
            return transition(label: "开始日期")
        case "endDate":
            return transition(label: "结束日期")
        case "status":
            return transition(label: "旅程状态", transform: Self.tripStatusText)
        case "amountInput":
            return transition(label: "金额")
        case "category":
            return transition(label: "分类", transform: Self.expenseCategoryText)
        case "expenseScope":
            return transition(label: "开支类型", transform: Self.expenseScopeText)
        case "note":
            return transition(label: "备注")
        case "type":
            return transition(label: "行程类型", transform: Self.itineraryTypeText)
        case "startTime":
            return transition(label: "开始时间")
        case "endTime":
            return transition(label: "结束时间")
        case "address":
            return transition(label: "地址")
        case "checkOutDate":
            return transition(label: "退房日期")
        case "totalNights":
            return transition(label: "住宿晚数", transform: { value in
                Self.unitText(value, unit: "晚", emptyText: "未设置")
            })
        case "deletedCount":
            return .message("删除了 \(newValue ?? oldValue ?? "0") 个关联行程")
        case "contentLength":
            return transition(label: "日志字数", transform: { value in
                Self.unitText(value, unit: "字", emptyText: "0 字")
            })
        case "photoCount":
            return transition(label: "照片", transform: { value in
                Self.unitText(value, unit: "张", emptyText: "0 张")
            })
        case "locationName":
            return transition(label: "地点")
        case "mood":
            return transition(label: "心情", transform: Self.moodText)
        case "isHighlight":
            return transition(label: "日志精选", transform: Self.booleanStateText)
        case "isFeatured":
            return transition(label: "照片精选", transform: Self.booleanStateText)
        case "visibility":
            return transition(label: "可见范围", transform: Self.visibilityText)
        case "occurredAt":
            return transition(label: "记录时间")
        default:
            return nil
        }
    }

    private func transition(
        label: String,
        transform: (String?) -> String = Self.plainText
    ) -> ActivityFieldChangePresentation {
        .transition(
            label: label,
            oldValue: transform(oldValue),
            newValue: transform(newValue)
        )
    }

    private static func plainText(_ value: String?) -> String {
        guard let value, !isEmpty(value) else { return "未设置" }
        return value
    }

    private static func tripStatusText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "planning": "规划中"
        case "ongoing": "进行中"
        case "completed": "已结束"
        default: plainText(value)
        }
    }

    private static func expenseCategoryText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "food": "餐饮"
        case "transport": "交通"
        case "hotel": "住宿"
        case "attraction": "景点"
        case "shopping": "购物"
        case "other": "其他"
        default: plainText(value)
        }
    }

    private static func expenseScopeText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "personal": "个人开支"
        case "group": "AA 分摊"
        default: plainText(value)
        }
    }

    private static func itineraryTypeText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "attraction": "景点"
        case "restaurant": "餐饮"
        case "transport": "交通"
        case "hotel": "住宿"
        case "shopping": "购物"
        case "other": "其他"
        default: plainText(value)
        }
    }

    private static func moodText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "happy": "开心"
        case "relaxed": "放松"
        case "excited": "兴奋"
        case "peaceful": "平静"
        case "thoughtful": "沉思"
        default: plainText(value)
        }
    }

    private static func booleanStateText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "true": "已开启"
        case "false": "未开启"
        default: plainText(value)
        }
    }

    private static func visibilityText(_ value: String?) -> String {
        switch value?.lowercased() {
        case "all": "旅程成员可见"
        case "private": "仅自己可见"
        default: plainText(value)
        }
    }

    private static func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private static func unitText(_ value: String?, unit: String, emptyText: String) -> String {
        guard let value, !isEmpty(value) else { return emptyText }
        return "\(value) \(unit)"
    }
}

enum ActivityFieldChangePresentation: Equatable {
    case transition(label: String, oldValue: String, newValue: String)
    case message(String)
}

extension ActivityLogResp {
    /// Journey history is for user-meaningful trip content changes.
    /// The backend returns content-focused records by default; this remains as a
    /// compatibility guard for old data or old backend builds.
    var isContentHistoryVisible: Bool {
        let normalizedTarget = (targetType ?? "").uppercased()
        let normalizedAction = action.uppercased()

        if normalizedTarget.contains("INVIT") ||
            normalizedTarget.contains("MEMBER") ||
            normalizedAction.contains("INVIT") ||
            normalizedAction.contains("MEMBER") ||
            normalizedAction.contains("JOIN") {
            return false
        }

        if normalizedTarget.isEmpty {
            return false
        }

        return normalizedTarget == "TRIP" ||
            normalizedTarget == "ITINERARY" ||
            normalizedTarget == "ITINERARY_NODE" ||
            normalizedTarget == "NODE" ||
            normalizedTarget == "EXPENSE" ||
            normalizedTarget == "JOURNAL" ||
            normalizedTarget == "JOURNAL_ENTRY"
    }
}

// MARK: - Join Error Helpers

enum JoinTripError: LocalizedError {
    case invalidCode
    case expired
    case usedUp
    case noPermission
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "邀请码无效，请检查后重试"
        case .expired:
            return "邀请码已过期，请联系旅程创建者重新生成"
        case .usedUp:
            return "邀请码使用次数已用尽，请联系旅程创建者重新生成"
        case .noPermission:
            return "无权限加入该旅程"
        case let .unknown(message):
            return message
        }
    }

    /// Map backend business error codes to user-friendly messages.
    /// Error codes per API spec v2.14 §16.3.
    static func from(apiError: APIError) -> JoinTripError {
        if case let .business(code, message) = apiError {
            switch code {
            case 40419: return .invalidCode
            case 42227: return .expired
            case 42228: return .usedUp
            case 40301: return .noPermission
            default: return .unknown(message)
            }
        }
        return .unknown(apiError.localizedDescription)
    }
}

// MARK: - Permission Error Helpers

enum CollaborationPermissionError: LocalizedError {
    /// 通用无权限（后端 40301 `FORBIDDEN` 文案中性，适用于转让/管理/写操作等）。
    case permissionDenied
    case viewerWriteDenied
    case ownerOnly
    case memberNotFound
    case invalidRoleOperation
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有权限执行此操作"
        case .viewerWriteDenied:
            return "你只有查看权限，无法执行此操作"
        case .ownerOnly:
            return "仅旅程创建者可执行此操作"
        case .memberNotFound:
            return "成员不存在或已离开旅程"
        case .invalidRoleOperation:
            return "无法执行此角色操作"
        case let .unknown(message):
            return message
        }
    }

    /// Check if an API error is a permission-related denial (40301, 40418, 42226).
    static func isPermissionDenied(_ error: Error) -> Bool {
        if case let APIError.business(code, _) = error {
            return [40301, 40418, 42226].contains(code)
        }
        return false
    }

    /// Map backend business error codes (member manage / ownership transfer).
    static func from(apiError: APIError) -> CollaborationPermissionError {
        if case let .business(code, message) = apiError {
            switch code {
            case 40301: return .permissionDenied
            case 40418: return .memberNotFound
            case 42226: return .invalidRoleOperation
            default: return .unknown(message)
            }
        }
        return .unknown(apiError.localizedDescription)
    }
}
