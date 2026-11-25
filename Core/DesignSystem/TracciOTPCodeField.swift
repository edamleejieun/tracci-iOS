import SwiftUI
import UIKit

/// Six-box OTP entry with a single hidden field so SMS autofill and paste keep working.
struct TracciOTPCodeField: View {
    @Binding var code: String
    var length: Int = 6
    var label: String = "验证码"
    var systemImage: String? = "number"
    var errorMessage: String?
    var autoFocus = false
    var onComplete: (() -> Void)?

    @FocusState private var isFieldFocused: Bool
    @State private var didFireComplete = false

    private var digits: [String] {
        let chars = Array(code)
        return (0..<length).map { index in
            index < chars.count ? String(chars[index]) : ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TracciFormMetrics.labelSpacing) {
            TracciFormLabel(title: label, systemImage: systemImage)

            ZStack {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<length, id: \.self) { index in
                        digitBox(
                            text: digits[index],
                            isActive: isFieldFocused && activeIndex == index,
                            hasError: errorMessage != nil
                        )
                    }
                }

                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFieldFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.02)
                    .accessibilityLabel(label)
                    .accessibilityValue(code.isEmpty ? "未输入" : code)
                    .accessibilityHint("输入 \(length) 位验证码")
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .onTapGesture {
                isFieldFocused = true
            }

            if let errorMessage {
                TracciFormErrorText(message: errorMessage)
            }
        }
        .tracciErrorShake(errorMessage)
        .onAppear {
            if autoFocus {
                DispatchQueue.main.async {
                    isFieldFocused = true
                }
            }
        }
        .onChange(of: code) { _, newValue in
            let sanitized = String(newValue.filter(\.isNumber).prefix(length))
            if sanitized != newValue {
                code = sanitized
                return
            }
            if sanitized.count == length {
                if !didFireComplete {
                    didFireComplete = true
                    AppHaptics.lightImpact()
                    onComplete?()
                }
            } else {
                didFireComplete = false
            }
        }
        .onChange(of: autoFocus) { _, shouldFocus in
            if shouldFocus {
                isFieldFocused = true
            }
        }
    }

    private var activeIndex: Int {
        min(code.count, length - 1)
    }

    private func digitBox(text: String, isActive: Bool, hasError: Bool) -> some View {
        Group {
            if text.isEmpty {
                Text(" ")
                    .font(AppTypography.formValueMonospaced)
                    .foregroundStyle(AppColors.textPrimary)
            } else {
                TracciNumberPopIn(
                    text: text,
                    font: AppTypography.formValueMonospaced,
                    color: AppColors.textPrimary
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
            .background(
                hasError
                    ? AppColors.dangerBackground
                    : (isActive
                        ? AppColors.brandPrimaryBackground.opacity(0.45)
                        : AppColors.subtleBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(
                        hasError
                            ? AppColors.danger.opacity(0.4)
                            : (isActive ? AppColors.brandPrimary.opacity(0.45) : AppColors.borderSubtle),
                        lineWidth: isActive || hasError ? 1.5 : 1
                    )
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("OTP") {
    struct Host: View {
        @State private var code = ""
        var body: some View {
            VStack {
                TracciOTPCodeField(code: $code, autoFocus: true)
                Text("code=\(code)")
                    .font(AppTypography.caption)
            }
            .padding()
            .tracciPageBackground()
        }
    }
    return Host()
}
#endif
