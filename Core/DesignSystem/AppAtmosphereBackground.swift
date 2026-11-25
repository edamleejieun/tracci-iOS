import SwiftUI

enum AppAtmosphereStyle: Hashable {
    case creek
    case paper
    case memory
    /// Journey-stage variant. Canvas is the same system grouped color as `.creek`.
    case creekOngoing
    /// Journey-stage variant. Canvas is the same system grouped color as `.creek`.
    case creekCompleted
    case none

    /// Page-base color where an immersive hero must blend into the canvas.
    /// All scene styles share the system grouped background; only `.none`
    /// stays on `systemBackground` (plain white in light mode).
    var heroSeamColor: Color {
        switch self {
        case .none:
            return AppColors.backgroundPrimary
        case .creek, .creekOngoing, .creekCompleted, .paper, .memory:
            return AppColors.backgroundGrouped
        }
    }
}

/// Scene-level page canvas. All styles except `.none` use system grouped background.
struct AppAtmosphereBackground: View {
    let style: AppAtmosphereStyle
    /// Kept for call-site compatibility. Page canvas is a flat system color;
    /// brand glow belongs on lockups, not as a full-page wash.
    var animatesGlow = false

    var body: some View {
        baseLayer
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var baseLayer: some View {
        switch style {
        case .none:
            AppColors.backgroundPrimary
        case .creek, .creekOngoing, .creekCompleted, .paper, .memory:
            AppColors.backgroundGrouped
        }
    }
}

/// A quiet creek-line divider for narrative streams and day sections.
struct AppCreekDivider: View {
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

    var body: some View {
        LinearGradient(
            colors: [.clear, AppColors.brandPrimary.opacity(0.20), AppColors.borderSubtle, .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .accessibilityHidden(true)
    }
}

private struct AppAtmosphereModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let style: AppAtmosphereStyle
    let animatesGlow: Bool

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                AppAtmosphereBackground(style: style, animatesGlow: animatesGlow)
                    .id(style)
                    .transition(.opacity)
            }
            .animation(
                AppMotion.animation(AppMotion.atmosphereTransition, reduceMotion: reduceMotion),
                value: style
            )
        }
    }
}

extension View {
    func tracciAtmosphere(
        _ style: AppAtmosphereStyle,
        animatesGlow: Bool = false
    ) -> some View {
        modifier(AppAtmosphereModifier(style: style, animatesGlow: animatesGlow))
    }
}

#Preview("Creek Editorial Foundations") {
    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            AppElevationCard(level: .l2, role: .hero, radius: AppRadius.hero) {
                VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                    Text("CREEK EDITORIAL")
                        .font(AppTypography.editorialMeta)
                        .tracking(1.1)
                        .foregroundStyle(AppColors.textMuted)
                    Text("让每段旅途，自然成溪")
                        .font(AppTypography.displayHero)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("氛围、编辑叙事与软景深，从同一套 Design System 生长。")
                        .font(AppTypography.narrativeBody)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AppGlassSurface {
                HStack {
                    Label("浮层 Glass", systemImage: "sparkles")
                    Spacer()
                    Text("L3")
                        .font(AppTypography.editorialMeta)
                }
                .foregroundStyle(AppColors.textPrimary)
            }

            HStack(spacing: AppSpacing.cozy) {
                AppElevationCard(level: .l0, role: .utility, padding: AppSpacing.cozy) {
                    Text("Utility · L0")
                        .font(AppTypography.captionSemibold)
                }
                AppElevationCard(level: .l1, role: .archive, padding: AppSpacing.cozy) {
                    Text("Archive · L1")
                        .font(AppTypography.captionSemibold)
                }
            }
        }
        .padding(AppSpacing.pageX)
    }
    .tracciAtmosphere(.creek)
    .preferredColorScheme(.light)
}

#Preview("Journey Stage Atmospheres") {
    VStack(spacing: AppSpacing.cozy) {
        atmospherePreview(
            title: "规划中",
            detail: "系统分组底",
            style: .creek
        )
        atmospherePreview(
            title: "进行中",
            detail: "系统分组底",
            style: .creekOngoing
        )
        atmospherePreview(
            title: "已完成",
            detail: "系统分组底 · 与规划中一致",
            style: .creekCompleted
        )
    }
    .padding(AppSpacing.pageX)
    .background(AppColors.backgroundPrimary)
    .preferredColorScheme(.light)
}

@ViewBuilder
private func atmospherePreview(
    title: String,
    detail: String,
    style: AppAtmosphereStyle
) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.xs) {
        Text(title)
            .font(AppTypography.cardTitle)
            .foregroundStyle(AppColors.textPrimary)
        Text(detail)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    .padding(AppSpacing.cardSmall)
    .background {
        AppAtmosphereBackground(style: style)
    }
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    .overlay {
        RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            .stroke(AppColors.borderSubtle, lineWidth: 0.8)
    }
}
