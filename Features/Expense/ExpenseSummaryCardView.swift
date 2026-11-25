import SwiftUI

struct ExpenseSummaryCardView: View {
    let summary: ExpenseSummary?
    let todayTotal: Decimal

    var body: some View {
        AppElevationCard(level: .l2, role: .active, radius: AppRadius.extraLarge, padding: 18) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .fill(AppColors.brandPrimary.opacity(0.1))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "wallet.bifold")
                                .font(AppTypography.bodyMedium)
                                .foregroundStyle(AppColors.brandPrimary)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本次旅行花费")
                            .font(AppTypography.editorialMeta)
                            .tracking(0.6)
                            .foregroundStyle(AppColors.textMuted)
                        Text("人民币 CNY")
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("¥")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textMuted)
                    Text(totalDisplayText)
                        .font(AppTypography.editorialNumber)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                HStack(spacing: AppSpacing.sm) {
                    statColumn(
                        color: AppColors.brandPrimary,
                        label: "日均花费",
                        value: perDayDisplayText
                    )
                    statColumn(
                        color: AppColors.successForeground,
                        label: "今日花费",
                        value: todayDisplayText
                    )
                }
            }
        }
    }

    private var totalDisplayText: String {
        guard let summary else { return "0.00" }
        return ExpenseFormatters.money(summary.totalCnyDecimal)
    }

    private var perDayDisplayText: String {
        guard let summary else { return "¥0.00" }
        return ExpenseFormatters.cny(summary.perDayCnyDecimal)
    }

    private var todayDisplayText: String {
        ExpenseFormatters.cny(todayTotal)
    }

    private func statColumn(color: Color, label: String, value: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.3))
                .frame(width: 4, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppTypography.chip)
                    .foregroundStyle(AppColors.textMuted)
                Text(value)
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.cozy)
        .background(AppColors.paperWarmLight.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColors.borderSubtle.opacity(0.7), lineWidth: 0.6)
        }
    }
}
