import SwiftUI
import UIKit

// MARK: - Metrics

enum TracciFormMetrics {
    /// Minimum single-line control height at default content size (grows with Dynamic Type).
    static let fieldHeight: CGFloat = 48
    static let fieldRadius: CGFloat = AppRadius.medium
    static let labelSpacing: CGFloat = 8
    static let labelIconWidth: CGFloat = 16
    static let textAreaMinHeight: CGFloat = 108
    static let fieldHorizontalPadding: CGFloat = AppSpacing.cardSmall
    static let fieldVerticalPadding: CGFloat = 12
}

// MARK: - Label

struct TracciFormLabel: View {
    let title: String
    var systemImage: String?
    var isOptional = false

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(minWidth: TracciFormMetrics.labelIconWidth)
            }

            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)

            if isOptional {
                Text("可选")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
        }
    }
}

// MARK: - Field Chrome

private struct TracciFormFieldChrome: ViewModifier {
    let hasError: Bool
    var isFocused = false
    var isFilled = false

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous))
            .overlay {
                if hasError {
                    RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous)
                        .stroke(AppColors.danger.opacity(0.35), lineWidth: 1.5)
                } else if isFocused {
                    RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.35), lineWidth: 1)
                } else if isFilled {
                    RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.18), lineWidth: 1)
                }
            }
    }

    private var backgroundColor: Color {
        if hasError { return AppColors.dangerBackground }
        if isFocused { return AppColors.brandPrimaryBackground.opacity(0.35) }
        if isFilled { return AppColors.brandPrimaryBackground.opacity(0.25) }
        return AppColors.subtleBackground
    }
}

private extension View {
    func tracciFormFieldChrome(
        hasError: Bool,
        isFocused: Bool = false,
        isFilled: Bool = false
    ) -> some View {
        modifier(TracciFormFieldChrome(hasError: hasError, isFocused: isFocused, isFilled: isFilled))
    }
}

// MARK: - Focusable Text Field

struct TracciFocusableFormField<FocusValue: Hashable>: View {
    let label: String
    var systemImage: String?
    var placeholder: String
    @Binding var text: String
    var errorMessage: String?
    var isOptional = false
    var focus: FocusValue
    var focusedField: FocusState<FocusValue>.Binding
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?
    var usesMonospacedFont = false
    var textInputAutocapitalization: TextInputAutocapitalization?
    var autocorrectionDisabled = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    @State private var wasEmptyWhenFocused = true

    private var hasError: Bool { errorMessage != nil }
    private var isFieldFocused: Bool { focusedField.wrappedValue == focus }
    private var isFilled: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var formTextField: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundStyle(AppColors.textPlaceholder)
        )
        .focused(focusedField, equals: focus)
        .submitLabel(submitLabel)
        .onSubmit { onSubmit?() }
        .font(usesMonospacedFont ? AppTypography.formValueMonospaced : AppTypography.formValue)
        .foregroundStyle(AppColors.textPrimary)
        .keyboardType(keyboardType)
        .autocorrectionDisabled(autocorrectionDisabled)
        .textInputAutocapitalization(textInputAutocapitalization ?? .sentences)
        .textContentType(textContentType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TracciFormMetrics.labelSpacing) {
            TracciFormLabel(title: label, systemImage: systemImage, isOptional: isOptional)

            formTextField
                .padding(.horizontal, TracciFormMetrics.fieldHorizontalPadding)
                .padding(.vertical, TracciFormMetrics.fieldVerticalPadding)
                .frame(minHeight: TracciFormMetrics.fieldHeight)
                .tracciFormFieldChrome(
                    hasError: hasError,
                    isFocused: isFieldFocused,
                    isFilled: isFilled
                )

            if let errorMessage {
                TracciFormErrorText(message: errorMessage)
            }
        }
        .tracciErrorShake(errorMessage)
        .onChange(of: isFieldFocused) { _, focused in
            if focused {
                wasEmptyWhenFocused = !isFilled
            } else if wasEmptyWhenFocused && isFilled {
                AppHaptics.lightImpact()
            }
        }
    }
}

// MARK: - Text Field

struct TracciFormField: View {
    let label: String
    var systemImage: String?
    var placeholder: String
    @Binding var text: String
    var errorMessage: String?
    var isOptional = false
    var usesMonospacedFont = false
    var textInputAutocapitalization: TextInputAutocapitalization?
    var autocorrectionDisabled = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    @FocusState private var isFieldFocused: Bool
    @State private var wasEmptyWhenFocused = true

    private var hasError: Bool { errorMessage != nil }
    private var isFilled: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var formTextField: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundStyle(AppColors.textPlaceholder)
        )
        .focused($isFieldFocused)
        .font(usesMonospacedFont ? AppTypography.formValueMonospaced : AppTypography.formValue)
        .foregroundStyle(AppColors.textPrimary)
        .keyboardType(keyboardType)
        .autocorrectionDisabled(autocorrectionDisabled)
        .textInputAutocapitalization(textInputAutocapitalization ?? .sentences)
        .textContentType(textContentType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TracciFormMetrics.labelSpacing) {
            TracciFormLabel(title: label, systemImage: systemImage, isOptional: isOptional)

            formTextField
                .padding(.horizontal, TracciFormMetrics.fieldHorizontalPadding)
                .padding(.vertical, TracciFormMetrics.fieldVerticalPadding)
                .frame(minHeight: TracciFormMetrics.fieldHeight)
                .tracciFormFieldChrome(hasError: hasError, isFocused: isFieldFocused, isFilled: isFilled)

            if let errorMessage {
                TracciFormErrorText(message: errorMessage)
            }
        }
        .tracciErrorShake(errorMessage)
        .onChange(of: isFieldFocused) { _, focused in
            if focused {
                wasEmptyWhenFocused = !isFilled
            } else if wasEmptyWhenFocused && isFilled {
                AppHaptics.lightImpact()
            }
        }
    }
}

// MARK: - Text Area

struct TracciFormTextArea: View {
    let label: String
    var systemImage: String?
    var placeholder: String
    @Binding var text: String
    var errorMessage: String?
    var isOptional = false
    var isFocused = false
    var contentFocus: FocusState<Bool>.Binding?
    var minHeight: CGFloat = TracciFormMetrics.textAreaMinHeight
    var maxLength: Int?
    var showsCharacterCount = false

    @FocusState private var isEditorFocused: Bool
    @State private var wasEmptyWhenFocused = true

    private var hasError: Bool { errorMessage != nil }
    private var isFilled: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var resolvedFocused: Bool {
        isFocused || isEditorFocused || (contentFocus?.wrappedValue == true)
    }

    @ViewBuilder
    private var textEditor: some View {
        let editor = TextEditor(text: $text)
            .font(AppTypography.formValue)
            .foregroundStyle(AppColors.textPrimary)
            .scrollContentBackground(.hidden)
            .onChange(of: text) { _, newValue in
                guard let maxLength, newValue.count > maxLength else { return }
                text = String(newValue.prefix(maxLength))
            }

        if let contentFocus {
            editor.focused(contentFocus)
        } else {
            editor.focused($isEditorFocused)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TracciFormMetrics.labelSpacing) {
            TracciFormLabel(title: label, systemImage: systemImage, isOptional: isOptional)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(AppTypography.formValue)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .padding(.horizontal, AppSpacing.cardSmall)
                        .padding(.vertical, AppSpacing.md)
                }

                textEditor
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.tight)
                    .frame(minHeight: minHeight)
            }
            .tracciFormFieldChrome(hasError: hasError, isFocused: resolvedFocused, isFilled: isFilled)

            HStack {
                if let errorMessage {
                    TracciFormErrorText(message: errorMessage)
                }
                Spacer(minLength: 0)
                if showsCharacterCount, let maxLength {
                    Text("\(text.count)/\(maxLength)")
                        .font(AppTypography.caption)
                        .foregroundStyle(
                            text.count > maxLength ? AppColors.danger : AppColors.textDisabled
                        )
                }
            }
        }
        .tracciErrorShake(errorMessage)
        .onChange(of: resolvedFocused) { _, focused in
            if focused {
                wasEmptyWhenFocused = !isFilled
            } else if wasEmptyWhenFocused && isFilled {
                AppHaptics.lightImpact()
            }
        }
    }
}

// MARK: - Picker Row

struct TracciFormPickerRow: View {
    let label: String
    var systemImage: String?
    var pickerIcon: String
    let pickerTitle: String
    let value: String
    var placeholder: String = "选择"
    var isOptional = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TracciFormMetrics.labelSpacing) {
            TracciFormLabel(title: label, systemImage: systemImage, isOptional: isOptional)

            TracciPickerTriggerRow(
                icon: pickerIcon,
                title: pickerTitle,
                value: value,
                placeholder: placeholder,
                action: action
            )
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: 1)
            }
        }
    }
}

// MARK: - Secure Field

/// Password field with show/hide toggle and form field chrome.
struct TracciSecureFormField: View {
    let label: String
    var systemImage: String? = "lock"
    var placeholder: String
    @Binding var text: String
    var errorMessage: String?
    var textContentType: UITextContentType? = .password

    @State private var isRevealed = false
    @FocusState private var isFieldFocused: Bool
    @State private var wasEmptyWhenFocused = true

    private var hasError: Bool { errorMessage != nil }
    private var isFilled: Bool { !text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: TracciFormMetrics.labelSpacing) {
            TracciFormLabel(title: label, systemImage: systemImage)

            HStack(spacing: AppSpacing.xs) {
                Group {
                    if isRevealed {
                        TextField(
                            "",
                            text: $text,
                            prompt: Text(placeholder).foregroundStyle(AppColors.textPlaceholder)
                        )
                        .textContentType(textContentType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    } else {
                        SecureField(
                            "",
                            text: $text,
                            prompt: Text(placeholder).foregroundStyle(AppColors.textPlaceholder)
                        )
                        .textContentType(textContentType)
                    }
                }
                .font(AppTypography.formValue)
                .foregroundStyle(AppColors.textPrimary)
                .focused($isFieldFocused)

                Button {
                    isRevealed.toggle()
                    AppHaptics.selection()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "隐藏密码" : "显示密码")
            }
            .padding(.leading, TracciFormMetrics.fieldHorizontalPadding)
            .padding(.trailing, AppSpacing.xxs)
            .frame(minHeight: TracciFormMetrics.fieldHeight)
            .tracciFormFieldChrome(hasError: hasError, isFocused: isFieldFocused, isFilled: isFilled)

            if let errorMessage {
                TracciFormErrorText(message: errorMessage)
            }
        }
        .tracciErrorShake(errorMessage)
        .onChange(of: isFieldFocused) { _, focused in
            if focused {
                wasEmptyWhenFocused = !isFilled
            } else if wasEmptyWhenFocused && isFilled {
                AppHaptics.lightImpact()
            }
        }
    }
}

// MARK: - Error Text

struct TracciFormErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.danger)
    }
}

#if DEBUG
#Preview("Tracci Form Fields") {
    struct Host: View {
        @State private var title = ""
        @State private var note = ""
        @FocusState private var focused: Bool

        var body: some View {
            ScrollView {
                VStack(spacing: AppSpacing.formSectionSpacing) {
                    TracciFormField(
                        label: "旅程名称",
                        systemImage: "textformat",
                        placeholder: "例如 东京 5 日",
                        text: $title,
                        errorMessage: title.isEmpty ? nil : nil
                    )

                    TracciFormField(
                        label: "邀请码",
                        systemImage: "person.badge.plus",
                        placeholder: "请输入 4 位邀请码",
                        text: $title,
                        usesMonospacedFont: true,
                        textInputAutocapitalization: .characters,
                        autocorrectionDisabled: true
                    )

                    TracciFormTextArea(
                        label: "备注",
                        systemImage: "note.text",
                        placeholder: "补充一些安排细节",
                        text: $note,
                        isOptional: true,
                        maxLength: 200,
                        showsCharacterCount: true
                    )

                    TracciFormPickerRow(
                        label: "消费日期",
                        systemImage: "calendar",
                        pickerIcon: "calendar",
                        pickerTitle: "日期",
                        value: "2026年7月2日",
                        action: {}
                    )
                }
                .padding(AppSpacing.pageX)
            }
            .tracciPageBackground()
        }
    }

    return Host()
}
#endif