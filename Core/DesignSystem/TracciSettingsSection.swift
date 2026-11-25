import SwiftUI

// MARK: - Settings Section

/// White grouped list chrome on a system grouped page.
/// Soft L0 lift + a 1pt inner highlight so cards read as surfaces, not flat slabs.
struct TracciGroupedSurface<Content: View>: View {
    var radius: CGFloat = AppRadius.settingsSurface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                AppColors.groupedRowSeparator.opacity(0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            }
            .tracciElevation(.l0)
    }
}

/// Quiet glyph well for grouped rows and action lists.
struct TracciSettingsGlyph: View {
    let systemImage: String
    var tint: Color = AppColors.textSecondary
    var fill: Color = AppColors.fillSubtle
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(AppTypography.labelSemibold)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Press overlay for rows inside a clipped grouped card. Avoids scale, which shears the clip.
struct TracciGroupedRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AppColors.fillSubtle : Color.clear)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// A flat grouped section for V2 Settings pages — title + surface + inset dividers.
///
/// Unlike `FormSection` (which wraps content in a card-within-a-card), this renders a
/// flat surface where rows sit directly with inset dividers. This avoids the "card within
/// a card" anti-pattern and matches the Final Settings aesthetic.
///
/// **Only use for V2 Settings pages.** Existing forms continue to use `FormSection`.
struct TracciSettingsSection<Header: View, Content: View>: View {
    var title: String?
    var subtitle: String?
    var showsSurface = true
    var radius: CGFloat = AppRadius.settingsSurface
    @ViewBuilder var content: () -> Content
    @ViewBuilder var header: () -> Header

    init(
        title: String? = nil,
        subtitle: String? = nil,
        showsSurface: Bool = true,
        radius: CGFloat = AppRadius.settingsSurface,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsSurface = showsSurface
        self.radius = radius
        self.content = content
        self.header = header
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || subtitle != nil {
                sectionHeader
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)
            }

            header()

            if showsSurface {
                TracciGroupedSurface(radius: radius) {
                    VStack(spacing: 0) {
                        content()
                    }
                }
            } else {
                content()
            }
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(AppTypography.sectionEyebrow)
                    .foregroundStyle(AppColors.textMuted)
                    .tracking(0.6)
            }
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
            }
        }
    }
}

// MARK: - Convenience init (no header, no subtitle surface alias)

extension TracciSettingsSection where Header == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsSurface: Bool = true,
        radius: CGFloat = AppRadius.settingsSurface,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsSurface: showsSurface,
            radius: radius,
            content: content,
            header: { EmptyView() }
        )
    }
}

// MARK: - Inset Divider

/// A divider that starts at the leading edge of row content (after an optional icon).
/// Use between `TracciSettingsRow` items inside a `TracciSettingsSection`.
struct TracciSettingsDivider: View {
    var leadingInset: CGFloat = AppSpacing.settingsDividerLeadingInset

    var body: some View {
        Rectangle()
            .fill(AppColors.groupedRowSeparator)
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tracci Settings Section") {
    struct Host: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sectionSpacingCompact) {
                    TracciSettingsSection(title: "基本信息") {
                        TracciSettingsRow(label: "旅程名称", value: "京都秋日漫游", action: {})
                        TracciSettingsDivider()
                        TracciSettingsRow(label: "目的地", value: "日本 · 京都", systemImage: "mappin.and.ellipse", action: {})
                        TracciSettingsDivider()
                        TracciSettingsRow(label: "出行日期", value: "2026.09.12 — 2026.09.18", systemImage: "calendar", action: {})
                    }

                    TracciSettingsSection(title: "封面", subtitle: "更改旅程封面图片") {
                        TracciSettingsRow(label: "当前封面", value: "已设置", systemImage: "photo", action: {})
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.vertical, AppSpacing.lg)
            }
            .tracciPageBackground()
        }
    }

    return Host()
}
#endif
