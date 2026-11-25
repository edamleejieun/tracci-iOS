import SwiftUI

struct TripCoverPickerPlaceholder: View {
    var coverURL: URL?
    var isUploading = false
    var height: CGFloat = 200
    var showsChangeBadge = true

    var body: some View {
        ZStack {
            if let coverURL {
                TripCoverView(url: coverURL, height: height, cornerRadius: AppRadius.hero)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.28)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showsChangeBadge {
                            changeCoverBadge
                                .padding(AppSpacing.md)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xE8E4DE), Color(hex: 0xF4F1EC), Color(hex: 0xE8E4DE)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: height)
                    .overlay {
                        decorativeCircles
                    }
                    .overlay {
                        placeholderContent
                    }
            }

            if isUploading {
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .fill(.black.opacity(0.24))
                    .frame(height: height)
                    .overlay {
                        VStack(spacing: AppSpacing.sm) {
                            ProgressView()
                                .tint(.white)
                            Text("正在上传封面")
                                .font(AppTypography.label)
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
        .tracciElevation(.l1)
    }

    private var placeholderContent: some View {
        VStack(spacing: AppSpacing.sm) {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(.white)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "photo.badge.plus")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
                .tracciElevation(.l0)

            Text("添加旅程封面")
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(AppColors.textMuted)

            Text("用于首页和旅程详情展示")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textDisabled)
        }
    }

    private var changeCoverBadge: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "photo.badge.plus")
                .font(AppTypography.captionSemibold)
            Text("更换封面")
                .font(AppTypography.label)
        }
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.tight)
        .background(.white.opacity(0.92))
        .clipShape(Capsule())
    }

    private var decorativeCircles: some View {
        ZStack {
            Circle()
                .fill(AppColors.brandPrimary.opacity(0.06))
                .frame(width: 140, height: 140)
                .offset(x: 120, y: -70)
            Circle()
                .fill(AppColors.ownerAmber.opacity(0.05))
                .frame(width: 100, height: 100)
                .offset(x: -110, y: 80)
        }
    }
}
