import SwiftUI

enum AppShadow {
    // MARK: - Elevation primitives

    /// L0 hairline lift for forms, settings, and utility rows.
    static let level0 = ShadowStyle(color: .black.opacity(0.025), radius: 3, y: 1)

    /// L1 standard content-card lift.
    static let level1 = ShadowStyle(color: .black.opacity(0.06), radius: 16, y: 6)

    /// L2 near shadow. Pair with `level2Far` for active and hero cards.
    static let level2Near = ShadowStyle(color: .black.opacity(0.055), radius: 10, y: 4)
    static let level2Far = ShadowStyle(color: .black.opacity(0.11), radius: 24, y: 11)

    /// L3 floating glass lift.
    static let level3 = ShadowStyle(color: .black.opacity(0.14), radius: 28, y: 14)

    /// L4 media lift. Readability scrims remain the responsibility of the media view.
    static let level4 = ShadowStyle(color: .black.opacity(0.16), radius: 30, y: 14)

    /// Soft shadow for small interactive elements (buttons, icons)
    /// Opacity: 5% — Figma Design Token
    static let soft = ShadowStyle(color: .black.opacity(0.05), radius: 8, y: 3)

    /// Default card shadow — used by AppCard
    /// Opacity: 6% — Figma Design Token
    static let card = level1

    /// Medium shadow for elevated cards
    /// Opacity: 8% — Figma Design Token
    static let medium = ShadowStyle(color: .black.opacity(0.08), radius: 18, y: 8)

    /// Large shadow for featured/prominent elements
    static let large = ShadowStyle(color: .black.opacity(0.12), radius: 24, y: 10)

    /// Brand-colored shadow for primary buttons
    static let brand = ShadowStyle(color: AppColors.brandPrimary.opacity(0.35), radius: 18, y: 8)

    /// WeChat green shadow
    static let wechat = ShadowStyle(color: Color(hex: 0x07C160).opacity(0.22), radius: 16, y: 8)

    // MARK: - Module-specific

    /// Floating shadow for FAB and floating controls
    static let floating = ShadowStyle(color: .black.opacity(0.18), radius: 32, y: 18)

    /// Strong text shadow for readability on variable backgrounds
    static let textStrong = ShadowStyle(color: .black.opacity(0.28), radius: 8, y: 2)

    /// Soft text shadow for secondary hero text (narrative line, editorial eyebrow).
    static let textSoft = ShadowStyle(color: .black.opacity(0.18), radius: 5, y: 1)

    /// Upward lift for the map explore dock panel. `progress` (0…1) scales the
    /// opacity so the lift rises together with the chrome entrance.
    static func dockLift(progress: Double) -> ShadowStyle {
        ShadowStyle(color: .black.opacity(0.10 * progress), radius: 16, y: -6)
    }
}

/// Semantic depth used by Creek Editorial Immersion surfaces.
enum AppElevationLevel: CaseIterable {
    case l0
    case l1
    case l2
    case l3
    case l4
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}

// MARK: - Elevation suppression (swipe / drag shells)

/// When true, `tracciElevation` becomes a no-op so sliding shells (e.g. swipe-to-delete)
/// do not leave soft-shadow “ghosts” in the revealed action well.
private struct TracciElevationSuppressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tracciElevationSuppressed: Bool {
        get { self[TracciElevationSuppressedKey.self] }
        set { self[TracciElevationSuppressedKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Apply a Tracci shadow style to this view.
    func tracciShadow(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }

    /// Applies role-based elevation without scattering private shadow values across features.
    /// Honors `tracciElevationSuppressed` so temporary interactive shells can drop lift cleanly.
    func tracciElevation(_ level: AppElevationLevel) -> some View {
        modifier(TracciElevationModifier(level: level))
    }
}

private struct TracciElevationModifier: ViewModifier {
    @Environment(\.tracciElevationSuppressed) private var suppressed
    let level: AppElevationLevel

    func body(content: Content) -> some View {
        if suppressed {
            content
        } else {
            switch level {
            case .l0:
                content.tracciShadow(AppShadow.level0)
            case .l1:
                content.tracciShadow(AppShadow.level1)
            case .l2:
                content
                    .tracciShadow(AppShadow.level2Near)
                    .tracciShadow(AppShadow.level2Far)
            case .l3:
                content.tracciShadow(AppShadow.level3)
            case .l4:
                content.tracciShadow(AppShadow.level4)
            }
        }
    }
}
