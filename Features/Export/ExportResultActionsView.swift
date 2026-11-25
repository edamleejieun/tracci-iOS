import SwiftUI

struct ExportResultActionsView: View {
    let hasImage: Bool
    let hasText: Bool
    let onPreview: () -> Void
    let onShare: () -> Void
    let onSave: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                if hasImage {
                    actionButton(title: "预览", icon: "eye", style: .secondary, action: onPreview)
                }
                actionButton(title: "分享", icon: "square.and.arrow.up", style: .secondary, action: onShare)
                if hasImage {
                    actionButton(title: "保存相册", icon: "square.and.arrow.down", style: .primary, action: onSave)
                }
            }

            Button(action: onReset) {
                Text("重新生成")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    private enum ActionStyle {
        case primary
        case secondary
    }

    private func actionButton(
        title: String,
        icon: String,
        style: ActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                Text(title)
            }
            .font(AppTypography.labelSemibold)
            .foregroundStyle(style == .primary ? .white : AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppControlMetrics.minimumTapTarget)
            .background(style == .primary ? AppColors.brandPrimary : AppColors.paperWarmLight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous)
                        .stroke(AppColors.borderDefault.opacity(0.55), lineWidth: 0.6)
                }
            }
            .tracciElevation(style == .primary ? .l2 : .l0)
        }
        .buttonStyle(PressableCardStyle(scale: 0.98, opacity: 0.94))
    }
}

struct ExportPrimaryActionButton: View {
    let title: String
    let systemImage: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.tight) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(AppTypography.buttonTitle)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(isDisabled ? AppColors.brandPrimary.opacity(0.45) : AppColors.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .tracciElevation(isDisabled ? .l0 : .l2)
            .shadow(
                color: isDisabled ? .clear : AppColors.brandPrimary.opacity(0.22),
                radius: 12,
                x: 0,
                y: 5
            )
        }
        .buttonStyle(PressableCardStyle(scale: 0.98, opacity: 0.94))
        .disabled(isDisabled || isLoading)
    }
}
