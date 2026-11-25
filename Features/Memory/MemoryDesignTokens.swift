import SwiftUI

// MARK: - Memory Module Design Tokens
// 专用于回忆/Story 模块的视觉参数。
// 通用 token（如 brandPrimary、pageBackground）继续使用 App* 系列。
//
// 有意分叉（B2 token 归一决策，2026-09-29）：以下 palette **刻意保留模块专属**，
// 不收敛进 AppColors——
//   1. story 深色背景（0x0F2744 等）：回忆故事是 art-directed 沉浸暗色体验，
//      与全局强制浅色的 app chrome 无关，不应跟随品牌重主题。
//   2. accent 6 色（blue/green/amber/pink/purple/emerald）：成组使用的数据分类色，
//      抽出单个会破坏组内协调；accentBlue 虽与 brandPrimaryLight 同 hex，但角色是
//      「回忆 accent 组的蓝」而非品牌色（见 MemoryStoryExperienceViews 中与
//      brandPrimary 并排做渐变）。
//   3. glow 三色（blue/amber/pink）：成组辉光，暗底专属。
// 与 AppColors 真正重复且语义相同的是 **Export 开支分类色**，已在
// ExportTemplateViews.categoryColor 收敛为 AppColors.cat*。


enum MemoryColors {
    // Story dark backgrounds (per-page gradient endpoints)
    static let storyDarkNavy       = Color(hex: 0x0F2744)
    static let storyDarkBlue       = Color(hex: 0x1A3A5C)
    static let storyDarkDeep       = Color(hex: 0x0D1F33)

    // Story page-specific dark variants
    static let storyPlacesDark     = Color(hex: 0x0A1628)
    static let storyPlacesMid      = Color(hex: 0x122A47)
    static let storyStatsDark      = Color(hex: 0x0C1829)
    static let storyStatsMid       = Color(hex: 0x122040)
    static let storyStatsDeep      = Color(hex: 0x0D1B30)
    static let storyJournalPurple1 = Color(hex: 0x2D1B4E)
    static let storyJournalPurple2 = Color(hex: 0x1F1147)
    static let storyJournalPurple3 = Color(hex: 0x0F0A2E)

    // Story accent palette (stats, places, metric items)
    static let accentBlue          = Color(hex: 0x60A5FA)
    static let accentGreen         = Color(hex: 0x34D399)
    static let accentAmber         = Color(hex: 0xFBBF24)
    static let accentPink          = Color(hex: 0xF472B6)
    static let accentPurple        = Color(hex: 0x8B5CF6)
    static let accentEmerald       = Color(hex: 0x10B981)

    // Segment control background
    static let segmentBackground   = Color(hex: 0xEDE9E3)

    // Ending page button text
    static let endingButtonText    = Color(hex: 0x1E3A5F)

    // Glow colors for animated highlights (stats page, memorable page)
    static let glowBlue            = Color(hex: 0x3B82F6).opacity(0.30)
    static let glowAmber           = Color(hex: 0xF59E0B).opacity(0.28)
    static let glowPink            = Color(hex: 0xEC4899).opacity(0.24)

    // Map texture (places page)
    static let mapGridLine         = Color.white.opacity(0.10)
    static let mapPathLine         = Color(hex: 0x60A5FA).opacity(0.20)

    // Progress bar (story overlay)
    static let progressDotActive   = Color.white
    static let progressDotInactive = Color.white.opacity(0.25)

    // NEW badge
    static let newBadgeBg          = Color(hex: 0x3B82F6).opacity(0.85)
    static let newBadgeText        = Color.white

    // Persona card
}

// MARK: - Memory Story Card Background

enum MemoryStoryCardBackgroundStyle {
    /// Warm white → very faint cool tint. Adds depth without competing with content.
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.62),
                AppColors.brandPrimary.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Near-flat fallback for A/B comparison on device.
    static var flat: some View {
        Color.white.opacity(0.55)
    }
}

// MARK: - Memory Gradients

enum MemoryGradients {
    static var storyDark: LinearGradient {
        LinearGradient(
            colors: [MemoryColors.storyDarkNavy, MemoryColors.storyDarkBlue, MemoryColors.storyDarkDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var posterFallback: LinearGradient { storyDark }

    static var mapTextureOverlay: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x0A1628), Color(hex: 0x122A47)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
