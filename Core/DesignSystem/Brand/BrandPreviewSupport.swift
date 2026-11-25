import SwiftUI

/// Shared preview helpers for brand components.
enum BrandPreviewSupport {
    /// Simulates reduce-motion presentation: no entrance animations in previews.
    static func reduceMotion<V: View>(_ content: V) -> some View {
        content.transaction { transaction in
            transaction.disablesAnimations = true
        }
    }
}