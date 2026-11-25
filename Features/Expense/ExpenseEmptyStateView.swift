import SwiftUI

/// Expense empty state. Primary add stays on trip-detail FAB when embedded in a day feed.
struct ExpenseEmptyStateView: View {
    /// Optional explicit add action. Prefer omitting so the view only guides to the FAB.
    var onAdd: (() -> Void)?

    var body: some View {
        if let onAdd {
            EmptyStateView(
                title: "还没有开支记录",
                subtitle: "记录第一笔开支，看看这段旅程花在哪里",
                buttonTitle: "记一笔",
                systemImage: "wallet.bifold",
                action: onAdd
            )
        } else {
            quietEmpty
        }
    }

    private var quietEmpty: some View {
        AppElevationCard(level: .l1, role: .hero, radius: AppRadius.hero, padding: 0) {
            VStack(spacing: AppSpacing.md) {
                // Same quiet leading mark as `EmptyStateView` — one symbol, no disc.
                Image(systemName: "wallet.bifold")
                    .font(AppFont.system(36, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColors.brandPrimary.opacity(0.62))
                    .frame(height: 44)
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.xs) {
                    Text("还没有开支记录")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("记录第一笔开支，看看这段旅程花在哪里")
                        .font(AppTypography.narrativeBody)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .font(AppTypography.label)
                    Text("点右下角 + 记一笔")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(AppColors.textDisabled)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.card)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("还没有开支记录。点右下角加号记一笔")
    }
}
