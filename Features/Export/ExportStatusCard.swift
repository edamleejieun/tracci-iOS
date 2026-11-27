import SwiftUI

struct ExportStatusCard: View {
    let phase: ExportPhase
    let message: String?
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        if phase == .loading || phase == .generating || phase == .failed {
            AppElevationCard(
                level: phase == .failed ? .l1 : .l0,
                role: phase == .failed ? .content : .utility,
                radius: AppRadius.large,
                padding: 14
            ) {
                HStack(alignment: .top, spacing: AppSpacing.cozy) {
                    statusIcon

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(title)
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.textPrimary)

                        if let detail = detailText {
                            Text(detail)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textMuted)
                        }

                        if phase == .failed {
                            Button("重试", action: onRetry)
                                .font(AppTypography.labelSemibold)
                                .foregroundStyle(AppColors.interactiveText)
                                .padding(.top, AppSpacing.xxs)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch phase {
        case .loading, .generating:
            ProgressView()
                .tint(AppColors.brandPrimary)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.danger)
        case .idle:
            EmptyView()
        }
    }

    private var title: String {
        switch phase {
        case .idle: ""
        case .loading: "正在取回路上的记录"
        case .generating: "正在生成回忆内容"
        case .success: "生成成功"
        case .failed: "生成失败"
        }
    }

    private var detailText: String? {
        switch phase {
        case .failed:
            return errorMessage
        case .success:
            return message
        case .loading:
            return "正在取回路上的照片和记录，稍等一下"
        case .generating:
            return "正在生成图片，请稍等，不用反复点"
        case .idle:
            return nil
        }
    }
}
