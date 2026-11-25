import SwiftUI

/// Form section groups related form fields with consistent spacing and visual hierarchy.
///
/// Wraps a vertical stack of form fields with a section header and L0 utility elevation
/// so create/edit sheets share the same material language as settings and secondary pages.
///
/// **Usage:**
/// ```swift
/// FormSection("基本信息") {
///     TracciFormField(label: "旅程名称", systemImage: "textformat", placeholder: "例如 东京 5 日", text: $title)
///     TracciFormPickerRow(label: "出发日期", pickerIcon: "calendar", pickerTitle: "日期", value: "2026.06.28") { }
/// }
/// ```
struct FormSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.formFieldSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.sectionEyebrow)
                    .foregroundStyle(AppColors.textSecondary)
                    .textCase(.uppercase)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .padding(.horizontal, AppSpacing.cardSmall)

            AppElevationCard(
                level: .l0,
                role: .utility,
                radius: AppRadius.large,
                padding: 0,
                showsBorder: true
            ) {
                content
            }
        }
    }
}

// MARK: - Preview

#Preview("FormSection") {
    FormSection("基本信息", subtitle: "填写旅程的基本信息") {
        TextField("旅程标题", text: .constant(""))
            .font(AppTypography.body)
            .padding(.horizontal, AppSpacing.cardSmall)
            .padding(.vertical, AppSpacing.md)

        Divider()
            .padding(.leading, AppSpacing.cardSmall)

        TextField("目的地", text: .constant(""))
            .font(AppTypography.body)
            .padding(.horizontal, AppSpacing.cardSmall)
            .padding(.vertical, AppSpacing.md)

        Divider()
            .padding(.leading, AppSpacing.cardSmall)

        TracciPickerTriggerRow(icon: "calendar", title: "出发日期", value: "2026.06.28") {}
            .padding(.horizontal, AppSpacing.cardSmall)
            .padding(.vertical, AppSpacing.md)
    }
    .padding(.vertical, AppSpacing.lg)
    .tracciPageBackground()
}
