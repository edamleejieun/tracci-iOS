import SwiftUI
import TracciNetworking

struct CreateInvitationView: View {
    @Environment(\.dismiss) private var dismiss

    let tripTitle: String
    let viewModel: CollaborationViewModel
    var onClose: (() -> Void)? = nil

    @State private var selectedRole: TripMemberRole = .editor
    @State private var copiedCode = false
    @State private var copiedLink = false

    var body: some View {
        VStack(spacing: 0) {
            TracciPickerSheetTopChrome()
            sheetHeader

            ScrollView {
                if let invitation = viewModel.createdInvitation {
                    invitationResultContent(invitation)
                } else {
                    createFormContent
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.cardBackground)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: AppSpacing.cozy) {
            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.createdInvitation == nil ? "邀请好友" : "邀请码已生成")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("「\(tripTitle)」")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 34, height: 34)
                    .background(AppColors.subtleBackground)
                    .clipShape(Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.bottom, AppSpacing.cardSmall)
    }

    // MARK: - Create Form

    private var createFormContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cardSmall) {
            roleSelectionSection

            if let error = viewModel.invitationError {
                errorBanner(error)
            }

            generateButton
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.bottom, sheetBottomInset)
    }

    private var roleSelectionSection: some View {
        FormSection("授予角色", subtitle: "选择同行者加入后的权限") {
            VStack(spacing: AppSpacing.tight) {
                roleOptionRow(role: .editor)
                roleOptionRow(role: .viewer)
            }
            .padding(AppSpacing.card)
        }
    }

    private var generateButton: some View {
        Button {
            Task {
                let result = await viewModel.createInvitation(roleToGrant: selectedRole)
                if result != nil {
                    AppHaptics.mediumImpact()
                } else {
                    AppHaptics.error()
                }
            }
        } label: {
            HStack(spacing: AppSpacing.tight) {
                if viewModel.isCreatingInvitation {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "link.badge.plus")
                        .font(AppTypography.buttonTitle)
                }
                Text(viewModel.isCreatingInvitation ? "生成中..." : "生成邀请码")
                    .font(AppTypography.listTitle)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.isCreatingInvitation ? AppColors.textDisabled : AppColors.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        }
        .disabled(viewModel.isCreatingInvitation)
        .buttonStyle(.plain)
    }

    private func roleOptionRow(role: TripMemberRole) -> some View {
        Button {
            selectedRole = role
            AppHaptics.selection()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: role.icon)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(selectedRole == role ? AppColors.brandPrimary : AppColors.textMuted)
                    .frame(width: 32, height: 32)
                    .background(selectedRole == role ? AppColors.brandPrimary.opacity(0.12) : AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.label)
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(role == .editor ? "可编辑行程、日志、开支" : "仅可查看旅程内容")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }

                Spacer(minLength: 8)

                Image(systemName: selectedRole == role ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(selectedRole == role ? AppColors.brandPrimary : AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.cozy)
            .padding(.vertical, 11)
            .background(selectedRole == role ? AppColors.brandPrimary.opacity(0.06) : AppColors.subtleBackground.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(
                        selectedRole == role ? AppColors.brandPrimary.opacity(0.3) : AppColors.borderDefault.opacity(0.45),
                        lineWidth: selectedRole == role ? 1 : 0.7
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Invitation Result

    private func invitationResultContent(_ invitation: TripInvitationResp) -> some View {
        VStack(spacing: AppSpacing.md) {
            VStack(spacing: AppSpacing.tight) {
                Text(invitation.inviteCode)
                    .font(AppFont.system(36, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.brandPrimary)
                    .textSelection(.enabled)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("授予 \(TripMemberRole(rawValue: invitation.roleToGrant)?.label ?? invitation.roleToGrant) · 复制邀请码或链接发送给好友")
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(AppColors.brandPrimary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))

            copyButton(
                title: copiedCode ? "已复制邀请码" : "复制邀请码",
                icon: copiedCode ? "checkmark" : "doc.on.doc",
                isPrimary: true,
                isCopied: copiedCode
            ) {
                UIPasteboard.general.string = invitation.inviteCode
                copiedCode = true
                AppHaptics.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    copiedCode = false
                }
            }

            copyButton(
                title: copiedLink ? "已复制链接" : "复制链接",
                icon: copiedLink ? "checkmark" : "link",
                isPrimary: false,
                isCopied: copiedLink
            ) {
                UIPasteboard.general.string = invitation.inviteURL
                copiedLink = true
                AppHaptics.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    copiedLink = false
                }
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.bottom, sheetBottomInset)
    }

    // MARK: - Shared UI

    private var sheetBottomInset: CGFloat {
        max(20, SafeAreaMetrics.bottom + 10)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.labelSemibold)
            .foregroundStyle(AppColors.textMuted)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.danger)
            Text(error)
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.cozy)
        .background(AppColors.dangerBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private func copyButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        isCopied: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: icon)
                    .font(AppTypography.bodySemibold)
                Text(title)
                    .font(AppTypography.buttonTitle)
            }
            .foregroundStyle(isPrimary ? .white : (isCopied ? AppColors.success : AppColors.brandPrimary))
            .frame(maxWidth: .infinity)
            .frame(height: isPrimary ? 50 : 44)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                        .fill(isCopied ? AppColors.success : AppColors.brandPrimary)
                } else {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(isCopied ? AppColors.success.opacity(0.08) : AppColors.brandPrimary.opacity(0.08))
                }
            }
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(isCopied ? AppColors.success.opacity(0.3) : AppColors.brandPrimary.opacity(0.2), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Create Invitation Form") {
    Color.gray.opacity(0.2)
        .sheet(isPresented: .constant(true)) {
            CreateInvitationView(
                tripTitle: "京都秋日漫游",
                viewModel: CollaborationViewModel(
                    tripId: "trip-preview",
                    tripTitle: "京都秋日漫游",
                    collaborationService: CollaborationService(apiClient: APIClient()),
                    currentUserId: "user-1"
                )
            )
        }
}
