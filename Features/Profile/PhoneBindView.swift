import SwiftUI
import TracciNetworking

struct PhoneBindView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PhoneBindViewModel
    @State private var showUnbindConfirm = false
    @State private var unbindError: String?
    @State private var feedbackToast: TracciToastMessage?
    @FocusState private var focusedField: Field?
    @State private var otpAutoFocus = false

    private enum Field: Hashable {
        case phone
    }

    init(viewModel: PhoneBindViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if viewModel.bindSuccess {
                    AccountBindSuccessCard(
                        title: viewModel.successTitle,
                        subtitle: viewModel.successSubtitle
                    )
                } else if viewModel.showsManagement {
                    managementView
                } else if viewModel.isCodeSent {
                    verifyCodeForm
                } else {
                    enterPhoneForm
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .onDisappear { viewModel.invalidateTimer() }
        .onChange(of: viewModel.bindSuccess) { _, isSuccess in
            guard isSuccess else { return }
            showUnbindConfirm = false
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            }
        }
        .onChange(of: viewModel.isCodeSent) { _, sent in
            otpAutoFocus = sent
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: $showUnbindConfirm,
                tone: .destructive,
                icon: "phone.badge.minus",
                title: "解绑手机号？",
                message: "解绑后，该手机号将不再关联到你的账号。请确保你仍有其他可用登录方式。",
                confirmTitle: "解绑",
                errorMessage: $unbindError,
                onConfirmAsync: {
                    await viewModel.unbind()
                    if viewModel.bindSuccess {
                        return true
                    }
                    unbindError = viewModel.errorMessage
                    return false
                }
            )
        }
        .tracciToast($feedbackToast, bottomPadding: 28)
    }

    private var navigationTitle: String {
        if viewModel.bindSuccess { return "手机号" }
        if viewModel.showsManagement { return "手机号管理" }
        if viewModel.isReplacing { return "更换手机号" }
        if viewModel.isCodeSent { return "验证手机号" }
        return "绑定手机号"
    }

    // MARK: - Management

    private var managementView: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            AccountBindIdentityCard(
                systemImage: "iphone",
                primaryText: AccountValidation.maskedPhone(viewModel.boundPhone),
                secondaryText: "已绑定 · 可用于登录验证"
            )

            if let error = viewModel.errorMessage {
                TracciFormErrorText(message: error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.xxs)
            }

            AccountBindActionList {
                AccountBindActionRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "更换手机号",
                    subtitle: "使用新手机号替换当前绑定",
                    showDivider: true
                ) {
                    viewModel.beginReplace()
                    focusedField = .phone
                }

                AccountBindActionRow(
                    icon: "phone.badge.minus",
                    title: "解绑手机号",
                    subtitle: "解除当前手机号的绑定",
                    showDivider: false,
                    isDestructive: true
                ) {
                    unbindError = nil
                    showUnbindConfirm = true
                }
            }
        }
    }

    // MARK: - Step 1

    private var enterPhoneForm: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            AccountBindStepHeader(
                step: 1,
                title: viewModel.isReplacing ? "输入新手机号" : "输入手机号",
                subtitle: "绑定后可用于登录验证和账号安全保护"
            )

            AccountBindFormCard {
                phoneNumberField

                if let error = viewModel.errorMessage {
                    TracciFormErrorText(message: error)
                }

                PrimaryButton(
                    title: "发送验证码",
                    isLoading: viewModel.isSendingCode
                ) {
                    focusedField = nil
                    Task { await viewModel.sendCode() }
                }
                .disabled(!viewModel.isStepOneEnabled)
                .opacity(viewModel.isStepOneEnabled ? 1 : 0.5)

                if viewModel.isReplacing {
                    AccountBindSecondaryButton(title: "返回手机号管理") {
                        viewModel.cancelReplaceOrBackToEnter()
                    }
                }
            }
        }
    }

    private var phoneNumberField: some View {
        VStack(alignment: .leading, spacing: TracciFormMetrics.labelSpacing) {
            TracciFormLabel(title: "手机号", systemImage: "iphone")

            HStack(spacing: AppSpacing.sm) {
                Text(AccountValidation.chinaCountryCode)
                    .font(AppTypography.formValueMonospaced)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, AppSpacing.cozy)
                    .frame(minHeight: TracciFormMetrics.fieldHeight)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous)
                            .stroke(AppColors.borderSubtle, lineWidth: 1)
                    }
                    .accessibilityLabel("区号 +86")

                TextField(
                    "",
                    text: Binding(
                        get: { viewModel.nationalNumber },
                        set: { viewModel.sanitizeNationalNumber($0) }
                    ),
                    prompt: Text("11 位手机号").foregroundStyle(AppColors.textPlaceholder)
                )
                .font(AppTypography.formValueMonospaced)
                .foregroundStyle(AppColors.textPrimary)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .focused($focusedField, equals: .phone)
                .padding(.horizontal, TracciFormMetrics.fieldHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: TracciFormMetrics.fieldHeight, alignment: .leading)
                .background(
                    viewModel.errorMessage != nil
                        ? AppColors.dangerBackground
                        : (focusedField == .phone
                            ? AppColors.brandPrimaryBackground.opacity(0.35)
                            : AppColors.subtleBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TracciFormMetrics.fieldRadius, style: .continuous)
                        .stroke(
                            viewModel.errorMessage != nil
                                ? AppColors.danger.opacity(0.35)
                                : (focusedField == .phone
                                    ? AppColors.brandPrimary.opacity(0.35)
                                    : Color.clear),
                            lineWidth: focusedField == .phone || viewModel.errorMessage != nil ? 1.5 : 0
                        )
                }
            }
        }
        .tracciErrorShake(viewModel.isCodeSent ? nil : viewModel.errorMessage)
    }

    // MARK: - Step 2

    private var verifyCodeForm: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            AccountBindStepHeader(
                step: 2,
                title: "输入验证码",
                subtitle: "验证码已发送至 \(AccountValidation.maskedPhone(viewModel.fullPhone))"
            )

            AccountBindFormCard {
                TracciOTPCodeField(
                    code: Binding(
                        get: { viewModel.code },
                        set: { viewModel.sanitizeCode($0) }
                    ),
                    label: "短信验证码",
                    errorMessage: viewModel.errorMessage,
                    autoFocus: otpAutoFocus,
                    onComplete: {
                        guard viewModel.isStepTwoEnabled else { return }
                        Task { await viewModel.confirmBind() }
                    }
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

                AccountBindSecondaryButton(title: "返回重新输入手机号") {
                    viewModel.cancelReplaceOrBackToEnter()
                }
            }
        }
    }
}

#if DEBUG
#Preview("绑定手机号") {
    let apiClient = APIClient(config: .simulator)
    NavigationStack {
        PhoneBindView(
            viewModel: PhoneBindViewModel(profileService: ProfileService(apiClient: apiClient))
        )
    }
}

#Preview("手机号管理") {
    let apiClient = APIClient(config: .simulator)
    NavigationStack {
        PhoneBindView(
            viewModel: PhoneBindViewModel(
                profileService: ProfileService(apiClient: apiClient),
                boundPhone: "+8613812345678"
            )
        )
    }
}
#endif
