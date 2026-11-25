import SwiftUI

// MARK: - StatsRadarDecoration

/// Subtle radar-style decorative element for the Insights page empty / loading states.
///
/// Design intent:
///   Three concentric pulse circles with a center Sparkles icon, expressing
///   "insights will slowly appear" — calm, warm, non-interactive.
///   Used only in the no-trip / empty-state context of the Insights tab.
///   Does not compete with content; opacity is intentionally restrained.
///
/// Visual reference: InsightScreen RadarDecor (Figma Make reference).
struct StatsRadarDecoration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Outer ring at 38% brand opacity, middle at 25%, inner at 12%
    private let ringColors: [Color] = [
        AppColors.brandPrimary.opacity(0.38),
        AppColors.brandPrimary.opacity(0.25),
        AppColors.brandPrimary.opacity(0.12),
    ]

    // Each ring expands by a different ratio — outermost expands most,
    // innermost barely moves — creating an outward-propagating pulse wave.
    private let scaleExpansions: [CGFloat] = [0.28, 0.18, 0.10]

    // Stagger delay between rings for sequential pulse (outer → middle → inner).
    private let ringStagger: TimeInterval = 0.6

    // One full pulse cycle duration.
    private let pulseCycle: TimeInterval = 3.0

    var body: some View {
        if reduceMotion {
            radarFrame(time: 0, animated: false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                radarFrame(time: timeline.date.timeIntervalSinceReferenceDate, animated: true)
            }
        }
    }

    // Use a typed array so ForEach can infer the collection element type.
    private var ringIndices: [Int] { Array(0..<ringColors.count) }

    private let baseOpacities: [Double] = [0.38, 0.25, 0.12]

    private func radarFrame(time: TimeInterval, animated: Bool) -> some View {
        ZStack {
            ForEach(ringIndices, id: \.self) { index in
                let phase = pulsePhase(time: time, delay: Double(index) * ringStagger)
                Circle()
                    .stroke(ringColors[index], lineWidth: 1.4)
                    .frame(width: ringSize(for: index), height: ringSize(for: index))
                    .scaleEffect(animated ? 0.88 + scaleExpansions[index] * phase : 1)
                    .opacity(animated ? baseOpacities[index] * (1 - phase) : baseOpacities[index])
            }

            Circle()
                .fill(AppColors.brandPrimaryBackground)
                .frame(width: 42, height: 42)
                .scaleEffect(animated ? 1 + 0.05 * breathePhase(time: time) : 1)

            Image(systemName: "sparkles")
                .font(AppTypography.listTitleMedium)
                .foregroundStyle(AppColors.brandPrimary.opacity(0.82))
                .scaleEffect(animated ? 1 + 0.06 * breathePhase(time: time) : 1)
                .opacity(animated ? 0.72 + 0.16 * breathePhase(time: time) : 0.82)
        }
    }

    private func pulsePhase(time: TimeInterval, delay: TimeInterval) -> CGFloat {
        let shifted = (time - delay).truncatingRemainder(dividingBy: pulseCycle)
        let normalized = shifted < 0 ? shifted / pulseCycle + 1 : shifted / pulseCycle
        return CGFloat(normalized)
    }

    private func breathePhase(time: TimeInterval) -> CGFloat {
        let t = (time.truncatingRemainder(dividingBy: pulseCycle)) / pulseCycle
        return CGFloat((sin(t * 2 * .pi - .pi / 2) + 1) / 2)
    }

    private func ringSize(for index: Int) -> CGFloat {
        // Center icon ~40pt; rings expand 24pt per step
        40 + CGFloat(index) * 24
    }
}

// MARK: - Preview

#if DEBUG
struct StatsRadarDecoration_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 48) {
            StatsRadarDecoration()
                .frame(width: 120, height: 120)

            StatsRadarDecoration()
                .frame(width: 120, height: 120)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
        .padding(.vertical, 60)
        .background(AppColors.backgroundPrimary)
    }
}
#endif
