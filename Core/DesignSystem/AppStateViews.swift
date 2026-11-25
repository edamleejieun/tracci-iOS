import SwiftUI

// MARK: - LoadingView

/// Auth-restore surface shown right after the launch screen.
///
/// The logo sits at the exact screen center at the launch asset's intrinsic
/// point size, so the launch frame hands off into this view without a jump;
/// wordmark, ambient glow and status fade in around it.
struct LoadingView: View {
    var message = "加载中"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chromeAppeared = false

    /// Matches the launch image's intrinsic point size (81×64) — see UILaunchScreen in Info.plist.
    private static let logoHeight: CGFloat = 64

    var body: some View {
        ZStack {
            BrandAmbientGlow()
                .opacity(chromeAppeared ? 1 : 0)

            BrandLogoView(style: .blue, height: Self.logoHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The chrome hangs *below* the centered logo, not centered as a group:
        // pin the stack's top edge to the screen center via an alignment guide,
        // then reserve half the logo + lockup spacing before the wordmark.
        // (Centering the whole stack would drag the wordmark up into the logo.)
        .overlay(alignment: .center) {
            VStack(spacing: BrandTokens.primaryStackSpacing) {
                Color.clear
                    .frame(height: Self.logoHeight / 2)
                brandChrome
            }
            .alignmentGuide(VerticalAlignment.center) { _ in 0 }
        }
        .tracciAtmosphere(.creek)
        .onAppear {
            guard !reduceMotion else {
                chromeAppeared = true
                return
            }
            withAnimation(AppMotion.animation(AppMotion.slow, reduceMotion: reduceMotion)) {
                chromeAppeared = true
            }
        }
    }

    private var brandChrome: some View {
        VStack(spacing: AppSpacing.xl) {
            BrandWordmarkView(style: .primary, size: BrandTokens.primaryWordmarkSize)

            VStack(spacing: AppSpacing.md) {
                AppProgressIndicator(diameter: 22)
                Text(message)
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .opacity(chromeAppeared ? 1 : 0)
        .offset(y: reduceMotion || chromeAppeared ? 0 : AppMotion.fadeSlideOffset)
        .accessibilityElement(children: .combine)
    }
}

#Preview("LoadingView") {
    LoadingView()
}

#Preview("LoadingView — Reduce Motion") {
    BrandPreviewSupport.reduceMotion(
        LoadingView()
    )
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let buttonTitle: String?
    var systemImage = "mappin.and.ellipse"
    var action: (() -> Void)?

    var body: some View {
        AppElevationCard(level: .l1, role: .hero, radius: AppRadius.hero, padding: 0) {
            VStack(spacing: 18) {
                // Quiet leading mark: one large light-weight hierarchical symbol,
                // no tinted disc. Copy does the work — tool first, no decoration.
                Image(systemName: systemImage)
                    .font(AppFont.system(36, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColors.brandPrimary.opacity(0.62))
                    .frame(height: 44)
                    .accessibilityHidden(true)
                    .tracciTextsReveal(index: 0)

                VStack(spacing: AppSpacing.tight) {
                    Text(title)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .tracciTextsReveal(index: 1)
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .tracciTextsReveal(index: 2)
                }

                if let buttonTitle, let action {
                    Button(action: action) {
                        HStack(spacing: AppSpacing.tight) {
                            Image(systemName: "plus")
                                .font(AppTypography.buttonIconCompact)
                            Text(buttonTitle)
                                .font(AppTypography.buttonTitle)
                        }
                        .foregroundStyle(AppColors.textPrimaryInverse)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 46)
                        .background(
                            TracciCTABackground(base: AppColors.brandPrimary, strokeRadius: AppRadius.button)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                        .tracciElevation(.l2)
                    }
                    .buttonStyle(TracciPressableButtonStyle())
                    .tracciTextsReveal(index: 3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, 44)
        }
    }
}

#Preview("EmptyStateView — 无操作") {
    EmptyStateView(
        title: "还没有旅程",
        subtitle: "创建第一段旅程，开始记录行程、日志和开支",
        buttonTitle: nil,
        systemImage: "map"
    )
    .padding(.horizontal, AppSpacing.pageX)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .tracciPageBackground()
}

#Preview("EmptyStateView — 带操作") {
    EmptyStateView(
        title: "还没有旅程",
        subtitle: "创建第一段旅程，开始记录行程、日志和开支",
        buttonTitle: "创建旅程",
        systemImage: "map"
    ) { }
    .padding(.horizontal, AppSpacing.pageX)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .tracciPageBackground()
}

// MARK: - InlineLoadingStateView

struct InlineLoadingStateView: View {
    var message: String
    var verticalPadding: CGFloat = 56

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            AppProgressIndicator(diameter: 24)
            Text(message)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
    }
}

#Preview("InlineLoadingStateView") {
    InlineLoadingStateView(message: "加载中")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tracciPageBackground()
}

// MARK: - ErrorStateView

struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle = "再试一次"
    var debugReloadFrameLogging = false
    var retry: () -> Void

    var body: some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.extraLarge, padding: 22) {
            VStack(spacing: AppSpacing.cardSmall) {
                ZStack {
                    Circle()
                        .fill(AppColors.dangerBackground)
                        .frame(width: 64, height: 64)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.danger)
                }
                .accessibilityHidden(true)

                VStack(spacing: AppSpacing.tight) {
                    Text(title)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: retry) {
                    Text(retryTitle)
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimaryInverse)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.cozy)
                        .frame(minHeight: 44)
                        .background(
                            // 与 Capsule 裁剪共用同一形状:大 Dynamic Type 下按钮
                            // 变高时,固定圆角的描边会与胶囊弧度错位。
                            TracciCTABackground(base: AppColors.brandPrimary, strokeShape: Capsule())
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(TracciPressableButtonStyle(scales: false))
                .accessibilityHint("重新加载数据")
                .tracciReloadFrameDebug(isEnabled: debugReloadFrameLogging)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }
}

#Preview("ErrorStateView") {
    ErrorStateView(
        title: "加载失败",
        message: "网络连接不稳定，请检查后重试",
        retry: { }
    )
    .padding(.horizontal, AppSpacing.pageX)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .tracciPageBackground()
}

#if DEBUG
private struct ReloadFrameDebugModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    log(frame)
                }
        } else {
            content
        }
    }

    private func log(_ frame: CGRect) {
        let safeAreaTop = SafeAreaMetrics.top
        print(
            "[SheetLayout] reload frame=\(format(frame)) safeArea top=\(rounded(safeAreaTop)) minY<safeAreaTop=\(frame.minY < safeAreaTop)"
        )
    }

    private func format(_ rect: CGRect) -> String {
        "(x:\(rounded(rect.minX)), y:\(rounded(rect.minY)), w:\(rounded(rect.width)), h:\(rounded(rect.height)), maxY:\(rounded(rect.maxY)))"
    }

    private func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
#endif

private extension View {
    @ViewBuilder
    func tracciReloadFrameDebug(isEnabled: Bool) -> some View {
        #if DEBUG
        modifier(ReloadFrameDebugModifier(isEnabled: isEnabled))
        #else
        self
        #endif
    }
}
