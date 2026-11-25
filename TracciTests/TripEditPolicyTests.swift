import XCTest
@testable import Tracci

/// TripEditPolicy 引擎单测。覆盖状态变更检测 + 角色判断矩阵。
/// 注意：Trip 的 startDate/endDate 是 String（yyyy-MM-dd），effectiveStatus 按日期实时计算。
final class TripEditPolicyTests: XCTestCase {

    // MARK: - 辅助

    private func access(
        role: TripMemberRole,
        permissions: Set<TripPermission>
    ) -> TripAccessContext {
        TripAccessContext(role: role, permissions: permissions)
    }

    /// 构造一个 Trip（通过解码 JSON，与生产路径一致）
    private func makeTrip(start: String, end: String, status: TripStatus = .planning) -> Trip {
        let json = """
        {
            "id": "trip-1",
            "title": "测试旅程",
            "startDate": "\(start)",
            "endDate": "\(end)",
            "status": "\(status.rawValue)"
        }
        """
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(Trip.self, from: data)
    }

    /// 相对于固定 "today" 的 date
    private func date(_ dayOffset: Int, from today: Date) -> Date {
        TracciDateContext.calendar.date(byAdding: .day, value: dayOffset, to: today)!
    }

    // MARK: - dateChangeOutcome

    func test_completedTrip_changingToEndInFuture_requiresConfirmationForOngoing() {
        // today = 2026-07-27; 旅程 07-01 ~ 07-05 → COMPLETED
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let trip = makeTrip(start: "2026-07-01", end: "2026-07-05", status: .completed)

        // 改 endDate 到 08-01（未来）→ 会变 ONGOING
        let outcome = TripEditPolicy.dateChangeOutcome(
            trip: trip,
            newStart: TripDateFormatting.date(from: "2026-07-01")!,
            newEnd: date(5, from: today),
            now: today
        )

        if case .needsConfirmation(let msg) = outcome {
            XCTAssertTrue(msg.contains("进行中"))
        } else {
            XCTFail("Expected needsConfirmation, got \(outcome)")
        }
    }

    func test_completedTrip_changingToFuture_requiresConfirmationForPlanning() {
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let trip = makeTrip(start: "2026-07-01", end: "2026-07-05", status: .completed)

        // 改到 08-01 ~ 08-05（全在未来）→ 会变 PLANNING
        let outcome = TripEditPolicy.dateChangeOutcome(
            trip: trip,
            newStart: date(5, from: today),
            newEnd: date(9, from: today),
            now: today
        )

        if case .needsConfirmation(let msg) = outcome {
            XCTAssertTrue(msg.contains("规划中"))
        } else {
            XCTFail("Expected needsConfirmation, got \(outcome)")
        }
    }

    func test_completedTrip_changingStartDateOnly_staysCompleted_isAllowed() {
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let trip = makeTrip(start: "2026-07-01", end: "2026-07-05", status: .completed)

        // 只把开始日期提前，结束日期不变（仍在过去）→ 仍为 COMPLETED
        let outcome = TripEditPolicy.dateChangeOutcome(
            trip: trip,
            newStart: TripDateFormatting.date(from: "2026-06-25")!,
            newEnd: TripDateFormatting.date(from: "2026-07-05")!,
            now: today
        )

        XCTAssertEqual(outcome.isAllowed, true)
    }

    func test_ongoingTrip_dateChange_isAllowed() {
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        // 07-25 ~ 07-30，today 07-27 → ONGOING
        let trip = makeTrip(start: "2026-07-25", end: "2026-07-30", status: .ongoing)

        let outcome = TripEditPolicy.dateChangeOutcome(
            trip: trip,
            newStart: TripDateFormatting.date(from: "2026-07-25")!,
            newEnd: TripDateFormatting.date(from: "2026-08-05")!,
            now: today
        )

        XCTAssertEqual(outcome.isAllowed, true)
    }

    func test_planningTrip_dateChange_isAllowed() {
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        // 08-01 ~ 08-05 → PLANNING
        let trip = makeTrip(start: "2026-08-01", end: "2026-08-05", status: .planning)

        let outcome = TripEditPolicy.dateChangeOutcome(
            trip: trip,
            newStart: TripDateFormatting.date(from: "2026-08-01")!,
            newEnd: TripDateFormatting.date(from: "2026-08-10")!,
            now: today
        )

        XCTAssertEqual(outcome.isAllowed, true)
    }

    // MARK: - 角色判断

    func test_canUpdateTrip_ownerIsTrue_editorIsFalse_viewerIsFalse_nilIsFalse() {
        XCTAssertTrue(TripEditPolicy.canUpdateTrip(access(role: .owner, permissions: [.updateTrip])))
        XCTAssertFalse(TripEditPolicy.canUpdateTrip(access(role: .editor, permissions: [.editContent])))
        XCTAssertFalse(TripEditPolicy.canUpdateTrip(access(role: .viewer, permissions: [.read])))
        XCTAssertFalse(TripEditPolicy.canUpdateTrip(nil))
    }

    /// submit 门禁：未知角色不硬拦（防入口未带 role 时误伤 owner）；已知非 owner 才拦
    func test_shouldBlockTripUpdate_nilAllows_ownerAllows_editorViewerBlock() {
        XCTAssertFalse(TripEditPolicy.shouldBlockTripUpdate(for: nil))
        XCTAssertFalse(TripEditPolicy.shouldBlockTripUpdate(
            for: access(role: .owner, permissions: [.updateTrip])
        ))
        XCTAssertTrue(TripEditPolicy.shouldBlockTripUpdate(
            for: access(role: .editor, permissions: [.editContent])
        ))
        XCTAssertTrue(TripEditPolicy.shouldBlockTripUpdate(
            for: access(role: .viewer, permissions: [.read])
        ))
    }

    func test_canEditContent_ownerAndEditor_true_viewerFalse_nilFalse() {
        XCTAssertTrue(TripEditPolicy.canEditContent(access(role: .owner, permissions: [.editContent])))
        XCTAssertTrue(TripEditPolicy.canEditContent(access(role: .editor, permissions: [.editContent])))
        XCTAssertFalse(TripEditPolicy.canEditContent(access(role: .viewer, permissions: [.read])))
        XCTAssertFalse(TripEditPolicy.canEditContent(nil))
    }

    func test_canDeleteTrip_ownerTrue_editorFalse_nilFalse() {
        XCTAssertTrue(TripEditPolicy.canDeleteTrip(access(role: .owner, permissions: [.deleteTrip])))
        XCTAssertFalse(TripEditPolicy.canDeleteTrip(access(role: .editor, permissions: [.editContent])))
        XCTAssertFalse(TripEditPolicy.canDeleteTrip(nil))
    }

    // MARK: - 内容门禁

    func test_contentAddOutcome_completedBlocked_othersAllowed() {
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let completed = makeTrip(start: "2026-07-01", end: "2026-07-05", status: .completed)
        XCTAssertEqual(TripEditPolicy.contentAddOutcome(trip: completed, now: today).isAllowed, false)

        let ongoing = makeTrip(start: "2026-07-25", end: "2026-07-30", status: .ongoing)
        XCTAssertEqual(TripEditPolicy.contentAddOutcome(trip: ongoing, now: today).isAllowed, true)
    }

    func test_contentEditOutcome_completedBlocked_othersAllowed() {
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let completed = makeTrip(start: "2026-07-01", end: "2026-07-05", status: .completed)
        XCTAssertEqual(TripEditPolicy.contentEditOutcome(trip: completed, now: today).isAllowed, false)

        let planning = makeTrip(start: "2026-08-01", end: "2026-08-05", status: .planning)
        XCTAssertEqual(TripEditPolicy.contentEditOutcome(trip: planning, now: today).isAllowed, true)
    }

    // MARK: - 备注编辑门禁（不受旅程状态限制）

    /// 备注是非结构化轻量补充，已结束旅程也允许修改。
    func test_noteEditOutcome_completedTrip_isAllowed() {
        let completed = makeTrip(start: "2026-07-01", end: "2026-07-05", status: .completed)
        XCTAssertEqual(TripEditPolicy.noteEditOutcome(trip: completed).isAllowed, true)
    }

    func test_noteEditOutcome_ongoingTrip_isAllowed() {
        let ongoing = makeTrip(start: "2026-07-25", end: "2026-07-30", status: .ongoing)
        XCTAssertEqual(TripEditPolicy.noteEditOutcome(trip: ongoing).isAllowed, true)
    }

    func test_noteEditOutcome_planningTrip_isAllowed() {
        let planning = makeTrip(start: "2026-08-01", end: "2026-08-05", status: .planning)
        XCTAssertEqual(TripEditPolicy.noteEditOutcome(trip: planning).isAllowed, true)
    }

    /// 已结束：全量内容编辑禁止，但内容交互仍可通过备注路径
    func test_allowsContentInteraction_completedStillTrue_viaNotePath() {
        let today = TracciDateContext.calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let completed = makeTrip(start: "2026-07-01", end: "2026-07-05", status: .completed)
        XCTAssertFalse(TripEditPolicy.contentEditOutcome(trip: completed, now: today).isAllowed)
        XCTAssertTrue(TripEditPolicy.allowsContentInteraction(trip: completed, now: today))
    }

    // MARK: - Outcome 语义

    func test_outcome_isAllowed_isBlocked_needsUserConfirmation_userMessage() {
        let allowed = TripEditPolicy.Outcome.allowed
        XCTAssertTrue(allowed.isAllowed)
        XCTAssertFalse(allowed.isBlocked)
        XCTAssertFalse(allowed.needsUserConfirmation)
        XCTAssertNil(allowed.userMessage)

        let confirm = TripEditPolicy.Outcome.needsConfirmation("需要确认")
        XCTAssertFalse(confirm.isAllowed)
        XCTAssertFalse(confirm.isBlocked)
        XCTAssertTrue(confirm.needsUserConfirmation)
        XCTAssertEqual(confirm.userMessage, "需要确认")

        let blocked = TripEditPolicy.Outcome.blocked("已锁定")
        XCTAssertFalse(blocked.isAllowed)
        XCTAssertTrue(blocked.isBlocked)
        XCTAssertFalse(blocked.needsUserConfirmation)
        XCTAssertEqual(blocked.userMessage, "已锁定")
    }

    func test_tripAPIBusinessCodes_matchBackendErrorCodes() {
        XCTAssertEqual(TripAPIBusinessCode.statusChangeRequiresConfirm, 42235)
        XCTAssertEqual(TripAPIBusinessCode.itineraryCompletedNodeNoteOnly, 42236)
        XCTAssertEqual(TripAPIBusinessCode.completedContentLocked, 42237)
    }
}
