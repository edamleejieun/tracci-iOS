import SwiftUI

struct ExpenseCategoryChartView: View {
    let breakdown: [CategoryBreakdown]
    let totalCny: Decimal

    var body: some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("花费分布")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(breakdown.count) 个分类")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                stackedBar

                VStack(spacing: AppSpacing.cozy) {
                    ForEach(breakdown) { item in
                        legendRow(for: item)
                    }
                }
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(breakdown.enumerated()), id: \.element.id) { index, item in
                    let width = max(0, geometry.size.width * item.ratio)
                    if width > 0 {
                        Rectangle()
                            .fill(categoryColor(for: item.category))
                            .frame(width: width)
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    private func categoryColor(for category: ExpenseCategory) -> Color {
        switch category {
        case .food:      AppColors.catFood
        case .transport: AppColors.catTransport
        case .hotel:     AppColors.catHotel
        case .attraction: AppColors.catAttraction
        case .shopping: AppColors.catShopping
        case .other:     AppColors.catOther
        case .custom:    Color(hex: category.colorHex)
        }
    }

    private func legendRow(for item: CategoryBreakdown) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            HStack(spacing: 9) {
                Circle()
                    .fill(categoryColor(for: item.category))
                    .frame(width: 10, height: 10)

                Text(item.category.displayName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(ExpenseFormatters.cny(item.amountCnyDecimal))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("\(item.percentInt)%")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .frame(minWidth: 38, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: 150, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
