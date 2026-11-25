import SwiftUI

struct BrandWordmarkView: View {
    enum Style {
        case primary
        case white
        case large
    }

    var style: Style = .primary
    var size: CGFloat = BrandTokens.headerWordmarkSize

    private var resolvedSize: CGFloat {
        style == .large ? BrandTokens.primaryWordmarkSize : size
    }

    private var textColor: Color {
        style == .white ? .white : BrandTokens.ink
    }

    var body: some View {
        Text("趣溪")
            .font(AppFont.system(resolvedSize, weight: .light))
            .tracking(BrandTokens.wordmarkTracking(for: resolvedSize))
            .foregroundStyle(textColor)
            .accessibilityLabel("趣溪")
    }
}

#Preview("BrandWordmarkView") {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
        BrandWordmarkView(style: .primary, size: 22)
        BrandWordmarkView(style: .primary, size: 16)
        BrandWordmarkView(style: .large)
        ZStack {
            Color.black
            BrandWordmarkView(style: .white, size: 22)
        }
        .frame(height: 60)
    }
    .padding()
}

#Preview("BrandWordmarkView — Reduce Motion") {
    BrandPreviewSupport.reduceMotion(
        BrandWordmarkView(style: .primary, size: 22)
            .padding()
    )
}