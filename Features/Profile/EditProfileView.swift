import PhotosUI
import SwiftUI
import TracciNetworking

struct EditProfileView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: EditProfileViewModel
    @State private var avatarItem: PhotosPickerItem?
    @State private var showBirthDatePicker = false
    @State private var showGenderPicker = false

    init(viewModel: EditProfileViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.sectionSpacing) {
                avatarHero
                profileInfoCard
                signatureCard
                privacyNote
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.pageTop)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .navigationTitle("编辑资料")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.save(into: authSession) }
                } label: {
                    saveToolbarLabel
                }
                .disabled(viewModel.isSaving || !viewModel.isSaveEnabled)
            }
        }
        .onChange(of: avatarItem) { _, newItem in
            guard let newItem else { return }
            Task { await viewModel.processAvatarItem(newItem) }
        }
        .onChange(of: viewModel.saveSuccess) { _, success in
            if success {
                AppHaptics.success()
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showBirthDatePicker) {
            TracciBirthDatePickerSheet(initialDate: viewModel.birthDate) { selected in
                viewModel.birthDate = selected
            }
        }
        .sheet(isPresented: $showGenderPicker) {
            TracciGenderPickerSheet(currentGender: viewModel.gender) { selected in
                viewModel.gender = selected
            }
        }
    }

    // MARK: - Avatar Hero

    private var avatarHero: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            // Decorative background + avatar, centered together
            ZStack {
                Circle()
                    .fill(AppColors.brandPrimaryBackground)
                    .frame(width: 120, height: 120)

                Circle()
                    .stroke(AppColors.brandPrimary.opacity(0.12), lineWidth: 2)
                    .frame(width: 112, height: 112)

                avatarImage
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                            .strokeBorder(.white, lineWidth: 4)
                    }
                    .tracciElevation(.l1)
            }
            // Camera button pinned to bottom-trailing of the decorative circle
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(
                    selection: $avatarItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "camera.fill")
                        .font(AppTypography.label)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(AppColors.brandPrimary)
                        .clipShape(Circle())
                        .tracciElevation(.l1)
                }
                .offset(x: 6, y: 6)
            }
            .padding(.top, AppSpacing.tight)

            // Upload status
            if viewModel.isUploadingAvatar {
                HStack(spacing: AppSpacing.xs) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在上传头像...")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }
            } else {
                Text("点击更换头像")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let uiImage = viewModel.localAvatarImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let urlString = viewModel.avatarUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    avatarPlaceholder
                case .empty:
                    ZStack {
                        avatarPlaceholder
                        ProgressView()
                            .tint(AppColors.brandPrimary.opacity(0.4))
                    }
                @unknown default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            AppColors.subtleBackground
            Image(systemName: "person.fill")
                .font(AppTypography.emptyIcon)
                .foregroundStyle(AppColors.textPlaceholder.opacity(0.4))
        }
    }

    // MARK: - Profile Info Card

    private var profileInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section: Basic Info
            cardSectionHeader(icon: "person.text.rectangle", title: "基本资料")
                .padding(.horizontal, AppSpacing.card)
                .padding(.top, AppSpacing.card)
                .padding(.bottom, AppSpacing.sectionHeaderBottom)

            nicknameRow

            // Divider between sections
            cardSectionDivider

            // Section: Personal Info
            cardSectionHeader(icon: "info.circle", title: "个人信息")
                .padding(.horizontal, AppSpacing.card)
                .padding(.top, AppSpacing.card)
                .padding(.bottom, AppSpacing.sectionHeaderBottom)

            genderRow
            cardRowDivider
            birthDateRow

            // Bottom inset
            Color.clear.frame(height: 4)
        }
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.borderHighlight, AppColors.borderSubtle.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .tracciElevation(.l0)
    }

    // MARK: Section Header (inside card)

    private func cardSectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: icon)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 18)

            Text(title)
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: Dividers

    private var cardSectionDivider: some View {
        // Full-width separator between sections with breathing room
        VStack(spacing: 0) {
            Color.clear.frame(height: AppSpacing.sm)
            Divider()
                .overlay(AppColors.groupedRowSeparator)
            Color.clear.frame(height: AppSpacing.sm)
        }
    }

    private var cardRowDivider: some View {
        Divider()
            .overlay(AppColors.groupedRowSeparator)
            .padding(.leading, rowDividerLeading)
    }

    /// Leading inset for row dividers — aligns with text after icon + padding.
    private var rowDividerLeading: CGFloat {
        AppSpacing.card + rowIconSize + AppSpacing.sm
    }

    // MARK: - Basic Info Row

    private var nicknameRow: some View {
        HStack(spacing: AppSpacing.sm) {
            rowIcon(systemName: "person", color: AppColors.brandPrimary)

            VStack(alignment: .leading, spacing: 3) {
                Text("昵称")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                TextField("请输入昵称", text: $viewModel.nickname)
                    .font(AppTypography.cardBody)
                    .foregroundStyle(AppColors.textPrimary)
                    .onChange(of: viewModel.nickname) { _, newValue in
                        if newValue.count > 50 {
                            viewModel.nickname = String(newValue.prefix(50))
                        }
                        viewModel.validationError = nil
                    }
            }

            Spacer(minLength: 0)

            // Character count
            if !viewModel.nickname.isEmpty {
                Text("\(viewModel.nickname.count)/50")
                    .font(AppTypography.caption)
                    .foregroundStyle(viewModel.nickname.count > 40 ? AppColors.warning : AppColors.textDisabled)
            }
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.md)
        .frame(minHeight: rowMinHeight)
    }

    // MARK: - Personal Info Rows

    private var genderRow: some View {
        Button {
            showGenderPicker = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                rowIcon(systemName: "person.fill", color: AppColors.textMuted)

                VStack(alignment: .leading, spacing: 3) {
                    Text("性别")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                    Text(viewModel.gender.displayName)
                        .font(AppTypography.cardBody)
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .frame(minHeight: rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle(scale: AppMotion.pressScale, opacity: AppMotion.pressOpacity))
        .accessibilityLabel("性别，\(viewModel.gender.displayName)")
        .accessibilityHint("打开性别选择器")
    }

    private var birthDateRow: some View {
        Button {
            showBirthDatePicker = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                rowIcon(systemName: "calendar", color: AppColors.textMuted)

                VStack(alignment: .leading, spacing: 3) {
                    Text("出生年月")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                    Text(birthDateDisplay.isEmpty ? "选择" : birthDateDisplay)
                        .font(AppTypography.cardBody)
                        .foregroundStyle(birthDateDisplay.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .frame(minHeight: rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle(scale: AppMotion.pressScale, opacity: AppMotion.pressOpacity))
        .accessibilityLabel("出生年月，\(birthDateDisplay.isEmpty ? "未选择" : birthDateDisplay)")
        .accessibilityHint("打开出生年月选择器")
    }

    private var birthDateDisplay: String {
        guard let date = viewModel.birthDate else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    // MARK: - Shared Row Components

    private func rowIcon(systemName: String, color: Color = AppColors.textMuted) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(color.opacity(0.10))
            Image(systemName: systemName)
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(color)
        }
        .frame(width: rowIconSize, height: rowIconSize)
    }

    private let rowIconSize: CGFloat = 36
    private let rowMinHeight: CGFloat = 56

    // MARK: - Signature Card

    private var signatureCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            signatureHeader
            signatureField
            signatureFooter
        }
        .padding(AppSpacing.card)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.borderHighlight, AppColors.borderSubtle.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .tracciElevation(.l0)
    }

    private var signatureHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            ZStack {
                AppColors.brandPrimaryBackground
                Image(systemName: "quote.bubble")
                    .font(AppTypography.buttonTitleMedium)
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("旅行宣言")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
                Text("让旅程报告里有你的态度")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
        }
    }

    private var signatureField: some View {
        TextField("写一句你的旅行态度，例如「慢走Citywalker」", text: $viewModel.signature, axis: .vertical)
            .font(AppTypography.cardBody)
            .foregroundStyle(viewModel.signature.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)
            .lineLimit(2...4)
            .padding(.horizontal, AppSpacing.cozy)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppColors.subtleBackground)
            )
            .onChange(of: viewModel.signature) { _, newValue in
                if newValue.count > 60 {
                    viewModel.signature = String(newValue.prefix(60))
                }
                viewModel.validationError = nil
            }
    }

    private var signatureFooter: some View {
        HStack(spacing: AppSpacing.xxs) {
            Spacer()
            if viewModel.signature.count > 50 {
                Image(systemName: "exclamationmark.circle")
                    .font(AppTypography.microRegular)
                    .foregroundStyle(AppColors.warning)
            }
            Text("还可以输入 \(max(0, 60 - viewModel.signature.count)) 字")
                .font(AppTypography.caption)
                .foregroundStyle(viewModel.signature.count > 50 ? AppColors.warning : AppColors.textPlaceholder)
        }
    }

    // MARK: - Save Toolbar

    @ViewBuilder
    private var saveToolbarLabel: some View {
        if viewModel.isSaving {
            ProgressView()
                .tint(AppColors.brandPrimary)
        } else {
            Text("保存")
                .font(AppTypography.buttonTitle)
                .foregroundStyle(viewModel.isSaveEnabled ? AppColors.brandPrimary : AppColors.textDisabled)
        }
    }

    // MARK: - Privacy Note

    private var privacyNote: some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: "lock.fill")
                .font(AppTypography.micro)
                .foregroundStyle(AppColors.textDisabled)

            Text("个人资料仅用于展示，不会公开分享给其他用户")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, AppSpacing.cardSmall)
    }
}

// MARK: - Preview

#Preview("EditProfile - Default") {
    let config = NetworkConfig.simulator
    let apiClient = APIClient(config: config)
    let authService = AuthService(apiClient: apiClient)
    let fileUploadService = FileUploadService(apiClient: apiClient)

    let mockViewModel = EditProfileViewModel(
        user: User(
            id: "user-1",
            username: "traveler",
            email: "travelt@example.com",
            phone: nil,
            phoneVerified: nil,
            nickname: "旅行者小明",
            avatarFileId: nil,
            avatarObjectKey: nil,
            avatarUrl: nil,
            createdAt: "2026-01-01T08:00:00Z",
            loginType: "EMAIL",
            signature: "慢走Citywalker",
            gender: "MALE",
            birthDate: "1995-06"
        ),
        authService: authService,
        fileUploadService: fileUploadService
    )

    NavigationStack {
        EditProfileView(viewModel: mockViewModel)
            .environment(AuthSession(
                tokenStore: KeychainTokenStore()
            ))
    }
}
