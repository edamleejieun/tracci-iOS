import Foundation

// MARK: - Trip API Business Codes

/// 旅程相关后端业务码（与 `ErrorCode` 数值保持一致，避免魔法数散落）。
enum TripAPIBusinessCode {
    /// `ErrorCode.TRIP_STATUS_CHANGE_REQUIRES_CONFIRM` — 改日期会改变旅程状态，需确认
    static let statusChangeRequiresConfirm = 42235
    /// `ErrorCode.ITINERARY_COMPLETED_NODE_NOTE_ONLY` — 已结束旅程节点仅允许改备注
    static let itineraryCompletedNodeNoteOnly = 42236
    /// `ErrorCode.TRIP_COMPLETED_CONTENT_LOCKED` — 已结束旅程内容锁定
    static let completedContentLocked = 42237
}

// MARK: - TripEditPolicy

/// 旅程编辑权限引擎。
///
/// 集中「状态变更检测 + 角色判断 + 文案生成」逻辑，作为客户端预检层。
/// 客户端预检用于好 UX（避免多余往返），后端（TripServiceImpl 状态变更守卫）是 source of truth（防绕过）。
/// 两端共用同一套状态算法：today < start → planning，today > end → completed，else → ongoing。
struct TripEditPolicy {

    /// 某次编辑是否被允许 + 是否需要确认
    enum Outcome {
        case allowed
        /// 需要弹确认，参数 = 告知用户的后果文案
        case needsConfirmation(String)
        /// 禁止，参数 = 禁止原因（用于 disabled 提示）
        case blocked(String)

        /// 是否可直接执行（不含「需确认」）。`needsConfirmation` 为 false。
        var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }

        /// 是否被硬性禁止（可展示 `userMessage` 作禁用原因）
        var isBlocked: Bool {
            if case .blocked = self { return true }
            return false
        }

        /// 是否需要用户确认后才能继续（既非直接允许，也非硬拦）
        var needsUserConfirmation: Bool {
            if case .needsConfirmation = self { return true }
            return false
        }

        /// 面向用户的提示文案；`.allowed` 为 `nil`
        var userMessage: String? {
            switch self {
            case .allowed:
                return nil
            case .needsConfirmation(let message), .blocked(let message):
                return message
            }
        }
    }

    /// 服务端能力：是否能改旅程基础信息（标题/目的地/日期/封面）。
    ///
    /// `nil`（能力尚未解析）返回 `false`，用于 UI 隐藏「编辑旅程」等入口，避免未知权限时误开。
    /// 提交门禁请用 `shouldBlockTripUpdate`：未知能力不本地硬拦，交给后端 capability 校验。
    static func canUpdateTrip(_ access: TripAccessContext?) -> Bool {
        access?.allows(.updateTrip) ?? false
    }

    /// 提交前是否应本地拦截「改旅程基础信息」。
    /// 仅在能力**已解析**且无 `trip.update` 时拦截；`nil` 不拦截（防列表入口未带 access 时误伤 owner）。
    /// 编辑页应尽快通过详情接口补齐 access。
    static func shouldBlockTripUpdate(for access: TripAccessContext?) -> Bool {
        guard let access else { return false }
        return !access.allows(.updateTrip)
    }

    /// 服务端能力：是否能删除旅程。`nil` 默认隐藏删除入口（fail-closed）。
    static func canDeleteTrip(_ access: TripAccessContext?) -> Bool {
        access?.allows(.deleteTrip) ?? false
    }

    /// 服务端能力：是否能编辑内容（节点/日志/开支）。
    /// `nil` 默认禁止（内容写操作 fail-closed，待详情 access 加载后再开放）。
    static func canEditContent(_ access: TripAccessContext?) -> Bool {
        access?.allows(.editContent) ?? false
    }

    /// 改日期是否需要确认。
    ///
    /// 仅对当前有效状态为 `.completed` 的旅程触发；规划中 / 进行中完全开放。
    /// - Parameters:
    ///   - trip: 当前旅程（取其 startDate/endDate 算当前状态）
    ///   - newStart: 修改后的开始日期
    ///   - newEnd: 修改后的结束日期
    /// - Returns: allowed 或 needsConfirmation(文案)
    static func dateChangeOutcome(
        trip: Trip,
        newStart: Date,
        newEnd: Date,
        now: Date = TracciDateContext.today()
    ) -> Outcome {
        let currentStatus = TracciDateContext.tripStatus(
            startDate: trip.startDate,
            endDate: trip.endDate,
            now: now
        ) ?? trip.status
        guard currentStatus == .completed else { return .allowed }

        let newStatus = TracciDateContext.tripStatus(startDate: newStart, endDate: newEnd, now: now)
        switch newStatus {
        case .ongoing:
            return .needsConfirmation("修改日期后，这段旅程将从「已结束」变为「进行中」。确定要继续吗？")
        case .planning:
            return .needsConfirmation("修改日期后，这段旅程将从「已结束」变为「规划中」。确定要继续吗？")
        case .completed, .unknown:
            return .allowed
        }
    }

    /// 新增内容（节点/日志/开支）是否允许
    static func contentAddOutcome(
        trip: Trip,
        now: Date = TracciDateContext.today()
    ) -> Outcome {
        effectiveStatus(of: trip, now: now) == .completed
            ? .blocked("已结束的旅程不能再添加内容")
            : .allowed
    }

    /// 编辑/删除已有内容是否允许
    static func contentEditOutcome(
        trip: Trip,
        now: Date = TracciDateContext.today()
    ) -> Outcome {
        effectiveStatus(of: trip, now: now) == .completed
            ? .blocked("已结束的旅程内容已锁定")
            : .allowed
    }

    /// 编辑备注是否允许。
    ///
    /// 备注是非结构化轻量补充，不影响行程结构与状态，即便旅程已结束也允许修改。
    /// 角色门禁（owner/editor）由调用方通过 `canEditContent` 另行校验。
    ///
    /// 当前对任意 `trip` 均返回 `.allowed`：状态不限制备注。保留本 API 是为了调用方
    /// 能用「contentEdit ∨ noteEdit」表达交互门禁，避免散落 `status != completed` 特例。
    static func noteEditOutcome(trip: Trip) -> Outcome {
        _ = trip
        return .allowed
    }

    /// 是否允许对内容进行任意写交互（全量编辑，或仅备注）。
    /// 用于长按菜单等入口：已结束旅程仍可进入 note-only。
    static func allowsContentInteraction(
        trip: Trip,
        now: Date = TracciDateContext.today()
    ) -> Bool {
        contentEditOutcome(trip: trip, now: now).isAllowed || noteEditOutcome(trip: trip).isAllowed
    }

    private static func effectiveStatus(of trip: Trip, now: Date) -> TripStatus {
        TracciDateContext.tripStatus(
            startDate: trip.startDate,
            endDate: trip.endDate,
            now: now
        ) ?? trip.status
    }
}
