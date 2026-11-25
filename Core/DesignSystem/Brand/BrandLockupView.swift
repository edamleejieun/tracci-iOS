import SwiftUI

struct BrandLockupView: View {
    enum Style {
        case header
        case primary
        case white
    }

    var style: Style = .header
    var showsGlow: Bool = false
    var showsSlogan: Bool = false
    var subtitle: String?
    var logoHeight: CGFloat?
    var wordmarkSize: CGFloat?

    private var isWhite: Bool { style == .white }

    private var resolvedLogoHeight: CGFloat {
        logoHeight ?? (style == .header ? BrandTokens.headerLogoHeight : BrandTokens.primaryLogoHeight)
    }

    private var resolvedWordmarkSize: CGFloat {
        wordmarkSize ?? (style == .header ? BrandTokens.headerWordmarkSize : BrandTokens.primaryWordmarkSize)
    }

    var body: some View {
        Group {
            switch style {
            case .header:
                headerLockup
            case .primary, .white:
                primaryLockup
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("趣溪")
    }

    private var headerLockup: some View {
        HStack(alignment: .center, spacing: BrandTokens.headerSpacing) {
            BrandLogoView(
                style: isWhite ? .white : .blue,
                height: resolvedLogoHeight
            )

            if let subtitle {
                VStack(alignment: .leading, spacing: 2) {
                    BrandWordmarkView(
                        style: isWhite ? .white : .primary,
                        size: resolvedWordmarkSize
                    )
                    Text(subtitle)
                        .font(AppFont.system(max(12, resolvedWordmarkSize * 0.75), weight: .semibold))
                        .foregroundStyle(isWhite ? .white.opacity(0.72) : Color(hex: 0x7B8589))
                }
            } else {
                BrandWordmarkView(
                    style: isWhite ? .white : .primary,
                    size: resolvedWordmarkSize
                )
            }
        }
    }

    private var primaryLockup: some View {
        VStack(spacing: BrandTokens.primaryStackSpacing) {
            ZStack {
                if showsGlow {
                    BrandAmbientGlow()
                }
                BrandLogoView(
                    style: isWhite ? .white : .blue,
                    height: resolvedLogoHeight
                )
            }

            BrandWordmarkView(
                style: isWhite ? .white : .primary,
                size: resolvedWordmarkSize
            )

            if let subtitle {
                Text(subtitle)
                    .font(AppFont.system(14, weight: .medium))
                    .foregroundStyle(isWhite ? .white.opacity(0.72) : Color(hex: 0x7B8589))
                    .padding(.top, BrandTokens.primarySloganSpacing - BrandTokens.primaryStackSpacing)
            } else if showsSlogan {
                BrandSloganView(style: isWhite ? .white : .primary)
                    .padding(.top, BrandTokens.primarySloganSpacing - BrandTokens.primaryStackSpacing)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("BrandLockupView — Header") {
    BrandLockupView(style: .header)
        .padding()
}

#Preview("BrandLockupView — Header Reduce Motion") {
    BrandPreviewSupport.reduceMotion(
        BrandLockupView(style: .header)
            .padding()
    )
}

#Preview("BrandLockupView — Primary") {
    BrandLockupView(style: .primary, showsGlow: true, showsSlogan: true)
        .padding()
}

#Preview("BrandLockupView — Primary Reduce Motion") {
    BrandPreviewSupport.reduceMotion(
        BrandLockupView(style: .primary, showsGlow: true, showsSlogan: true)
            .padding()
    )
}

#Preview("BrandLockupView — White") {
    ZStack {
        Color.black
        BrandLockupView(style: .white, showsSlogan: true)
    }
    .frame(height: 280)
}