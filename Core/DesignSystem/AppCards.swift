import SwiftUI

// MARK: - Role-based Surfaces

enum AppCardRole {
    case utility
    case content
    case archive
    case active
    case hero
    case immersive
}

/// Creek Editorial card foundation. New screens opt into a semantic role and elevation;
/// existing `AppCard` calls keep their established L1 appearance until migrated.
struct AppElevationCard<Content: View>: View {
    let level: AppElevationLevel
    let role: AppCardRole
    var radius: CGFloat = AppRadius.card
    var padding: CGFloat = AppSpacing.card
    var showsBorder = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background { surfaceBackground }
            .clipShape(cardShape)
            .overlay { borderOverlay }
            .tracciElevation(level)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        switch level {
        case .l3:
            AppGlassBackground(cornerRadius: radius)
        case .l4:
            Color.clear
        case .l0, .l1, .l2:
            roleBackground
        }
    }

    @ViewBuilder
    private var roleBackground: some View {
        switch role {
        case .utility, .content, .archive, .hero:
            AppColors.cardBackground
        case .active:
            LinearGradient(
                colors: [AppColors.cardBackground, AppColors.stageOngoingBackground.opacity(0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .immersive:
            Color.clear
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if showsBorder, level != .l3, level != .l4 {
            cardShape
                .stroke(
                    LinearGradient(
                        colors: [AppColors.borderHighlight, AppColors.borderSubtle.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: level == .l0 ? 0.8 : 0.65
                )
        }
    }
}

/// Content container for floating chrome. It respects Reduce Transparency automatically.
struct AppGlassSurface<Content: View>: View {
    var radius: CGFloat = AppRadius.large
    var padding: CGFloat = AppSpacing.cardSmall
    var elevation: AppElevationLevel = .l3
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background { AppGlassBackground(cornerRadius: radius) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .tracciElevation(elevation)
    }
}

private struct AppGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let cornerRadius: CGFloat

    var body: some View {
        FloatingGlassBackground(
            cornerRadius: cornerRadius,
            reduceTransparency: reduceTransparency,
            isHighContrast: differentiateWithoutColor
        )
    }
}

// MARK: - AppCard

/// Card container — wraps content with consistent background, radius, shadow, and padding.
///
/// **Usage:**
/// ```swift
/// AppCard {
///     VStack(spacing: AppSpacing.cozy) {
///         Text("Title")
///         Text("Body")
///     }
/// }
///
/// // Custom radius / padding
/// AppCard(radius: AppRadius.hero, padding: AppSpacing.lg) {
///     featuredContent
/// }
/// ```
struct AppCard<Content: View>: View {
    var radius: CGFloat = AppRadius.card
    var padding: CGFloat = AppSpacing.card
    @ViewBuilder var content: Content

    var body: some View {
        AppElevationCard(
            level: .l1,
            role: .content,
            radius: radius,
            padding: padding,
            showsBorder: false
        ) {
            content
        }
    }
}

// MARK: - AppCompanionCard

/// Companion-style narrative card for tab insight / memory / journey stage states.
///
/// Three-layer narrative structure (inspired by Figma Make CompanionCard):
///   - **context** — time / scene context (e.g. "今天是东京的第 2 天")
///   - **scene**   — narrative description embedding data into prose
///   - **insight** — the "one-sentence perception" with stronger visual weight
///
/// An optional **leftBar** accent strip (3pt brandPrimary) anchors the card
/// with a subtle visual signal — used when the card needs extra warmth or
/// when the insight layer wants a visual "pulse point."
struct AppCompanionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let eyebrow: String

    // MARK: Narrative layers
    var context: String?      // time / scene context — optional
    var scene: String         // narrative description — required (formerly `message`)
    var insight: String?      // one-sentence insight — optional

    // MARK: Accent
    var leftBar: Bool = false // optional 3pt accent vertical bar

    var body: some View {
        AppElevationCard(level: .l1, role: .hero, radius: AppRadius.hero, padding: AppSpacing.xl) {
            HStack(alignment: .top, spacing: leftBar ? 16 : 0) {
                if leftBar {
                    LinearGradient(
                        colors: [AppColors.brandPrimary.opacity(0.74), AppColors.dawnGold.opacity(0.52)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                        .frame(width: 3)
                        .clipShape(Capsule())
                        .padding(.vertical, 2)
                }

                VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                    // Symbol icon
                    Image(systemName: symbol)
                        .font(AppFont.system(24, weight: .light))
                        .foregroundStyle(AppColors.brandPrimary)
                        .opacity(reduceMotion ? 1 : 0.92)
                        .tracciTextsReveal(index: 0)

                    // Eyebrow label
                    Text(eyebrow)
                        .font(AppTypography.editorialMeta)
                        .foregroundStyle(AppColors.textMuted)
                        .tracking(0.8)
                        .tracciTextsReveal(index: 1)

                    // Context line — optional
                    if let context {
                        Text(context)
                            .font(AppTypography.editorialMeta)
                            .foregroundStyle(AppColors.textSecondary)
                            .tracking(0.45)
                            .padding(.top, 2)
                            .tracciTextsReveal(index: 2)
                    }

                    // Scene — narrative body (formerly `message`)
                    Text(scene)
                        .font(AppTypography.narrativeBody)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(6)
                        .padding(.top, context != nil ? 8 : 0)
                        .tracciTextsReveal(index: context == nil ? 2 : 3)

                    // Insight — strongest visual weight, optional
                    if let insight {
                        Text(insight)
                            .font(AppTypography.dayTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineSpacing(5)
                            .padding(.top, AppSpacing.cozy)
                            .tracciTextsReveal(index: context == nil ? 3 : 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - PageBackground

struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.backgroundGrouped.ignoresSafeArea())
    }
}

// MARK: - GlassBackground

/// Frosted glass effect for tab bars, sticky headers, and overlays
struct GlassBackground: ViewModifier {
    var background: Color = .white.opacity(0.84)
    var showTopBorder = true

    func body(content: Content) -> some View {
        content
            .background {
                Rectangle()
                    .fill(background)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        if showTopBorder {
                            Rectangle()
                                .fill(AppColors.borderDefault.opacity(0.55))
                                .frame(height: 1)
                        }
                    }
            }
    }
}

// MARK: - iOS 26+ Liquid Glass Tab Bar Modifier

/// iOS 26+：外层胶囊铺 glass（与 per-tab glass、滑动 Lens 三层叠加，还原 Apple Music / Telegram 玻璃效果）。
/// iOS 17/25：轻量 material + 描边。
struct LiquidGlassTabBarModifier: ViewModifier {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool
    let isHighContrast: Bool
    let namespace: Namespace.ID
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            content.background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.clear.tint(.white), in: .capsule)
                    .glassEffectID("tab-bar-outer", in: namespace)
                    .overlay(crystallineHighlight, in: .capsule)
            }
        } else if reduceTransparency {
            content.background {
                Capsule().fill(solidFallback)
            }
        } else {
            content.background { pre26Background }
        }
        #else
        if reduceTransparency {
            content.background {
                Capsule().fill(solidFallback)
            }
        } else {
            content.background { pre26Background }
        }
        #endif
    }

    @ViewBuilder
    private var pre26Background: some View {
        if reduceTransparency {
            Capsule()
                .fill(solidFallback)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().fill(surfaceTint)
                }
                .overlay {
                    Capsule()
                        .stroke(
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28),
                            lineWidth: isHighContrast ? 0.9 : 0.55
                        )
                        .blendMode(.plusLighter)
                }
        }
    }

    private var surfaceTint: Color {
        if colorScheme == .dark {
            return Color(uiColor: .systemBackground).opacity(isHighContrast ? 0.14 : 0.06)
        }
        return AppColors.surfaceTint
    }

    private var solidFallback: Color {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemBackground)
            : Color(uiColor: .systemBackground).opacity(0.92)
    }

    /// 顶部高光线条：模拟玻璃边缘的折射亮线，增强水晶质感。
    @ViewBuilder
    private var crystallineHighlight: some View {
        Capsule()
            .stroke(
                LinearGradient(
                    colors: highlightColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
    }

    private var highlightColors: [Color] {
        colorScheme == .dark
            ? [Color.white.opacity(0.30), Color.white.opacity(0.08), .clear]
            : [Color.white.opacity(0.70), Color.white.opacity(0.25), .clear]
    }
}

// MARK: - FloatingGlassBackground

/// Material intensity for floating glass chrome.
enum FloatingGlassStyle: Equatable {
    /// Default floating surfaces (menus, generic glass cards).
    case standard
    /// Global tab capsule — slightly clearer, less “plastic white”.
    case navigationChrome
}

/// Frosted glass background for floating capsule-shaped bars.
/// On iOS 26+ applies native liquid glass effect.
/// On older iOS uses layered material, gradients, and borders.
struct FloatingGlassBackground: View {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool
    let isHighContrast: Bool
    var style: FloatingGlassStyle = .standard
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        #if compiler(>=26)
        if #available(iOS 26, *) {
            if !reduceTransparency {
                // Navigation chrome uses a lighter clear-tinted glass; standard uses regular.
                if style == .navigationChrome {
                    shape.glassEffect(.clear.tint(.white.opacity(0.18)), in: shape)
                } else {
                    shape.glassEffect(.regular.interactive(), in: shape)
                }
            } else {
                shape.fill(solidFallback)
            }
        } else {
            pre26Body(shape: shape)
        }
        #else
        pre26Body(shape: shape)
        #endif
    }

    @ViewBuilder
    private func pre26Body(shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape.fill(solidFallback)
        } else {
            shape
                .fill(baseMaterial)
                .overlay {
                    shape.fill(surfaceTint)
                }
                .overlay {
                    LinearGradient(
                        colors: highlightGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                }
                .overlay(alignment: .bottom) {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(colorScheme == .dark ? 0.14 : bottomShadeOpacity),
                                    .clear
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .opacity(isHighContrast ? 0.72 : 0.22)
                        .blendMode(.multiply)
                        .clipShape(shape)
                }
                .overlay {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: edgeStrokeColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isHighContrast ? 1.2 : 0.85
                        )
                        .blendMode(.plusLighter)
                }
                .overlay {
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.75
                        )
                        .padding(1.1)
                        .blendMode(.plusLighter)
                }
                .overlay {
                    shape
                        .stroke(borderColor, lineWidth: isHighContrast ? 1.2 : 0.65)
                }
        }
    }

    private var baseMaterial: Material {
        switch style {
        case .standard:
            return .ultraThinMaterial
        case .navigationChrome:
            // Thin material reads clearer over Creek Mist / Paper than ultraThin alone.
            return .thinMaterial
        }
    }

    private var highlightGradient: [Color] {
        switch style {
        case .standard:
            return [
                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.42),
                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.16),
                .clear
            ]
        case .navigationChrome:
            return [
                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.52),
                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.14),
                AppColors.brandPrimary.opacity(colorScheme == .dark ? 0.0 : 0.03),
                .clear
            ]
        }
    }

    private var edgeStrokeColors: [Color] {
        [
            Color.white.opacity(colorScheme == .dark ? 0.24 : 0.78),
            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.32),
            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.12)
        ]
    }

    private var bottomShadeOpacity: Double {
        style == .navigationChrome ? 0.028 : 0.035
    }

    private var surfaceTint: Color {
        if colorScheme == .dark {
            return Color(uiColor: .systemBackground).opacity(isHighContrast ? 0.42 : 0.26)
        }
        switch style {
        case .standard:
            return AppColors.surfaceTint
        case .navigationChrome:
            // Slightly more opaque paper so labels stay crisp over busy covers.
            return Color(uiColor: .systemBackground).opacity(isHighContrast ? 0.22 : 0.10)
        }
    }

    private var solidFallback: Color {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemBackground)
            : Color(uiColor: .systemBackground).opacity(style == .navigationChrome ? 0.94 : 0.88)
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHighContrast ? 0.30 : 0.16)
        }
        return Color.white.opacity(isHighContrast ? 0.78 : (style == .navigationChrome ? 0.52 : 0.46))
    }
}

// MARK: - View Extensions

extension View {
    func tracciPageBackground() -> some View {
        modifier(PageBackground())
    }

    func tracciGlass() -> some View {
        modifier(GlassBackground())
    }

    func tracciGlass(background: Color = .white.opacity(0.84), showTopBorder: Bool = true) -> some View {
        modifier(GlassBackground(background: background, showTopBorder: showTopBorder))
    }

    /// Media-overlay chrome glass (G5.1): native Liquid Glass with press ripple on
    /// iOS 26; below iOS 26 falls back to the legacy wash + ultra-thin material +
    /// hairline recipe. Under Reduce Transparency both paths use an opaque fill
    /// (`opaqueFallback`) — no material, no translucency.
    ///
    /// `wash` layers inside the glass for glyph legibility: dark chrome (white
    /// glyphs over covers/maps) passes a black wash; light content cards (dark
    /// text, e.g. the map node card) pass a light wash instead. The same split
    /// applies to `opaqueFallback`: dark chrome keeps the default dark fill,
    /// light content cards pass a light one.
    func tracciMediaChromeGlass<S: Shape>(
        in shape: S,
        wash: Color = .black.opacity(0.18),
        opaqueFallback: Color = .black.opacity(0.55)
    ) -> some View {
        modifier(
            TracciMediaChromeGlassModifier(
                shape: shape,
                wash: wash,
                opaqueFallback: opaqueFallback
            )
        )
    }

    /// G5.6 Seamless background extension: on iOS 26 the view's background is
    /// duplicated into blurred mirrored copies that fill the safe-area regions
    /// around the view, removing the seam between a background's edge and the
    /// page/sheet canvas so the surface reads as one continuous material.
    ///
    /// Apply with discretion (Apple guidance): at most one background carrier
    /// per screen — never per-row. Below iOS 26 the existing background stays
    /// unchanged (no-op). This is a static visual extension with no material or
    /// translucency involved, so it needs no Reduce Transparency branch.
    @ViewBuilder
    func tracciBackgroundExtension(isEnabled: Bool = true) -> some View {
        #if compiler(>=26)
        if #available(iOS 26, *) {
            self.backgroundExtensionEffect(isEnabled: isEnabled)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct TracciMediaChromeGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let wash: Color
    /// Opaque fill for Reduce Transparency — must carry contrast on its own.
    let opaqueFallback: Color

    func body(content: Content) -> some View {
        #if compiler(>=26)
        if #available(iOS 26, *), !reduceTransparency {
            content
                .background(wash, in: shape)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            legacyBody(content)
        }
        #else
        legacyBody(content)
        #endif
    }

    @ViewBuilder
    private func legacyBody(_ content: Content) -> some View {
        if reduceTransparency {
            content
                .background(opaqueFallback, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.26), lineWidth: 0.6)
                }
        } else {
            content
                .background(wash, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.26), lineWidth: 0.6)
                }
        }
    }
}
