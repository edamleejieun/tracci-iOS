import SwiftUI

struct ChangePasswordView: View {
    @Environment(AuthSession.self) private var authSession
    @State private var viewModel: ChangePasswordViewModel
    @State private var showSuccessAlert = false
    @State private var showPasswordResetSheet = false

    init(viewModel: ChangePasswordViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if viewModel.hasPassword {
                    passwordForm
                } else {
                    unavailableNotice
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .navigationTitle("修改密码")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .overlay {
            TracciNoticeSheet(
                isPresented: $showSuccessAlert,
                title: "密码修改成功",
                message: "密码已修改，所有设备需要重新登录。即将退出当前账号。",
                buttonTitle: "确定",
                onAcknowledge: {
                    Task { await authSession.logout() }
                }
            )
        }
        .onChange(of: viewModel.changeSuccess) { _, success in
            if success { showSuccessAlert = true }
        }
        .sheet(isPresented: $showPasswordResetSheet) {
            PasswordResetView(
                viewModel: PasswordResetViewModel(authService: viewModel.authService),
                context: .accountSecurity
            )
            .tracciNavigationFormSheet()
        }
    }

    // MARK: - Password Form

    private var passwordForm: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.cardSmall) {
                passwordField(title: "原密码", text: $viewModel.oldPassword, placeholder: "请输入原密码")

                Button {
                    showPasswordResetSheet = true
                } label: {
                    Text("忘记原密码？通过邮箱找回")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.interactiveText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)

                passwordField(title: "新密码", text: $viewModel.newPassword, placeholder: "8-30 位，包含字母和数字")
                passwordField(title: "确认新密码", text: $viewModel.confirmPassword, placeholder: "请再次输入新密码")

                if let validation = viewModel.validationError {
                    Text(validation)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                }

                PrimaryButton(title: "修改密码", isLoading: viewModel.isChangingPassword) {
                    Task { await viewModel.changePassword() }
                }
                .disabled(!viewModel.isChangePasswordEnabled)
            }
        }
    }

    private func passwordField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textSecondary)
            SecureField(placeholder, text: text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .textContentType(.password)
                .padding(.horizontal, AppSpacing.cardSmall)
                .frame(height: 44)
                .background(AppColors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
    }

    // MARK: - Unavailable Notice

    private var unavailableNotice: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(spacing: AppSpacing.cozy) {
                Image(systemName: "lock.slash")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(AppColors.textPlaceholder)

                Text("当前账号未设置登录密码")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("你的账号通过第三方登录，暂不支持在 iOS 端设置或修改密码。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
    }
}
