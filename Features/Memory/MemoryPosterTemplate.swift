import SwiftUI

// MARK: - Memory Poster Template

struct MemoryPosterTemplate: View {
    let summary: TripSummaryResponse
    let coverImage: UIImage?

    private var displayTitle: String {
        summary.trip.title
    }

    private var narrative: MemoryStoryNarrative {
        MemoryStoryNarrativeBuilder.build(for: summary)
    }

    private var visitedPlaces: [String] {
        MemoryStoryNarrativeBuilder.visitedPlaces(from: summary)
    }

    private var visitedPlaceCount: Int {
        visitedPlaces.count
    }

    private var primaryMetric: MemoryStoryHeroMetric {
        MemoryStoryNarrativeBuilder.primaryHeroMetric(for: summary)
    }

    private var quoteText: String? {
        summary.highlightLogs
            .compactMap { $0.content?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private var dateLine: String {
        ExportFormatting.dateRangeText(
            startDate: summary.trip.startDate,
            endDate: summary.trip.endDate
        )
    }

    var body: some View {
        ZStack {
            backgroundLayer
            posterAtmosphere
            contentLayer
        }
        .frame(width: 1080, height: 1920)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .scaledToFill()
                .frame(width: 1080, height: 1920)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.38), location: 0),
                            .init(color: .black.opacity(0.05), location: 0.3),
                            .init(color: .black.opacity(0.05), location: 0.5),
                            .init(color: .black.opacity(0.50), location: 0.75),
                            .init(color: .black.opacity(0.72), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.20)],
                        center: .center,
                        startRadius: 300,
                        endRadius: 800
                    )
                }
        } else {
            ZStack {
                MemoryGradients.posterFallback
                LinearGradient(
                    colors: [
                        MemoryColors.storyStatsDark.opacity(0.35),
                        MemoryColors.storyJournalPurple2.opacity(0.45),
                        MemoryColors.storyDarkDeep.opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var posterAtmosphere: some View {
        ZStack {
            Circle()
                .fill(MemoryColors.accentBlue.opacity(0.24))
                .frame(width: 560, height: 560)
                .blur(radius: 160)
                .offset(x: 350, y: -610)

            Circle()
                .fill(primaryMetric.color.opacity(0.25))
                .frame(width: 520, height: 520)
                .blur(radius: 150)
                .offset(x: -380, y: 320)

            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 2)
                .frame(width: 620, height: 620)
                .offset(x: 310, y: 110)

            Canvas { context, size in
                let step: CGFloat = 84
                var y: CGFloat = 260
                while y < size.height - 260 {
                    var x: CGFloat = 90
                    while x < size.width - 90 {
                        let rect = CGRect(x: x, y: y, width: 4, height: 4)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.08)))
                        x += step
                    }
                    y += step
                }
            }
        }
    }

    // MARK: - Content

    private var contentLayer: some View {
        VStack(spacing: 0) {
            headerBlock
                .padding(.top, 128)

            Spacer(minLength: 52)

            heroBlock

            Spacer(minLength: 48)

            storyBlock

            Spacer(minLength: 44)

            footerBlock
                .padding(.bottom, 94)
        }
        .padding(.horizontal, 84)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("TRIP STORY")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))
                    .tracking(4)
                Spacer()
                Text("\(summary.trip.dayCount) DAYS")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .background(.white.opacity(0.10), in: Capsule())
            }

            Text(displayTitle)
                .font(.system(size: 86, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .tracciElevation(.l4)

            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 24, weight: .medium))
                Text(dateLine)
                    .font(.system(size: 30, weight: .medium))
                if visitedPlaceCount > 0 {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.40))
                    Text("\(visitedPlaceCount) 个地点")
                        .font(.system(size: 30, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroBlock: some View {
        HStack(alignment: .center, spacing: 42) {
            ZStack {
                Circle()
                    .fill(primaryMetric.color.opacity(0.16))
                    .frame(width: 350, height: 350)
                    .blur(radius: 52)
                Circle()
                    .fill(.white.opacity(0.09))
                    .frame(width: 286, height: 286)
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 1.6)
                    .frame(width: 286, height: 286)

                VStack(spacing: 12) {
                    Text("\(primaryMetric.value)")
                        .font(.system(size: 108, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)
                    Text(primaryMetric.unit)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(primaryMetric.color)
                    Text(primaryMetric.caption)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.50))
                }
                .frame(width: 250)
            }

            VStack(alignment: .leading, spacing: 18) {
                Text(narrative.poster)
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineSpacing(10)
                    .minimumScaleFactor(0.72)
                    .lineLimit(4)

                Text(narrative.endingSummary)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(0.6)
            }
        }
    }

    @ViewBuilder
    private var storyBlock: some View {
        if let quoteText {
            MemoryPosterQuotePanel(quote: quoteText)
        } else if !visitedPlaces.isEmpty {
            MemoryPosterPlacePanel(places: Array(visitedPlaces.prefix(5)))
        } else {
            MemoryPosterQuotePanel(quote: "这段旅程，留下了一些。")
        }
    }

    private var footerBlock: some View {
        VStack(spacing: 34) {
            HStack(spacing: 14) {
                MemoryPosterMetricItem(
                    icon: "calendar",
                    value: summary.stats.dayCount,
                    label: "天",
                    color: MemoryColors.accentBlue
                )
                MemoryPosterMetricItem(
                    icon: "mappin",
                    value: visitedPlaceCount,
                    label: "个地点",
                    color: MemoryColors.accentGreen
                )
                MemoryPosterMetricItem(
                    icon: "camera",
                    value: summary.stats.photoCount,
                    label: "张照片",
                    color: MemoryColors.accentAmber
                )
                MemoryPosterMetricItem(
                    icon: "book",
                    value: summary.stats.journalCount,
                    label: "篇日志",
                    color: MemoryColors.accentPink
                )
            }

            HStack {
                BrandWatermarkView(style: .watermarkLight, logoHeight: 28, wordmarkSize: 24)
                Spacer()
                Text("趣溪 · 旅途记录")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
            }
        }
    }
}

// MARK: - Metric Item

struct MemoryPosterMetricItem: View {
    let icon: String
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(color)

            Text("\(value)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(label)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))
        }
        .frame(width: 172, height: 154)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct MemoryPosterQuotePanel: View {
    let quote: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(.white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 46, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1.2)
                }

            Circle()
                .fill(MemoryColors.accentPink.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: -74, y: -92)

            VStack(alignment: .leading, spacing: 26) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(MemoryColors.accentPink.opacity(0.72))

                Text(quote)
                    .font(.system(size: 38, weight: .medium, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(12)
                    .lineLimit(5)
                    .minimumScaleFactor(0.74)

                HStack(spacing: 14) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [MemoryColors.accentAmber, MemoryColors.accentPink],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 6, height: 58)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("来自旅途中的记录")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text("来自这段旅程的记录")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
            }
            .padding(46)
        }
        .frame(height: 430)
    }
}

private struct MemoryPosterPlacePanel: View {
    let places: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("你走过的地方")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            FlowPlaceRows(places: places)
        }
        .padding(42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1.2)
        }
    }
}

private struct FlowPlaceRows: View {
    let places: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(places, id: \.self) { place in
                HStack(spacing: 14) {
                    Image(systemName: "mappin")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(MemoryColors.accentGreen)
                    Text(place)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)
                .frame(height: 58)
                .background(.white.opacity(0.08), in: Capsule())
            }
        }
    }
}
