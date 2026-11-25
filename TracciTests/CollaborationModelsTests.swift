import XCTest
@testable import Tracci
import TracciNetworking
import ImageIO
import UniformTypeIdentifiers

final class CollaborationModelsTests: XCTestCase {

    // MARK: - TripMemberResp Decoding

    func testTripMemberRespDecode() throws {
        let json = """
        {
            "id": "member-1",
            "tripId": "trip-1",
            "userId": "user-1",
            "nickname": "Alice",
            "avatarUrl": "https://example.com/avatar.jpg?sign=temporary",
            "role": "owner",
            "status": "active",
            "joinedAt": "2026-06-16T12:00:00"
        }
        """.data(using: .utf8)!

        let member = try JSONDecoder().decode(TripMemberResp.self, from: json)

        XCTAssertEqual(member.id, "member-1")
        XCTAssertEqual(member.tripId, "trip-1")
        XCTAssertEqual(member.userId, "user-1")
        XCTAssertEqual(member.nickname, "Alice")
        XCTAssertEqual(member.avatarURL?.absoluteString, "https://example.com/avatar.jpg?sign=temporary")
        XCTAssertEqual(member.role, .owner)
        XCTAssertEqual(member.status, "active")
        XCTAssertEqual(member.joinedAt, "2026-06-16T12:00:00")
        XCTAssertTrue(member.isOwner)
        XCTAssertTrue(member.isActive)
    }

    func testDeletedAccountMemberIsNotAnEffectiveActiveMember() throws {
        let json = """
        {
            "id": "member-deleted",
            "tripId": "trip-1",
            "userId": "user-deleted",
            "nickname": "已注销用户",
            "role": "editor",
            "status": "active",
            "accountStatus": "deleted"
        }
        """.data(using: .utf8)!

        let member = try JSONDecoder().decode(TripMemberResp.self, from: json)

        XCTAssertTrue(member.isAccountDeleted)
        XCTAssertFalse(member.isActive)
    }

    func testTripDetailDecodesCurrentUserRole() throws {
        let json = """
        {
            "id": "trip-1",
            "title": "测试旅程",
            "startDate": "2026-08-01",
            "endDate": "2026-08-03",
            "status": "planning",
            "access": {
                "role": "owner",
                "permissions": [
                    "trip.read",
                    "trip.content.edit",
                    "trip.update",
                    "trip.delete",
                    "trip.invitation.create",
                    "trip.members.manage",
                    "trip.ownership.transfer",
                    "trip.share.manage"
                ]
            }
        }
        """.data(using: .utf8)!

        let trip = try JSONDecoder().decode(Trip.self, from: json)

        XCTAssertEqual(trip.access?.role, .owner)
        XCTAssertTrue(trip.access?.allows(.updateTrip) == true)
        XCTAssertTrue(trip.access?.allows(.transferOwnership) == true)
    }

    func testTransferOwnershipResponseDecodesDowngradedAccess() throws {
        let json = """
        {
            "tripId": "trip-1",
            "previousOwnerMemberId": "member-1",
            "newOwnerMemberId": "member-2",
            "newOwnerUserId": "user-2",
            "access": {
                "role": "editor",
                "permissions": [
                    "trip.read",
                    "trip.content.edit",
                    "trip.invitation.create",
                    "trip.share.manage"
                ]
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(
            TransferTripOwnershipResponse.self,
            from: json
        )

        XCTAssertEqual(response.previousOwnerMemberId, "member-1")
        XCTAssertEqual(response.newOwnerMemberId, "member-2")
        XCTAssertEqual(response.access.role, .editor)
        XCTAssertFalse(response.access.allows(.manageMembers))
        XCTAssertFalse(response.access.allows(.transferOwnership))
    }

    func testTripMemberRespEditorRole() throws {
        let json = """
        {
            "id": "member-2",
            "tripId": "trip-1",
            "userId": "user-2",
            "nickname": "Bob",
            "role": "editor",
            "status": "active"
        }
        """.data(using: .utf8)!

        let member = try JSONDecoder().decode(TripMemberResp.self, from: json)

        XCTAssertEqual(member.role, .editor)
        XCTAssertNil(member.avatarURL)
        XCTAssertFalse(member.isOwner)
    }

    func testTripMemberRespViewerRole() throws {
        let json = """
        {
            "id": "member-3",
            "tripId": "trip-1",
            "userId": "user-3",
            "nickname": "Charlie",
            "role": "viewer",
            "status": "active"
        }
        """.data(using: .utf8)!

        let member = try JSONDecoder().decode(TripMemberResp.self, from: json)

        XCTAssertEqual(member.role, .viewer)
    }

    // MARK: - TripInviteCode

    func testTripInviteCodeNormalize() {
        XCTAssertEqual(TripInviteCode.normalize(" 8k3m "), "8K3M")
    }

    func testTripInviteCodeSanitizedInput() {
        XCTAssertEqual(TripInviteCode.sanitizedInput("8k-3m!"), "8K3M")
        XCTAssertEqual(TripInviteCode.sanitizedInput("8k3mxy"), "8K3M")
    }

    func testTripInviteCodeSubmittableLengths() {
        XCTAssertTrue(TripInviteCode.isSubmittable("8K3M"))
        XCTAssertFalse(TripInviteCode.isSubmittable("8K3"))
        XCTAssertFalse(TripInviteCode.isSubmittable("8K3MX"))
        XCTAssertFalse(TripInviteCode.isSubmittable(""))
    }

    // MARK: - TripInvitationResp Decoding

    func testTripInvitationRespDecode() throws {
        let json = """
        {
            "id": "inv-1",
            "tripId": "trip-1",
            "inviteCode": "8K3M",
            "roleToGrant": "editor",
            "expiresAt": "2026-06-23T12:00:00",
            "maxUses": 10,
            "usedCount": 0,
            "webInviteUrl": "https://tracci.cn/co-editor?id=trip-1&code=8K3M",
            "miniProgramPath": "/pages/co-editor/index?id=trip-1&code=8K3M",
            "appDeepLink": "tracci://co-editor?id=trip-1&code=8K3M",
            "shareText": "邀请你一起编辑趣溪旅行：京都五日旅行。邀请码：8K3M"
        }
        """.data(using: .utf8)!

        let invitation = try JSONDecoder().decode(TripInvitationResp.self, from: json)

        XCTAssertEqual(invitation.id, "inv-1")
        XCTAssertEqual(invitation.inviteCode, "8K3M")
        XCTAssertEqual(invitation.inviteCode.count, TripInviteCode.codeLength)
        XCTAssertEqual(invitation.roleToGrant, "editor")
        XCTAssertEqual(invitation.maxUses, 10)
        XCTAssertEqual(invitation.usedCount, 0)
        XCTAssertEqual(invitation.webInviteUrl, "https://tracci.cn/co-editor?id=trip-1&code=8K3M")
        XCTAssertEqual(invitation.appDeepLink, "tracci://co-editor?id=trip-1&code=8K3M")
        XCTAssertNotNil(invitation.shareText)
    }

    // MARK: - JoinInvitationResponse Decoding

    func testJoinInvitationResponseDecode() throws {
        let json = """
        {
            "tripId": "trip-1",
            "memberId": "member-2",
            "role": "editor",
            "status": "active",
            "joinedAt": "2026-06-16T12:00:00"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(JoinInvitationResponse.self, from: json)

        XCTAssertEqual(response.tripId, "trip-1")
        XCTAssertEqual(response.memberId, "member-2")
        XCTAssertEqual(response.role, "editor")
        XCTAssertEqual(response.status, "active")
    }

    // MARK: - ActivityLogResp Decoding

    func testActivityLogRespDecode() throws {
        let json = """
        {
            "id": "log-1",
            "tripId": "trip-1",
            "actor": {
                "userId": "user-1",
                "memberId": "member-1",
                "nickname": "Alice"
            },
            "action": "EXPENSE_UPDATED",
            "targetType": "EXPENSE",
            "targetId": "expense-1",
            "summary": "更新了账单",
            "fieldChanges": [
                { "field": "amountInput", "oldValue": "100.00", "newValue": "120.00" }
            ],
            "createdAt": "2026-06-16T12:00:00"
        }
        """.data(using: .utf8)!

        let log = try JSONDecoder().decode(ActivityLogResp.self, from: json)

        XCTAssertEqual(log.id, "log-1")
        XCTAssertEqual(log.actor.nickname, "Alice")
        XCTAssertEqual(log.action, "EXPENSE_UPDATED")
        XCTAssertEqual(log.summary, "更新了账单")
        XCTAssertEqual(log.fieldChanges.count, 1)
        XCTAssertEqual(log.fieldChanges[0].field, "amountInput")
        XCTAssertEqual(log.fieldChanges[0].oldValue, "100.00")
        XCTAssertEqual(log.fieldChanges[0].newValue, "120.00")
        XCTAssertTrue(log.isContentHistoryVisible)
    }

    func testActivityLogRespContentHistoryVisibility() throws {
        let journal = ActivityLogResp(
            id: "log-journal",
            tripId: "trip-1",
            actor: ActivityActor(userId: "user-1", memberId: "member-1", nickname: "Alice"),
            action: "JOURNAL_CREATED",
            targetType: "JOURNAL",
            targetId: "journal-1",
            summary: "创建旅行日志",
            fieldChanges: [],
            createdAt: "2026-06-16T12:00:00"
        )
        let legacyJournal = ActivityLogResp(
            id: "log-legacy-journal",
            tripId: "trip-1",
            actor: ActivityActor(userId: "user-1", memberId: "member-1", nickname: "Alice"),
            action: "JOURNAL_UPDATED",
            targetType: "journal",
            targetId: "journal-1",
            summary: "更新旅行日志",
            fieldChanges: [],
            createdAt: "2026-06-16T12:00:00"
        )
        let invitation = ActivityLogResp(
            id: "log-invitation",
            tripId: "trip-1",
            actor: ActivityActor(userId: "user-1", memberId: "member-1", nickname: "Alice"),
            action: "INVITATION_CREATED",
            targetType: "TRIP_INVITATION",
            targetId: "invitation-1",
            summary: "创建了旅行邀请",
            fieldChanges: [],
            createdAt: "2026-06-16T12:00:00"
        )
        let member = ActivityLogResp(
            id: "log-member",
            tripId: "trip-1",
            actor: ActivityActor(userId: "user-1", memberId: "member-1", nickname: "Alice"),
            action: "MEMBER_ROLE_UPDATED",
            targetType: "TRIP_MEMBER",
            targetId: "member-2",
            summary: "修改了成员角色",
            fieldChanges: [],
            createdAt: "2026-06-16T12:00:00"
        )

        XCTAssertTrue(journal.isContentHistoryVisible)
        XCTAssertTrue(legacyJournal.isContentHistoryVisible)
        XCTAssertFalse(invitation.isContentHistoryVisible)
        XCTAssertFalse(member.isContentHistoryVisible)
    }

    func testActivityLogRespEmptyFieldChanges() throws {
        let json = """
        {
            "id": "log-2",
            "tripId": "trip-1",
            "actor": {
                "userId": "user-1",
                "memberId": "member-1",
                "nickname": "Alice"
            },
            "action": "TRIP_CREATED",
            "summary": "创建了旅程",
            "fieldChanges": [],
            "createdAt": "2026-06-16T12:00:00"
        }
        """.data(using: .utf8)!

        let log = try JSONDecoder().decode(ActivityLogResp.self, from: json)

        XCTAssertEqual(log.action, "TRIP_CREATED")
        XCTAssertTrue(log.fieldChanges.isEmpty)
        XCTAssertNil(log.targetType)
        XCTAssertNil(log.targetId)
    }

    func testActivityFieldChangePresentation_hidesCoverIdentifier() {
        let change = FieldChange(
            field: "coverFileId",
            oldValue: nil,
            newValue: "baf5e630e1e99b66cb273636dc002303"
        )

        XCTAssertEqual(change.activityPresentation, .message("添加了旅程封面"))
        XCTAssertFalse(String(describing: change.activityPresentation).contains("baf5e630"))
    }

    func testActivityFieldChangePresentation_mapsKnownFieldAndValue() {
        let change = FieldChange(field: "category", oldValue: "food", newValue: "transport")

        XCTAssertEqual(
            change.activityPresentation,
            .transition(label: "分类", oldValue: "餐饮", newValue: "交通")
        )
    }

    func testActivityFieldChangePresentation_omitsInternalAndUnknownFields() {
        XCTAssertNil(
            FieldChange(field: "statusChangeConfirmed", oldValue: nil, newValue: "true")
                .activityPresentation
        )
        XCTAssertNil(
            FieldChange(field: "futureInternalField", oldValue: "secret-a", newValue: "secret-b")
                .activityPresentation
        )
    }

    // MARK: - ExpenseSettlement Decoding

    func testExpenseSettlementDecode() throws {
        let json = """
        {
            "tripId": "trip-1",
            "currency": "CNY",
            "totalGroupAmount": "300.00",
            "members": [
                {
                    "memberId": "member-1",
                    "userId": "user-1",
                    "displayName": "Alice",
                    "paidAmount": "300.00",
                    "shareAmount": "100.00",
                    "balanceAmount": "200.00"
                },
                {
                    "memberId": "member-2",
                    "userId": "user-2",
                    "displayName": "Bob",
                    "paidAmount": "0.00",
                    "shareAmount": "100.00",
                    "balanceAmount": "-100.00"
                }
            ],
            "suggestedTransfers": [
                { "fromMemberId": "member-2", "toMemberId": "member-1", "amount": "100.00" }
            ]
        }
        """.data(using: .utf8)!

        let settlement = try JSONDecoder().decode(ExpenseSettlement.self, from: json)

        XCTAssertEqual(settlement.tripId, "trip-1")
        XCTAssertEqual(settlement.currency, "CNY")
        XCTAssertEqual(settlement.totalGroupAmount, "300.00")
        XCTAssertEqual(settlement.members.count, 2)
        XCTAssertEqual(settlement.members[0].displayName, "Alice")
        XCTAssertEqual(settlement.members[0].paidAmount, "300.00")
        XCTAssertTrue(settlement.members[0].isPositiveBalance)
        XCTAssertTrue(settlement.members[1].isNegativeBalance)
        XCTAssertEqual(settlement.suggestedTransfers.count, 1)
        XCTAssertEqual(settlement.suggestedTransfers[0].fromMemberId, "member-2")
        XCTAssertEqual(settlement.suggestedTransfers[0].toMemberId, "member-1")
        XCTAssertEqual(settlement.suggestedTransfers[0].amount, "100.00")

        let owed = ExpenseSettlementFact.headline(settlement: settlement, currentUserMemberId: "member-2")
        XCTAssertEqual(owed?.title, "Alice 为你垫付 \(ExpenseFormatters.money(Decimal(100), symbol: "¥"))")
        let receivable = ExpenseSettlementFact.headline(settlement: settlement, currentUserMemberId: "member-1")
        XCTAssertEqual(receivable?.title, "你为同伴垫付 \(ExpenseFormatters.money(Decimal(200), symbol: "¥"))")
    }

    /// 欠款分散给多个垫付人时，标题不得点名为单人，避免金额归属误导。
    func testSettlementHeadlineStaysGenericWhenMultipleLenders() throws {
        let json = """
        {
            "tripId": "trip-1",
            "currency": "CNY",
            "totalGroupAmount": "500.00",
            "members": [
                { "memberId": "member-1", "userId": "user-1", "displayName": "Alice", "paidAmount": "300.00", "shareAmount": "166.67", "balanceAmount": "133.33" },
                { "memberId": "member-2", "userId": "user-2", "displayName": "Bob", "paidAmount": "200.00", "shareAmount": "166.67", "balanceAmount": "33.33" },
                { "memberId": "member-3", "userId": "user-3", "displayName": "Cara", "paidAmount": "0.00", "shareAmount": "166.66", "balanceAmount": "-166.66" }
            ],
            "suggestedTransfers": [
                { "fromMemberId": "member-3", "toMemberId": "member-1", "amount": "100.00" },
                { "fromMemberId": "member-3", "toMemberId": "member-2", "amount": "66.66" }
            ]
        }
        """.data(using: .utf8)!

        let settlement = try JSONDecoder().decode(ExpenseSettlement.self, from: json)
        let headline = try XCTUnwrap(
            ExpenseSettlementFact.headline(settlement: settlement, currentUserMemberId: "member-3")
        )
        let expectedAmount = ExpenseFormatters.money(Decimal(string: "166.66")!, symbol: "¥")
        XCTAssertEqual(headline.title, "同伴为你垫付 \(expectedAmount)")
    }

    // MARK: - CreateExpenseRequest Encoding (group)

    func testCreateExpenseRequestEncodeGroup() throws {
        let request = CreateExpenseRequest(
            amountInput: "300.00",
            currency: "CNY",
            category: "food",
            note: "团队晚餐",
            spentAt: "2026-06-16T19:30:00Z",
            expenseScope: "group",
            payerMemberId: "member-1",
            participantMemberIds: ["member-1", "member-2", "member-3"],
            splitMethod: "equal"
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["expenseScope"] as? String, "group")
        XCTAssertEqual(json["payerMemberId"] as? String, "member-1")
        XCTAssertEqual(json["splitMethod"] as? String, "equal")

        let participants = json["participantMemberIds"] as? [String]
        XCTAssertEqual(participants?.count, 3)
        XCTAssertTrue(participants?.contains("member-1") ?? false)
    }

    func testCreateExpenseRequestEncodePersonal() throws {
        let request = CreateExpenseRequest(
            amountInput: "50.00",
            currency: "CNY",
            category: "food",
            note: nil,
            spentAt: "2026-06-16T12:00:00Z",
            expenseScope: nil,
            payerMemberId: nil,
            participantMemberIds: nil,
            splitMethod: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNil(json["expenseScope"])
        XCTAssertNil(json["payerMemberId"])
        XCTAssertNil(json["participantMemberIds"])
        XCTAssertNil(json["splitMethod"])
    }

    // MARK: - Expense Scope Decoding

    func testExpenseDecodeWithGroupScope() throws {
        let json = """
        {
            "id": "expense-1",
            "tripId": "trip-1",
            "amountInput": "300.00",
            "currency": "CNY",
            "amountCny": "300.00",
            "exchangeRate": "1.00000000",
            "category": "food",
            "note": "团队晚餐",
            "spentAt": "2026-06-16T19:30:00Z",
            "expenseScope": "group",
            "payerMemberId": "member-1",
            "participantMemberIds": ["member-1", "member-2", "member-3"],
            "createdByMemberId": "member-1",
            "splitMethod": "equal",
            "createdAt": "2026-06-16T12:00:00Z"
        }
        """.data(using: .utf8)!

        let expense = try JSONDecoder().decode(Expense.self, from: json)

        XCTAssertEqual(expense.expenseScope, .group)
        XCTAssertEqual(expense.payerMemberId, "member-1")
        XCTAssertEqual(expense.participantMemberIds, ["member-1", "member-2", "member-3"])
        XCTAssertEqual(expense.splitMethod, .equal)
        XCTAssertTrue(expense.isGroupExpense)
    }

    func testExpenseDecodePersonalScope() throws {
        let json = """
        {
            "id": "expense-2",
            "tripId": "trip-1",
            "amountInput": "50.00",
            "currency": "CNY",
            "amountCny": "50.00",
            "category": "food",
            "note": "午餐",
            "spentAt": "2026-06-16T12:00:00Z"
        }
        """.data(using: .utf8)!

        let expense = try JSONDecoder().decode(Expense.self, from: json)

        XCTAssertNil(expense.expenseScope)
        XCTAssertNil(expense.payerMemberId)
        XCTAssertFalse(expense.isGroupExpense)
        XCTAssertNil(expense.linkedNodeId)
        XCTAssertNil(expense.linkedStayGroupId)
    }

    func testExpenseDecodeLinkedItinerary() throws {
        let json = """
        {
            "id": "expense-3",
            "tripId": "trip-1",
            "amountInput": "2400.00",
            "currency": "CNY",
            "amountCny": "2400.00",
            "category": "hotel",
            "spentAt": "2026-06-16T12:00:00Z",
            "linkedStayGroupId": "stay-1",
            "linkedItinerary": {
                "stayGroupId": "stay-1",
                "title": "京王广场酒店",
                "type": "hotel"
            }
        }
        """.data(using: .utf8)!

        let expense = try JSONDecoder().decode(Expense.self, from: json)
        XCTAssertEqual(expense.linkedStayGroupId, "stay-1")
        XCTAssertEqual(expense.linkedItinerary?.title, "京王广场酒店")
        XCTAssertEqual(expense.linkedTitle(in: []), "京王广场酒店")
    }

    // MARK: - JoinTripError Mapping (error codes per API spec v2.14 §16.3)

    func testJoinTripErrorMapping() {
        let invalidCode = JoinTripError.from(apiError: .business(code: 40419, message: "not found"))
        XCTAssertEqual(invalidCode.errorDescription, "邀请码无效，请检查后重试")

        let expired = JoinTripError.from(apiError: .business(code: 42227, message: "expired"))
        XCTAssertEqual(expired.errorDescription, "邀请码已过期，请联系旅程创建者重新生成")

        let usedUp = JoinTripError.from(apiError: .business(code: 42228, message: "used up"))
        XCTAssertEqual(usedUp.errorDescription, "邀请码使用次数已用尽，请联系旅程创建者重新生成")

        let noPermission = JoinTripError.from(apiError: .business(code: 40301, message: "forbidden"))
        XCTAssertEqual(noPermission.errorDescription, "无权限加入该旅程")
    }

    // MARK: - Permission Helpers

    func testPermissionDeniedDetection() {
        XCTAssertTrue(CollaborationPermissionError.isPermissionDenied(APIError.business(code: 40301, message: "no permission")))
        XCTAssertTrue(CollaborationPermissionError.isPermissionDenied(APIError.business(code: 40418, message: "member not found")))
        XCTAssertTrue(CollaborationPermissionError.isPermissionDenied(APIError.business(code: 42226, message: "invalid role operation")))
        XCTAssertFalse(CollaborationPermissionError.isPermissionDenied(APIError.business(code: 40401, message: "not found")))
        XCTAssertFalse(CollaborationPermissionError.isPermissionDenied(APIError.noData))
    }

    // MARK: - CollaborationPermissionError Mapping (§16.5 / §16.6)

    func testPermissionErrorMapping() {
        let permissionDenied = CollaborationPermissionError.from(
            apiError: .business(code: 40301, message: "not owner")
        )
        XCTAssertEqual(permissionDenied.errorDescription, "没有权限执行此操作")

        let memberNotFound = CollaborationPermissionError.from(
            apiError: .business(code: 40418, message: "member not found")
        )
        XCTAssertEqual(memberNotFound.errorDescription, "成员不存在或已离开旅程")

        let invalidRole = CollaborationPermissionError.from(
            apiError: .business(code: 42226, message: "cannot modify owner")
        )
        XCTAssertEqual(invalidRole.errorDescription, "无法执行此角色操作")

        let unknown = CollaborationPermissionError.from(
            apiError: .business(code: 50000, message: "server error")
        )
        XCTAssertEqual(unknown.errorDescription, "server error")
    }

    func testTripAccessContextIgnoresUnknownPermissions() throws {
        let json = """
        {
            "role": "owner",
            "permissions": [
                "trip.read",
                "trip.content.edit",
                "trip.update",
                "trip.delete",
                "trip.invitation.create",
                "trip.members.manage",
                "trip.ownership.transfer",
                "trip.share.manage",
                "trip.future.feature"
            ]
        }
        """.data(using: .utf8)!

        let access = try JSONDecoder().decode(TripAccessContext.self, from: json)

        XCTAssertEqual(access.role, .owner)
        XCTAssertTrue(access.allows(.transferOwnership))
        XCTAssertTrue(access.allows(.deleteTrip))
        XCTAssertFalse(access.permissions.map(\.rawValue).contains("trip.future.feature"))
    }

    // MARK: - Journal capture date + expense create draft

    func testJournalOccurrenceDateUsesInRangeCaptureTime() {
        let calendar = TracciDateContext.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let captured = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 11, minute: 30))!
        let dayAnchor = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 18))!

        let resolved = JournalOccurrenceDate.resolveCreate(
            capturedAt: captured,
            dayAnchor: dayAnchor,
            tripStartDate: start,
            tripEndDate: end,
            now: now
        )

        XCTAssertEqual(calendar.startOfDay(for: resolved), calendar.startOfDay(for: captured))
        XCTAssertEqual(calendar.component(.hour, from: resolved), 11)
        XCTAssertEqual(calendar.component(.minute, from: resolved), 30)
    }

    func testJournalOccurrenceDateOutOfRangeKeepsSelectedDayAndCaptureClock() {
        let calendar = TracciDateContext.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let captured = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 9, minute: 15))!
        let dayAnchor = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!

        let resolved = JournalOccurrenceDate.resolveCreate(
            capturedAt: captured,
            dayAnchor: dayAnchor,
            tripStartDate: start,
            tripEndDate: end,
            now: Date()
        )

        XCTAssertEqual(calendar.startOfDay(for: resolved), calendar.startOfDay(for: dayAnchor))
        XCTAssertEqual(calendar.component(.hour, from: resolved), 9)
        XCTAssertEqual(calendar.component(.minute, from: resolved), 15)
    }

    func testJournalOccurrenceDateMissingCaptureUsesNowClockOnSelectedDay() {
        let calendar = TracciDateContext.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let dayAnchor = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 18, minute: 40))!

        let resolved = JournalOccurrenceDate.resolveCreate(
            capturedAt: nil,
            dayAnchor: dayAnchor,
            tripStartDate: start,
            tripEndDate: end,
            now: now
        )

        XCTAssertEqual(calendar.startOfDay(for: resolved), calendar.startOfDay(for: dayAnchor))
        XCTAssertEqual(calendar.component(.hour, from: resolved), 18)
        XCTAssertEqual(calendar.component(.minute, from: resolved), 40)
    }

    func testImagePickerReadsCaptureDateFromOriginalBytes() throws {
        let stamp = "2026:05:03 11:30:00"
        let data = try Self.jpegWithEXIFDate(stamp)
        let parsed = try XCTUnwrap(ImagePickerProcessing.captureDate(from: data))
        let expected = try XCTUnwrap(ImagePickerProcessing.parseEXIFDate(stamp))
        XCTAssertEqual(parsed, expected)
    }

    /// EXIF 墙钟时间必须按业务日历（Asia/Shanghai）解释：
    /// 晚上 20:30 拍的照片，startOfDay 仍归 5 月 3 日，而不是次日。
    func testEXIFDateIsInterpretedInBusinessTimeZone() throws {
        let parsed = try XCTUnwrap(ImagePickerProcessing.parseEXIFDate("2026:05:03 20:30:00"))
        let calendar = TracciDateContext.calendar
        let mayThird = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
        XCTAssertEqual(calendar.startOfDay(for: parsed), mayThird)
        XCTAssertEqual(calendar.component(.hour, from: parsed), 20)
        XCTAssertEqual(calendar.component(.minute, from: parsed), 30)
    }

    func testExpenseCreateDefaultsSoloIsPersonalWithLastCategory() {
        let me = Self.member(id: "m1", userId: "u1")
        let draft = ExpenseFormDraft.createDefaults(
            members: [me],
            currentUserId: "u1",
            suggestedCategory: nil,
            lastCategory: .food,
            duplicate: nil
        )
        XCTAssertEqual(draft.expenseScope, .personal)
        XCTAssertNil(draft.payerMemberId)
        XCTAssertTrue(draft.participantIds.isEmpty)
        XCTAssertEqual(draft.category, .food)
        XCTAssertEqual(draft.amount, "")
    }

    func testExpenseCreateDefaultsGroupPaysAndSplitsEveryone() {
        let me = Self.member(id: "m1", userId: "u1")
        let other = Self.member(id: "m2", userId: "u2")
        let draft = ExpenseFormDraft.createDefaults(
            members: [me, other],
            currentUserId: "u1",
            suggestedCategory: .hotel,
            lastCategory: .food,
            duplicate: nil
        )
        XCTAssertEqual(draft.expenseScope, .group)
        XCTAssertEqual(draft.payerMemberId, "m1")
        XCTAssertEqual(draft.participantIds, ["m1", "m2"])
        XCTAssertEqual(draft.category, .hotel)
    }

    func testExpenseDuplicatePrefillsAmountScopeAndParticipants() throws {
        let json = """
        {
            "id": "expense-1",
            "tripId": "trip-1",
            "amountInput": "88.50",
            "currency": "CNY",
            "amountCny": "88.50",
            "category": "food",
            "spentAt": "2026-06-16T19:30:00Z",
            "expenseScope": "group",
            "payerMemberId": "member-1",
            "participantMemberIds": ["member-1", "member-2"],
            "splitMethod": "equal"
        }
        """.data(using: .utf8)!
        let expense = try JSONDecoder().decode(Expense.self, from: json)
        let draft = ExpenseFormDraft.createDefaults(
            members: [],
            currentUserId: nil,
            suggestedCategory: .shopping,
            lastCategory: .other,
            duplicate: expense
        )
        XCTAssertEqual(draft.amount, "88.50")
        XCTAssertEqual(draft.category, .food)
        XCTAssertEqual(draft.expenseScope, .group)
        XCTAssertEqual(draft.payerMemberId, "member-1")
        XCTAssertEqual(draft.participantIds, ["member-1", "member-2"])
    }

    private static func member(id: String, userId: String) -> TripMemberResp {
        TripMemberResp(
            id: id,
            tripId: "trip-1",
            userId: userId,
            nickname: id,
            role: .editor,
            status: "active",
            joinedAt: nil
        )
    }

    private static func jpegWithEXIFDate(_ stamp: String) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "exif-fixture", code: 1)
        }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let image = context.makeImage() else {
            throw NSError(domain: "exif-fixture", code: 1)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "exif-fixture", code: 2)
        }
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: stamp]
        let properties: [CFString: Any] = [kCGImagePropertyExifDictionary: exif]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "exif-fixture", code: 3)
        }
        return data as Data
    }
}
