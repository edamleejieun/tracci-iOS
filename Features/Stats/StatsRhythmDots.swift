import SwiftUI

// MARK: - StatsRhythmDots

/// Compact “today” rhythm — three counts for 行程 / 日志 / 照片.
///
/// Tool-first labels (not soft companion names). Optional outer card when used alone;
/// pass `showsCard: false` when the parent already provides a surface.
struct StatsRhythmDots: View {
    let itineraryCount: Int
    let journalCount: Int
    let photoCount: Int
    /// Formatted expense when amount > 0, e.g. "¥66". Nil hides the footer.
    let expenseText: String?
    /// When false, only the rhythm content is drawn (parent owns the card).
    var showsCard: Bool = true
    var title: String = "今天"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let total: Int
    private let hasContent: Bool

    init(
        itineraryCount: Int = 0,
        journalCount: Int = 0,
        photoCount: Int = 0,
        expenseText: String? = nil,
        showsCard: Bool = true,
        title: String = "今天"
    ) {
        self.itineraryCount = itineraryCount
        self.journalCount = journalCount
        self.photoCount = photoCount
        self.expenseText = expenseText
        self.showsCard = showsCard
        self.title = title
        self.total = itineraryCount + journalCount + photoCount
        self.hasContent = total > 0
    }

    var body: some View {
        if showsCard {
            AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: AppSpacing.cardSmall) {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if showsCard {
                Text(title)
                    .font(AppTypography.editorialMeta)
                    .tracking(0.5)
                    .foregroundStyle(AppColors.textMuted)
            }

            HStack(alignment: .top, spacing: 0) {
                rhythmDot(
                    count: itineraryCount,
                    icon: "list.bullet.rectangle",
                    label: "行程",
                    color: AppColors.brandPrimary,
                    index: 0
                )
                rhythmDot(
                    count: journalCount,
                    icon: "book.closed",
                    label: "日志",
                    color: AppColors.memoryViolet,
                    index: 1
                )
                rhythmDot(
                    count: photoCount,
                    icon: "photo",
                    label: "照片",
                    color: AppColors.stageOngoing,
                    index: 2
                )
            }
            .frame(maxWidth: .infinity)

            if let expenseText {
                expenseFooter(expenseText)
            }
        }
    }

    private func expenseFooter(_ text: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "yensign.circle")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.dawnGold)
            Text("今天花费 \(text)")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今天花费 \(text)")
    }

    @ViewBuilder
    private func rhythmDot(count: Int, icon: String, label: String, color: Color, index: Int) -> some View {
        let active = count > 0
        let dotSize: CGFloat = 32
        let iconSize: CGFloat = active ? 14 : 12

        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppFont.system(iconSize, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color.opacity(active ? 0.95 : 0.4))
                .frame(width: dotSize, height: dotSize)
                .background(
                    Circle()
                        .fill(active ? color.opacity(0.10) : AppColors.paperWarmLight.opacity(0.55))
                )
                .overlay(
                    Circle()
                        .stroke(
                            active ? color.opacity(0.28) : AppColors.borderSubtle.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .fadeSlideIn(index: index, animation: AppMotion.slow)

            Group {
                if active {
                    TracciNumberPopIn(
                        text: displayText(for: count),
                        font: AppTypography.captionMedium,
                        color: AppColors.textPrimary
                    )
                } else {
                    Text("—")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }
            .frame(height: 16)

            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(active ? AppColors.textSecondary : AppColors.textPlaceholder)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(active ? displayText(for: count) : "无")")
    }

    private func displayText(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

// MARK: - Previews

#if DEBUG
struct StatsRhythmDots_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                StatsRhythmDots(itineraryCount: 2, journalCount: 1, photoCount: 3, expenseText: "¥66")
                    .padding(.horizontal, AppSpacing.pageX)

                StatsRhythmDots(itineraryCount: 4, journalCount: 0, photoCount: 0)
                    .padding(.horizontal, AppSpacing.pageX)

                StatsRhythmDots(itineraryCount: 0, journalCount: 0, photoCount: 0)
                    .padding(.horizontal, AppSpacing.pageX)

                StatsRhythmDots(
                    itineraryCount: 1,
                    journalCount: 5,
                    photoCount: 12,
                    expenseText: "¥248",
                    showsCard: false
                )
                .padding()
                .background(AppColors.paperWarmLight, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, AppSpacing.pageX)
            }
            .padding(.vertical, AppSpacing.xl)
            .background(AppColors.backgroundPrimary)
        }
        .ignoresSafeArea(.container, edges: .top)
        .previewDisplayName("RhythmDots — all states")
    }
}
#endif
