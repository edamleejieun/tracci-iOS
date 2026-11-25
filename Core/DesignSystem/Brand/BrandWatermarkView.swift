import SwiftUI

struct BrandWatermarkView: View {
    enum Style {
        case watermarkDark
        case watermarkLight
    }

    var style: Style
    var logoHeight: CGFloat = BrandTokens.watermarkLogoHeight
    var wordmarkSize: CGFloat = BrandTokens.watermarkWordmarkSize

    private var isDark: Bool { style == .watermarkDark }

    var body: some View {
        HStack(spacing: BrandTokens.watermarkSpacing) {
            BrandLogoView(
                style: isDark ? .blue : .white,
                height: logoHeight
            )
            BrandWordmarkView(
                style: isDark ? .primary : .white,
                size: wordmarkSize
            )
        }
        .opacity(BrandTokens.watermarkOpacity(isDark: isDark))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("BrandWatermarkView") {
    VStack(spacing: 32) {
        BrandWatermarkView(style: .watermarkDark)
        ZStack {
            Color.black
            BrandWatermarkView(style: .watermarkLight)
        }
        .frame(height: 80)
    }
    .padding()
}

#Preview("BrandWatermarkView — Reduce Motion") {
    BrandPreviewSupport.reduceMotion(
        BrandWatermarkView(style: .watermarkDark)
            .padding()
    )
}