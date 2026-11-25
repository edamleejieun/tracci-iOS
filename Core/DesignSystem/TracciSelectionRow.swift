import SwiftUI

// MARK: - Selection Row State

enum TracciSelectionRowState: Equatable {
    case idle
    case selected
    case loading
    case error

    var accessibilityStatus: String {
        switch self {
        case .idle: return ""
        case .selected: return "已选择"
        case .loading: return "正在保存"
        case .error: return "保存失败，请重试"
        }
    }

    var allowsSelection: Bool {
        self != .loading
    }
}

// MARK: - Selection Row

/// A flat selection row for V2 Selection sheets — shows a checkmark when selected,
/// a spinner when the selection is being committed, and an error hint on failure.
///
/// Tapping commits the selection immediately (no separate Done). On failure the row
/// stays open and shows the error state so the user can retry.
///
/// Use inside a `ScrollView` within a `TracciSettingsSection` (showsSurface: false) or
/// a plain `VStack` for standalone selection sheets.
struct TracciSelectionRow: View {
    let title: String
    var systemImage: String?
    var subtitle: String?
    var state: TracciSelectionRowState = .idle
    var isEnabled = true
    var action: () -> Void

    @Environment(\.isEnabled) private var environmentIsEnabled

    private var isSelected: Bool { state == .selected }
    private var isLoading: Bool { state == .loading }
    private var hasError: Bool { state == .error }
    private var isEffectivelyEnabled: Bool { isEnabled && environmentIsEnabled }

    var body: some View {
        Button {
            guard isEffectivelyEnabled && state.allowsSelection else { return }
            AppHaptics.selection()
            action()
        } label: {
            HStack(spacing: AppSpacing.cozy) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(rowIconColor)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: AppSpacing.sm)

                trailingIndicator
            }
            .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
            .padding(.vertical, AppSpacing.settingsRowVerticalPadding)
            .frame(minHeight: AppSpacing.settingsRowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEffectivelyEnabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        switch state {
        case .idle:
            EmptyView()
        case .selected:
            Image(systemName: "checkmark")
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.brandPrimary)
        case .loading:
            ProgressView()
                .tint(AppColors.brandPrimary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.danger)
        }
    }

    private var rowIconColor: Color {
        if hasError { return AppColors.danger }
        if isSelected { return AppColors.brandPrimary }
        return AppColors.textMuted
    }

    private var accessibilityValue: String {
        [subtitle, state.accessibilityStatus]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "，")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tracci Selection Rows") {
    struct Host: View {
        @State private var selectedType = "attraction"
        @State private var loadingId: String?
        @State private var errorId: String?

        private let types: [(id: String, title: String, icon: String)] = [
            ("attraction", "景点", "mountain.2"),
            ("restaurant", "餐厅", "fork.knife"),
            ("transport", "交通", "airplane"),
            ("hotel", "住宿", "bed.double"),
            ("shopping", "购物", "bag"),
            ("other", "其他", "circle.grid.2x2"),
        ]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sectionSpacingCompact) {
                    TracciSettingsSection(title: "选择节点类型", showsSurface: false) {
                        ForEach(types, id: \.id) { type in
                            TracciSelectionRow(
                                title: type.title,
                                systemImage: type.icon,
                                state: rowState(for: type.id),
                                action: { selectType(type.id) }
                            )
                            TracciSettingsDivider()
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.vertical, AppSpacing.lg)
            }
            .tracciPageBackground()
        }

        private func rowState(for id: String) -> TracciSelectionRowState {
            if errorId == id { return .error }
            if loadingId == id { return .loading }
            if selectedType == id { return .selected }
            return .idle
        }

        private func selectType(_ id: String) {
            loadingId = id
            selectedType = id
            // Simulate commit
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                loadingId = nil
            }
        }
    }

    return Host()
}

#Preview("Tracci Selection Row States") {
    VStack(spacing: 0) {
        TracciSelectionRow(title: "默认", state: .idle, action: {})
        TracciSettingsDivider()
        TracciSelectionRow(title: "已选择", subtitle: "当前类型", state: .selected, action: {})
        TracciSettingsDivider()
        TracciSelectionRow(title: "正在保存", state: .loading, action: {})
        TracciSettingsDivider()
        TracciSelectionRow(title: "保存失败", state: .error, action: {})
        TracciSettingsDivider()
        TracciSelectionRow(title: "不可选择", isEnabled: false, action: {})
    }
    .padding(AppSpacing.pageX)
    .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
