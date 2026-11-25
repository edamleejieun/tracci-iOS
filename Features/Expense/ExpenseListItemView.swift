import SwiftUI

struct ExpenseListItemView: View {
    let expense: Expense
    let onTap: () -> Void
    var onDuplicate: (() -> Void)? = nil
    let onDelete: () -> Void
    /// 是否允许编辑/删除（已结束旅程内容锁定时为 false，仅只读展示）
    var canManage: Bool = true
    var linkedTitle: String? = nil
    var members: [TripMemberResp] = []

    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: {
            guard canManage else { return }
            onTap()
        }) {
            AppElevationCard(level: .l1, role: .content, radius: AppRadius.medium, padding: 16) {
                HStack(spacing: AppSpacing.cozy) {
                    categoryIcon
                    expenseInfo
                    amountDisplay
                }
            }
        }
        .pressableCardStyle()
        .tracciLongPressActions(title: primaryTitle, actions: expenseActions)
        .overlay {
            TracciConfirmSheet(
                isPresented: $showDeleteConfirm,
                title: "确认删除这笔开支？",
                message: "删除后无法恢复，账本统计会同步更新。",
                confirmTitle: "删除",
                onConfirm: onDelete
            )
        }
    }

    private var expenseActions: [TracciActionItem] {
        guard canManage else { return [] }
        var actions = [
            TracciActionItem(title: "编辑", systemImage: "pencil", action: onTap)
        ]
        if let onDuplicate {
            actions.append(TracciActionItem(title: "再来一笔", systemImage: "plus.square.on.square", action: onDuplicate))
        }
        actions.append(
            TracciActionItem(title: "删除", systemImage: "trash", role: .destructive) {
                showDeleteConfirm = true
            }
        )
        return actions
    }

    private var categoryIcon: some View {
        RoundedRectangle(cornerRadius: AppRadius.medium)
            .fill(Color(hex: expense.category.colorHex).opacity(0.12))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: expense.category.systemImage)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(Color(hex: expense.category.colorHex))
            }
    }

    private var expenseInfo: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(primaryTitle)
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: AppSpacing.xs) {
                if hasCustomNote {
                    Text(expense.category.displayName)
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textMuted)

                    Circle()
                        .fill(AppColors.textDisabled)
                        .frame(width: 3, height: 3)
                }

                if let linkedTitle, !linkedTitle.isEmpty {
                    Text(linkedTitle)
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)

                    Circle()
                        .fill(AppColors.textDisabled)
                        .frame(width: 3, height: 3)
                }

                Text(expense.displayTime)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountDisplay: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
            Text("-\(expense.displayAmount)")
                .font(AppTypography.listTitle)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if expense.currencyEnum != .cny {
                Text(expense.displayCnyAmount)
                    .font(AppTypography.chipRegular)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(1)
            }

            groupSplitMeta
        }
        .frame(minWidth: 88, alignment: .trailing)
    }

    @ViewBuilder
    private var groupSplitMeta: some View {
        if expense.isGroupExpense, members.count >= 2 {
            HStack(spacing: AppSpacing.xxs) {
                if let payer {
                    TripMemberAvatarView(member: payer, size: 16)
                }
                Text(splitChipText)
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(1)
            }
            .accessibilityLabel(splitAccessibilityLabel)
        }
    }

    private var payer: TripMemberResp? {
        guard let payerMemberId = expense.payerMemberId else { return nil }
        return members.first { $0.id == payerMemberId }
    }

    private var splitChipText: String {
        if let count = expense.participantMemberIds?.count, count > 0 {
            return "均分 · \(count) 人"
        }
        return "均分"
    }

    private var splitAccessibilityLabel: String {
        let payerName = payer?.nickname
        if let payerName, let count = expense.participantMemberIds?.count, count > 0 {
            return "\(payerName) 垫付，均分 \(count) 人"
        }
        if let payerName {
            return "\(payerName) 垫付，均分"
        }
        return splitChipText
    }

    private var primaryTitle: String {
        let trimmedNote = expense.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedNote.isEmpty ? expense.category.displayName : trimmedNote
    }

    private var hasCustomNote: Bool {
        !(expense.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
