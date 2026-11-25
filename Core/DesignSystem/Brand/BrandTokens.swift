import SwiftUI

enum BrandTokens {
    // MARK: - Colors

    static let inkHex: UInt = 0x18181B
    static var ink: Color { Color("BrandColors/BrandInk") }
    static var blue: Color { Color("BrandColors/BrandBlue") }
    static var background: Color { Color("BrandColors/BrandBackground") }

    // MARK: - Typography

    static let wordmarkTrackingRatio: CGFloat = 0.12
    static let sloganTrackingRatio: CGFloat = 0.08
    static let sloganLineHeight: CGFloat = 20

    // MARK: - Sizes (pt)

    static let headerLogoHeight: CGFloat = 32
    static let headerWordmarkSize: CGFloat = 28
    static let headerSpacing: CGFloat = 10

    static let primaryLogoHeight: CGFloat = 60
    static let primaryWordmarkSize: CGFloat = 44
    static let primaryStackSpacing: CGFloat = 12
    static let primarySloganSpacing: CGFloat = 18

    static let profileTopWordmarkSize: CGFloat = 17
    static let profileTopWordmarkOpacity: Double = 0.8

    static let watermarkLogoHeight: CGFloat = 15
    static let watermarkWordmarkSize: CGFloat = 13
    static let watermarkSpacing: CGFloat = 6

    // MARK: - Opacity

    static let watermarkDarkOpacity: Double = 0.16
    static let watermarkLightOpacity: Double = 0.70

    // MARK: - Ambient Glow

    static let glowMinOpacity: Double = 0.04
    static let glowMaxOpacity: Double = 0.08
    static let glowPrimaryDiameter: CGFloat = 120
    static let glowSecondaryDiameter: CGFloat = 80

    // MARK: - Helpers

    static func wordmarkTracking(for size: CGFloat) -> CGFloat {
        size * wordmarkTrackingRatio
    }

    static func watermarkOpacity(isDark: Bool) -> Double {
        isDark ? watermarkDarkOpacity : watermarkLightOpacity
    }

    static func exportWatermarkLogoHeight(canvasWidth: CGFloat) -> CGFloat {
        canvasWidth * 0.07
    }

    /// Vertical height for primary lockup — must match `BrandLockupView` + `BrandPrimaryLockupHostView`.
    static func primaryLockupHeight(showsSlogan: Bool) -> CGFloat {
        var height = primaryLogoHeight + primaryStackSpacing + primaryWordmarkSize
        if showsSlogan {
            height += primarySloganSpacing + sloganLineHeight
        }
        return height
    }
}