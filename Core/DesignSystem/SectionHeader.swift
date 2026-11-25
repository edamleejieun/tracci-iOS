import SwiftUI

/// Section header for content grouping within a page.
///
/// Provides consistent visual rhythm across list/card screens.
/// Use between content sections to establish scanning hierarchy.
///
/// **Trailing priority:** if both `trailingText` and `action` are provided,
/// `trailingText` wins and the action button is not shown. Prefer one or the other.
///
/// **Usage:**
/// ```swift
/// SectionHeader("进行中的旅程")
///
/// SectionHeader("目的地", trailingText: "3 个")
///
/// SectionHeader("进行中的旅程", action: { /* 查看全部 */ })
/// ```
struct SectionHeader: View {
    let title: String
    var trailingText: String? = nil
    var action: (() -> Void)? = nil

    init(_ title: String, trailingText: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.trailingText = trailingText
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            // trailingText 优先于 action；两者同时传入时只展示次级计数文案。
            if let trailingText {
                Text(trailingText)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPlaceholder)
            } else if let action {
                Button(action: action) {
                    Text("查看全部")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.brandPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppSpacing.sectionHeaderBottom)
    }
}

// MARK: - Preview

#Preview("SectionHeader") {
    VStack(spacing: 0) {
        SectionHeader("进行中的旅程")

        RoundedRectangle(cornerRadius: AppRadius.large)
            .fill(AppColors.cardBackground)
            .frame(height: 120)
            .shadow(color: AppColors.border.opacity(0.3), radius: 1, y: 1)

        SectionHeader("目的地", trailingText: "3 个")

        RoundedRectangle(cornerRadius: AppRadius.large)
            .fill(AppColors.cardBackground)
            .frame(height: 80)
            .shadow(color: AppColors.border.opacity(0.3), radius: 1, y: 1)

        SectionHeader("已完成的旅程", action: {})

        RoundedRectangle(cornerRadius: AppRadius.large)
            .fill(AppColors.cardBackground)
            .frame(height: 120)
            .shadow(color: AppColors.border.opacity(0.3), radius: 1, y: 1)
    }
    .tracciPageBackground()
}
