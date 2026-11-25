import SwiftUI

struct BrandSloganView: View {
    enum Style {
        case primary
        case white
    }

    var style: Style = .primary

    private var textColor: Color {
        style == .white ? .white : BrandTokens.ink
    }

    var body: some View {
        Text("让每段旅途，自然成溪")
            .font(AppFont.system(16, weight: .light))
            .tracking(16 * BrandTokens.sloganTrackingRatio)
            .foregroundStyle(textColor)
    }
}

#Preview("BrandSloganView") {
    VStack(spacing: AppSpacing.cardSmall) {
        BrandSloganView(style: .primary)
        ZStack {
            Color.black
            BrandSloganView(style: .white)
        }
        .frame(height: 60)
    }
    .padding()
}

#Preview("BrandSloganView — Reduce Motion") {
    BrandPreviewSupport.reduceMotion(
        BrandSloganView(style: .primary)
            .padding()
    )
}