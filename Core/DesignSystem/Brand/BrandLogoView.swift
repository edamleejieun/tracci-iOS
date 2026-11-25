import SwiftUI

struct BrandLogoView: View {
    enum Style {
        case blue
        case white
    }

    var style: Style = .blue
    var height: CGFloat = BrandTokens.headerLogoHeight

    private var assetName: String {
        switch style {
        case .blue: "Brand/BrandLogoBlue"
        case .white: "Brand/BrandLogoWhite"
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

#Preview("BrandLogoView") {
    VStack(spacing: AppSpacing.pageTop) {
        BrandLogoView(style: .blue, height: 22)
        BrandLogoView(style: .blue, height: 64)
        ZStack {
            Color.black
            BrandLogoView(style: .white, height: 64)
        }
        .frame(height: 100)
    }
    .padding()
}

#Preview("BrandLogoView — Reduce Motion") {
    BrandPreviewSupport.reduceMotion(
        BrandLogoView(style: .blue, height: 22)
            .padding()
    )
}