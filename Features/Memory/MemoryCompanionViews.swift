import SwiftUI

struct MemoryEmptyHeroCard: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.brandPrimaryBackground.opacity(0.88),
                            AppColors.brandPrimaryBackground.opacity(0.46),
                            AppColors.subtleWarm
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            MemoryHeroFlowDecoration()
                .frame(width: 188, height: 142)
                .offset(x: 28, y: -22)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(AppColors.brandPrimary)
                        .frame(width: 6, height: 6)
                    Text("从第一段旅程开始")
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(AppColors.brandPrimary)
                }

                Text("有了第一段旅程，\n这里就能开始回看")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineSpacing(4)

                Text("不用提前准备。出发之后，照片、日志和花费会逐步出现在这里。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.xl)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .stroke(AppColors.brandPrimary.opacity(0.10), lineWidth: 0.8)
        }
    }
}

private struct MemoryHeroFlowDecoration: View {
    var body: some View {
        Canvas { context, size in
            let lines: [(CGFloat, Color, CGFloat)] = [
                (0.28, AppColors.brandPrimary.opacity(0.10), 1.6),
                (0.58, AppColors.brandWarm.opacity(0.08), 1.2)
            ]

            for (offset, color, width) in lines {
                var path = Path()
                path.move(to: CGPoint(x: size.width * -0.02, y: size.height * offset))
                path.addCurve(
                    to: CGPoint(x: size.width * 1.08, y: size.height * (offset + 0.10)),
                    control1: CGPoint(x: size.width * 0.30, y: size.height * (offset - 0.24)),
                    control2: CGPoint(x: size.width * 0.64, y: size.height * (offset + 0.28))
                )
                context.stroke(path, with: .color(color), lineWidth: width)
            }

            context.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.64, y: size.height * 0.12, width: 54, height: 54)),
                with: .color(.white.opacity(0.34))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * 0.12, y: size.height * 0.72, width: 28, height: 28)),
                with: .color(.white.opacity(0.24))
            )
        }
    }
}

struct MemoryMaterialSourcesView: View {
    /// Equal-height bricks — no staggered heights/offsets (avoids “unfinished layout” look).
    private static let brickHeight: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            Text("可以在这里查看")
                .font(AppTypography.chipSemibold)
                .tracking(0.8)
                .foregroundStyle(AppColors.textMuted)

            HStack(alignment: .top, spacing: AppSpacing.sm) {
                MemoryMaterialSourceCard(
                    systemImage: "camera",
                    title: "照片",
                    subtitle: "旅途中拍下的照片",
                    height: Self.brickHeight
                )

                MemoryMaterialSourceCard(
                    systemImage: "square.and.pencil",
                    title: "日志",
                    subtitle: "路上的记录与时间",
                    height: Self.brickHeight
                )

                MemoryMaterialSourceCard(
                    systemImage: "creditcard",
                    title: "花费",
                    subtitle: "钱花在了哪里",
                    height: Self.brickHeight
                )
            }
        }
    }
}

private struct MemoryMaterialSourceCard: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 36, height: 36)
                .background(
                    AppColors.brandPrimaryBackground.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                )

            Spacer(minLength: AppSpacing.sm)

            Text(title)
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Text(subtitle)
                .font(AppTypography.chipRegular)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
                .lineSpacing(2)
                .padding(.top, 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            AppColors.cardAltBackground,
            in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 0.6)
        }
    }
}

struct MemoryConvergingFlowView: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 4)
            let starts: [CGPoint] = [
                CGPoint(x: size.width * 0.16, y: 0),
                CGPoint(x: size.width * 0.50, y: 0),
                CGPoint(x: size.width * 0.84, y: 0)
            ]
            let opacities: [Double] = [0.28, 0.20, 0.14]

            for (index, start) in starts.enumerated() {
                var path = Path()
                path.move(to: start)
                path.addCurve(
                    to: center,
                    control1: CGPoint(x: start.x, y: size.height * 0.48),
                    control2: CGPoint(x: center.x, y: size.height * 0.52)
                )
                context.stroke(
                    path,
                    with: .color(AppColors.brandPrimary.opacity(opacities[index])),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])
                )
            }

            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                with: .color(AppColors.brandPrimary.opacity(0.32))
            )
        }
        .frame(height: 42)
        .accessibilityHidden(true)
    }
}

// MARK: - Encourage (insight-first, Memory-only)

/// Memory ongoing encourage surface — insight first, meta last.
/// Separate from `AppCompanionCard` so Stats/Insight keep their narrative order.
struct MemoryEncourageCard: View {
    let insight: String
    let scene: String
    var meta: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(insight)
                .font(AppTypography.dayTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 0.7)

            Text(scene)
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let meta, !meta.isEmpty {
                Text(meta)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
            }
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    AppColors.cardBackground,
                    AppColors.brandPrimaryBackground.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                .stroke(AppColors.brandPrimary.opacity(0.10), lineWidth: 0.7)
        }
        .tracciElevation(.l1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Planning focus (light, no cover)

/// Lightweight planning anchor — no cover (home already shows covers).
struct MemoryPlanningFocusCard: View {
    let title: String
    let destinationName: String?
    let dateRange: String
    let departureText: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: AppSpacing.md) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColors.brandPrimary.opacity(0.72))
                    .frame(width: 3, height: 44)

                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    Text(title)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: AppSpacing.tight) {
                        Text(departureText)
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.brandPrimary)
                        Text("·")
                            .foregroundStyle(AppColors.textPlaceholder.opacity(0.35))
                        Text(dateRange)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                            .lineLimit(1)
                    }

                    if let destinationName, !destinationName.isEmpty {
                        Text(destinationName)
                            .font(AppTypography.chipRegular)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textPlaceholder.opacity(0.45))
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md + 4)
            .background(
                AppColors.cardAltBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: 0.65)
            }
        }
        .pressableCardStyle(scale: 0.985, opacity: 0.96)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(departureText)，查看旅程")
        .accessibilityHint("打开旅程详情")
    }
}

/// Memory tab status — creek strip + trip title + day progress.
/// Deliberately different from Stats green “进行中” chip (Insight owns live pace).
struct MemoryOngoingStatusStrip: View {
    let overview: TripStageOverview

    private var trip: TripStageFocusTrip? { overview.focusTrip }
    private var today: TripStageToday? { overview.ongoing?.today }

    private var dayText: String {
        guard let trip, let today else { return "旅途中" }
        return "第 \(Self.dayIndex(today: today, trip: trip)) / \(trip.totalDays) 天"
    }

    private var titleText: String {
        trip?.title ?? "当前旅程"
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.brandPrimary)
                .frame(width: 3, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(AppTypography.labelSemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.tight) {
                    Text("还在路上")
                        .font(AppTypography.chipSemibold)
                        .foregroundStyle(AppColors.brandPrimary)
                    Text("·")
                        .foregroundStyle(AppColors.textPlaceholder.opacity(0.35))
                    Text(dayText)
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            if let date = today?.date {
                Text(Self.shortDate(date))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    AppColors.brandPrimaryBackground.opacity(0.55),
                    AppColors.subtleWarm.opacity(0.50)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                .stroke(AppColors.brandPrimary.opacity(0.12), lineWidth: 0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titleText)，还在路上，\(dayText)")
    }

    static func dayIndex(today: TripStageToday, trip: TripStageFocusTrip) -> Int {
        guard let todayDate = TripDateFormatting.date(from: today.date),
              let startDate = TripDateFormatting.date(from: trip.startDate),
              let raw = TracciDateContext.dayIndex(for: todayDate, startDate: startDate) else {
            return 1
        }
        return max(1, min(trip.totalDays, raw))
    }

    private static func shortDate(_ dateString: String) -> String {
        guard let date = TripDateFormatting.date(from: dateString) else { return dateString }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

/// Trip-level accumulation chips for Memory tab.
/// Renders only when journal/photo counts are non-zero — never shows zero stats.
struct MemoryMaterialProgressCard: View {
    let memory: TripStageMemory?

    private var journalCount: Int { memory?.journalCount ?? 0 }
    private var photoCount: Int { memory?.photoCount ?? 0 }
    private var featuredCount: Int {
        (memory?.userFeaturedPhotoCount ?? 0) + (memory?.userFeaturedJournalCount ?? 0)
    }

    static func hasMaterials(_ memory: TripStageMemory?) -> Bool {
        (memory?.journalCount ?? 0) > 0 || (memory?.photoCount ?? 0) > 0
    }

    private var headline: String {
        if photoCount >= 3 || (journalCount >= 2 && photoCount >= 1) {
            return "已经可以回看了"
        }
        return "已经有一些记录了"
    }

    private var bodyCopy: String {
        if featuredCount > 0 {
            return "你标过 \(featuredCount) 处重要内容，回看时会优先看到。"
        }
        return "特别想留的画面，点一下星标即可。"
    }

    var body: some View {
        Group {
            if Self.hasMaterials(memory) {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            Text("这段旅程留下的")
                .font(AppTypography.sectionEyebrow)
                .foregroundStyle(AppColors.textMuted)
                .tracking(0.05)

            Text(headline)
                .font(AppTypography.buttonTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text(bodyCopy)
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.sm) {
                if journalCount > 0 {
                    materialChip(
                        value: "\(journalCount)",
                        unit: "篇日志",
                        systemImage: "book.closed.fill"
                    )
                }
                if photoCount > 0 {
                    materialChip(
                        value: "\(photoCount)",
                        unit: "张照片",
                        systemImage: "photo.fill"
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    AppColors.subtleWarm,
                    AppColors.brandPrimaryBackground.opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                .stroke(AppColors.brandPrimary.opacity(0.10), lineWidth: 0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if journalCount > 0 { parts.append("\(journalCount) 篇日志") }
        if photoCount > 0 { parts.append("\(photoCount) 张照片") }
        return "这段旅程留下了 \(parts.joined(separator: "，"))。\(headline)。"
    }

    private func materialChip(value: String, unit: String, systemImage: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: systemImage)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 28, height: 28)
                .background(AppColors.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(AppFont.system(18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(AppTypography.chipRegular)
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground.opacity(0.88), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

struct MemoryJourneyPreviewCard: View {
    let trip: Trip
    let dateRange: String
    let note: String

    var body: some View {
        HStack(spacing: AppSpacing.cardSmall) {
            VStack(alignment: .leading, spacing: 7) {
                Text(trip.destinationName ?? trip.title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(dateRange)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                Text(note)
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.cardSmall)
        .background(AppColors.cardAltBackground, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
    }
}

/// Recent photos / highlight log strip.
/// Callers must only mount when `hasVisibleContent` is true — never show empty shell.
struct MemoryMaterialFlow: View {
    let summary: TripSummaryResponse
    let onToggleFeatured: ((TripSummaryPhoto) -> Void)?

    private var photos: [TripSummaryPhoto] {
        Array((summary.userFeaturedPhotos + summary.recommendedPhotos).prefix(9))
    }

    private var highlightLogText: String? {
        guard let content = summary.highlightLogs.first?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return nil }
        return content
    }

    static func hasVisibleContent(_ summary: TripSummaryResponse) -> Bool {
        let photos = summary.userFeaturedPhotos + summary.recommendedPhotos
        if !photos.isEmpty { return true }
        if let content = summary.highlightLogs.first?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            if !photos.isEmpty {
                HStack {
                    Text("最近留下的画面")
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(photos.count) 张")
                        .font(AppTypography.chipRegular)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(photos) { photo in
                            ZStack(alignment: .topTrailing) {
                                TripCoverFillView(url: photo.squareURLs.first, iconPointSize: 16)
                                    .frame(width: 112, height: 132)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))

                                if let onToggleFeatured {
                                    Button {
                                        onToggleFeatured(photo)
                                    } label: {
                                        Image(systemName: photo.userFeatured ? "star.fill" : "star")
                                            .font(AppTypography.captionSemibold)
                                            .foregroundStyle(photo.userFeatured ? AppColors.featured : .white)
                                            .frame(width: 30, height: 30)
                                            .background(Color.black.opacity(0.34), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(7)
                                    .accessibilityLabel(photo.userFeatured ? "取消精选照片" : "加入精选照片")
                                }

                                if !photo.userFeatured {
                                    Text("推荐")
                                        .font(AppFont.system(9, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, AppSpacing.xxs)
                                        .background(Color.black.opacity(0.34), in: Capsule())
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                        .padding(7)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                }
            }

            if let highlightLogText {
                Text("“\(highlightLogText)”")
                    .font(AppTypography.body)
                    .italic()
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(18)
        .background(AppColors.cardAltBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
    }
}
