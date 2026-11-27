import SwiftUI

struct SettlementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: SettlementViewModel
    @State private var copiedTransferIds: Set<String> = []

    init(
        tripId: String,
        expenseService: ExpenseService,
        currentUserMemberId: String? = nil,
        demoSettlement: ExpenseSettlement? = nil
    ) {
        let vm = SettlementViewModel(
            tripId: tripId,
            expenseService: expenseService,
            currentUserMemberId: currentUserMemberId
        )
        if let demoSettlement {
            vm.applyDemoSettlement(demoSettlement)
        }
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.settlement == nil {
                LoadingView(message: "加载结算数据")
            } else if let error = viewModel.errorMessage, viewModel.settlement == nil {
                ErrorStateView(
                    title: "结算加载失败",
                    message: error,
                    retryTitle: "再试一次"
                ) {
                    Task { await viewModel.loadSettlement() }
                }
            } else if let settlement = viewModel.settlement {
                if settlement.members.isEmpty {
                    emptyState
                } else {
                    settlementContent(settlement)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle(viewModel.isDemoMode ? "示例 AA 结算" : "AA 结算")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.backgroundGrouped)
        .task {
            await viewModel.loadSettlement()
        }
        .onChange(of: viewModel.settlement) { _, newValue in
            if newValue != nil { AppHaptics.lightImpact() }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AppColors.backgroundGrouped)
                    .frame(width: 88, height: 88)
                Image(systemName: "banknote")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
            VStack(spacing: AppSpacing.tight) {
                Text("还没有需要分摊的开支")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("记一笔一起花的，这里会算出该谁转谁。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Settlement Content

    private func settlementContent(_ settlement: ExpenseSettlement) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                if viewModel.isDemoMode {
                    demoReadOnlyBanner
                }

                // Total
                totalCard(settlement)

                // My balance summary
                if let summary = viewModel.myBalanceSummary {
                    myBalanceBanner(summary)
                }

                // Member balances
                memberBalancesSection(settlement)

                // Suggested transfers
                if !settlement.suggestedTransfers.isEmpty {
                    transfersSection(settlement)
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.cardSmall)
            .padding(.bottom, 40)
        }
    }

    private var demoReadOnlyBanner: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "eye")
                .font(AppTypography.captionSemibold)
            Text(DemoReadOnlyCopy.settlementReadOnly)
                .font(AppTypography.captionMedium)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppColors.interactiveText)
        .padding(.horizontal, AppSpacing.cardSmall)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.brandPrimary.opacity(0.08))
        )
        .accessibilityLabel(DemoReadOnlyCopy.settlementReadOnly)
    }

    private func myBalanceBanner(_ summary: String) -> some View {
        let me = viewModel.currentUserSettlementMember
        let isPositive = me?.isPositiveBalance ?? false
        let isNegative = me?.isNegativeBalance ?? false

        let tint: Color = {
            if isPositive { return AppColors.success }
            if isNegative { return AppColors.warning }
            return AppColors.brandPrimary
        }()

        let iconName: String = {
            if isPositive { return "arrow.down.circle.fill" }
            if isNegative { return "arrow.up.circle.fill" }
            return "checkmark.seal.fill"
        }()

        let subtitleText: String = {
            if isPositive { return "小伙伴们会转账给你" }
            if isNegative { return "记得转账给小伙伴哦" }
            return "大家已互相结清，旅途愉快"
        }()

        return VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.cozy) {
                Image(systemName: iconName)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary)
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitleText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }

                Spacer()
            }
        }
        .padding(AppSpacing.cardSmall)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(tint.opacity(0.15), lineWidth: 0.7)
        }
    }

    private func totalCard(_ settlement: ExpenseSettlement) -> some View {
        AppElevationCard(level: .l2, role: .active, radius: AppRadius.large, padding: 24) {
            VStack(spacing: AppSpacing.tight) {
                Text("团队总开支")
                    .font(AppTypography.editorialMeta)
                    .tracking(0.6)
                    .foregroundStyle(AppColors.textPlaceholder)
                TracciNumberPopIn(
                    text: settlement.displayTotal,
                    font: AppTypography.editorialNumber,
                    color: AppColors.textPrimary
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func memberBalancesSection(_ settlement: ExpenseSettlement) -> some View {
        let sorted = sortedMembers(settlement.members)

        return VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            Text("成员分摊明细")
                .font(AppTypography.buttonTitle)
                .foregroundStyle(AppColors.textPrimary)

            AppElevationCard(level: .l1, role: .content, radius: AppRadius.medium, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, member in
                        memberBalanceRow(member, currency: settlement.currency)

                        if index < sorted.count - 1 {
                            Divider().padding(.horizontal, AppSpacing.cardSmall)
                        }
                    }
                }
            }
        }
    }

    /// Sort members so the current user appears first.
    private func sortedMembers(_ members: [SettlementMember]) -> [SettlementMember] {
        guard let currentId = viewModel.currentUserMemberId else { return members }
        var sorted = members
        if let idx = sorted.firstIndex(where: { $0.memberId == currentId }), idx > 0 {
            let me = sorted.remove(at: idx)
            sorted.insert(me, at: 0)
        }
        return sorted
    }

    private func memberBalanceRow(_ member: SettlementMember, currency: String) -> some View {
        let symbol = ExpenseCurrency(rawValue: currency)?.symbol ?? ""
        let isMe = member.memberId == viewModel.currentUserMemberId
        let identityColor = MemberPalette.color(for: member.userId)

        // Share proportion relative to total (for progress bar)
        let totalGroup = viewModel.settlement?.totalGroupAmountDecimal ?? 0
        let shareFraction = totalGroup > 0
            ? min(Double(truncating: (member.shareAmountDecimal / totalGroup) as NSNumber), 1)
            : 0

        return VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.cozy) {
                // Avatar — member identity color
                Circle()
                    .fill(MemberPalette.background(for: member.userId))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(member.displayInitial)
                            .font(AppTypography.buttonTitle)
                            .foregroundStyle(identityColor)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(member.displayName)
                            .font(AppTypography.buttonTitleMedium)
                            .foregroundStyle(AppColors.textPrimary)

                        if isMe {
                            Text("我")
                                .font(AppTypography.microSemibold)
                                .foregroundStyle(AppColors.interactiveText)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                                .background(AppColors.brandPrimary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: AppSpacing.xs) {
                        Text("已付 \(ExpenseFormatters.money(member.paidAmountDecimal, symbol: symbol))")
                            .font(AppTypography.caption)
                        Text("·")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textDisabled)
                        Text("应付 \(ExpenseFormatters.money(member.shareAmountDecimal, symbol: symbol))")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.textMuted)
                }

                Spacer()

                // Balance
                VStack(alignment: .trailing, spacing: 2) {
                    Text(balanceLabel(member))
                        .font(AppTypography.chip)
                        .foregroundStyle(balanceColor(member))

                    if !member.isZeroBalance {
                        Text(ExpenseFormatters.money(abs(member.balanceAmountDecimal), symbol: symbol))
                            .font(AppTypography.listTitle)
                            .foregroundStyle(balanceColor(member))
                    }
                }
            }

            // Share proportion bar
            if totalGroup > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColors.subtleBackground)
                            .frame(height: 4)
                        Capsule()
                            .fill(identityColor.opacity(0.5))
                            .frame(width: max(4, geo.size.width * shareFraction), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, AppSpacing.cardSmall)
        .padding(.vertical, AppSpacing.md)
        .background(isMe ? AppColors.backgroundGrouped : .clear)
    }

    private func transfersSection(_ settlement: ExpenseSettlement) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("转账明细")
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("· 点击可复制提醒")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
            }

            VStack(spacing: AppSpacing.sm) {
                ForEach(settlement.suggestedTransfers) { transfer in
                    transferCard(transfer, currency: settlement.currency)
                }
            }
        }
    }

    private func transferCard(_ transfer: SuggestedTransfer, currency: String) -> some View {
        let symbol = ExpenseCurrency(rawValue: currency)?.symbol ?? ""
        let fromName = viewModel.memberName(for: transfer.fromMemberId)
        let toName = viewModel.memberName(for: transfer.toMemberId)
        let fromColor = viewModel.memberColor(for: transfer.fromMemberId)
        let toColor = viewModel.memberColor(for: transfer.toMemberId)
        let shareText = viewModel.transferShareText(for: transfer)

        let isCopied = copiedTransferIds.contains(transfer.id)

        return AppElevationCard(level: .l1, role: .content, radius: AppRadius.medium, padding: 16) {
            VStack(spacing: AppSpacing.md) {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    transferParty(name: fromName, color: fromColor)

                    VStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "arrow.right")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textPlaceholder)
                        Text(ExpenseFormatters.money(transfer.amountDecimal, symbol: symbol))
                            .font(AppTypography.editorialNumber)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)

                    transferParty(name: toName, color: toColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(fromName) 转给 \(toName) \(ExpenseFormatters.money(transfer.amountDecimal, symbol: symbol))")

                HStack {

                    Spacer()

                    Button {
                        UIPasteboard.general.string = shareText
                        AppHaptics.success()
                        copiedTransferIds.insert(transfer.id)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            copiedTransferIds.remove(transfer.id)
                        }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: isCopied ? "checkmark" : "square.and.arrow.up")
                                .font(AppTypography.labelSemibold)
                            Text(isCopied ? "已复制" : "复制提醒")
                                .font(AppTypography.label)
                        }
                        .foregroundStyle(isCopied ? AppColors.success : AppColors.brandPrimary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.tight)
                        .background(
                            isCopied
                                ? AppColors.success.opacity(0.08)
                                : AppColors.brandPrimary.opacity(0.08)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func transferParty(name: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(color)
                }
            Text(name)
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 72)
        }
        .frame(minWidth: 44)
    }

    // MARK: - Helpers

    private func balanceLabel(_ member: SettlementMember) -> String {
        if member.isPositiveBalance { return "可收回" }
        if member.isNegativeBalance { return "待支付" }
        return "已结清 ✓"
    }

    private func balanceColor(_ member: SettlementMember) -> Color {
        if member.isPositiveBalance { return AppColors.success }
        if member.isNegativeBalance { return AppColors.warning }
        return AppColors.textMuted
    }
}
