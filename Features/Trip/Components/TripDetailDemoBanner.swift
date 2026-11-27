import SwiftUI

/// Demo Journey 的只读身份、阶段切换与退出入口。
struct TripDetailDemoBanner: View {
    let isSwitchingScene: Bool
    @Binding var sceneSelection: DemoJourneySceneKind
    let showsSoftCoach: Bool
    let reduceMotion: Bool
    let onCreateOwnTrip: () -> Void
    let onOpenActivity: () -> Void
    let onDismissSoftCoach: () -> Void

    var body: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.medium, padding: AppSpacing.cardSmall) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                identityRow

                TracciSegmentedControl(
                    selection: $sceneSelection,
                    options: Array(DemoJourneySceneKind.allCases),
                    title: { $0.displayLabel }
                )
                .disabled(isSwitchingScene)
                .opacity(isSwitchingScene ? 0.72 : 1)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("示例旅程阶段")
                .accessibilityHint("切换规划中、进行中或已结束示例")

                Text(sceneSelection.browseHint)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(sceneSelection.browseHint)

                activityButton

                if showsSoftCoach {
                    softCoachRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: showsSoftCoach
        )
    }

    private var identityRow: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "eye")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.brandPrimary)
                .accessibilityHidden(true)
            Text(DemoReadOnlyCopy.identityPill)
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: AppSpacing.sm)
            if isSwitchingScene {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("正在切换示例阶段")
            }
            Button {
                AppHaptics.mediumImpact()
                onCreateOwnTrip()
            } label: {
                Text(DemoReadOnlyCopy.createOwnTrip)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.interactiveText)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColors.brandPrimary.opacity(0.12))
                    )
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DemoReadOnlyCopy.createOwnTrip)
            .accessibilityHint(DemoReadOnlyCopy.createOwnTripAccessibilityHint)
        }
    }

    private var activityButton: some View {
        Button(action: onOpenActivity) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppTypography.captionSemibold)
                Text(DemoReadOnlyCopy.activityEntry)
                    .font(AppTypography.captionMedium)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
            }
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DemoReadOnlyCopy.activityEntry)
        .accessibilityHint(DemoReadOnlyCopy.activityReadOnly)
    }

    private var softCoachRow: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "lightbulb")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.brandPrimary)
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text(DemoReadOnlyCopy.softCoach)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismissSoftCoach) {
                Text(DemoReadOnlyCopy.softCoachDismiss)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.interactiveText)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DemoReadOnlyCopy.softCoachDismiss)
            .accessibilityHint(DemoReadOnlyCopy.softCoachAccessibilityHint)
        }
        .padding(.top, AppSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DemoReadOnlyCopy.softCoach)
    }
}
