import SwiftUI

// MARK: - Settings Row

/// A flat grouped settings row — the basic building block of V2 Settings pages.
///
/// Mirrors the visual language of `TracciPickerTriggerRow` but tuned for read-first
/// settings surfaces: quieter chevron, no card chrome, inset within a `TracciSettingsSection`.
///
/// The entire row is a single accessibility element that reads as "标签，当前值，按钮".
/// When `action` is nil, the row is display-only and exposes no button trait.
struct TracciSettingsRow: View {
    let label: String
    var value: String?
    var systemImage: String?
    var disclosure: Bool = true
    var showsChevron: Bool = true
    var action: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled

    private var hasValue: Bool {
        guard let value else { return false }
        return !value.isEmpty
    }

    private var isInteractive: Bool {
        action != nil
    }

    var body: some View {
        rowContent
            .frame(minHeight: AppSpacing.settingsRowMinHeight)
            .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
            .padding(.vertical, AppSpacing.settingsRowVerticalPadding)
            .contentShape(Rectangle())
            .modifier(RowAccessibilityModifier(label: label, value: value, isInteractive: isInteractive))
            .modifier(RowActionModifier(action: action))
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: 10) {
            if let systemImage {
                TracciSettingsGlyph(systemImage: systemImage)
            }

            Text(label)
                .font(AppTypography.settingsRowLabel)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: AppSpacing.sm)

            if hasValue {
                Text(value ?? "")
                    .font(AppTypography.settingsRowValue)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if disclosure && showsChevron && isInteractive {
                Image(systemName: "chevron.right")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Accessibility

struct TracciSettingsRowAccessibility: Equatable {
    let label: String
    let value: String
    let hint: String

    init(label: String, value: String?, isInteractive: Bool) {
        self.label = label
        self.value = value ?? ""
        self.hint = isInteractive ? "打开\(label)" : ""
    }
}

private struct RowAccessibilityModifier: ViewModifier {
    let label: String
    let value: String?
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let accessibility = TracciSettingsRowAccessibility(
            label: label,
            value: value,
            isInteractive: isInteractive
        )
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(accessibility.value)
            .accessibilityAddTraits(isInteractive ? .isButton : [])
            .accessibilityHint(accessibility.hint)
    }
}

private struct RowActionModifier: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            Button {
                AppHaptics.selection()
                action()
            } label: {
                content
            }
            .buttonStyle(TracciGroupedRowButtonStyle())
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tracci Settings Rows") {
    struct Host: View {
        var body: some View {
            VStack(spacing: AppSpacing.lg) {
                // Grouped surface
                VStack(spacing: 0) {
                    TracciSettingsRow(label: "旅程名称", value: "京都秋日漫游", action: {})
                    divider
                    TracciSettingsRow(label: "目的地", value: "日本 · 京都", systemImage: "mappin.and.ellipse", action: {})
                    divider
                    TracciSettingsRow(label: "出行日期", value: "2026.09.12 — 2026.09.18", systemImage: "calendar", action: {})
                    divider
                    TracciSettingsRow(label: "备注", disclosure: false, action: {})
                }
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous))

                // Display-only (no action)
                VStack(spacing: 0) {
                    TracciSettingsRow(label: "创建者", value: "张三", systemImage: "person.crop.circle", disclosure: false)
                    divider
                    TracciSettingsRow(label: "创建时间", value: "2026年8月9日", disclosure: false)
                }
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous))

                // Disabled state
                TracciSettingsRow(label: "行程总览", value: "已完成", systemImage: "checkmark.circle", action: {})
                    .disabled(true)
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous))
            }
            .padding(AppSpacing.pageX)
            .tracciPageBackground()
        }

        private var divider: some View {
            Rectangle()
                .fill(AppColors.groupedRowSeparator)
                .frame(height: 0.5)
                .padding(.leading, AppSpacing.settingsDividerLeadingInset)
        }
    }

    return Host()
}
#endif
