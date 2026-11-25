import SwiftUI

// MARK: - Editor Sheet Scaffold

/// A keyboard-first editor sheet scaffold for focused single-field edits.
///
/// Provides:
/// - `FormSheetTopBar` in editor mode (cancel + 完成)
/// - Scrollable content area with consistent padding
/// - Inline error display
/// - Blank-tap keyboard dismissal
/// - Dirty-dismiss protection (pass `isDirty` to block swipe-away)
///
/// The caller is responsible for auto-focusing the field inside `content` and for
/// surfacing a confirmation dialog when a dirty dismiss is attempted.
///
/// Present via `.tracciEditorSheet()`.
struct TracciEditorSheetScaffold<Content: View>: View {
    let title: String
    var doneTitle = "完成"
    var isDoneEnabled = true
    var isSubmitting = false
    var errorMessage: String?
    var isDirty = false
    var showsDragBar = true
    var onAttemptToDismiss: (() -> Void)?
    let onCancel: () -> Void
    let onDone: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: title,
                saveTitle: doneTitle,
                isCancelEnabled: !isSubmitting,
                isSubmitting: isSubmitting,
                isSaveEnabled: isDoneEnabled,
                showsSaveButton: true,
                presentation: .sheet,
                onCancel: onCancel,
                onSave: onDone
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                        .padding(.horizontal, AppSpacing.editorContentPadding)
                        .padding(.top, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.xl)

                    if let errorMessage {
                        errorBanner(message: errorMessage)
                            .padding(.horizontal, AppSpacing.editorContentPadding)
                            .padding(.bottom, AppSpacing.lg)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundGrouped)
        .tracciDismissKeyboardOnBlankTap()
        .tracciInteractiveDismissDisabled(isDirty || isSubmitting) {
            onAttemptToDismiss?()
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.danger)
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.dangerBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tracci Editor Sheet") {
    struct Host: View {
        @State private var name = "京都秋日漫游"
        @State private var note = ""
        @State private var showError = false

        var body: some View {
            TracciEditorSheetScaffold(
                title: "编辑名称",
                isDoneEnabled: !name.isEmpty,
                isSubmitting: false,
                errorMessage: showError ? "名称不能超过 50 个字" : nil,
                isDirty: name != "京都秋日漫游",
                onCancel: {},
                onDone: {}
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("旅程名称")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)

                    TextField("", text: $name, prompt: Text("例如 东京 5 日").foregroundStyle(AppColors.textPlaceholder))
                        .font(AppTypography.formValue)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, AppSpacing.cozy)
                        .padding(.vertical, AppSpacing.sm)
                        .frame(minHeight: 48)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    Text("\(name.count)/50")
                        .font(AppTypography.caption)
                        .foregroundStyle(name.count > 50 ? AppColors.danger : AppColors.textDisabled)
                }
            }
            .tracciEditorSheet()
        }
    }

    return Host()
}
#endif
