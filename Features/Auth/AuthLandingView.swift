import SwiftUI
import TracciNetworking

// MARK: - Auth Mode

private enum AuthMode: String, CaseIterable {
    case login = "登录"
    case register = "注册"
}

// MARK: - Auth Landing View

/// Single-page auth experience centered around email login/register.
///
/// Design principles:
/// - Brand section at top with reduced density
/// - Email login/register as the primary (and currently only working) auth flow
/// - Inline form expansion: tap the email card → form animates open below
/// - Segmented toggle switches between login and register modes in-place
/// - Agreement consent lives in each flow: SDK page checkbox (phone) or form checkbox (email)
struct AuthLandingView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let authService: AuthService

    // MARK: - State

    @State private var isFormExpanded = false
    @State private var authMode: AuthMode = .login
    @State private var viewModel: AuthViewModel
    @State private var toastMessage: String?
    @State private var showsPasswordReset = false
    @Namespace private var authModeNamespace

    // MARK: - Entrance Choreography
    // 每屏 ≤2 主动画：① 品牌/溪线入场 ② CTA 区 spring

    @State private var brandVisible = false
    @State private var methodsVisible = false

    init(authService: AuthService, phoneAuthProvider: any PhoneAuthProviding) {
        self.authService = authService
        _viewModel = State(initialValue: AuthViewModel(phoneAuthProvider: phoneAuthProvider))
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    brandSection
                        .padding(.bottom, isFormExpanded ? AppSpacing.sm : AppSpacing.md)

                    if isFormExpanded {
                        formPanel
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.top, AppSpacing.sm)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        Spacer(minLength: 16)
                    } else {
                        // 把登录入口压到视觉中下区，避免小屏首屏只见插画
                        Spacer(minLength: max(28, proxy.size.height * 0.08))

                        loginMethodsGroup
                            .padding(.horizontal, AppSpacing.xl)
                            .transition(.opacity)

                        Spacer(minLength: max(24, proxy.size.height * 0.06))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tracciDismissKeyboardOnBlankTap()
        .tracciAtmosphere(.paper)
        .safeAreaPadding(.bottom, 16)
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetView(
                viewModel: PasswordResetViewModel(authService: authService),
                context: .authEntry
            )
            .tracciNavigationFormSheet()
        }
        .task {
            // Prewarm carrier prefetch + brand host + self-drawn images so present
            // can run a richer page animation without a first-frame hitch.
            await viewModel.preparePhoneLogin()
        }
        .onAppear {
            playEntranceSequence()
        }
        .overlay(alignment: .top) {
            if let message = toastMessage {
                toastView(message: message)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, 60)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
        }
    }

    // MARK: - ① Brand Section
    // 刊头：Logo + 字标（无 Slogan）+ 一条静溪线 + 能力 meta

    private var brandSection: some View {
        VStack(spacing: AppSpacing.md) {
            BrandLockupView(style: .primary, showsGlow: true)
                .opacity(brandVisible ? 1 : 0)
                .offset(y: brandVisible ? 0 : 6)
                .animation(AppMotion.animation(AppMotion.slow, reduceMotion: reduceMotion), value: brandVisible)

            if !isFormExpanded {
                // 刊头签名：S 形双层溪线（非下划线弧）
                if brandVisible {
                    CreekDivider(
                        style: .stream,
                        opacity: 0.36,
                        height: 48,
                        lineWidth: 1.9,
                        showsMidDot: true
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .transition(.opacity)
                }

                Text("规划 · 记录 · 协作 · 回忆")
                    .font(AppFont.system(12, weight: .medium))
                    .foregroundStyle(AppColors.textMuted)
                    .tracking(0.16)
                    .opacity(brandVisible ? 1 : 0)
                    .animation(AppMotion.animation(AppMotion.slow.delay(0.08), reduceMotion: reduceMotion), value: brandVisible)
                    .accessibilityLabel("规划、记录、协作、回忆")
            }
        }
        .padding(.top, isFormExpanded ? 28 : 56)
    }

    // MARK: - ② Login Methods (Collapsed)

    private var loginMethodsGroup: some View {
        VStack(spacing: AppSpacing.cozy) {
            Text("登录后即可开始规划")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .opacity(methodsVisible ? 1 : 0)
                .offset(y: methodsVisible || reduceMotion ? 0 : 6)
                .animation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion), value: methodsVisible)
                .padding(.bottom, AppSpacing.xs)

            // 主路径：本机号码一键登录（实心强调）
            LoginMethodCard(
                icon: "smartphone",
                label: viewModel.phoneLoginPhase.buttonTitle,
                isLoading: viewModel.phoneLoginPhase.isLoading,
                style: .primary
            ) {
                Task { await handlePhoneOneTapLogin() }
            }
            .disabled(viewModel.phoneLoginPhase.isLoading)
            .opacity(methodsVisible ? 1 : 0)
            .offset(y: methodsVisible || reduceMotion ? 0 : 10)
            .animation(AppMotion.animation(AppMotion.softSpring.delay(0.0), reduceMotion: reduceMotion), value: methodsVisible)

            // 次路径：邮箱登录
            LoginMethodCard(
                icon: "envelope",
                label: "邮箱登录 / 注册",
                style: .outlined
            ) {
                withAnimation(AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion)) {
                    isFormExpanded = true
                    viewModel.resetPhoneLogin()
                }
            }
            .opacity(methodsVisible ? 1 : 0)
            .offset(y: methodsVisible || reduceMotion ? 0 : 10)
            .animation(AppMotion.animation(AppMotion.softSpring.delay(0.05), reduceMotion: reduceMotion), value: methodsVisible)

            if let status = viewModel.phoneLoginPhase.statusMessage {
                PhoneLoginStatusView(
                    message: status,
                    isError: !viewModel.phoneLoginPhase.isLoading && viewModel.phoneLoginPhase != .userCancelled
                ) {
                    expandEmailLogin()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - ③ Form Panel (Expanded)

    private var formPanel: some View {
        AuthPanel {
            VStack(spacing: AppSpacing.md) {
                // 诚实返回：就地展开，不是可拖拽 sheet
                HStack {
                    Button {
                        dismissForm()
                    } label: {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "chevron.left")
                                .font(AppFont.system(13, weight: .semibold))
                            Text("返回")
                                .font(AppTypography.label)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回登录方式")

                    Spacer()
                }

                // Login / Register segmented toggle
                authModeToggle

                // Email field
                TracciTextField(
                    title: "邮箱地址",
                    text: $viewModel.email,
                    systemImage: "envelope",
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    isError: viewModel.errorMessage != nil
                )

                // Nickname field (register mode only)
                if authMode == .register {
                    TracciTextField(
                        title: "昵称（可选）",
                        text: $viewModel.nickname,
                        systemImage: "person",
                        textContentType: .nickname
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Password field
                TracciSecureField(
                    title: authMode == .login ? "密码" : "密码（8-30 位，含字母和数字）",
                    text: $viewModel.password,
                    textContentType: authMode == .login ? .password : .newPassword,
                    isError: viewModel.errorMessage != nil
                )

                if authMode == .login {
                    HStack {
                        Spacer()
                        Button {
                            showsPasswordReset = true
                        } label: {
                            Text("忘记密码？")
                                .font(AppTypography.label)
                                .foregroundStyle(AppColors.brandPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                }

                // Confirm password field (register mode only)
                if authMode == .register {
                    TracciSecureField(
                        title: "确认密码",
                        text: $viewModel.confirmPassword,
                        textContentType: .newPassword,
                        isError: viewModel.errorMessage != nil
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Agreement checkbox
                AuthLegalConsentRow(isOn: $viewModel.agreedToTerms)
                    .padding(.top, 2)

                // Error message
                if let errorMessage = viewModel.errorMessage {
                    ErrorMessageView(message: errorMessage)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Action button
                AuthFilledButton(
                    title: authMode == .login ? "登录" : "创建账号",
                    isLoading: viewModel.isLoading,
                    isEnabled: authMode == .login ? viewModel.canLogin : viewModel.canRegister
                ) {
                    handleSubmit()
                }
                .padding(.top, AppSpacing.xxs)
            }
        }
    }

    // MARK: - Auth Mode Toggle

    private var authModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(AuthMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion)) {
                        authMode = mode
                        viewModel.errorMessage = nil
                    }
                    AppHaptics.selection()
                } label: {
                    Text(mode.rawValue)
                        .font(AppFont.system(15, weight: authMode == mode ? .semibold : .medium))
                        .foregroundStyle(authMode == mode ? .white : AppColors.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            TracciSlidingSelectionPill(
                                isSelected: authMode == mode,
                                namespace: authModeNamespace,
                                fill: AppColors.brandPrimary,
                                shape: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.xxs)
        .background(AppColors.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .animation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion), value: authMode)
    }

    // MARK: - Toast

    private func toastView(message: String) -> some View {
        AppGlassSurface(radius: AppRadius.pill, padding: 0) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "info.circle.fill")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.brandPrimary)

                Text(message)
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.cardSmall)
            .padding(.vertical, AppSpacing.md)
        }
        .onTapGesture { dismissToast() }
    }

    private func showToast(_ message: String) {
        AppHaptics.lightImpact()
        withAnimation(AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            dismissToast()
        }
    }

    private func dismissToast() {
        withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
            toastMessage = nil
        }
    }

    // MARK: - Form Actions

    private func dismissForm() {
        viewModel.errorMessage = nil
        withAnimation(AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion)) {
            isFormExpanded = false
        }
    }

    private func expandEmailLogin() {
        withAnimation(AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion)) {
            authMode = .login
            isFormExpanded = true
        }
    }

    private func handleSubmit() {
        Task {
            if authMode == .login {
                await viewModel.login(authSession: authSession)
            } else {
                await viewModel.register(authSession: authSession)
            }
        }
    }

    @MainActor
    private func handlePhoneOneTapLogin() async {
        AppHaptics.lightImpact()
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            handlePhoneLoginEvent(viewModel.presenterUnavailable())
            return
        }
        handlePhoneLoginEvent(
            await viewModel.phoneOneTapLogin(
                authSession: authSession,
                presenting: rootVC
            )
        )
    }

    private func handlePhoneLoginEvent(_ event: PhoneLoginUIEvent) {
        switch event {
        case .none:
            break
        case .showToast(let message):
            showToast(message)
        case .expandEmail:
            expandEmailLogin()
        case .success:
            AppHaptics.success()
        }
    }

    // MARK: - Entrance Choreography

    /// ① 品牌/溪线入场 → ② CTA spring。总时长约 0.9s，无循环浮动。
    private func playEntranceSequence() {
        if UIAccessibility.isReduceMotionEnabled {
            brandVisible = true
            methodsVisible = true
            return
        }

        withAnimation(.easeOut(duration: 0.42).delay(0.08)) {
            brandVisible = true
        }

        withAnimation(AppMotion.softSpring.delay(0.42)) {
            methodsVisible = true
        }
    }
}

private struct PhoneLoginStatusView: View {
    let message: String
    let isError: Bool
    let fallbackAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(isError ? AppColors.danger : AppColors.textMuted)

                Text(message)
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(isError ? AppColors.danger : AppColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isError {
                Button(action: fallbackAction) {
                    Text("使用邮箱登录")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.brandPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.cozy)
        .background(isError ? AppColors.dangerBackground : AppColors.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

// MARK: - Login Method Card Button

/// 登录方式入口卡片。
/// - primary: 实心品牌色背景 + 白色文字，用于主路径（一键登录）
/// - outlined: 浅色背景 + 品牌图标，用于次路径（邮箱登录）
private struct LoginMethodCard: View {
    let icon: String
    let label: String
    var isLoading: Bool = false
    var style: CardStyle = .outlined
    let action: () -> Void

    enum CardStyle {
        case primary
        case outlined
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, AppSpacing.cardSmall)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 60)
                .background(backgroundView)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                .tracciShadow(style == .primary ? AppShadow.brand : AppShadow.level1)
        }
        .buttonStyle(PressableCardStyle())
    }

    private var content: some View {
        HStack(spacing: AppSpacing.md) {
            iconView
            labelView
            Spacer(minLength: 8)
            trailingView
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if style == .primary {
            LinearGradient(
                colors: [AppColors.brandPrimary, AppColors.brandPrimary.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            AppColors.cardBackground
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if style == .primary {
            Image(systemName: icon)
                .font(AppTypography.cardTitle)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.20), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        } else {
            Image(systemName: icon)
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 36, height: 36)
                .background(AppColors.brandPrimaryBackground, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
    }

    private var labelView: some View {
        Text(label)
            .font(AppTypography.listTitleMedium)
            .foregroundStyle(
                style == .primary
                    ? .white
                    : (isLoading ? AppColors.textMuted : AppColors.textPrimary)
            )
    }

    @ViewBuilder
    private var trailingView: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(0.8)
                .tint(style == .primary ? .white : AppColors.brandPrimary)
        } else if style == .primary {
            Image(systemName: "chevron.right")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white.opacity(0.75))
        } else {
            Image(systemName: "chevron.right")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textDisabled)
        }
    }
}

// MARK: - Preview

#Preview("Login Landing") {
    let client = APIClient()
    let service = AuthService(apiClient: client)
    let session = AuthSession(tokenStore: KeychainTokenStore())
    return AuthLandingView(
        authService: service,
        phoneAuthProvider: UnavailablePhoneAuthProvider()
    )
        .environment(session)
}
