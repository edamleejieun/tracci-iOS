import SwiftUI

struct MemoryTripList: View {
    let trips: [Trip]
    let dateRangeText: (Trip) -> String
    let daysText: (Trip) -> String
    let isNew: (String) -> Bool
    let onOpenReport: (Trip) -> Void
    var launchNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(spacing: AppSpacing.cozy) {
            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                MemoryStoryEntryCard(
                    trip: trip,
                    dateRangeText: dateRangeText(trip),
                    daysText: daysText(trip),
                    isNew: isNew(trip.id),
                    onOpen: {
                        onOpenReport(trip)
                    },
                    launchNamespace: launchNamespace
                )
                .fadeSlideIn(index: index, offset: 12)
            }
        }
    }
}

// MARK: - Memory Story Entry Text Provider

enum MemoryStoryEntryText {
    /// Short status line — date range and day count already on the row above.
    /// Tool-first; no cover/metrics on the entry (those live inside Story).
    static func moodText(for trip: Trip, isNew: Bool) -> String {
        if MemoryDisplayCopy.isSparse(trip: trip) {
            return "记录还不多，也可以先打开看看"
        }
        if isNew {
            return "可以打开回看了"
        }
        return "点开查看照片、日志和花费"
    }
}

struct MemoryStoryEntryCard: View {
    let trip: Trip
    let dateRangeText: String
    let daysText: String
    let isNew: Bool
    let onOpen: () -> Void
    var launchNamespace: Namespace.ID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardRadius: CGFloat = AppRadius.extraLarge

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // Row 1: title + NEW badge + chevron
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(trip.title)
                        .font(AppTypography.storyTitleSerif)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if isNew {
                        MemoryNewBadge()
                            .padding(.leading, AppSpacing.tight)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPlaceholder.opacity(0.45))
                }

                // Row 2: date · days
                HStack(spacing: AppSpacing.tight) {
                    Label(dateRangeText, systemImage: "calendar")
                    Text("·")
                        .foregroundStyle(AppColors.textPlaceholder.opacity(0.3))
                    Label(daysText, systemImage: "clock")
                }
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.textMuted)

                // Row 3: light status line (tool-first)
                Text(MemoryStoryEntryText.moodText(for: trip, isNew: isNew))
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(2)
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MemoryStoryCardBackgroundStyle.gradient)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.borderHighlight, AppColors.memoryViolet.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.65
                    )
            }
            .tracciElevation(.l1)
        }
        .pressableCardStyle(scale: 0.985, opacity: 0.96)
        .contentShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        .modifier(MemoryLaunchZoomSourceModifier(
            id: trip.id,
            namespace: launchNamespace,
            reduceMotion: reduceMotion
        ))
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开这段旅程的回忆")
    }
}

struct MemoryLaunchZoomSourceModifier: ViewModifier {
    let id: String
    var namespace: Namespace.ID?
    var reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.matchedGeometryEffect(
                id: "memory-launch-\(id)",
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )
        } else {
            content
        }
    }
}

struct MemoryLaunchZoomDestinationModifier: ViewModifier {
    let id: String
    var namespace: Namespace.ID?
    var reduceMotion: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.matchedGeometryEffect(
                id: "memory-launch-\(id)",
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: false
            )
        } else {
            content
        }
    }
}

/// Empty-account product tour entry. It mirrors a real Story card without
/// inserting the synthetic trip into MemoryPageViewModel.trips.
struct MemoryDemoStoryEntryCard: View {
    let trip: Trip
    let dateRangeText: String
    let daysText: String
    let journalCount: Int
    let photoCount: Int
    let coverURL: URL?
    let coverFallbackURL: URL?
    let onOpen: () -> Void
    var launchNamespace: Namespace.ID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardRadius: CGFloat = AppRadius.hero
    private static let coverHeight: CGFloat = 218

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    TripCoverView(
                        url: coverURL,
                        fallbackURL: coverFallbackURL,
                        height: Self.coverHeight,
                        cornerRadius: 0
                    )
                    .frame(maxWidth: .infinity)
                    .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.10), location: 0),
                            .init(color: .black.opacity(0.04), location: 0.34),
                            .init(color: .black.opacity(0.76), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.tight) {
                        HStack(spacing: AppSpacing.xs) {
                            Text("示例回忆")
                                .font(AppTypography.captionSemibold)
                                .foregroundStyle(AppColors.memoryViolet)
                                .padding(.horizontal, AppSpacing.sm)
                                .frame(height: 26)
                                .background(.white.opacity(0.94), in: Capsule())

                            Text("仅供查看")
                                .font(AppTypography.chipSemibold)
                                .foregroundStyle(.white.opacity(0.82))
                                .padding(.horizontal, AppSpacing.sm)
                                .frame(height: 26)
                                .background(.black.opacity(0.26), in: Capsule())
                        }

                        Spacer(minLength: 28)

                        Text(trip.title)
                            .font(AppTypography.pageTitle)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .tracciShadow(AppShadow.textStrong)

                        HStack(spacing: AppSpacing.tight) {
                            Label(dateRangeText, systemImage: "calendar")
                            Text("·")
                                .foregroundStyle(.white.opacity(0.45))
                            Text(daysText)
                        }
                        .font(AppTypography.label)
                        .foregroundStyle(.white.opacity(0.84))
                    }
                    .padding(AppSpacing.card)
                }
                .frame(height: Self.coverHeight)

                HStack(spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(journalCount) 条日志 · \(photoCount) 张照片")
                            .font(AppTypography.labelSemibold)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("看看一段完整旅程如何变成回忆")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: AppSpacing.sm)

                    HStack(spacing: 6) {
                        Text("打开示例")
                        Image(systemName: "arrow.right")
                    }
                    .font(AppTypography.labelSemibold)
                    .foregroundStyle(AppColors.memoryViolet)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(height: 40)
                    .background(AppColors.memoryMist, in: Capsule())
                }
                .padding(AppSpacing.card)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppColors.memoryViolet.opacity(0.42),
                                AppColors.borderHighlight,
                                AppColors.memoryViolet.opacity(0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            }
            .tracciElevation(.l2)
        }
        .pressableCardStyle(scale: 0.98, opacity: 0.95)
        .contentShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
        .modifier(MemoryLaunchZoomSourceModifier(
            id: trip.id,
            namespace: launchNamespace,
            reduceMotion: reduceMotion
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("示例回忆，\(trip.title)，\(journalCount) 条日志，\(photoCount) 张照片")
        .accessibilityHint("打开只读示例回忆")
    }
}

// MARK: - Memory New Badge

struct MemoryNewBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        Text("NEW")
            .font(AppFont.system(9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(MemoryColors.newBadgeText)
            .padding(.horizontal, AppSpacing.tight)
            .frame(height: 20)
            .background(MemoryColors.newBadgeBg, in: Capsule())
            .scaleEffect(appeared || reduceMotion ? 1 : 0.62)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(
                x: appeared || reduceMotion ? 0 : -AppMotion.fadeSlideOffset * 0.6,
                y: appeared || reduceMotion ? 0 : AppMotion.fadeSlideOffset * 0.6
            )
            .onAppear {
                withAnimation(AppMotion.animation(AppMotion.badgePop, reduceMotion: reduceMotion)) {
                    appeared = true
                }
            }
    }
}
