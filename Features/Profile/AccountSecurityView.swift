import SwiftUI

struct AccountSecurityView: View {
    @Environment(AuthSession.self) private var authSession
    @State private var viewModel: AccountSecurityViewModel

    @State private var showDeleteAccountSheet = false
    @State private var navigateToChangePassword = false
    @State private var navigateToEmailBind = false
    @State private var navigateToPhoneBind = false

    init(viewModel: AccountSecurityViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.cardSmall) {
                securityStatusCard
                if viewModel.isLoadingSecurity && viewModel.securityStatus == nil {
                    InlineLoadingStateView(message: "正在读取账号安全信息", verticalPadding: 28)
                } else if let error = viewModel.securityError, viewModel.securityStatus == nil {
                    ErrorStateView(
                        title: "账号安全信息加载失败",
                        message: error,
                        retryTitle: "重新加载"
                    ) {
                        Task { await viewModel.reloadStatus() }
                    }
                } else {
                    securitySettingsList
                    dangerZoneCard
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.cardSmall)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .navigationTitle("账号安全")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
        .task {
            await viewModel.loadSecurityStatus()
        }
        .navigationDestination(isPresented: $navigateToChangePassword) {
            ChangePasswordView(
                viewModel: ChangePasswordViewModel(
                    authService: viewModel.authService,
                    hasPassword: viewModel.hasPassword
                )
            )
        }
        .navigationDestination(isPresented: $navigateToEmailBind) {
            EmailBindView(
                viewModel: EmailBindViewModel(profileService: viewModel.profileService)
            )
            .onDisappear {
                if viewModel.securityStatus != nil {
                    Task { await viewModel.reloadStatus() }
                }
            }
        }
        .navigationDestination(isPresented: $navigateToPhoneBind) {
            PhoneBindView(
                viewModel: PhoneBindViewModel(
                    profileService: viewModel.profileService,
                    boundPhone: viewModel.securityStatus?.phone
                )
            )
            .onDisappear {
                if viewModel.securityStatus != nil {
                    Task { await viewModel.reloadStatus() }
                }
            }
        }
        .sheet(isPresented: $showDeleteAccountSheet, onDismiss: {
            if !viewModel.deleteSuccess {
                viewModel.resetDeleteFlow()
            }
        }) {
            deleteAccountSheet
                .tracciFormSheet()
        }
    }

    // MARK: - Security Overview

    private var securityStatusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    AppColors.brandPrimaryBackground
                    Image(systemName: "shield.checkered")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.brandPrimary)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("账号安全")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("查看登录邮箱，管理手机号和登录密码")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(2)
                }
            }

            if viewModel.isLoadingSecurity {
                ProgressView()
                    .tint(AppColors.brandPrimary)
                    .padding(.top, AppSpacing.md)
            } else if let error = viewModel.securityError {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
                    .padding(.top, AppSpacing.md)
            }
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
        .tracciElevation(.l0)
    }

    private var securitySettingsList: some View {
        VStack(spacing: 0) {
            securityRow(
                icon: "envelope",
                title: "邮箱",
                value: emailRowValue,
                action: emailRowAction,
                isChecked: viewModel.securityStatus?.email?.isEmpty == false,
                onTap: canBindEmail ? { navigateToEmailBind = true } : nil
            )

            divider

            securityRow(
                icon: "smartphone",
                title: "手机号",
                value: phoneRowValue,
                action: viewModel.securityStatus?.phone == nil ? "去绑定" : "管理",
                isChecked: viewModel.securityStatus?.phoneVerified == true,
                onTap: { navigateToPhoneBind = true }
            )

            divider

            securityRow(
                icon: "key",
                title: "登录密码",
                value: viewModel.hasPassword ? "已设置" : "未设置密码",
                action: viewModel.hasPassword ? "修改" : "暂不支持",
                isChecked: viewModel.hasPassword,
                onTap: viewModel.hasPassword ? handlePasswordRowTap : nil
            )
        }
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
        .tracciElevation(.l0)
    }

    @ViewBuilder
    private func securityRow(
        icon: String,
        title: String,
        value: String,
        action: String,
        isChecked: Bool,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let isTappable = onTap != nil
        let content = HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppTypography.listBody)
                .foregroundStyle(AppColors.textMuted)
                .frame(width: 40, height: 40)
                .background(AppColors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.cardBody)
                        .foregroundStyle(AppColors.textPrimary)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(AppFont.system(9, weight: .bold))
                            .foregroundStyle(AppColors.success)
                            .frame(width: 16, height: 16)
                            .background(AppColors.success.opacity(0.15))
                            .clipShape(Circle())
                    }
                }

                Text(value)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isTappable {
                Text(action)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.interactiveText)
                Image(systemName: "chevron.right")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textDisabled)
            } else {
                Text(action)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textDisabled)
            }
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.md)
        .opacity(isPassiveAction(action) ? 0.78 : 1)

        if let onTap {
            Button(action: onTap) {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    // MARK: - Danger

    private var dangerZoneCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Text("危险操作")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.horizontal, AppSpacing.xxs)

            Button {
                viewModel.resetDeleteFlow()
                showDeleteAccountSheet = true
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "trash")
                        .font(AppTypography.listBody)
                        .foregroundStyle(AppColors.danger)
                        .frame(width: 40, height: 40)
                        .background(AppColors.danger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("注销账号")
                            .font(AppTypography.cardBody)
                            .foregroundStyle(AppColors.danger)
                        Text("永久删除账号和所有数据")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger.opacity(0.7))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.danger.opacity(0.4))
                }
                .padding(.horizontal, AppSpacing.card)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, AppSpacing.tight)
    }

    // MARK: - Delete Account Sheet

    private var deleteAccountSheet: some View {
        VStack(spacing: 0) {
            TracciPickerSheetTopChrome()
            deleteAccountSheetHeader
                .padding(.horizontal, AppSpacing.pageX)

            ScrollView {
                Group {
                    switch viewModel.deleteStep {
                    case .confirm:
                        deleteConfirmStepContent
                    case .reason:
                        deleteReasonStepContent
                    case .verify:
                        deleteVerifyStepContent
                    case .final:
                        deleteFinalStepContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.cardSmall)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            deleteStepFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.pageBackground)
        .tracciDismissKeyboardOnBlankTap()
        .onChange(of: viewModel.deleteSuccess) { _, success in
            if success {
                showDeleteAccountSheet = false
                authSession.clear()
            }
        }
    }

    private var deleteAccountSheetHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            HStack(alignment: .top, spacing: AppSpacing.cozy) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.danger)
                    .frame(width: 40, height: 40)
                    .background(AppColors.dangerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous))

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("注销账号")
                        .font(AppTypography.pickerSheetTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(deleteStepLabel)
                        .font(AppTypography.pickerSheetSubtitle)
                        .foregroundStyle(AppColors.textMuted)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: AppSpacing.xs) {
                ForEach(0..<DeleteAccountStep.allCases.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= deleteStepIndex ? AppColors.danger : AppColors.borderSubtle)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("步骤 \(deleteStepIndex + 1)，共 \(DeleteAccountStep.allCases.count) 步")
        }
    }

    private var deleteStepIndex: Int {
        switch viewModel.deleteStep {
        case .confirm: return 0
        case .reason: return 1
        case .verify: return 2
        case .final: return 3
        }
    }

    private var deleteStepLabel: String {
        switch viewModel.deleteStep {
        case .confirm: return "注销账号 · 风险确认"
        case .reason: return "注销账号 · 原因反馈"
        case .verify: return "注销账号 · 身份验证"
        case .final: return "注销账号 · 最终确认"
        }
    }

    private var deleteConfirmStepContent: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            deleteWarningHeader(title: "确定要注销账号吗？", subtitle: "注销后，以下数据将被永久删除且无法恢复")

            VStack(spacing: AppSpacing.sm) {
                deletedDataRow(icon: "map", text: "所有旅行记录")
                deletedDataRow(icon: "wallet.pass", text: "开支和统计数据")
                deletedDataRow(icon: "photo", text: "日志和照片")
                deletedDataRow(icon: "person", text: "个人资料和设置")
            }
            .padding(AppSpacing.md)
            .background(AppColors.dangerBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }

    private var deleteReasonStepContent: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            sheetTitle("告诉我们你离开的原因", subtitle: "你的反馈将帮助我们改进产品")

            VStack(spacing: AppSpacing.sm) {
                ForEach(DeleteReason.allCases) { reason in
                    Button {
                        viewModel.deleteReason = reason
                    } label: {
                        HStack(spacing: AppSpacing.cozy) {
                            Image(systemName: viewModel.deleteReason == reason ? "checkmark.circle.fill" : "circle")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(viewModel.deleteReason == reason ? AppColors.brandPrimary : AppColors.textDisabled)
                            Text(reason.title)
                                .font(AppTypography.cardBody)
                                .foregroundStyle(viewModel.deleteReason == reason ? AppColors.brandPrimary : AppColors.textPrimary)
                            Spacer()
                        }
                        .padding(AppSpacing.cozy)
                        .background(viewModel.deleteReason == reason ? AppColors.brandPrimaryBackground : AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.deleteReason == .other {
                    TextField("请简单说明原因", text: $viewModel.customDeleteReason)
                        .font(AppTypography.body)
                        .padding(.horizontal, AppSpacing.md)
                        .frame(height: 44)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }
            }
        }
    }

    private var deleteVerifyStepContent: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            sheetTitle("验证你的身份", subtitle: viewModel.hasPassword ? "请输入登录密码，并输入 DELETE 确认" : "请输入 DELETE 确认注销账号")

            VStack(spacing: AppSpacing.cozy) {
                if viewModel.hasPassword {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("登录密码")
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.textSecondary)
                        SecureField("请输入密码", text: $viewModel.deletePassword)
                            .font(AppTypography.body)
                            .textContentType(.password)
                            .padding(.horizontal, AppSpacing.cardSmall)
                            .frame(height: 44)
                            .background(AppColors.subtleBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("输入 DELETE 确认")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("DELETE", text: $viewModel.deleteConfirmText)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.danger)
                        .textInputAutocapitalization(.characters)
                        .padding(.horizontal, AppSpacing.cardSmall)
                        .frame(height: 44)
                        .background(AppColors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        .onChange(of: viewModel.deleteConfirmText) { _, newValue in
                            viewModel.deleteConfirmText = newValue.uppercased()
                        }
                }
            }

            // MARK: 短信验证码提示已临时屏蔽 — 个人开发者无法申请短信服务
            // Text("当前版本没有短信验证码接口，因此不会伪造验证码流程。")
            //     .font(AppTypography.caption)
            //     .foregroundStyle(AppColors.textPlaceholder)
        }
    }

    private var deleteFinalStepContent: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            sheetTitle("最后一步", subtitle: "请确认你已了解注销后果，此操作不可撤销", titleColor: AppColors.danger)

            Button {
                viewModel.deleteFinalAgreed.toggle()
                viewModel.deleteError = nil
            } label: {
                HStack(alignment: .top, spacing: AppSpacing.cozy) {
                    Image(systemName: viewModel.deleteFinalAgreed ? "checkmark.square.fill" : "square")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(viewModel.deleteFinalAgreed ? AppColors.danger : AppColors.danger.opacity(0.4))
                    Text("我确认注销账号，了解所有数据将被永久删除且无法恢复，包括旅行记录、开支数据、日志照片等。")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(AppSpacing.cardSmall)
                .background(AppColors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)

            if let error = viewModel.deleteError {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
            }
        }
    }

    @ViewBuilder
    private var deleteStepFooter: some View {
        VStack(spacing: AppSpacing.cozy) {
            switch viewModel.deleteStep {
            case .confirm:
                destructiveSheetButton("我已了解，继续注销") {
                    viewModel.deleteStep = .reason
                }
                neutralSheetButton("我再想想") {
                    showDeleteAccountSheet = false
                }
            case .reason:
                HStack(spacing: AppSpacing.cozy) {
                    neutralSheetButton("返回") {
                        viewModel.deleteStep = .confirm
                    }
                    destructiveSheetButton("下一步", isEnabled: viewModel.isDeleteReasonSelected) {
                        viewModel.deleteStep = .verify
                    }
                }
            case .verify:
                HStack(spacing: AppSpacing.cozy) {
                    neutralSheetButton("返回") {
                        viewModel.deleteStep = .reason
                    }
                    destructiveSheetButton(
                        "下一步",
                        isEnabled: viewModel.deleteConfirmText == "DELETE" && (!viewModel.hasPassword || !viewModel.deletePassword.isEmpty)
                    ) {
                        viewModel.deleteStep = .final
                    }
                }
            case .final:
                HStack(spacing: AppSpacing.cozy) {
                    neutralSheetButton("返回") {
                        viewModel.deleteStep = .verify
                    }
                    destructiveSheetButton("确认注销", isEnabled: viewModel.isDeleteEnabled, isLoading: viewModel.isDeletingAccount) {
                        Task { await viewModel.deleteAccount() }
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.cozy)
        .padding(.bottom, AppSpacing.pickerFooterBottom)
        .background(AppColors.pageBackground)
    }

    private func deleteWarningHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.system(24, weight: .medium))
                .foregroundStyle(AppColors.danger)
                .frame(width: 52, height: 52)
                .background(AppColors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            sheetTitle(title, subtitle: subtitle)
        }
    }

    private func sheetTitle(_ title: String, subtitle: String, titleColor: Color = AppColors.textPrimary) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.cardTitle)
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func deletedDataRow(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.cozy) {
            Image(systemName: icon)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.danger)
                .frame(width: 24, height: 24)
                .background(AppColors.danger.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
            Spacer()
        }
    }

    private func destructiveSheetButton(
        _ title: String,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(AppTypography.cardBody)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isEnabled ? AppColors.danger : AppColors.textDisabled)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .disabled(!isEnabled || isLoading)
        .buttonStyle(.plain)
    }

    private func neutralSheetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.cardBody)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppColors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emailRowValue: String {
        guard let email = viewModel.securityStatus?.email, !email.isEmpty else {
            return "未使用邮箱登录"
        }
        return AccountValidation.maskedEmail(email)
    }

    private var emailRowAction: String {
        guard let email = viewModel.securityStatus?.email, !email.isEmpty else {
            return canBindEmail ? "去绑定" : "未设置"
        }
        return "邮箱登录"
    }

    private var canBindEmail: Bool {
        viewModel.securityStatus?.email?.isEmpty != false
            && authSession.currentUser?.loginType == "PHONE_ONE_TAP"
    }

    /*
     FUTURE（待产品确认）：已有邮箱的换绑入口。
     当前邮箱行保持只读；确认换绑产品与 API 契约后，可在这里增加独立导航，
     但不要复用 canBindEmail 或首次绑定页面直接覆盖现有邮箱。
     */

    private var phoneRowValue: String {
        guard let phone = viewModel.securityStatus?.phone, !phone.isEmpty else {
            return "未绑定"
        }
        let masked = AccountValidation.maskedPhone(phone)
        if viewModel.securityStatus?.phoneVerified == true {
            return "\(masked) · 已验证"
        }
        return "\(masked) · 未验证"
    }

    private func handlePasswordRowTap() {
        navigateToChangePassword = true
    }

    private func isPassiveAction(_ action: String) -> Bool {
        action == "暂未开放" || action == "暂不支持"
    }

    private var divider: some View {
        Divider()
            .background(AppColors.borderSubtle)
            .padding(.leading, 76)
    }
}
