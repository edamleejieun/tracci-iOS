import Foundation

// MARK: - Expense Settlement

/// Matches `GET /api/v1/trips/{tripId}/expenses/settlement` response.
struct ExpenseSettlement: Decodable, Equatable {
    let tripId: String
    let currency: String
    let totalGroupAmount: String
    let members: [SettlementMember]
    let suggestedTransfers: [SuggestedTransfer]

    var totalGroupAmountDecimal: Decimal {
        ExpenseFormatters.decimal(from: totalGroupAmount) ?? 0
    }

    var displayTotal: String {
        let symbol = ExpenseCurrency(rawValue: currency)?.symbol ?? ""
        return ExpenseFormatters.money(totalGroupAmountDecimal, symbol: symbol)
    }
}

struct SettlementMember: Decodable, Identifiable, Equatable {
    let memberId: String
    let userId: String
    let displayName: String
    let paidAmount: String
    let shareAmount: String
    let balanceAmount: String

    var id: String { memberId }

    var paidAmountDecimal: Decimal {
        ExpenseFormatters.decimal(from: paidAmount) ?? 0
    }

    var shareAmountDecimal: Decimal {
        ExpenseFormatters.decimal(from: shareAmount) ?? 0
    }

    var balanceAmountDecimal: Decimal {
        ExpenseFormatters.decimal(from: balanceAmount) ?? 0
    }

    /// Positive = others owe this member; negative = this member owes others.
    var isPositiveBalance: Bool { balanceAmountDecimal > 0 }
    var isNegativeBalance: Bool { balanceAmountDecimal < 0 }
    var isZeroBalance: Bool { balanceAmountDecimal == 0 }

    var displayInitial: String {
        guard let first = displayName.first else { return "?" }
        return String(first)
    }
}

enum ExpenseSettlementFact {
    struct Headline: Equatable {
        let title: String
        let detail: String
    }

    static func headline(
        settlement: ExpenseSettlement,
        currentUserMemberId: String?
    ) -> Headline? {
        guard let currentUserMemberId,
              let me = settlement.members.first(where: { $0.memberId == currentUserMemberId })
        else { return nil }

        let symbol = ExpenseCurrency(rawValue: settlement.currency)?.symbol ?? ""
        let amountText = ExpenseFormatters.money(abs(me.balanceAmountDecimal), symbol: symbol)

        if me.isNegativeBalance {
            // 只有当全部欠款都转给同一人时才点名，避免把总额错记在某一个垫付人头上。
            if let name = soleCounterpartName(
                settlement: settlement,
                currentUserMemberId: currentUserMemberId
            ) {
                return Headline(title: "\(name) 为你垫付 \(amountText)", detail: "查看分摊与转账")
            }
            return Headline(title: "同伴为你垫付 \(amountText)", detail: "查看分摊与转账")
        }
        if me.isPositiveBalance {
            return Headline(title: "你为同伴垫付 \(amountText)", detail: "查看分摊与转账")
        }
        return Headline(title: "AA 结算", detail: "账已平")
    }

    private static func soleCounterpartName(
        settlement: ExpenseSettlement,
        currentUserMemberId: String
    ) -> String? {
        let receiverIds = Set(
            settlement.suggestedTransfers
                .filter { $0.fromMemberId == currentUserMemberId }
                .map(\.toMemberId)
        )
        guard receiverIds.count == 1, let receiverId = receiverIds.first else { return nil }
        let name = settlement.members.first(where: { $0.memberId == receiverId })?.displayName
        return (name?.isEmpty == false) ? name : nil
    }
}

struct SuggestedTransfer: Decodable, Identifiable, Equatable {
    let fromMemberId: String
    let toMemberId: String
    let amount: String

    var id: String { "\(fromMemberId)-\(toMemberId)" }

    var amountDecimal: Decimal {
        ExpenseFormatters.decimal(from: amount) ?? 0
    }
}
