import SwiftUI
import TracciNetworking

struct ProfileView: View {
    @Environment(AuthSession.self) private var authSession
    @State private var viewModel: ProfileViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLogoutConfirm = false
    @State private var isLoggingOut = false

    let authService: AuthService
    let profileService: ProfileService
    let fileUploadService: FileUploadService
    let savedPlaceService: SavedPlaceService
    /// 行程能力：为 nil 时入口资产卡仍可用，但列表页不展示「加入行程」入口。
    private let tripProvider: (any SavedPlaceTripProviding)?
    @Binding var navigationPath: NavigationPath
    var bottomTabBarContentInset: CGFloat = AppNavigationMetrics.contentInset(for: SafeAreaMetrics.bottom)
    var onRootScrollOffsetChange: (CGFloat) -> Void = { _ in }

    init(
        viewModel: ProfileViewModel,
        authService: AuthService,
        profileService: ProfileService,
        fileUploadService: FileUploadService,
        savedPlaceService: SavedPlaceService,
        tripProvider: (any SavedPlaceTripProviding)? = nil,
        navigationPath: Binding<NavigationPath>,
        bottomTabBarContentInset: CGFloat = AppNavigationMetrics.contentInset(for: SafeAreaMetrics.bottom),
        onRootScrollOffsetChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.authService = authService
        self.profileService = profileService
        self.fileUploadService = fileUploadService
        self.savedPlaceService = savedPlaceService
        self.tripProvider = tripProvider
        self.bottomTabBarContentInset = bottomTabBarContentInset
        self.onRootScrollOffsetChange = onRootScrollOffsetChange
        _viewModel = State(initialValue: viewModel)
        _navigationPath = navigationPath
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    profileToolbar

                    contentState
                        .id(profileContentKey)
                        // 与探索/回忆对齐：页头→正文 pageHeaderToContent。
                        .padding(.top, AppSpacing.pageHeaderToContent)
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                        .animation(
                            AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion),
                            value: profileContentKey
                        )

                    if !isAccountUnavailable {
                        settingsGroup
                            .fadeSlideIn(index: 1)

                        logoutButton
                            .padding(.top, AppSpacing.lg)
                            .padding(.bottom, AppSpacing.lg)
                            .fadeSlideIn(index: 2)
                    }

                    brandFooter
                        .fadeSlideIn(index: 3)
                }
                .padding(.horizontal, AppSpacing.pageX)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: RootScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("ProfileRootScroll")).minY
                        )
                    }
                }
            }
            .coordinateSpace(name: "ProfileRootScroll")
            .tracciRootScrollOffset { offset in
                guard navigationPath.isEmpty else {
                    onRootScrollOffsetChange(0)
                    return
                }
                onRootScrollOffsetChange(max(0, offset))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomTabBarContentInset)
            }
            .tracciAtmosphere(.creek)
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityElement(children: .contain)

            .refreshable {
                AppHaptics.lightImpact()
                await viewModel.refreshUser(into: authSession)
                await viewModel.loadStats()
            }
            .task {
                if authSession.currentUser == nil && !viewModel.isLoading {
                    await viewModel.loadUser(into: authSession)
                }
                await viewModel.loadStats()
                await viewModel.checkForUpdate()
            }
            .overlay {
                TracciConfirmSheet(
                    isPresented: $showLogoutConfirm,
                    tone: .caution,
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "退出登录？",
                    message: "退出后，你需要重新登录才能继续使用趣溪。",
                    confirmTitle: "退出登录",
                    confirmColor: AppColors.danger,
                    onConfirm: {
                        isLoggingOut = true
                        Task {
                            await authSession.logout()
                            isLoggingOut = false
                        }
                    }
                )
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                Group {
                    switch route {
                    case .editProfile:
                        if let user = authSession.currentUser {
                            EditProfileView(
                                viewModel: EditProfileViewModel(
                                    user: user,
                                    authService: authService,
                                    fileUploadService: fileUploadService
                                )
                            )
                        }
                    case .accountSecurity:
                        AccountSecurityView(
                            viewModel: AccountSecurityViewModel(
                                authService: authService,
                                profileService: profileService
                            )
                        )
                    case .helpFeedback:
                        HelpFeedbackView(
                            viewModel: HelpFeedbackViewModel(profileService: profileService)
                        )
                    case .legalPrivacy:
                        LegalPrivacyView()
                    case .about:
                        AboutTracciView()
                    case .version:
                        VersionInfoView(checker: viewModel.updateChecker)
                    case .contact:
                        ContactUsView()
                    case .savedPlaces:
                        SavedPlacesView(
                            service: savedPlaceService,
                            onOpenDetail: { placeId in
                                navigationPath.append(ProfileRoute.placeDetail(placeId: placeId))
                            }
                        )
                    case .placeDetail(let placeId):
                        PlaceDetailView(
                            service: savedPlaceService,
                            placeId: placeId,
                            tripProvider: tripProvider
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Page Toolbar

extension ProfileView {
    /// 页头（决策 2026-09-18）：「我的」回到普通底栏 Tab，与探索/回忆对齐的
    /// `AppTabPageHeader`（标题「我的」+ 品牌字标 trailing）。cover 模式已随头像入口一起取消。
    private var profileToolbar: some View {
        AppTabPageHeader(
            systemImage: AppTab.profile.systemImage,
            title: AppTab.profile.title,
            trailing: {
                BrandWordmarkView(
                    style: .primary,
                    size: BrandTokens.profileTopWordmarkSize
                )
                .opacity(BrandTokens.profileTopWordmarkOpacity)
            }
        )
    }
}

// MARK: - Profile Card

extension ProfileView {
    private var isAccountUnavailable: Bool {
        authSession.currentUser == nil && viewModel.errorMessage != nil
    }

    private var profileContentKey: String {
        if viewModel.isLoading && authSession.currentUser == nil {
            return "loading"
        }
        if authSession.currentUser == nil, viewModel.errorMessage != nil {
            return "error"
        }
        return "loaded"
    }

    @ViewBuilder
    private var contentState: some View {
        if viewModel.isLoading && authSession.currentUser == nil {
            profileLoadingCard
                .padding(.bottom, AppSpacing.lg)
        } else if authSession.currentUser == nil, let error = viewModel.errorMessage {
            ErrorStateView(
                title: "暂时无法读取账号信息",
                message: error,
                retryTitle: "重新加载",
                debugReloadFrameLogging: true
            ) {
                Task { await viewModel.loadUser(into: authSession) }
            }
            .padding(.bottom, AppSpacing.lg)
            .frame(minHeight: profileUnavailableStateMinHeight, alignment: .top)
        } else {
            profileCard
                .padding(.bottom, AppSpacing.lg)
        }
    }

    private var profileUnavailableStateMinHeight: CGFloat {
        360 + SafeAreaMetrics.top
    }

    private var profileLoadingCard: some View {
        AppElevationCard(level: .l1, role: .hero, radius: AppRadius.hero, padding: AppSpacing.card) {
            HStack(spacing: AppSpacing.md) {
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .fill(AppColors.subtleBackground)
                    .frame(width: 88, height: 88)
                    .overlay {
                        ProgressView()
                            .tint(AppColors.brandPrimary)
                    }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.subtleBackground)
                        .frame(width: 132, height: 18)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.subtleBackground)
                        .frame(width: 180, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.subtleBackground)
                        .frame(width: 112, height: 12)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在加载用户信息")
        }
    }

    private var profileCard: some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.hero, padding: 0) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.brandPrimary.opacity(0.08), .clear],
                            center: .topTrailing,
                            startRadius: 8,
                            endRadius: 120
                        )
                    )
                    .frame(width: 160, height: 160)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 48, y: -56)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.brandPrimaryLight.opacity(0.05), .clear],
                            center: .bottomLeading,
                            startRadius: 4,
                            endRadius: 90
                        )
                    )
                    .frame(width: 112, height: 112)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: -44, y: 44)

                HStack(alignment: .top, spacing: AppSpacing.md) {
                    avatarView
                    userInfoView
                }
                .padding(AppSpacing.card)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var avatarView: some View {
        Group {
            if let urlString = authSession.currentUser?.avatarUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        avatarContainer {
                            image.resizable().scaledToFill()
                        }
                    case .failure:
                        avatarContainer { defaultAvatar }
                    case .empty:
                        avatarContainer {
                            ProgressView()
                                .tint(AppColors.brandPrimary.opacity(0.4))
                        }
                    @unknown default:
                        avatarContainer { defaultAvatar }
                    }
                }
            } else {
                avatarContainer { defaultAvatar }
            }
        }
    }

    private func avatarContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .stroke(AppColors.cardBackground, lineWidth: 4)
            )
            .tracciElevation(.l1)
    }

    private var defaultAvatar: some View {
        ZStack {
            AppColors.subtleBackground
            Image(systemName: "person.fill")
                .font(AppFont.system(36, weight: .regular))
                .foregroundStyle(AppColors.textPlaceholder.opacity(0.5))
        }
        .frame(width: 88, height: 88)
    }

    private var userInfoView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Text(displayName)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            // MARK: 手机号展示已临时屏蔽 — 个人开发者无法申请短信服务
            // HStack(spacing: 5) {
            //     Image(systemName: "phone")
            //         .font(AppTypography.caption)
            //         .foregroundStyle(AppColors.textPlaceholder)
            //     Text(phoneDisplay)
            //         .font(AppTypography.label)
            //         .foregroundStyle(AppColors.textMuted)
            //         .lineLimit(1)
            // }

            if let joinedDisplay {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(AppTypography.microRegular)
                        .foregroundStyle(AppColors.textPlaceholder)
                    Text(joinedDisplay)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .lineLimit(1)
                }
            }

            HStack(spacing: AppSpacing.tight) {
                profileBadge(icon: loginTypeIcon, text: loginTypeDisplay)
                if let accountStatusDisplay {
                    profileBadge(icon: "checkmark.shield", text: accountStatusDisplay)
                }
            }

            if let overview = viewModel.statsOverview, overview.tripCount > 0 {
                Divider()
                    .background(AppColors.borderSubtle)
                    .padding(.top, 2)

                HStack(alignment: .top, spacing: AppSpacing.cozy) {
                    profileStatItem(value: "\(overview.tripCount)", unit: "次", label: "旅行")
                    statDivider
                    profileStatItem(value: "\(overview.totalTravelDays)", unit: "天", label: "天数")
                    statDivider
                    profileStatItem(value: "\(overview.destinationCount)", unit: "个", label: "目的地")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileStatItem(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(AppFont.system(22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Text(unit)
                    .font(AppTypography.chip)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(AppColors.textPrimary)
            .fixedSize(horizontal: true, vertical: false)

            Text(label)
                .font(AppTypography.chipRegular)
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(AppColors.borderSubtle)
            .frame(width: 1, height: 28)
    }

    private var displayName: String {
        if let nickname = authSession.currentUser?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nickname.isEmpty {
            return nickname
        }
        if let username = authSession.currentUser?.username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            return username
        }
        return authSession.currentUser == nil ? "未登录" : "旅人"
    }

    private var loginTypeDisplay: String {
        switch authSession.currentUser?.loginType {
        case "email", "EMAIL":
            return "邮箱登录"
        case "phone", "PHONE":
            return "手机号登录"
        case .some:
            return "已登录"
        case .none:
            return "未登录"
        }
    }

    private var loginTypeIcon: String {
        switch authSession.currentUser?.loginType {
        case "email", "EMAIL":
            return "envelope"
        case "phone", "PHONE":
            return "phone"
        default:
            return "person"
        }
    }

    private var accountStatusDisplay: String? {
        guard let user = authSession.currentUser else { return nil }
        if user.phoneVerified == true {
            return "手机号已验证"
        }
        return nil
    }

    private func profileBadge(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppTypography.micro)
            Text(text)
                .font(AppTypography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(AppColors.textMuted)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(AppColors.subtleBackground)
        .clipShape(Capsule())
    }

    private var joinedDisplay: String? {
        guard let createdAt = authSession.currentUser?.createdAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
        guard let date else { return nil }
        return "加入于 \(date.formatted(.dateTime.year().month(.defaultDigits)))"
    }
}

// MARK: - Settings Group

extension ProfileView {
    private var settingsGroup: some View {
        VStack(spacing: AppSpacing.lg) {
            savedPlacesEntrySection

            profileSection(title: "身份") {
                settingsRow(
                    icon: "pencil",
                    title: "编辑资料",
                    destination: .editProfile
                )
            }

            profileSection(title: "安全") {
                settingsRow(
                    icon: "shield.checkered",
                    title: "账号安全",
                    destination: .accountSecurity
                )
            }

            profileSection(title: "支持") {
                settingsRow(
                    icon: "bubble.left.and.bubble.right",
                    title: "帮助与反馈",
                    destination: .helpFeedback
                )
                Divider().background(AppColors.borderSubtle).padding(.leading, 76)
                settingsRow(
                    icon: "envelope",
                    title: "联系我们",
                    destination: .contact
                )
            }

            profileSection(title: "品牌") {
                settingsRow(
                    icon: "doc.text",
                    title: "协议与隐私",
                    destination: .legalPrivacy
                )
                Divider().background(AppColors.borderSubtle).padding(.leading, 76)
                settingsRow(
                    icon: "sparkles",
                    title: "关于趣溪",
                    destination: .about
                )
            }

            profileSection(title: "版本") {
                versionInfoRow
            }
        }
    }

    /// 「旅行」分区：想去的地点是内容资产而非设置项，
    /// 用资产卡（数量 meta + 最近地名）与下方 L0 设置行拉开层级。
    private var savedPlacesEntrySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionHeaderBottom) {
            Text("旅行")
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.horizontal, AppSpacing.xxs)

            SavedPlacesEntryCard(service: savedPlaceService) {
                navigationPath.append(ProfileRoute.savedPlaces)
            }
        }
    }

    private var versionInfoRow: some View {
        NavigationLink(value: ProfileRoute.version) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    AppColors.brandPrimaryBackground
                    Image(systemName: "app.badge.checkmark")
                        .font(AppTypography.listTitleMedium)
                        .foregroundStyle(AppColors.brandPrimary)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                Text("版本信息")
                    .font(AppTypography.cardBody)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AppSpacing.tight) {
                    Text("v\(viewModel.updateChecker.currentVersion)")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .monospacedDigit()
                    CreekStatusDot(kind: viewModel.updateChecker.status.creekDotKind)
                }

                Image(systemName: "chevron.right")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("版本信息，当前 \(viewModel.updateChecker.currentVersion)，\(viewModel.updateChecker.status.subtitle)")
        .accessibilityHint("点按进入版本信息")
    }

    private func profileSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionHeaderBottom) {
            Text(title)
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.horizontal, AppSpacing.xxs)

            AppElevationCard(
                level: .l0,
                role: .utility,
                radius: AppRadius.extraLarge,
                padding: 0
            ) {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }

    @ViewBuilder
    private func settingsRow(
        icon: String,
        title: String,
        destination: ProfileRoute?
    ) -> some View {
        if let destination {
            NavigationLink(value: destination) {
                settingsRowContent(icon: icon, title: title)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint("点按进入\(title)")
        } else {
            settingsRowContent(icon: icon, title: title)
                .opacity(0.6)
                .accessibilityLabel(title)
        }
    }

    private func settingsRowContent(
        icon: String,
        title: String
    ) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                AppColors.brandPrimaryBackground
                Image(systemName: icon)
                    .font(AppTypography.listTitleMedium)
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            Text(title)
                .font(AppTypography.cardBody)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textDisabled)
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }
}

// MARK: - Logout

extension ProfileView {
    private var logoutButton: some View {
        Button { showLogoutConfirm = true } label: {
            HStack(spacing: AppSpacing.tight) {
                if isLoggingOut {
                    ProgressView()
                        .tint(AppColors.danger)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(AppTypography.listBody)
                }
                Text("退出登录")
                    .font(AppTypography.cardBody)
            }
            .foregroundStyle(AppColors.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .tracciElevation(.l0)
        }
        .buttonStyle(.plain)
        .disabled(isLoggingOut)
        .accessibilityLabel("退出登录")
        .accessibilityHint("点击后需要二次确认")
    }
}

// MARK: - Brand Footer

extension ProfileView {
    private var brandFooter: some View {
        Text("趣溪 Tracci")
            .font(AppTypography.chipRegular)
            .foregroundStyle(AppColors.textDisabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.tight)
            .accessibilityLabel("趣溪 Tracci")
    }
}

// MARK: - Navigation Routes

enum ProfileRoute: Hashable {
    case savedPlaces
    case placeDetail(placeId: String)
    case editProfile
    case accountSecurity
    case helpFeedback
    case contact
    case legalPrivacy
    case about
    case version
}
