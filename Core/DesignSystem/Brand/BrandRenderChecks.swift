import SwiftUI
import UIKit

/// Lightweight render-path checks for brand views used in export/share snapshots.
/// Self-contained in DesignSystem (no Feature reverse dependency).
enum BrandRenderChecks {
    @MainActor
    static func canRenderWatermarkAndLockup() -> Bool {
        let watermark = render(
            BrandWatermarkView(style: .watermarkDark),
            size: CGSize(width: 320, height: 120)
        )
        let lockup = render(
            BrandLockupView(style: .header),
            size: CGSize(width: 320, height: 80)
        )
        return watermark != nil && lockup != nil
    }

    /// Minimal ImageRenderer helper for light-mode brand snapshots.
    @MainActor
    private static func render<V: View>(_ content: V, size: CGSize, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = scale
        return renderer.uiImage
    }
}

#if DEBUG
#Preview("Brand Render Checks") {
    Text(BrandRenderChecks.canRenderWatermarkAndLockup() ? "Render OK" : "Render Failed")
        .padding()
}
#endif
