import SwiftUI
import UIKit

// MARK: - Scaled system font helper

/// Builds system fonts that track Dynamic Type while keeping design sizes at the default content size.
///
/// Prefer these tokens over raw `Font.system(size:)` so type scales with Settings → Display & Text Size.
enum AppFont {
    /// Scaled system font. `size` is the design size at the default content-size category.
    static func scaled(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        let base = makeUIFont(size: size, weight: weight, design: design)
        let metrics = UIFontMetrics(forTextStyle: textStyle.uiKitTextStyle)
        return Font(metrics.scaledFont(for: base))
    }

    /// Drop-in replacement for `Font.system(size:weight:design:)` that scales with Dynamic Type.
    ///
    /// Prefer named `AppTypography` tokens when a role is clear; use this for one-off sizes
    /// (icons, dense chrome) so they still track the system content-size category.
    static func system(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        scaled(size: size, weight: weight, design: design, relativeTo: relativeTextStyle(for: size))
    }

    /// Picks a UIFontMetrics text style anchor from the design size.
    static func relativeTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ...11: return .caption2
        case ...12.5: return .caption
        case ...13.5: return .footnote
        case ...14.5: return .subheadline
        case ...15.5: return .callout
        case ...16.5: return .body
        case ...18: return .headline
        case ...20: return .title3
        case ...24: return .title2
        case ...30: return .title
        default: return .largeTitle
        }
    }

    private static func makeUIFont(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design
    ) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight)
        guard let descriptor = system.fontDescriptor.withDesign(design.uiFontDesign) else {
            return system
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

private extension Font.TextStyle {
    var uiKitTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

private extension Font.Weight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

private extension Font.Design {
    var uiFontDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .default: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        @unknown default: return .default
        }
    }
}

// MARK: - App Typography tokens

/// Shared type scale. All tokens scale with Dynamic Type.
///
/// Design sizes match the previous fixed pt values at the **default** content-size category.
enum AppTypography {
    // MARK: - Editorial roles

    /// Emotional hero line. Use sparingly and never color Chinese display titles blue.
    static var displayHero: Font {
        AppFont.scaled(size: 32, weight: .semibold, relativeTo: .largeTitle)
    }

    // MARK: - Home editorial (system rounded — no third-party fonts)

    /// Home greeting line — rounded for warmth without leaving the system stack.
    static var homeGreeting: Font {
        AppFont.scaled(size: 26, weight: .semibold, design: .rounded, relativeTo: .title)
    }

    /// Home companion sentence under the greeting.
    static var homeCompanion: Font {
        AppFont.scaled(size: 15, weight: .regular, design: .rounded, relativeTo: .subheadline)
    }

    /// Home date / slogan meta with editorial tracking applied at call site.
    static var homeMeta: Font {
        AppFont.scaled(size: 12, weight: .medium, design: .rounded, relativeTo: .caption)
    }

    /// No-cover featured journey title. Slightly quieter than a full media hero headline.
    static var homeStageTitle: Font {
        AppFont.scaled(size: 26, weight: .semibold, relativeTo: .title)
    }

    /// Compact remaining-journey row title.
    static var homeArchiveTitle: Font {
        AppFont.scaled(size: 15, weight: .medium, relativeTo: .body)
    }

    static var tripTitle: Font {
        AppFont.scaled(size: 28, weight: .semibold, relativeTo: .title)
    }

    static var dayTitle: Font {
        AppFont.scaled(size: 20, weight: .semibold, relativeTo: .title3)
    }

    static var narrativeBody: Font {
        AppFont.scaled(size: 16, weight: .regular, relativeTo: .body)
    }

    /// Date, stage, and editorial metadata. Pair with restrained tracking at the call site.
    static var editorialMeta: Font {
        AppFont.scaled(size: 11, weight: .semibold, relativeTo: .caption2)
    }

    static var editorialNumber: Font {
        AppFont.scaled(size: 24, weight: .semibold, design: .rounded, relativeTo: .title2)
            .monospacedDigit()
    }

    // MARK: - Page / Section

    static var pageTitle: Font {
        AppFont.scaled(size: 24, weight: .semibold, relativeTo: .title2)
    }

    /// Bottom sheet picker titles — aligned with date/range pickers.
    static var pickerSheetTitle: Font {
        AppFont.scaled(size: 24, weight: .semibold, relativeTo: .title2)
    }

    static var pickerSheetSubtitle: Font {
        AppFont.scaled(size: 14, weight: .regular, relativeTo: .subheadline)
    }

    static var pageSubtitle: Font {
        AppFont.scaled(size: 13, weight: .regular, relativeTo: .footnote)
    }

    static var sectionTitle: Font {
        AppFont.scaled(size: 18, weight: .semibold, relativeTo: .title3)
    }

    static var sectionEyebrow: Font {
        AppFont.scaled(size: 13, weight: .medium, relativeTo: .footnote)
    }

    /// Settings / grouped-list row label — closer to iOS Settings 17pt than body 14.
    static var settingsRowLabel: Font {
        AppFont.scaled(size: 16, weight: .regular, relativeTo: .body)
    }

    static var settingsRowValue: Font {
        AppFont.scaled(size: 15, weight: .regular, relativeTo: .subheadline)
    }

    // MARK: - Card

    static var cardTitle: Font {
        AppFont.scaled(size: 17, weight: .semibold, relativeTo: .headline)
    }

    static var cardBody: Font {
        AppFont.scaled(size: 14, weight: .regular, relativeTo: .subheadline)
    }

    // MARK: - Serif Display pilot (G2.1)

    /// Editorial display serif (system New York / 宋体栈 — zero third-party fonts).
    /// Approved pilot positions only: 回忆页故事标题 / 年度年份. Body, tool and form
    /// text stays sans; story & poster export canvases keep their fixed-size raw
    /// serif rendering (pixel-precise, intentionally not Dynamic-Type scaled).
    static var storyTitleSerif: Font {
        AppFont.scaled(size: 17, weight: .semibold, design: .serif, relativeTo: .headline)
    }

    /// Year mark for the yearly-report card — serif digits read as an editorial masthead.
    static var yearMarkSerif: Font {
        AppFont.scaled(size: 18, weight: .semibold, design: .serif, relativeTo: .title3)
    }

    // MARK: - Body / Label / Caption

    static var body: Font {
        AppFont.scaled(size: 14, weight: .regular, relativeTo: .subheadline)
    }

    static var bodyMedium: Font {
        AppFont.scaled(size: 14, weight: .medium, relativeTo: .subheadline)
    }

    static var bodySemibold: Font {
        AppFont.scaled(size: 14, weight: .semibold, relativeTo: .subheadline)
    }

    static var label: Font {
        AppFont.scaled(size: 13, weight: .medium, relativeTo: .footnote)
    }

    static var labelRegular: Font {
        AppFont.scaled(size: 13, weight: .regular, relativeTo: .footnote)
    }

    static var labelSemibold: Font {
        AppFont.scaled(size: 13, weight: .semibold, relativeTo: .footnote)
    }

    static var caption: Font {
        AppFont.scaled(size: 12, weight: .regular, relativeTo: .caption)
    }

    static var captionMedium: Font {
        AppFont.scaled(size: 12, weight: .medium, relativeTo: .caption)
    }

    static var captionSemibold: Font {
        AppFont.scaled(size: 12, weight: .semibold, relativeTo: .caption)
    }

    /// Dense chrome / badges (~11pt).
    static var chip: Font {
        AppFont.scaled(size: 11, weight: .medium, relativeTo: .caption2)
    }

    static var chipSemibold: Font {
        AppFont.scaled(size: 11, weight: .semibold, relativeTo: .caption2)
    }

    /// Micro badges / timeline markers (~11pt — iOS 可读下限，勿低于 11pt).
    static var micro: Font {
        AppFont.scaled(size: 11, weight: .medium, relativeTo: .caption2)
    }

    static var microSemibold: Font {
        AppFont.scaled(size: 11, weight: .semibold, relativeTo: .caption2)
    }

    /// Single-line form field value / text editor body (default ~15pt).
    static var formValue: Font {
        AppFont.scaled(size: 15, weight: .regular, relativeTo: .body)
    }

    /// Monospaced form value (e.g. invite codes).
    static var formValueMonospaced: Font {
        AppFont.scaled(size: 15, weight: .medium, design: .monospaced, relativeTo: .body)
    }

    /// Secondary list title (~16pt).
    static var listTitle: Font {
        AppFont.scaled(size: 16, weight: .semibold, relativeTo: .body)
    }

    static var listTitleMedium: Font {
        AppFont.scaled(size: 16, weight: .medium, relativeTo: .body)
    }

    static var listBody: Font {
        AppFont.scaled(size: 16, weight: .regular, relativeTo: .body)
    }

    /// Dense chip regular (~11pt).
    static var chipRegular: Font {
        AppFont.scaled(size: 11, weight: .regular, relativeTo: .caption2)
    }

    /// Micro regular (~11pt — iOS 可读下限).
    static var microRegular: Font {
        AppFont.scaled(size: 11, weight: .regular, relativeTo: .caption2)
    }

    /// Form / callout semibold alias (same as buttonTitle).
    static var calloutSemibold: Font {
        buttonTitle
    }

    static var calloutMedium: Font {
        buttonTitleMedium
    }

    static var callout: Font {
        formValue
    }

    // MARK: - Metric / Display

    static var bigNumber: Font {
        AppFont.scaled(size: 42, weight: .semibold, relativeTo: .largeTitle)
    }

    /// Completed-trip insight evidence grid — 大数字 + 小标签.
    /// Sits between `editorialNumber` (24) and `bigNumber` (42) so long CNY
    /// amounts still fit a two-column grid cell; rounded + tabular digits.
    static var evidenceNumber: Font {
        AppFont.scaled(size: 30, weight: .semibold, design: .rounded, relativeTo: .title)
            .monospacedDigit()
    }

    static var metricValue: Font {
        AppFont.scaled(size: 22, weight: .bold, design: .rounded, relativeTo: .title2)
    }

    // MARK: - Button

    static var buttonTitle: Font {
        AppFont.scaled(size: 15, weight: .semibold, relativeTo: .callout)
    }

    static var buttonTitleMedium: Font {
        AppFont.scaled(size: 15, weight: .medium, relativeTo: .callout)
    }

    static var buttonTitleSecondary: Font {
        AppFont.scaled(size: 15, weight: .medium, relativeTo: .callout)
    }

    // MARK: - Icon / Empty State (module-specific)

    static var eyebrow: Font {
        AppFont.scaled(size: 12, weight: .semibold, relativeTo: .caption)
    }

    static var iconLabel: Font {
        AppFont.scaled(size: 12, weight: .semibold, relativeTo: .caption)
    }

    static var emptyIcon: Font {
        AppFont.scaled(size: 36, weight: .light, relativeTo: .title)
    }

    /// SF Symbol size paired with button titles.
    static var buttonIcon: Font {
        AppFont.scaled(size: 16, weight: .semibold, relativeTo: .callout)
    }

    /// Compact SF Symbol size for secondary / ghost buttons.
    static var buttonIconCompact: Font {
        AppFont.scaled(size: 14, weight: .medium, relativeTo: .footnote)
    }
}
