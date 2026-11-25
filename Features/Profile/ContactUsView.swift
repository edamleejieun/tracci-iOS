import SwiftUI
import UIKit

/// Contact channels page. Email first; WeChat / QQ / 小红书 can be added as rows later.
struct ContactUsView: View {
    @State private var didCopyEmail = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.cardSmall) {
                introCard
                channelsCard
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.top, AppSpacing.cardSmall)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .navigationTitle("联系我们")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationSubpage(background: AppColors.creekMistBottom)
    }

    private var introCard: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.large, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Text("需要帮助时可以联系我们")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("目前支持邮件联系。日常问题也可先走「帮助与反馈」。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var channelsCard: some View {
        VStack(spacing: 0) {
            emailChannelRow

            // Future channels (WeChat / QQ / 小红书) can append as more rows here.
        }
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
        .tracciElevation(.l0)
    }

    private var emailChannelRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "envelope")
                .font(AppTypography.listBody)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 40, height: 40)
                .background(AppColors.brandPrimaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("邮箱")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                Text(ProfileSupportLinks.supportEmailDisplay)
                    .font(AppTypography.cardBody)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: AppSpacing.sm)

            Button {
                copyEmail()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: didCopyEmail ? "checkmark" : "doc.on.doc")
                        .font(AppTypography.caption)
                    Text(didCopyEmail ? "已复制" : "复制")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(didCopyEmail ? AppColors.success : AppColors.brandPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            didCopyEmail
                                ? AppColors.successBackground
                                : AppColors.brandPrimaryBackground
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(didCopyEmail ? "已复制邮箱" : "复制邮箱")
            .accessibilityHint("将 \(ProfileSupportLinks.supportEmailDisplay) 复制到剪贴板")
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .contain)
    }

    private func copyEmail() {
        UIPasteboard.general.string = ProfileSupportLinks.supportEmailDisplay
        didCopyEmail = true
        AppHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            didCopyEmail = false
        }
    }
}

#Preview("联系我们") {
    NavigationStack {
        ContactUsView()
    }
}
