import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var authSession
    @State private var viewModel = AuthViewModel()
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    let authService: AuthService

    var body: some View {
        ScrollView {
            AuthPanel {
                VStack(spacing: AppSpacing.md) {
                    TracciTextField(
                        title: "邮箱地址",
                        text: $viewModel.email,
                        systemImage: "envelope",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        isError: viewModel.errorMessage != nil,
                        isFocused: $emailFocused
                    )

                    TracciSecureField(
                        title: "密码",
                        text: $viewModel.password,
                        textContentType: .password,
                        isError: viewModel.errorMessage != nil,
                        isFocused: $passwordFocused
                    )

                    AuthLegalConsentRow(isOn: $viewModel.agreedToTerms)
                        .padding(.top, 2)

                    if let errorMessage = viewModel.errorMessage {
                        ErrorMessageView(message: errorMessage)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    AuthFilledButton(
                        title: "登录",
                        isLoading: viewModel.isLoading,
                        isEnabled: viewModel.canLogin
                    ) {
                        emailFocused = false
                        passwordFocused = false
                        Task {
                            await viewModel.login(authSession: authSession)
                        }
                    }
                    .padding(.top, AppSpacing.xs)

                    Text("忘记密码时，可返回入口页通过邮箱验证码重置")
                        .font(AppTypography.labelRegular)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .padding(.top, AppSpacing.cozy)
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .tracciAtmosphere(.paper)
        .navigationTitle("邮箱登录")
        .navigationBarTitleDisplayMode(.inline)
    }
}
