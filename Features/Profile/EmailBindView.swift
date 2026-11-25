import SwiftUI
import TracciNetworking

struct EmailBindView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EmailBindViewModel
    @FocusState private var focusedField: Field?
    @State private var otpAutoFocus = false

    private enum Field: Hashable {
        case email
    }

    init(viewModel: EmailBindViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if viewModel.bindSuccess {
                    AccountBindSuccessCard(
                        title: "邮箱绑定成功",
                        subtitle: "现在可使用该邮箱登录和找回密码"
                    )
                } else if viewModel.isCodeSent {
                    bindPasswordForm
                } else {
                    bindEmailForm
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .navigationTitle(viewModel.isCodeSent ? "验证并绑定" : "绑定邮箱")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .onDisappear { viewModel.invalidateTimer() }
        .onChange(of: viewModel.bindSuccess) { _, isSuccess in
            guard isSuccess else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            }
        }
        .onChange(of: viewModel.isCodeSent) { _, sent in
            otpAutoFocus = sent
        }
    }

    private var bindEmailForm: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            AccountBindStepHeader(
                step: 1,
                title: "输入邮箱",
                subtitle: "仅用于手机号一键登录账号首次绑定"
            )

            AccountBindFormCard {
                TracciFocusableFormField(
                    label: "邮箱地址",
                    systemImage: "envelope",
                    placeholder: "name@example.com",
                    text: $viewModel.email,
                    errorMessage: viewModel.errorMessage,
                    focus: Field.email,
                    focusedField: $focusedField,
                    textInputAutocapitalization: .never,
                    autocorrectionDisabled: true,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )

                PrimaryButton(title: "发送验证码", isLoading: viewModel.isSendingCode) {
                    focusedField = nil
                    Task { await viewModel.sendCode() }
                }
                .disabled(!viewModel.isStepOneEnabled)
                .opacity(viewModel.isStepOneEnabled ? 1 : 0.5)
            }
        }
    }

    private var bindPasswordForm: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            AccountBindStepHeader(
                step: 2,
                title: "验证并设置密码",
                subtitle: "验证码已发送至 \(AccountValidation.maskedEmail(viewModel.email))"
            )

            AccountBindFormCard {
                TracciOTPCodeField(
                    code: Binding(
                        get: { viewModel.code },
                        set: { viewModel.sanitizeCode($0) }
                    ),
                    label: "验证码",
                    errorMessage: viewModel.errorMessage,
                    autoFocus: otpAutoFocus
                )

                TracciSecureFormField(
                    label: "设置登录密码",
                    placeholder: "8-30 位，包含字母和数字",
                    text: $viewModel.password,
                    errorMessage: viewModel.password.isEmpty ? nil : viewModel.passwordValidationError,
                    textContentType: .newPassword
                )

                TracciSecureFormField(
                    label: "确认密码",
                    placeholder: "请再次输入密码",
                    text: $viewModel.confirmPassword,
                    errorMessage: viewModel.confirmPassword.isEmpty ? nil : viewModel.confirmValidationError,
                    textContentType: .newPassword
                )

                PrimaryButton(title: "确认绑定", isLoading: viewModel.isBinding) {
                    Task { await viewModel.confirmBind() }
                }
                .disabled(!viewModel.isStepTwoEnabled)
                .opacity(viewModel.isStepTwoEnabled ? 1 : 0.5)

                AccountBindResendRow(
                    canResend: viewModel.canResendCode,
                    isSending: viewModel.isSendingCode,
                    countdown: viewModel.countdown
                ) {
                    Task { await viewModel.sendCode() }
                }

                AccountBindSecondaryButton(title: "返回重新输入邮箱") {
                    viewModel.backToEmailEntry()
                }
            }
        }
    }
}

#if DEBUG
#Preview("绑定邮箱") {
    let apiClient = APIClient(config: .simulator)
    NavigationStack {
        EmailBindView(
            viewModel: EmailBindViewModel(profileService: ProfileService(apiClient: apiClient))
        )
    }
}
#endif
