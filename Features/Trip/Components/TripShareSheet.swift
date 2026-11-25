import SwiftUI

/// 分享与协作底部弹出层
struct TripShareSheet: View {
    let tripTitle: String
    let members: [TripMemberResp]
    let onCopyLink: () -> Void
    let onInviteFriends: () -> Void
    let onExportLongImage: () -> Void
    let onDismiss: () -> Void
    /// 嵌入 `TracciBottomSheet` 时去掉自有圆角/阴影/拖拽条，避免双层 chrome。
    var embeddedInBottomSheet: Bool = true

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            if !embeddedInBottomSheet {
                Capsule()
                    .fill(AppColors.borderDefault.opacity(0.45))
                    .frame(width: 44, height: 5)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, 18)
            }

            header
                .padding(.top, embeddedInBottomSheet ? 8 : 0)

            inviteCard
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, 18)

            quickActions
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, embeddedInBottomSheet ? TracciDialogMetrics.bottomInset : max(22, SafeAreaMetrics.bottom + 12))
        }
        .frame(maxWidth: .infinity)
        .modifier(TripShareSheetChromeModifier(embeddedInBottomSheet: embeddedInBottomSheet))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.cozy) {
            VStack(alignment: .leading, spacing: 5) {
                Text("分享与协作")
                    .font(AppFont.system(22, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(tripTitle)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(1)

                if !activeMembers.isEmpty {
                    memberSummary
                        .padding(.top, AppSpacing.xs)
                }
            }

            Spacer()

            Button {
                onDismiss()
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
        }
        .padding(.horizontal, AppSpacing.pageX)
    }

    private var activeMembers: [TripMemberResp] {
        members.filter(\.isActive)
    }

    private var memberSummary: some View {
        HStack(spacing: AppSpacing.tight) {
            TripMemberAvatarStack(members: activeMembers, size: 26)

            Text("\(activeMembers.count) 位旅程成员")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
        }
    }

    private var inviteCard: some View {
        Button(action: onInviteFriends) {
            HStack(spacing: AppSpacing.cardSmall) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous)
                        .fill(AppColors.brandPrimary.opacity(0.12))
                        .frame(width: 58, height: 58)

                    Image(systemName: "person.badge.plus")
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.brandPrimary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("邀请共同编辑")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("生成邀请链接，让同行者加入这段旅程")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 32, height: 32)
                    .background(AppColors.brandPrimary.opacity(0.08))
                    .clipShape(Circle())
            }
            .padding(AppSpacing.cardSmall)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColors.brandPrimaryBackground.opacity(0.75))
            )
        }
        .buttonStyle(PressableCardStyle(scale: 0.98, opacity: 0.95))
    }

    private var quickActions: some View {
        HStack(spacing: AppSpacing.sm) {
            actionTile(icon: copied ? "checkmark" : "link", title: copied ? "已复制" : "复制链接") {
                onCopyLink()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    copied = false
                }
            }

            actionTile(icon: "doc.text.image", title: "导出行程单", action: onExportLongImage)
        }
    }

    private func actionTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppColors.brandPrimary.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous))

                Text(title)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous)
                    .stroke(AppColors.borderDefault.opacity(0.45), lineWidth: 0.7)
            }
        }
        .buttonStyle(PressableCardStyle(scale: 0.96, opacity: 0.92))
    }
}

private struct TripShareSheetChromeModifier: ViewModifier {
    let embeddedInBottomSheet: Bool

    func body(content: Content) -> some View {
        if embeddedInBottomSheet {
            content
        } else {
            content.background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
                .fill(AppColors.cardBackground)
                .tracciElevation(.l3)
            )
        }
    }
}
