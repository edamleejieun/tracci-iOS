import SwiftUI

enum PasswordResetContext {
    case authEntry
    case accountSecurity
}

struct PasswordResetView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PasswordResetViewModel
    @State private var showSuccessAlert = false
    let context: PasswordResetContext

    init(
        viewModel: PasswordResetViewModel,
        context: PasswordResetContext = .accountSecurity
    ) {
        _viewModel = State(initialValue: viewModel)
        self.context = context
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if viewModel.resetSuccess {
                        successView
                    } else if viewModel.isCodeSent {
                        resetPasswordForm
                    } else {
                        sendCodeForm
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.pageBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .tracciDismissKeyboardOnBlankTap()
            .tracciPageBackground()
            .navigationTitle("找回密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(context == .authEntry ? "完成" : "关闭") { dismiss() }
                        .font(AppTypography.buttonTitleMedium)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .onDisappear { viewModel.invalidateTimer() }
            .overlay {
                TracciNoticeSheet(
                    isPresented: $showSuccessAlert,
                    title: "密码重置成功",
                    message: "密码已重置，请使用新密码登录。",
                    onAcknowledge: handleResetSuccessAcknowledged
                )
            }
            .onChange(of: viewModel.resetSuccess) { _, success in
                if success { showSuccessAlert = true }
            }
        }
    }

    // MARK: - Step 1: Send Code

    private var sendCodeForm: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.cardSmall) {
                Text("输入邮箱，我们会发送 6 位验证码用于重置密码。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("邮箱地址")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("请输入邮箱", text: $viewModel.email)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, AppSpacing.cardSmall)
                        .frame(height: 44)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }

                if let error = viewModel.errorMessage {
                    inlineError(error)
                }

                if let success = viewModel.successMessage {
                    inlineSuccess(success)
                }

                PrimaryButton(
                    title: viewModel.canResendCode
                        ? "发送验证码"
                        : "\(viewModel.countdown)s 后重发",
                    isLoading: viewModel.isSendingCode
                ) {
                    Task { await viewModel.sendCode() }
                }
                .disabled(!viewModel.isStepOneEnabled)
            }
        }
    }

    // MARK: - Step 2: Reset Password

    private var resetPasswordForm: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.cardSmall) {
                Text("验证码已发送至 \(viewModel.maskedEmail)")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("验证码")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("请输入 6 位验证码", text: $viewModel.code)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, AppSpacing.cardSmall)
                        .frame(height: 44)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("新密码")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    SecureField("8-30 位，包含字母和数字", text: $viewModel.newPassword)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .textContentType(.newPassword)
                        .padding(.horizontal, AppSpacing.cardSmall)
                        .frame(height: 44)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }

                if let error = viewModel.passwordValidationError {
                    inlineError(error)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("确认新密码")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    SecureField("请再次输入新密码", text: $viewModel.confirmPassword)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .textContentType(.newPassword)
                        .padding(.horizontal, AppSpacing.cardSmall)
                        .frame(height: 44)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }

                if let error = viewModel.confirmValidationError {
                    inlineError(error)
                }

                if let error = viewModel.errorMessage {
                    inlineError(error)
                }

                if let success = viewModel.successMessage {
                    inlineSuccess(success)
                }

                PrimaryButton(title: "重置密码", isLoading: viewModel.isResetting) {
                    Task { await viewModel.resetPassword() }
                }
                .disabled(!viewModel.isStepTwoEnabled)

                Button {
                    viewModel.resetForm()
                } label: {
                    Text("返回重新输入邮箱")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Success

    private var successView: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(spacing: AppSpacing.cardSmall) {
                TracciSuccessCheck(size: 48)

                Text("密码重置成功")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("请使用新密码登录你的账号")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)

                if context == .authEntry {
                    PrimaryButton(title: "返回登录") {
                        dismiss()
                    }
                    .padding(.top, AppSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Image(systemName: "exclamationmark.circle")
                .font(AppTypography.bodyMedium)
            Text(message)
                .font(AppTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppColors.danger)
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.dangerBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }

    private func inlineSuccess(_ message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Image(systemName: "checkmark.circle")
                .font(AppTypography.bodyMedium)
            Text(message)
                .font(AppTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppColors.success)
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.success.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }

    private func handleResetSuccessAcknowledged() {
        if context == .accountSecurity {
            Task { await authSession.logout() }
        } else {
            dismiss()
        }
    }
}
