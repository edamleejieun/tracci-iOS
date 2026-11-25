import SwiftUI
import UIKit

struct RegisterView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AuthViewModel()
    @FocusState private var emailFocused: Bool
    @FocusState private var nicknameFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var confirmPasswordFocused: Bool

    let authService: AuthService

    var body: some View {
        ScrollView {
            AuthPanel {
                VStack(spacing: AppSpacing.md) {
                    TracciTextField(
                        title: "邮箱",
                        text: $viewModel.email,
                        systemImage: "envelope",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        isError: viewModel.errorMessage != nil,
                        isFocused: $emailFocused
                    )

                    TracciTextField(
                        title: "昵称（可选）",
                        text: $viewModel.nickname,
                        systemImage: "person",
                        textContentType: .nickname,
                        isFocused: $nicknameFocused
                    )

                    TracciSecureField(
                        title: "密码（8-30 位，含字母和数字）",
                        text: $viewModel.password,
                        textContentType: .newPassword,
                        isError: viewModel.errorMessage != nil,
                        isFocused: $passwordFocused
                    )

                    TracciSecureField(
                        title: "确认密码",
                        text: $viewModel.confirmPassword,
                        textContentType: .newPassword,
                        isError: viewModel.errorMessage != nil,
                        isFocused: $confirmPasswordFocused
                    )

                    AuthLegalConsentRow(isOn: $viewModel.agreedToTerms)
                        .padding(.top, 2)

                    if let errorMessage = viewModel.errorMessage {
                        ErrorMessageView(message: errorMessage)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    AuthFilledButton(title: "创建账号", isLoading: viewModel.isLoading, isEnabled: viewModel.canRegister) {
                        emailFocused = false
                        nicknameFocused = false
                        passwordFocused = false
                        confirmPasswordFocused = false
                        Task {
                            await viewModel.register(authSession: authSession)
                        }
                    }
                    .padding(.top, 2)

                    SecondaryTextButton(title: "已有账号，返回登录") {
                        dismiss()
                    }
                    .frame(height: 36)
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, 22)
            .padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .tracciAtmosphere(.paper)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AuthBrandHero: View {
    let title: String
    let subtitle: String
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 18 : 22) {
            BrandLockupView(style: .primary, showsGlow: true)

            VStack(spacing: 7) {
                Text(title)
                    .font(AppFont.system(compact ? 22 : 25, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, compact ? 10 : 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct AuthPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        AppElevationCard(
            level: .l1,
            role: .content,
            radius: AppRadius.extraLarge,
            padding: AppSpacing.card
        ) {
            content
        }
    }
}

struct TracciTextField: View {
    let title: String
    @Binding var text: String
    var systemImage: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var isError: Bool = false
    var isFocused: FocusState<Bool>.Binding?

    @FocusState private var internalFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effectiveFocus: Bool {
        isFocused?.wrappedValue ?? internalFocus
    }

    private var borderColor: Color {
        if isError { return AppColors.danger.opacity(0.5) }
        if effectiveFocus { return AppColors.brandPrimary.opacity(0.5) }
        return AppColors.textDisabled.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: AppSpacing.cozy) {
            Image(systemName: systemImage)
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(isError ? AppColors.danger : (effectiveFocus ? AppColors.textSecondary : AppColors.textPlaceholder))
                .frame(width: 18)
            TextField(title, text: $text)
                .focused($internalFocus)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTypography.formValue)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, AppSpacing.cardSmall)
        .frame(height: 54)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        // 聚焦时的品牌微光 — "被溪流点亮"
        .shadow(
            color: effectiveFocus ? AppColors.brandPrimary.opacity(0.18) : .clear,
            radius: effectiveFocus ? 10 : 0,
            y: 2
        )
        .animation(AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion), value: effectiveFocus)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: isError)
        .tracciErrorShake(isError, haptic: false)
        .tracciElevation(.l0)
        .onChange(of: internalFocus) {
            isFocused?.wrappedValue = internalFocus
            if internalFocus { AppHaptics.selection() }
        }
        .onChange(of: isFocused?.wrappedValue) {
            if isFocused?.wrappedValue == true && !internalFocus { internalFocus = true }
            if isFocused?.wrappedValue == false && internalFocus { internalFocus = false }
        }
    }
}

struct TracciSecureField: View {
    let title: String
    @Binding var text: String
    var textContentType: UITextContentType?
    var isError: Bool = false
    var isFocused: FocusState<Bool>.Binding?
    @State private var isTextVisible = false
    @FocusState private var internalFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effectiveFocus: Bool {
        isFocused?.wrappedValue ?? internalFocus
    }

    private var borderColor: Color {
        if isError { return AppColors.danger.opacity(0.5) }
        if effectiveFocus { return AppColors.brandPrimary.opacity(0.5) }
        return AppColors.textDisabled.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: AppSpacing.cozy) {
            Image(systemName: "lock")
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(isError ? AppColors.danger : (effectiveFocus ? AppColors.textSecondary : AppColors.textPlaceholder))
                .frame(width: 18)

            if isTextVisible {
                TextField(title, text: $text)
                    .focused($internalFocus)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppTypography.formValue)
                    .foregroundStyle(AppColors.textPrimary)
            } else {
                SecureField(title, text: $text)
                    .focused($internalFocus)
                    .textContentType(textContentType)
                    .font(AppTypography.formValue)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Button {
                isTextVisible.toggle()
                AppHaptics.selection()
            } label: {
                Image(systemName: isTextVisible ? "eye.slash" : "eye")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, AppSpacing.cardSmall)
        .padding(.trailing, AppSpacing.cozy)
        .frame(height: 54)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        // 聚焦时的品牌微光 — "被溪流点亮"
        .shadow(
            color: effectiveFocus ? AppColors.brandPrimary.opacity(0.18) : .clear,
            radius: effectiveFocus ? 10 : 0,
            y: 2
        )
        .animation(AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion), value: effectiveFocus)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: isError)
        .tracciErrorShake(isError, haptic: false)
        .tracciElevation(.l0)
        .onChange(of: internalFocus) {
            isFocused?.wrappedValue = internalFocus
            if internalFocus { AppHaptics.selection() }
        }
        .onChange(of: isFocused?.wrappedValue) {
            if isFocused?.wrappedValue == true && !internalFocus { internalFocus = true }
            if isFocused?.wrappedValue == false && internalFocus { internalFocus = false }
        }
    }
}

struct AuthFilledButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.tight) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(AppTypography.listTitle)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isEnabled ? AppColors.brandPrimary : AppColors.textDisabled.opacity(0.75))
            .clipShape(Capsule())
            // Brand CTA glow token — not a page-card soft shadow.
            .tracciShadow(isEnabled ? AppShadow.brand : ShadowStyle(color: .clear, radius: 0, y: 0))
        }
        .disabled(isLoading || !isEnabled)
        .buttonStyle(.plain)
    }
}

struct AuthMethodButton: View {
    let systemImage: String
    let title: String
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 24)

                Text(title)
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 8)

                if let badge {
                    Text(badge)
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 5)
                        .background(AppColors.subtleSurface)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(.white)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppColors.borderDefault, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct AuthLegalConsentRow: View {
    @Binding var isOn: Bool
    @Environment(\.openURL) private var openURL

    private static let termsURL = URL(string: "https://tracci.cn/terms")!
    private static let privacyURL = URL(string: "https://tracci.cn/privacy")!

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Button {
                isOn.toggle()
                AppHaptics.selection()
            } label: {
                TracciStrokeCheckbox(isOn: isOn, size: 22)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[.bottom] - dimensions.height * 0.28
                    }
            }
            .buttonStyle(.plain)

            Text(agreementText)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .accessibilityLabel(isOn ? "已同意用户协议和隐私政策" : "未同意用户协议和隐私政策")
    }

    private var agreementText: AttributedString {
        var text = AttributedString("我已阅读并同意")
        text.foregroundColor = UIColor(AppColors.textPlaceholder)
        text.font = .systemFont(ofSize: 12)

        var terms = AttributedString("《用户协议》")
        terms.foregroundColor = UIColor(AppColors.brandPrimary)
        terms.font = .systemFont(ofSize: 12)
        terms.link = Self.termsURL

        var and = AttributedString("和")
        and.foregroundColor = UIColor(AppColors.textPlaceholder)
        and.font = .systemFont(ofSize: 12)

        var privacy = AttributedString("《隐私政策》")
        privacy.foregroundColor = UIColor(AppColors.brandPrimary)
        privacy.font = .systemFont(ofSize: 12)
        privacy.link = Self.privacyURL

        return text + terms + and + privacy
    }
}

struct ErrorMessageView: View {
    let message: String

    var body: some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: "exclamationmark.circle")
                .font(AppTypography.buttonTitleMedium)
            Text(message)
                .font(AppTypography.labelRegular)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppColors.danger)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.cozy)
        .background(AppColors.dangerBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .tracciErrorShake(message, haptic: true, onAppear: true)
    }
}
