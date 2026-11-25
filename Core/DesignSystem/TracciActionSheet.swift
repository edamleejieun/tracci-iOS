import SwiftUI

// MARK: - Action Model

enum TracciActionRole {
    case normal
    case destructive
}

struct TracciActionItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var role: TracciActionRole = .normal
    let action: () -> Void
}

struct TracciChoiceItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
}

// MARK: - Presentation State

/// Root-level action sheet presenter. Attach `.tracciActionSheetHost()` on a tab or navigation root.
@MainActor
@Observable
final class TracciActionSheetPresenterState {
    var isPresented = false
    private(set) var title: String?
    private(set) var subtitle: String?
    private(set) var actions: [TracciActionItem] = []

    func present(title: String?, subtitle: String?, actions: [TracciActionItem]) {
        guard !actions.isEmpty else { return }
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

/// Root-level choice sheet presenter. Attach `.tracciChoiceSheetHost()` where pickers are used inside sheets.
@MainActor
@Observable
final class TracciChoiceSheetPresenterState {
    var isPresented = false
    private(set) var title = ""
    private(set) var subtitle: String?
    private(set) var items: [TracciChoiceItem] = []
    private(set) var selectedID: String?
    private var onSelectHandler: ((TracciChoiceItem) -> Void)?

    func present(
        title: String,
        subtitle: String? = nil,
        items: [TracciChoiceItem],
        selectedID: String?,
        onSelect: @escaping (TracciChoiceItem) -> Void
    ) {
        guard !items.isEmpty else { return }
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.selectedID = selectedID
        onSelectHandler = onSelect
        isPresented = true
    }

    func select(_ item: TracciChoiceItem) {
        onSelectHandler?(item)
        dismiss()
    }

    func dismiss() {
        isPresented = false
        onSelectHandler = nil
    }
}

// MARK: - Action Sheet Panel

struct TracciActionSheetPanel: View {
    let title: String?
    let subtitle: String?
    let actions: [TracciActionItem]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TracciPickerSheetTopChrome()

            VStack(spacing: 0) {
                if title != nil || subtitle != nil {
                    header
                        .padding(.horizontal, AppSpacing.pageX)
                        .padding(.bottom, AppSpacing.md)
                }

                TracciGroupedSurface {
                    VStack(spacing: 0) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                TracciSettingsDivider()
                            }
                            actionRow(item)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)

                Button {
                    AppHaptics.selection()
                    onDismiss()
                } label: {
                    Text("取消")
                        .font(AppFont.scaled(size: 16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 54)
                }
                .buttonStyle(TracciGroupedRowButtonStyle())
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.88), lineWidth: 0.6)
                }
                .tracciElevation(.l0)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, 12)
                .padding(.bottom, TracciDialogMetrics.bottomInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AppColors.backgroundGrouped)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, subtitle != nil {
                Text(title)
                    .font(AppTypography.editorialMeta)
                    .foregroundStyle(AppColors.textMuted)
                    .tracking(1.0)
                    .textCase(.uppercase)
            } else if let title {
                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionRow(_ item: TracciActionItem) -> some View {
        Button {
            AppHaptics.selection()
            onDismiss()
            item.action()
        } label: {
            HStack(spacing: 12) {
                TracciSettingsGlyph(
                    systemImage: item.systemImage,
                    tint: item.role == .destructive ? AppColors.danger : AppColors.brandPrimary,
                    fill: item.role == .destructive ? AppColors.dangerBackground : AppColors.brandPrimaryBackground,
                    size: 30
                )

                Text(item.title)
                    .font(AppTypography.settingsRowLabel)
                    .foregroundStyle(item.role == .destructive ? AppColors.danger : AppColors.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TracciGroupedRowButtonStyle())
    }
}

// MARK: - Choice Sheet Panel

struct TracciChoiceSheetPanel: View {
    let title: String
    let subtitle: String?
    let items: [TracciChoiceItem]
    let selectedID: String?
    let onSelect: (TracciChoiceItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TracciPickerSheetTopChrome()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.bottom, AppSpacing.md)

                TracciGroupedSurface {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                TracciSettingsDivider()
                            }
                            choiceRow(item)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.bottom, TracciDialogMetrics.bottomInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AppColors.backgroundGrouped)
    }

    private func choiceRow(_ item: TracciChoiceItem) -> some View {
        let isSelected = selectedID == item.id

        return Button {
            AppHaptics.selection()
            onSelect(item)
            onDismiss()
        } label: {
            HStack(spacing: AppSpacing.cozy) {
                TracciSettingsGlyph(
                    systemImage: item.systemImage,
                    tint: isSelected ? AppColors.brandPrimary : AppColors.textSecondary,
                    fill: isSelected ? AppColors.brandPrimaryBackground : AppColors.fillSubtle,
                    size: 30
                )

                Text(item.title)
                    .font(AppTypography.settingsRowLabel)
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textPrimary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTypography.labelSemibold)
                        .foregroundStyle(AppColors.brandPrimary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? AppColors.brandPrimary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(TracciGroupedRowButtonStyle())
    }
}

// MARK: - Host Modifiers

private struct TracciActionSheetHostModifier: ViewModifier {
    @State private var state = TracciActionSheetPresenterState()

    func body(content: Content) -> some View {
        content
            .environment(state)
            .tracciBottomSheet(
                isPresented: Binding(
                    get: { state.isPresented },
                    set: { isPresented in
                        if isPresented {
                            state.isPresented = true
                        } else {
                            state.dismiss()
                        }
                    }
                ),
                height: TracciDialogMetrics.actionSheetHeight(
                    actionCount: state.actions.count,
                    hasHeader: state.title != nil || state.subtitle != nil
                ),
                showDragBar: false
            ) {
                TracciActionSheetPanel(
                    title: state.title,
                    subtitle: state.subtitle,
                    actions: state.actions,
                    onDismiss: { state.dismiss() }
                )
            }
    }
}

private struct TracciChoiceSheetHostModifier: ViewModifier {
    @State private var state = TracciChoiceSheetPresenterState()

    func body(content: Content) -> some View {
        content
            .environment(state)
            .tracciBottomSheet(
                isPresented: Binding(
                    get: { state.isPresented },
                    set: { isPresented in
                        if isPresented {
                            state.isPresented = true
                        } else {
                            state.dismiss()
                        }
                    }
                ),
                height: TracciDialogMetrics.choiceSheetHeight(itemCount: state.items.count),
                showDragBar: false
            ) {
                TracciChoiceSheetPanel(
                    title: state.title,
                    subtitle: state.subtitle,
                    items: state.items,
                    selectedID: state.selectedID,
                    onSelect: { state.select($0) },
                    onDismiss: { state.dismiss() }
                )
            }
    }
}

// MARK: - Menu Button

struct TracciActionMenuButton<Label: View>: View {
    var title: String?
    var subtitle: String?
    let actions: [TracciActionItem]
    @ViewBuilder let label: () -> Label

    @Environment(TracciActionSheetPresenterState.self) private var actionSheet

    var body: some View {
        Button {
            AppHaptics.lightImpact()
            actionSheet.present(title: title, subtitle: subtitle, actions: actions)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Choice Trigger

struct TracciCompactChoiceTrigger: View {
    let title: String
    let value: String
    let icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.brandPrimary.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textPlaceholder)
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(AppTypography.chipSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
            .padding(.horizontal, AppSpacing.cozy)
            .frame(height: 56)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: 1)
            }
        }
        .pressableCardStyle(scale: 0.98, opacity: 0.92)
    }
}

struct TracciChoiceMenuButton: View {
    let title: String
    var subtitle: String?
    let triggerTitle: String
    let triggerValue: String
    let triggerIcon: String
    let items: [TracciChoiceItem]
    let selectedID: String?
    let onSelect: (TracciChoiceItem) -> Void

    @Environment(TracciChoiceSheetPresenterState.self) private var choiceSheet

    var body: some View {
        TracciCompactChoiceTrigger(
            title: triggerTitle,
            value: triggerValue,
            icon: triggerIcon
        ) {
            choiceSheet.present(
                title: title,
                subtitle: subtitle,
                items: items,
                selectedID: selectedID,
                onSelect: onSelect
            )
        }
    }
}

// MARK: - View Modifiers

extension View {
    /// Mount a single root-level action sheet presenter for this subtree.
    func tracciActionSheetHost() -> some View {
        modifier(TracciActionSheetHostModifier())
    }

    /// Mount a single root-level choice sheet presenter for this subtree.
    func tracciChoiceSheetHost() -> some View {
        modifier(TracciChoiceSheetHostModifier())
    }

    func tracciActionSheet(
        isPresented: Binding<Bool>,
        title: String? = nil,
        subtitle: String? = nil,
        actions: [TracciActionItem]
    ) -> some View {
        modifier(
            TracciActionSheetBindingModifier(
                isPresented: isPresented,
                title: title,
                subtitle: subtitle,
                actions: actions
            )
        )
    }

    func tracciLongPressActions(
        title: String? = nil,
        subtitle: String? = nil,
        actions: [TracciActionItem]
    ) -> some View {
        modifier(
            TracciLongPressActionModifier(
                title: title,
                subtitle: subtitle,
                actions: actions
            )
        )
    }

    func tracciChoiceSheet(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        items: [TracciChoiceItem],
        selectedID: String?,
        onSelect: @escaping (TracciChoiceItem) -> Void
    ) -> some View {
        modifier(
            TracciChoiceSheetBindingModifier(
                isPresented: isPresented,
                title: title,
                subtitle: subtitle,
                items: items,
                selectedID: selectedID,
                onSelect: onSelect
            )
        )
    }
}

private struct TracciLongPressActionModifier: ViewModifier {
    let title: String?
    let subtitle: String?
    let actions: [TracciActionItem]

    @Environment(TracciActionSheetPresenterState.self) private var actionSheet

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.45) {
                AppHaptics.mediumImpact()
                actionSheet.present(title: title, subtitle: subtitle, actions: actions)
            }
    }
}

private struct TracciActionSheetBindingModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String?
    let subtitle: String?
    let actions: [TracciActionItem]

    @Environment(TracciActionSheetPresenterState.self) private var actionSheet

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, show in
                guard show else { return }
                actionSheet.present(title: title, subtitle: subtitle, actions: actions)
            }
            .onChange(of: actionSheet.isPresented) { _, show in
                if !show, isPresented {
                    isPresented = false
                }
            }
    }
}

private struct TracciChoiceSheetBindingModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let subtitle: String?
    let items: [TracciChoiceItem]
    let selectedID: String?
    let onSelect: (TracciChoiceItem) -> Void

    @Environment(TracciChoiceSheetPresenterState.self) private var choiceSheet

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, show in
                guard show else { return }
                choiceSheet.present(
                    title: title,
                    subtitle: subtitle,
                    items: items,
                    selectedID: selectedID,
                    onSelect: onSelect
                )
            }
            .onChange(of: choiceSheet.isPresented) { _, show in
                if !show, isPresented {
                    isPresented = false
                }
            }
    }
}

#if DEBUG
#Preview("Tracci Action Sheet") {
    struct Host: View {
        @State private var show = true

        var body: some View {
            Color.clear
                .tracciPageBackground()
                .tracciActionSheetHost()
                .tracciActionSheet(
                    isPresented: $show,
                    title: "旅程操作",
                    subtitle: "京都秋日漫游",
                    actions: [
                        TracciActionItem(title: "分享行程", systemImage: "square.and.arrow.up", action: {}),
                        TracciActionItem(title: "删除行程", systemImage: "trash", role: .destructive, action: {})
                    ]
                )
        }
    }

    return Host()
}
#endif
