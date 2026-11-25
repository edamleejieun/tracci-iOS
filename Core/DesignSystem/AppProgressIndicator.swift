import SwiftUI

/// Branded progress indicator — replaces bare `ProgressView()` on main paths
/// so loading moments share the creek shimmer language instead of the system spinner.
///
/// Two styles:
/// - `.ring`: circular arc with a sweeping rotation (buttons, inline waits).
/// - `.creekLine`: thin creek line with a traveling glint (linear waits, footers).
///
/// Reduce Motion: both styles settle into a static composition with no repeating motion.
struct AppProgressIndicator: View {
    enum Style {
        case ring
        case creekLine
    }

    var style: Style = .ring
    var tint: Color = AppColors.brandPrimary
    /// Ring diameter. Ignored by `.creekLine`.
    var diameter: CGFloat = 22
    /// Creek line height. Ignored by `.ring`.
    var lineHeight: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepRotation: Double = 0
    @State private var glintOffset: CGFloat = -1

    var body: some View {
        switch style {
        case .ring:
            ringBody
        case .creekLine:
            creekLineBody
        }
    }

    // MARK: - Ring

    private var ringLineWidth: CGFloat {
        max(2, diameter * 0.11)
    }

    private var ringBody: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: ringLineWidth)

            Circle()
                .trim(from: 0.06, to: 0.74)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90 + sweepRotation))
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                sweepRotation = 360
            }
        }
    }

    // MARK: - Creek line

    private var creekLineBody: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let glintWidth = width * 0.32

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.14))

                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(0.0), location: 0),
                                .init(color: tint.opacity(0.78), location: 0.5),
                                .init(color: tint.opacity(0.0), location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: glintWidth)
                    .offset(x: glintOffset * width)
            }
        }
        .frame(height: lineHeight)
        .onAppear {
            guard !reduceMotion else { return }
            glintOffset = -0.4
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                glintOffset = 1.1
            }
        }
    }
}

// MARK: - Previews

#Preview("AppProgressIndicator") {
    VStack(spacing: AppSpacing.xl) {
        HStack(spacing: AppSpacing.lg) {
            AppProgressIndicator(diameter: 18)
            AppProgressIndicator(diameter: 22)
            AppProgressIndicator(diameter: 32)
            AppProgressIndicator(tint: .white, diameter: 24)
                .padding(8)
                .background(Color.black, in: Circle())
        }
        AppProgressIndicator(style: .creekLine)
            .frame(width: 220)
    }
    .padding(AppSpacing.xl)
    .tracciPageBackground()
}
