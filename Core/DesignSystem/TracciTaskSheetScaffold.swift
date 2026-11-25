import SwiftUI
import UIKit

// MARK: - Task Sheet Scaffold

enum TracciTaskSheetDismissGesturePolicy {
    static func isDownwardDismissAttempt(_ translation: CGSize) -> Bool {
        translation.height >= 60 && abs(translation.width) < translation.height
    }
}

/// A task sheet scaffold for create/add flows — top chrome + scrollable content + page-bottom CTA.
///
/// Provides:
/// - `FormSheetTopBar` in task mode (cancel only, no save) — or a custom chrome block
/// - Scrollable content area
/// - Page-bottom CTA that remains attached to the sheet instead of the software keyboard
/// - Inline error display above the CTA
/// - Blank-tap keyboard dismissal
/// - Dirty-dismiss protection
///
/// The primary CTA lives at the bottom of the sheet, not in the top bar. It is temporarily
/// removed while the keyboard is visible instead of being lifted into a keyboard-accessory
/// position. This matches
/// the Final "创建旅程" / "添加节点" pattern where the user completes sub-tasks and the
/// bottom CTA commits the whole draft.
///
/// Present via `.tracciTaskSheet()`, or as a full-screen cover. Full-screen brand hosts
/// (Create Trip) pass a custom `chrome` block and pair the scaffold with
/// `tracciFormChromePage(presentation: .pushed)` so the canvas runs under the status bar
/// while the chrome positions itself below the safe area.
struct TracciTaskSheetScaffold<Content: View, Chrome: View>: View {
    let title: String
    var cancelTitle: String
    var ctaTitle: String
    var ctaSystemImage: String?
    var isCTAEnabled: Bool
    var isCTALoading: Bool
    var errorMessage: String?
    var isDirty: Bool
    var presentation: FormChromePresentation
    var onAttemptToDismiss: (() -> Void)?
    let onCancel: () -> Void
    let onCTA: () -> Void
    @ViewBuilder let chrome: () -> Chrome
    @ViewBuilder let content: () -> Content

    @State private var isKeyboardVisible = false

    init(
        title: String,
        cancelTitle: String = "取消",
        ctaTitle: String,
        ctaSystemImage: String? = nil,
        isCTAEnabled: Bool = true,
        isCTALoading: Bool = false,
        errorMessage: String? = nil,
        isDirty: Bool = false,
        presentation: FormChromePresentation = .sheet,
        onAttemptToDismiss: (() -> Void)? = nil,
        onCancel: @escaping () -> Void,
        onCTA: @escaping () -> Void,
        @ViewBuilder chrome: @escaping () -> Chrome,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.ctaTitle = ctaTitle
        self.ctaSystemImage = ctaSystemImage
        self.isCTAEnabled = isCTAEnabled
        self.isCTALoading = isCTALoading
        self.errorMessage = errorMessage
        self.isDirty = isDirty
        self.presentation = presentation
        self.onAttemptToDismiss = onAttemptToDismiss
        self.onCancel = onCancel
        self.onCTA = onCTA
        self.chrome = chrome
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            chrome()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded(handleHeaderDrag)
                )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                        .padding(.horizontal, AppSpacing.editorContentPadding)
                        .padding(.top, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.pageBottom)

                    if let errorMessage {
                        errorBanner(message: errorMessage)
                            .padding(.horizontal, AppSpacing.editorContentPadding)
                            .padding(.bottom, AppSpacing.lg)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isKeyboardVisible {
                TracciFixedBottomCTA(backgroundColor: AppColors.backgroundGrouped) {
                    PrimaryButton(
                        title: ctaTitle,
                        systemImage: ctaSystemImage,
                        isLoading: isCTALoading,
                        isEnabled: isCTAEnabled,
                        action: onCTA
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundGrouped)
        .tracciDismissKeyboardOnBlankTap()
        .tracciInteractiveDismissDisabled(isDirty || isCTALoading) {
            onAttemptToDismiss?()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            updateKeyboardVisibility(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            updateKeyboardVisibility(false)
        }
    }

    private func updateKeyboardVisibility(_ isVisible: Bool) {
        TracciSheetUIUpdateScheduler.afterCurrentUpdate {
            isKeyboardVisible = isVisible
        }
    }

    private func handleHeaderDrag(_ value: DragGesture.Value) {
        guard isDirty || isCTALoading,
              TracciTaskSheetDismissGesturePolicy.isDownwardDismissAttempt(value.translation) else {
            return
        }
        TracciSheetUIUpdateScheduler.afterCurrentUpdate {
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

extension TracciTaskSheetScaffold where Chrome == FormSheetTopBar {
    /// Standard task chrome: cancel-only `FormSheetTopBar`.
    init(
        title: String,
        cancelTitle: String = "取消",
        ctaTitle: String,
        ctaSystemImage: String? = nil,
        isCTAEnabled: Bool = true,
        isCTALoading: Bool = false,
        errorMessage: String? = nil,
        isDirty: Bool = false,
        presentation: FormChromePresentation = .sheet,
        onAttemptToDismiss: (() -> Void)? = nil,
        onCancel: @escaping () -> Void,
        onCTA: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            cancelTitle: cancelTitle,
            ctaTitle: ctaTitle,
            ctaSystemImage: ctaSystemImage,
            isCTAEnabled: isCTAEnabled,
            isCTALoading: isCTALoading,
            errorMessage: errorMessage,
            isDirty: isDirty,
            presentation: presentation,
            onAttemptToDismiss: onAttemptToDismiss,
            onCancel: onCancel,
            onCTA: onCTA,
            chrome: {
                FormSheetTopBar(
                    title: title,
                    cancelTitle: cancelTitle,
                    isCancelEnabled: !isCTALoading,
                    showsSaveButton: false,
                    presentation: presentation,
                    onCancel: onCancel
                )
            },
            content: content
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tracci Task Sheet") {
    struct Host: View {
        @State private var destination = "日本 · 京都"
        @State private var isSubmitting = false

        var body: some View {
            TracciTaskSheetScaffold(
                title: "创建旅程",
                ctaTitle: "创建旅程",
                ctaSystemImage: "plus",
                isCTAEnabled: !destination.isEmpty,
                isCTALoading: isSubmitting,
                onCancel: {},
                onCTA: {}
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.formFieldSpacing) {
                    Text("目的地")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)

                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textMuted)
                        Text(destination)
                            .font(AppTypography.formValue)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textDisabled)
                    }
                    .padding(.horizontal, AppSpacing.cozy)
                    .padding(.vertical, AppSpacing.sm)
                    .frame(minHeight: 48)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    Text("出行日期")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)

                    HStack {
                        Image(systemName: "calendar")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textMuted)
                        Text("2026.09.12 — 2026.09.18")
                            .font(AppTypography.formValue)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textDisabled)
                    }
                    .padding(.horizontal, AppSpacing.cozy)
                    .padding(.vertical, AppSpacing.sm)
                    .frame(minHeight: 48)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                }
            }
            .tracciTaskSheet()
        }
    }

    return Host()
}
#endif
