import SwiftUI

// MARK: - Step header

struct AccountBindStepHeader: View {
    let step: Int
    var total: Int = 2
    let title: String
    let subtitle: String
    var accent: Color = AppColors.brandPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? accent : AppColors.borderSubtle)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("步骤 \(step)，共 \(total) 步")

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("第 \(step) 步 · \(title)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xxs)
    }
}

// MARK: - Bound identity card

struct AccountBindIdentityCard: View {
    let systemImage: String
    let primaryText: String
    let secondaryText: String

    var body: some View {
        AppElevationCard(level: .l1, role: .active, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            HStack(spacing: AppSpacing.cozy) {
                Image(systemName: systemImage)
                    .font(AppTypography.listBody)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppColors.brandPrimaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryText)
                        .font(AppTypography.cardBody)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(secondaryText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Management actions

struct AccountBindActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var showDivider = true
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: icon)
                        .font(AppTypography.listBody)
                        .foregroundStyle(isDestructive ? AppColors.danger : AppColors.brandPrimary)
                        .frame(width: 40, height: 40)
                        .background((isDestructive ? AppColors.danger : AppColors.brandPrimary).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AppTypography.cardBody)
                            .foregroundStyle(isDestructive ? AppColors.danger : AppColors.textPrimary)
                        Text(subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .padding(.horizontal, AppSpacing.card)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())

                if showDivider {
                    Divider()
                        .background(AppColors.borderSubtle)
                        .padding(.leading, 76)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(subtitle)
    }
}

struct AccountBindActionList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: .zero) {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

// MARK: - Success

struct AccountBindSuccessCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppElevationCard(level: .l1, role: .active, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(spacing: AppSpacing.cardSmall) {
                TracciSuccessCheck(size: 48)

                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Resend + back

struct AccountBindResendRow: View {
    let canResend: Bool
    let isSending: Bool
    let countdown: Int
    let onResend: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            if canResend {
                Button(action: onResend) {
                    Text(isSending ? "发送中…" : "重新发送验证码")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.brandPrimary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            } else {
                Text("\(countdown)s 后可重新发送")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .monospacedDigit()
                    .frame(minHeight: 44)
            }
            Spacer(minLength: 0)
        }
    }
}

struct AccountBindSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Form card shell

struct AccountBindFormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.cardSmall) {
                content
            }
        }
    }
}
