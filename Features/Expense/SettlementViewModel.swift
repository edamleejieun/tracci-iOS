import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SettlementViewModel: DemoModeProviding {
    let tripId: String
    let currentUserMemberId: String?
    private let expenseService: ExpenseService

    private(set) var settlement: ExpenseSettlement?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Demo Journey read-only guard.
    var isDemoMode = false

    /// The current user's settlement member, if found.
    var currentUserSettlementMember: SettlementMember? {
        guard let currentUserMemberId else { return nil }
        return settlement?.members.first { $0.memberId == currentUserMemberId }
    }

    /// A human-readable summary of the current user's balance.
    var myBalanceSummary: String? {
        guard let me = currentUserSettlementMember else { return nil }
        let symbol = ExpenseCurrency(rawValue: settlement?.currency ?? "")?.symbol ?? ""
        if me.isPositiveBalance {
            return "你应收 \(ExpenseFormatters.money(me.balanceAmountDecimal, symbol: symbol))"
        } else if me.isNegativeBalance {
            return "你应付 \(ExpenseFormatters.money(abs(me.balanceAmountDecimal), symbol: symbol))"
        } else {
            return "无需转账"
        }
    }

    init(tripId: String, expenseService: ExpenseService, currentUserMemberId: String? = nil) {
        self.tripId = tripId
        self.expenseService = expenseService
        self.currentUserMemberId = currentUserMemberId
    }

    func loadSettlement() async {
        guard !isDemoMode else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            settlement = try await expenseService.fetchSettlement(tripId: tripId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isDemoMode else { return }
        await loadSettlement()
    }

    /// Demo Journey: hydrate from Bundle without network.
    func applyDemoSettlement(_ settlement: ExpenseSettlement) {
        isDemoMode = true
        self.settlement = settlement
        isLoading = false
        errorMessage = nil
    }

    /// Look up member display name by memberId for transfer display.
    func memberName(for memberId: String) -> String {
        settlement?.members.first { $0.memberId == memberId }?.displayName ?? "未知"
    }

    /// Look up member identity color by memberId for transfer avatar display.
    func memberColor(for memberId: String) -> Color {
        guard let userId = settlement?.members.first(where: { $0.memberId == memberId })?.userId else {
            return AppColors.textMuted
        }
        return MemberPalette.color(for: userId)
    }

    /// Generate a WeChat-shareable transfer reminder text.
    func transferShareText(for transfer: SuggestedTransfer) -> String {
        let fromName = memberName(for: transfer.fromMemberId)
        let toName = memberName(for: transfer.toMemberId)
        let symbol = ExpenseCurrency(rawValue: settlement?.currency ?? "")?.symbol ?? ""
        let amount = ExpenseFormatters.money(transfer.amountDecimal, symbol: symbol)
        return "【AA 结算提醒】\n\(fromName) → \(toName)\n转账金额：\(amount)\n来自：趣溪"
    }

    /// Look up member userId by memberId.
    func memberUserId(for memberId: String) -> String {
        settlement?.members.first { $0.memberId == memberId }?.userId ?? ""
    }
}
