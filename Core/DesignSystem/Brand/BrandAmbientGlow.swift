import SwiftUI

struct BrandAmbientGlow: View {
    /// When true, skips breathing animation (used for reduce-motion previews).
    var isStatic: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(BrandTokens.blue.opacity(breathe ? BrandTokens.glowMaxOpacity : BrandTokens.glowMinOpacity))
                .frame(width: BrandTokens.glowPrimaryDiameter, height: BrandTokens.glowPrimaryDiameter)
                .blur(radius: 28)

            Circle()
                .fill(BrandTokens.blue.opacity(breathe ? BrandTokens.glowMinOpacity : BrandTokens.glowMaxOpacity * 0.75))
                .frame(width: BrandTokens.glowSecondaryDiameter, height: BrandTokens.glowSecondaryDiameter)
                .blur(radius: 18)
                .offset(x: 12, y: -8)
        }
        // Flatten blur layers into one texture so opacity breathing is cheaper
        // during concurrent page transitions (auth SDK present, etc.).
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, !isStatic else { return }
            // Slightly longer breathe reads calmer on emotional surfaces (auth / empty).
            let breatheMotion = Animation.easeInOut(duration: AppMotion.slowDuration * 2.4)
            let animation = AppMotion.animation(breatheMotion, reduceMotion: reduceMotion) ?? breatheMotion
            withAnimation(animation.repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

#Preview("BrandAmbientGlow") {
    ZStack {
        Color.white
        BrandAmbientGlow()
        BrandLogoView(style: .blue, height: 60)
    }
    .frame(width: 200, height: 200)
}

#Preview("BrandAmbientGlow — Reduce Motion") {
    ZStack {
        BrandTokens.background
        BrandAmbientGlow(isStatic: true)
        BrandLogoView(style: .blue, height: 60)
    }
    .frame(width: 200, height: 200)
}