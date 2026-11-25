import SwiftUI
import UIKit

// MARK: - Home featured journey (Media Hero / Narrative Stage)

/// Home / All-Trips featured surface.
///
/// - **Media Hero** when a user-provided cover image loads successfully (photo + scrim + light type).
/// - **Narrative Stage** for a system destination image, no usable cover, or image loading failure
///   (ink type + stage wash).
///
/// Cover is an enhancement, not the foundation — empty-cover journeys must still read as a premium hero.
struct HomeJourneyWorkbenchCard: View {
    let trip: Trip
    let viewModel: HomeViewModel
    var onShare: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mediaImage: UIImage?
    @State private var didFailMedia = false
    @State private var displayedNarrativeProgress: CGFloat = 0

    private var primaryCoverURL: URL? {
        trip.homeFeaturedCoverURL
    }

    private var secondaryCoverURL: URL? {
        trip.homeFeaturedCoverFallbackURL
    }

    private var coverLoadToken: String {
        [primaryCoverURL?.absoluteString, secondaryCoverURL?.absoluteString]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    /// Keep Media Hero geometry stable while a configured cover resolves.
    private var usesMediaHero: Bool {
        return mediaImage != nil || (primaryCoverURL != nil && !didFailMedia)
    }

    private var destinationName: String? {
        guard let name = trip.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            return nil
        }
        return name
    }

    /// Hide pin line when title already says the place (“北京” / “北京市”).
    private var showsDestinationLine: Bool {
        guard let destinationName else { return false }
        let title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title == destinationName { return false }
        if title.contains(destinationName) || destinationName.contains(title) { return false }
        // “北京” vs “北京市”
        let strippedDestination = destinationName
            .replacingOccurrences(of: "市", with: "")
            .replacingOccurrences(of: "省", with: "")
            .replacingOccurrences(of: "自治区", with: "")
        if !strippedDestination.isEmpty,
           title == strippedDestination || title.contains(strippedDestination) {
            return false
        }
        return true
    }

    private var nodeCount: Int { trip.nodeCount ?? 0 }
    private var journalCount: Int { trip.journalCount ?? 0 }

    /// Only non-zero stats — never surface “0 日志” on the hero.
    private var mediaStatPills: [(systemImage: String, value: String)] {
        var pills: [(String, String)] = []
        if nodeCount > 0 {
            pills.append(("point.topleft.down.curvedto.point.bottomright.up", "\(nodeCount) 行程"))
        }
        if journalCount > 0 {
            pills.append(("book.closed", "\(journalCount) 日志"))
        }
        return pills
    }

    private var hasProgressStats: Bool {
        nodeCount > 0 || journalCount > 0
    }

    var body: some View {
        Group {
            if usesMediaHero {
                mediaHero(image: mediaImage)
                    .transition(mediaTransition)
            } else {
                narrativeStage
                    .transition(mediaTransition)
            }
        }
        .animation(AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion), value: usesMediaHero)
        .tracciLongPressActions(title: trip.title, actions: tripManagementActions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tripCardAccessibilityLabel)
        .accessibilityHint("打开旅程详情")
        .accessibilityAddTraits(.isButton)
        .task(id: coverLoadToken) {
            await loadMediaIfNeeded()
        }
    }

    private var mediaTransition: AnyTransition {
        AppMotion.revealTransition(reduceMotion: reduceMotion)
    }

    // MARK: Media Hero

    /// Fixed-height shell first, then fill media — never let `scaledToFill` report full bitmap height to the parent.
    private func mediaHero(image: UIImage?) -> some View {
        let height = HomeFeaturedMetrics.mediaHeight
        let shape = RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)

        return GeometryReader { geo in
            ZStack {
                TripCoverChrome(phase: .loading, iconPointSize: 28, showsGlyph: false)
                    .frame(width: geo.size.width, height: geo.size.height)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(AppMotion.revealTransition(reduceMotion: reduceMotion))
                }

                featuredImageScrim

                VStack(alignment: .leading, spacing: 0) {
                    mediaBadgeRow
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    mediaBottomContent
                }
                .padding(.horizontal, AppSpacing.card)
                .padding(.top, AppSpacing.cardSmall)
                .padding(.bottom, AppSpacing.card)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(
                AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion),
                value: image != nil
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay {
            shape
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .contentShape(shape)
        .tracciElevation(.l2)
    }

    private var mediaBadgeRow: some View {
        HStack(spacing: AppSpacing.tight) {
            // On photo: use brand-blue / glass, not green status chip (reads like system traffic light).
            FeaturedStatusBadge(
                text: viewModel.featuredStatusWord(for: trip),
                style: .primary,
                statusColor: AppColors.brandPrimary
            )
            if let dayBadge = viewModel.featuredDayBadgeText(for: trip) {
                FeaturedStatusBadge(text: dayBadge, style: .glass)
            }
        }
    }

    /// Editorial stack: title → quiet meta → progress creek → stats/CTA. Avoid pin+title+calendar triple stack.
    private var mediaBottomContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if showsDestinationLine, let destinationName {
                Text(destinationName)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(.white.opacity(0.86))
                    .tracking(0.6)
            }

            Text(trip.title)
                .font(AppTypography.pageTitle)
                .foregroundStyle(.white)
                .lineLimit(2)
                .tracciShadow(AppShadow.textStrong)

            Text(viewModel.dateRangeText(for: trip))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.78))

            if trip.effectiveStatus == .ongoing {
                mediaProgressCreek
            }

            HStack(alignment: .center, spacing: AppSpacing.tight) {
                ForEach(Array(mediaStatPills.enumerated()), id: \.offset) { _, pill in
                    GlassStatPill(systemImage: pill.systemImage, value: pill.value)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Text(primaryCTATitle)
                        .font(AppTypography.captionSemibold)
                    Image(systemName: "chevron.right")
                        .font(AppTypography.microSemibold)
                }
                .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Horizontal progress creek for ongoing Media Hero. Visualizes the
    /// journey's day progress (current/total) without relying on the
    /// Narrative Stage's curved path — keeps photo prominence while adding
    /// "where am I now" context.
    private var mediaProgressCreek: some View {
        HStack(spacing: AppSpacing.xs) {
            if let dayText = viewModel.currentDayText(for: trip) {
                Text(dayText)
                    .font(AppTypography.chipSemibold)
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: true, vertical: false)
            }

            GeometryReader { geo in
                let progress = min(1, max(0.04, viewModel.narrativeProgress(for: trip)))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.92),
                                    AppColors.dawnGold.opacity(0.92),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * progress), height: 4)
                }
                .frame(height: 4)
            }
            .frame(height: 4)

            if let remaining = viewModel.remainingDaysText(for: trip) {
                Text(remaining)
                    .font(AppTypography.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .accessibilityHidden(true)
    }

    private var featuredImageScrim: some View {
        ZStack {
            // Soft top veil so status chips stay readable on bright skies.
            LinearGradient(
                colors: [
                    .black.opacity(0.34),
                    .black.opacity(0.06),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Deep bottom scrim — text lives here; keep mid photo open for the scene.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.38),
                    .init(color: .black.opacity(0.18), location: 0.58),
                    .init(color: .black.opacity(0.52), location: 0.78),
                    .init(color: .black.opacity(0.78), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: Narrative Stage (no cover)

    private var narrativeStage: some View {
        ZStack(alignment: .topTrailing) {
            stageBackground

            stageAtmosphere

            narrativeProgressCreek

            VStack(alignment: .leading, spacing: 0) {
                stageBadgeRow
                    .padding(.bottom, AppSpacing.cozy)

                if showsDestinationLine, let destinationName {
                    HStack(spacing: AppSpacing.xs) {
                        Circle()
                            .fill(stageAccent.opacity(0.72))
                            .frame(width: 4, height: 4)
                        Text(destinationName)
                            .font(AppTypography.editorialMeta)
                            .tracking(0.7)
                    }
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.bottom, AppSpacing.xs)
                }

                Text(trip.title)
                    .font(AppTypography.homeStageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, AppSpacing.tight)

                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "calendar")
                        .font(AppTypography.captionSemibold)
                    Text(viewModel.dateRangeText(for: trip))
                        .font(AppTypography.homeMeta)
                        .tracking(0.25)
                }
                .foregroundStyle(AppColors.textMuted)
                .padding(.bottom, AppSpacing.tight)

                Text(viewModel.featuredCompanionText(for: trip))
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280, alignment: .leading)

                Spacer(minLength: 48)
                stageFooter
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.cardSmall + 2)
            .frame(
                maxWidth: .infinity,
                minHeight: HomeFeaturedMetrics.stageHeight - (AppSpacing.cardSmall + 2) * 2,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: HomeFeaturedMetrics.stageHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .stroke(stageAccent.opacity(0.16), lineWidth: 0.8)
        }
        .tracciElevation(.l2)
        .onAppear { updateNarrativeProgress() }
        .onChange(of: viewModel.narrativeProgress(for: trip)) { _, _ in
            updateNarrativeProgress()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateNarrativeProgress()
        }
    }

    private var narrativeProgressCreek: some View {
        GeometryReader { proxy in
            let progress = min(1, max(0.02, displayedNarrativeProgress))
            ZStack {
                NarrativeCreekPath()
                    .stroke(
                        stageAccent.opacity(trip.effectiveStatus == .planning ? 0.10 : 0.07),
                        style: StrokeStyle(
                            lineWidth: 1,
                            lineCap: .round,
                            dash: trip.effectiveStatus == .planning ? [2, 7] : []
                        )
                    )

                if trip.effectiveStatus != .planning {
                    NarrativeCreekPath()
                        .trim(from: 0, to: progress)
                        .stroke(
                            stageAccent.opacity(0.34),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                }

                if trip.effectiveStatus == .ongoing {
                    Circle()
                        .fill(AppColors.dawnGold.opacity(0.78))
                        .frame(width: 5, height: 5)
                        .position(narrativeCreekPoint(progress: progress, in: proxy.size))
                } else if trip.effectiveStatus == .completed {
                    Circle()
                        .fill(stageAccent.opacity(0.70))
                        .frame(width: 4.5, height: 4.5)
                        .position(narrativeCreekPoint(progress: 0.98, in: proxy.size))
                }
            }
        }
        .frame(height: 130)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func narrativeCreekPoint(progress: CGFloat, in size: CGSize) -> CGPoint {
        let x = size.width * (-0.02 + 1.04 * progress)
        let y = size.height * (0.80 - 0.34 * progress + sin(progress * .pi) * 0.025)
        return CGPoint(x: x, y: y)
    }

    private func updateNarrativeProgress() {
        let target = viewModel.narrativeProgress(for: trip)
        if reduceMotion {
            displayedNarrativeProgress = target
            return
        }
        if displayedNarrativeProgress > target {
            displayedNarrativeProgress = 0
        }
        withAnimation(AppMotion.slow.delay(0.12)) {
            displayedNarrativeProgress = target
        }
    }

    private var stageAtmosphere: some View {
        // One cool stage skylight is enough to establish hierarchy. Avoid a second warm bloom:
        // repeated with archive surfaces it made the entire home screen read yellow on device.
        RadialGradient(
            colors: [
                stageAccent.opacity(0.20),
                stageAccent.opacity(0.06),
                .clear,
            ],
            center: .topTrailing,
            startRadius: 6,
            endRadius: 175
        )
        .frame(width: 230, height: 175)
        .offset(x: 48, y: -42)
        .allowsHitTesting(false)
    }

    private var stageBadgeRow: some View {
        HStack(spacing: AppSpacing.tight) {
            StageInkBadge(
                text: viewModel.featuredStatusWord(for: trip),
                foreground: stageAccent,
                background: stageAccent.opacity(0.11)
            )
            if let currentDayText = viewModel.currentDayText(for: trip) {
                StageInkBadge(
                    text: currentDayText,
                    foreground: AppColors.textSecondary,
                    background: AppColors.cardBackground.opacity(0.72)
                )
            }
            Spacer(minLength: 0)
        }
    }

    private var stageFooter: some View {
        HStack(spacing: AppSpacing.cozy) {
            Rectangle()
                .fill(AppColors.borderSubtle.opacity(0.78))
                .frame(height: 1)
            stageCTA
        }
    }

    private var stageCTA: some View {
        HStack(spacing: 4) {
            Text(narrativeCTATitle)
                .font(AppTypography.captionSemibold)
            Image(systemName: "chevron.right")
                .font(AppTypography.microSemibold)
        }
        .foregroundStyle(stageAccent)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var narrativeCTATitle: String {
        switch trip.effectiveStatus {
        case .ongoing:
            return "查看今天的行程"
        case .planning:
            return "去规划"
        case .completed:
            return "打开回忆"
        case .unknown:
            return "打开旅程"
        }
    }

    private var primaryCTATitle: String {
        switch trip.effectiveStatus {
        case .ongoing:
            return "继续旅程"
        case .planning:
            return "完善行程"
        case .completed:
            return "查看旅程"
        case .unknown:
            return "打开旅程"
        }
    }

    private var stageAccent: Color {
        switch trip.effectiveStatus {
        case .planning:
            return AppColors.stagePlanning
        case .ongoing:
            return AppColors.stageOngoing
        case .completed:
            return AppColors.stageCompleted
        case .unknown:
            return AppColors.brandPrimary
        }
    }

    private var stageBackground: some View {
        LinearGradient(
            stops: [
                .init(color: AppColors.cardBackground, location: 0),
                .init(color: stageWashTop, location: 0.42),
                .init(color: stageWashBottom, location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var stageWashTop: Color {
        switch trip.effectiveStatus {
        case .planning:
            return AppColors.stagePlanningBackground.opacity(0.92)
        case .ongoing:
            return AppColors.stageOngoingBackground.opacity(0.88)
        case .completed:
            return AppColors.creekMistBottom.opacity(0.72)
        case .unknown:
            return AppColors.brandPrimaryBackground.opacity(0.7)
        }
    }

    private var stageWashBottom: Color {
        switch trip.effectiveStatus {
        case .planning:
            return AppColors.stagePlanningBackground.opacity(0.55)
        case .ongoing:
            return AppColors.creekMistTop.opacity(0.96)
        case .completed:
            return AppColors.creekMistTop.opacity(0.96)
        case .unknown:
            return AppColors.creekMistTop.opacity(0.9)
        }
    }

    // MARK: Loading

    @MainActor
    private func loadMediaIfNeeded() async {
        let requestedToken = coverLoadToken
        mediaImage = nil
        didFailMedia = false

        guard let primaryCoverURL else {
            return
        }

        if let cached = TracciImageCache.image(for: primaryCoverURL) {
            mediaImage = cached
            return
        }
        if let secondaryCoverURL,
           let cachedFallback = TracciImageCache.image(for: secondaryCoverURL) {
            mediaImage = cachedFallback
            return
        }

        if let image = await TripCoverImageLoader.load(url: primaryCoverURL) {
            guard requestedToken == coverLoadToken else { return }
            mediaImage = image
            return
        }

        if let secondaryCoverURL,
           let image = await TripCoverImageLoader.load(url: secondaryCoverURL, timeout: 8) {
            guard requestedToken == coverLoadToken else { return }
            mediaImage = image
            return
        }

        guard requestedToken == coverLoadToken else { return }
        mediaImage = nil
        didFailMedia = true
    }

    // MARK: A11y / actions

    private var tripCardAccessibilityLabel: String {
        TripListItemAccessibility.label(
            trip: trip,
            destination: showsDestinationLine ? (destinationName ?? "") : "",
            dateRange: viewModel.dateRangeText(for: trip),
            currentDayText: viewModel.currentDayText(for: trip),
            isFeatured: true
        )
    }

    private var tripManagementActions: [TracciActionItem] {
        TripListItemActionBuilder.make(onShare: onShare, onEdit: onEdit, onDelete: onDelete)
    }
}

private enum HomeFeaturedMetrics {
    /// Fixed layout height — must not depend on cover bitmap aspect ratio.
    static let mediaHeight: CGFloat = 248
    static let stageHeight: CGFloat = 236
}

private struct NarrativeCreekPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -rect.width * 0.02, y: rect.height * 0.80))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.58),
            control1: CGPoint(x: rect.width * 0.24, y: rect.height * 0.72),
            control2: CGPoint(x: rect.width * 0.45, y: rect.height * 0.66)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 1.02, y: rect.height * 0.46),
            control1: CGPoint(x: rect.width * 0.78, y: rect.height * 0.54),
            control2: CGPoint(x: rect.width * 0.92, y: rect.height * 0.48)
        )
        return path
    }
}

private struct StageInkBadge: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(AppTypography.micro)
            .foregroundStyle(foreground)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .frame(minHeight: 23)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(foreground.opacity(0.12), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Regular trip list card

struct TripCard: View {
    let trip: Trip
    var onShare: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        AppElevationCard(
            level: cardElevation,
            role: cardRole,
            radius: AppRadius.large,
            padding: AppSpacing.cozy,
            showsBorder: true
        ) {
            HStack(spacing: AppSpacing.md) {
                ArchiveTripThumbnail(trip: trip)
                    .frame(width: HomeArchiveMetrics.thumbnail, height: HomeArchiveMetrics.thumbnail)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                        Text(trip.title)
                            .font(AppTypography.homeArchiveTitle)
                            .foregroundStyle(isArchive ? AppColors.textSecondary : AppColors.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatusBadge(text: trip.effectiveStatus.label, statusColor: trip.effectiveStatus.statusColor)
                    }

                    Text(TripPresentation.phaseSubtitleText(for: trip))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .lineLimit(1)

                    let metaTexts = TripPresentation.phaseMetaTexts(for: trip)
                    if !metaTexts.isEmpty {
                        HStack(spacing: AppSpacing.xs) {
                            ForEach(Array(metaTexts.enumerated()), id: \.offset) { index, text in
                                if index > 0 {
                                    DotSeparator()
                                }
                                Text(text)
                            }
                        }
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textDisabled.opacity(0.78))
                    .accessibilityHidden(true)
            }
        }
        .tracciLongPressActions(title: trip.title, actions: tripManagementActions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tripCardAccessibilityLabel)
        .accessibilityHint("打开旅程详情")
        .accessibilityAddTraits(.isButton)
    }

    private var tripCardAccessibilityLabel: String {
        TripListItemAccessibility.label(
            trip: trip,
            destination: TripPresentation.destinationText(for: trip),
            dateRange: TripPresentation.dateRangeText(for: trip),
            currentDayText: TripPresentation.currentDayText(for: trip),
            isFeatured: false
        )
    }

    private var isArchive: Bool {
        trip.effectiveStatus == .completed
    }

    private var cardElevation: AppElevationLevel {
        switch trip.effectiveStatus {
        case .ongoing:
            return .l1
        case .completed:
            return .l0
        case .planning, .unknown:
            return .l1
        }
    }

    private var cardRole: AppCardRole {
        switch trip.effectiveStatus {
        case .ongoing:
            return .active
        case .completed:
            return .archive
        case .planning, .unknown:
            return .content
        }
    }

    private var tripManagementActions: [TracciActionItem] {
        TripListItemActionBuilder.make(onShare: onShare, onEdit: onEdit, onDelete: onDelete)
    }
}

private enum HomeArchiveMetrics {
    static let thumbnail: CGFloat = 56
}

private struct ArchiveTripThumbnail: View {
    let trip: Trip

    private var hasResolvedCover: Bool {
        (trip.coverThumbnailURL ?? trip.coverPreviewURL) != nil
    }

    var body: some View {
        Group {
            if hasResolvedCover {
                TripCoverView(
                    url: trip.coverThumbnailURL,
                    fallbackURL: trip.coverPreviewURL,
                    height: HomeArchiveMetrics.thumbnail,
                    cornerRadius: AppRadius.small
                )
                .overlay {
                    LinearGradient(
                        colors: [
                            AppColors.archivePhotoVeilLight.opacity(0.16),
                            AppColors.archivePhotoVeilDark.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }
            } else {
                ArchiveDestinationMotif(
                    destination: trip.destinationName ?? trip.title,
                    isOngoing: trip.effectiveStatus == .ongoing
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ArchiveDestinationMotif: View {
    let destination: String
    let isOngoing: Bool

    private var palette: ArchiveMotifPalette {
        ArchiveMotifPalette(destination: destination)
    }

    private var initial: String {
        var city = destination
        for suffix in ["特别行政区", "自治区", "省", "市"] where city.hasSuffix(suffix) {
            city.removeLast(suffix.count)
            break
        }
        return city.first.map(String.init) ?? "旅"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [palette.fill, palette.fillDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                for index in 0..<3 {
                    var path = Path()
                    let base = size.height * (0.38 + CGFloat(index) * 0.20)
                    path.move(to: CGPoint(x: -2, y: base))
                    path.addCurve(
                        to: CGPoint(x: size.width + 2, y: base - 7),
                        control1: CGPoint(x: size.width * 0.26, y: base - 8),
                        control2: CGPoint(x: size.width * 0.60, y: base + 8)
                    )
                    let color = index == 1 && isOngoing ? AppColors.brandPrimary : palette.creek
                    let opacity = [0.34, 0.58, 0.24][index]
                    let width: CGFloat = [1.2, 1.6, 1.0][index]
                    context.stroke(
                        path,
                        with: .color(color.opacity(opacity)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round)
                    )
                }
            }

            Text(initial)
                .font(AppTypography.labelRegular)
                .foregroundStyle(palette.text.opacity(0.70))
                .padding(.trailing, AppSpacing.tight)
                .padding(.bottom, AppSpacing.xs)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }
}

private struct ArchiveMotifPalette {
    let fill: Color
    let fillDeep: Color
    let creek: Color
    let text: Color

    init(destination: String) {
        let hash = destination.unicodeScalars.reduce(0) { partial, scalar in
            (partial * 31 + Int(scalar.value)) % 360
        }
        let hue = Double(185 + (hash % 75)) / 360.0
        fill = Color(hue: hue, saturation: 0.12, brightness: 0.96)
        fillDeep = Color(hue: hue, saturation: 0.18, brightness: 0.88)
        creek = Color(hue: hue, saturation: 0.30, brightness: 0.64)
        text = Color(hue: hue, saturation: 0.24, brightness: 0.48)
    }
}

private enum TripListItemAccessibility {
    static func label(
        trip: Trip,
        destination: String,
        dateRange: String,
        currentDayText: String?,
        isFeatured: Bool
    ) -> String {
        var parts: [String] = []
        if isFeatured {
            parts.append("精选旅程")
        }
        parts.append(trip.title)
        parts.append(trip.effectiveStatus.label)
        if let currentDayText, !currentDayText.isEmpty {
            parts.append(currentDayText)
        }
        if !destination.isEmpty {
            parts.append(destination)
        }
        if !dateRange.isEmpty {
            parts.append(dateRange)
        }
        parts.append("\(trip.nodeCount ?? 0) 个行程")
        parts.append("\(trip.journalCount ?? 0) 篇日志")
        return parts.joined(separator: "，")
    }
}

private enum TripListItemActionBuilder {
    static func make(
        onShare: (() -> Void)?,
        onEdit: (() -> Void)?,
        onDelete: (() -> Void)?
    ) -> [TracciActionItem] {
        var actions: [TracciActionItem] = []
        if let onShare {
            actions.append(TracciActionItem(title: "分享行程", systemImage: "square.and.arrow.up", action: onShare))
        }
        if let onEdit {
            actions.append(TracciActionItem(title: "编辑信息", systemImage: "pencil", action: onEdit))
        }
        if let onDelete {
            actions.append(TracciActionItem(title: "删除行程", systemImage: "trash", role: .destructive, action: onDelete))
        }
        return actions
    }
}

// MARK: - Shared cover loader view (list thumbs, pickers)

struct TripCoverView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let url: URL?
    var fallbackURL: URL? = nil
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var loadedImage: UIImage?
    @State private var phase: TripCoverChromePhase = .empty
    @State private var loadedToken: String?

    /// Icon size scales with cover height so thumbs and featured cards stay balanced.
    private var iconPointSize: CGFloat {
        min(28, max(15, height * 0.11))
    }

    private var loadToken: String {
        [url?.absoluteString, fallbackURL?.absoluteString]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Fixed chrome under media so async loads never collapse layout height.
                TripCoverChrome(phase: loadedImage == nil ? phase : .empty, iconPointSize: iconPointSize)

                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(AppMotion.revealTransition(reduceMotion: reduceMotion))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(AppMotion.animation(AppMotion.imageFade, reduceMotion: reduceMotion), value: loadedImage != nil)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: loadToken) {
            await loadCoverImage()
        }
    }

    @MainActor
    private func loadCoverImage() async {
        // Keep previous frame while the same logical cover reloads (scroll reuse / refresh).
        if loadedToken != loadToken {
            loadedImage = nil
            loadedToken = loadToken
        }

        guard let url else {
            phase = .empty
            loadedImage = nil
            return
        }

        if let cached = TracciImageCache.image(for: url) {
            loadedImage = cached
            phase = .empty
            return
        }
        if let fallbackURL,
           fallbackURL != url,
           let cachedFallback = TracciImageCache.image(for: fallbackURL) {
            loadedImage = cachedFallback
            phase = .empty
            return
        }

        if loadedImage == nil {
            phase = .loading
        }

        if let image = await TripCoverImageLoader.load(url: url) {
            loadedImage = image
            phase = .empty
            return
        }

        if let fallbackURL, fallbackURL != url, let image = await TripCoverImageLoader.load(url: fallbackURL, timeout: 8) {
            loadedImage = image
            phase = .empty
            return
        }

        if loadedImage == nil {
            phase = .failure
        }
    }
}

private struct StatusBadge: View {
    let text: String
    var statusColor: Color = AppColors.textMuted

    var body: some View {
        Text(text)
            .font(AppTypography.micro)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, AppSpacing.xxs)
            .frame(minHeight: 22)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

private struct FeaturedStatusBadge: View {
    enum Style {
        case primary
        case glass
    }

    let text: String
    let style: Style
    var statusColor: Color = AppColors.brandPrimary

    var body: some View {
        Text(text)
            .font(AppTypography.micro)
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .frame(minHeight: 23)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(style == .primary ? 0.18 : 0.20), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            statusColor.opacity(0.82)
        case .glass:
            Capsule()
                .fill(.white.opacity(0.13))
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct GlassStatPill: View {
    let systemImage: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(AppTypography.chipSemibold)
            Text(value)
                .font(AppTypography.chipSemibold)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .frame(minHeight: 28)
        .background(.white.opacity(0.16))
        .clipShape(Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 0.6)
        }
        .accessibilityHidden(true)
    }
}

private struct DotSeparator: View {
    var body: some View {
        Circle()
            .fill(AppColors.textDisabled)
            .frame(width: 3, height: 3)
    }
}
