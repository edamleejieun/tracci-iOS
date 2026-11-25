import SwiftUI
import UIKit

enum AppColors {
    // MARK: - Brand

    static let brandPrimary = Color(hex: 0x3B82F6)
    static let brandPrimaryLight = Color(hex: 0x60A5FA)
    static let brandPrimaryBackground = Color(hex: 0xEBF4FF)
    /// 承载白色正文的品牌蓝面（用户消息气泡）。`brandPrimary` 上白字仅 ~3.7:1，
    /// 深一档（~#2563EB）对白字 ~5.2:1，满足正文 4.5:1。
    static let brandPrimaryStrong = Color(hex: 0x2563EB)
    static let brandWarm = Color(hex: 0xF0A06A)
    /// Legacy name. Do not use as a page/card canvas; maps to brand soft blue.
    static let brandWarmBackground = brandPrimaryBackground

    // MARK: - Backgrounds

    static let backgroundPrimary = Color(uiColor: .systemBackground)
    static let backgroundGrouped = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .systemBackground)
    static let cardAltBackground = Color(uiColor: .secondarySystemGroupedBackground)
    /// Inset well / chip fill. Distinct from both grouped page and white cards.
    static let fillSubtle = Color(uiColor: .tertiarySystemFill)
    static let subtleSurface = fillSubtle
    /// Legacy name. Page canvas is system grouped — do not reintroduce a warm paper hex.
    static let brandWarmSurface = backgroundGrouped
    /// Legacy name. Raised chips/cards use system card white.
    static let subtleWarm = cardBackground
    static let subtleBackground = fillSubtle

    // MARK: - Creek Editorial Atmospheres

    /// Page canvas. Unified to system grouped — no custom cool-mist or warm-paper hex.
    /// Creek blue belongs only to localized glow, stream, and selection accents.
    static let creekMistTop = backgroundGrouped
    static let creekMistBottom = backgroundGrouped

    /// Legacy names kept so existing call sites resolve to the system canvas / card.
    static let paperWarm = backgroundGrouped
    static let paperWarmLight = cardBackground

    /// Reserved for memory/story atmosphere. Keep violet at very low opacity.
    static let memoryMist = Color(hex: 0xF3F0F6)
    static let memoryViolet = Color(hex: 0x9286A8)
    static let dawnGold = Color(hex: 0xD7A45F)
    static let dawnGoldBackground = Color(hex: 0xFBF2E5)

    /// Cool veil used to keep real archive thumbnails at the same visual weight as motif tiles.
    static let archivePhotoVeilLight = Color(hex: 0xB5C9DE)
    static let archivePhotoVeilDark = Color(hex: 0x1F293D)

    /// Warm ink for completed-trip cover scrims (paired with the default black
    /// scrim) — archive media reads as warm memory, not cold information.
    static let scrimWarmInk = Color(hex: 0x2D2319)

    /// Deep warm ink for explore media scrims (`designs/explore-v2` `#14100C`):
    /// city card / city hero / place sheet scrims dim covers without going cold black.
    static let mediaScrimInk = Color(hex: 0x14100C)

    /// Owner identity amber: crown mark and owner ring. Same hue as `warning`
    /// but semantically member identity, not an alert state.
    static let ownerAmber = Color(hex: 0xF59E0B)

    // MARK: - Journey Stages

    static let stagePlanning = Color(hex: 0x789CC8)
    static let stagePlanningBackground = Color(hex: 0xEDF3FA)
    static let stageOngoing = brandPrimary
    static let stageOngoingBackground = brandPrimaryBackground
    static let stageCompleted = Color(hex: 0x716B63)
    static let stageCompletedBackground = Color(uiColor: .tertiarySystemGroupedBackground)

    // MARK: - Itinerary Stream

    /// Muted type accents for itinerary timeline nodes. These intentionally reuse the
    /// expense Morandi family so route, spend, and journal surfaces feel related.
    static let itineraryAttraction = Color(hex: 0x5FA77D)
    static let itineraryRestaurant = Color(hex: 0xC98255)
    static let itineraryTransport = Color(hex: 0x659BC8)
    static let itineraryHotel = Color(hex: 0x8E7CB3)
    static let itineraryShopping = Color(hex: 0xB69B48)
    static let itineraryOther = stageCompleted

    /// Page canvas for sheets, settings, and pushed tools. Matches `backgroundGrouped`.
    static let pageBackground = backgroundGrouped

    // MARK: - Semantic Surface Aliases

    /// Surface tint for glass/material overlays (top highlight layer).
    static let surfaceTint = Color(uiColor: .systemBackground).opacity(0.03)

    /// Surface for elevated overlays in dark mode.
    static let surfaceElevatedDark = Color(uiColor: .secondarySystemBackground)

    // MARK: - Text

    static let textPrimary = Color(hex: 0x2F2A25)
    static let textSecondary = Color(hex: 0x5C5650)
    static let textMuted = Color(hex: 0x7A746B)
    static let textPlaceholder = Color(hex: 0x9B958C)
    static let textDisabled = Color(hex: 0xC4BEB5)

    /// Inverse text for use on brandPrimary or dark surfaces.
    static let textPrimaryInverse = Color.white

    // MARK: - Borders / Separators

    static let separator = Color(uiColor: .separator).opacity(0.36)
    /// Hairline between rows inside a grouped white list (settings, action sheet).
    static let groupedRowSeparator = Color(uiColor: .separator)
    static let border = Color(uiColor: .separator).opacity(0.28)
    static let borderDefault = Color(uiColor: .separator).opacity(0.32)
    static let borderSubtle = Color(uiColor: .separator).opacity(0.18)
    static let borderHighlight = Color.white.opacity(0.72)

    // MARK: - Semantic

    static let danger = Color(hex: 0xEF4444)
    static let dangerBackground = Color(hex: 0xFEF2F2)
    static let success = Color(hex: 0x22C55E)
    static let successForeground = Color(hex: 0x1A8040)
    static let successBackground = Color(hex: 0xE8F5E9)
    static let warning = Color(hex: 0xF59E0B)
    static let featured = Color(hex: 0xFFB800)

    static let textInverse = Color.white
    static let brandShadow = Color(hex: 0x3B82F6, alpha: 0.2)

    // MARK: - Expense Category Colors (Morandi palette)

    static let catFood = Color(hex: 0xE8B87D)
    static let catTransport = Color(hex: 0x7DB8E8)
    static let catHotel = Color(hex: 0xB8A4D9)
    static let catAttraction = Color(hex: 0x8FD9B6)
    static let catShopping = Color(hex: 0xE8D97D)
    static let catOther = Color(hex: 0xB7B1AA)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Member Identity Palette

/// Stable warm-tone color palette for member identity across the app.
/// Each member gets a deterministic color based on their userId,
/// so the same person always appears in the same hue everywhere —
/// activity logs, settlement, member list, expense forms.
enum MemberPalette {

    /// 12 travel-themed warm hues for visual member identity.
    private static let hexValues: [UInt] = [
        0xD4786B, // 陶土红 Terracotta
        0x9CAF88, // 鼠尾草绿 Sage
        0x7EB8DA, // 天空蓝 Sky Blue
        0xDAAD5E, // 琥珀黄 Amber
        0xB4A0D4, // 薰衣草紫 Lavender
        0xE8927C, // 珊瑚橙 Coral
        0x7DB5B5, // 青碧色 Teal
        0xD487A6, // 玫瑰粉 Rose
        0xDBA87E, // 暖杏色 Apricot
        0x8CB89F, // 薄荷绿 Mint
        0x8899C4, // 鸢尾蓝 Iris
        0xD9B368, // 蜜橙色 Honey
    ]

    private static var colorCache: [Color] {
        hexValues.map { Color(hex: $0) }
    }

    /// Returns a stable, deterministic color for the given identifier.
    /// Uses djb2 hash for cross-launch stability.
    static func color(for identifier: String) -> Color {
        let palette = colorCache
        guard !identifier.isEmpty else { return palette[0] }
        var hash: UInt64 = 5381
        for byte in identifier.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }

    /// Background tint (12% opacity) of the member's identity color.
    static func background(for identifier: String) -> Color {
        color(for: identifier).opacity(0.12)
    }
}
