import SwiftUI
import UIKit

struct MemoryStoryContainerView: View {
    let trip: Trip
    let dateRangeText: String
    @Bindable var viewModel: MemoryStoryViewModel
    let onClose: () -> Void
    let onSaveToPhotoLibrary: () -> Void
    let onShareFailed: (String) -> Void
    /// When false (Demo), hide save/share and show a browse-only note on the ending page.
    var allowsExportActions: Bool = true

    @State private var pageTransitionDirection = 1
    @State private var isPaging = false
    @State private var swipeHintBounce = false
    @State private var entered = false
    @State private var isShareSheetPresented = false
    /// When true, Photos carousel is handling a horizontal drag — ignore vertical page turns.
    @State private var suppressVerticalPaging = false
    /// Live top inset — `ignoresSafeArea` makes GeometryReader report 0; refresh from window metrics.
    @State private var topSafeInset: CGFloat = SafeAreaMetrics.top
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Never place chrome under the status-bar clock; floor covers Dynamic Island when metrics lag.
    private var resolvedTopInset: CGFloat {
        max(topSafeInset, SafeAreaMetrics.top, 54)
    }

    /// Close / progress row height + breathing room below status bar.
    private var chromeTopPadding: CGFloat {
        resolvedTopInset + 10
    }

    /// Content clears the chrome row (44pt hit target) plus a small gap.
    private var contentTopInset: CGFloat {
        chromeTopPadding + 44 + 10
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                if viewModel.isLoading && !viewModel.hasLoaded {
                    Color.clear
                        .overlay {
                        ProgressView("生成旅程报告")
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                } else if let error = viewModel.errorMessage, !viewModel.hasLoaded {
                    Color.clear
                        .overlay {
                        ErrorStateView(title: "报告加载失败", message: error, retryTitle: "重试") {
                            Task { await viewModel.refresh() }
                        }
                        .padding(.horizontal, 24)
                    }
                } else if let summary = viewModel.summary {
                    ZStack {
                        storyPage(summary: summary, size: proxy.size)
                            .id(viewModel.selectedPageIndex)
                            .transition(storyDepthTransition)

                        storyOverlay
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(storyDragGesture)
                }
            }
            .opacity(entered ? 1 : 0)
            .scaleEffect(entered ? 1 : 0.97)
        }
        .ignoresSafeArea()
        .onAppear {
            refreshTopSafeInset()
            withAnimation(AppMotion.storyEntry) { entered = true }
            // Window metrics can lag one frame after immersive presentation.
            for delay in [0.05, 0.15, 0.35] as [TimeInterval] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    refreshTopSafeInset()
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .exportSharePresenter(isPresented: $isShareSheetPresented, items: viewModel.shareItems())
    }

    private func refreshTopSafeInset() {
        let resolved = SafeAreaMetrics.top
        guard resolved > 0 else { return }
        if abs(topSafeInset - resolved) > 0.5 {
            topSafeInset = resolved
        }
    }

    private var storyPageCount: Int {
        max(viewModel.storyPageKinds.count, 1)
    }

    private var storyDepthTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .modifier(
                active: StoryDepthTransitionModifier(
                    opacity: 0,
                    scale: 1.08,
                    yOffset: pageTransitionDirection > 0 ? 92 : -92,
                    blur: 10
                ),
                identity: StoryDepthTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    yOffset: 0,
                    blur: 0
                )
            ),
            removal: .modifier(
                active: StoryDepthTransitionModifier(
                    opacity: 0,
                    scale: 0.94,
                    yOffset: pageTransitionDirection > 0 ? -70 : 70,
                    blur: 8
                ),
                identity: StoryDepthTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    yOffset: 0,
                    blur: 0
                )
            )
        )
    }

    private func storyPage(summary: TripSummaryResponse, size: CGSize) -> some View {
        let pageKind = viewModel.pageKind(at: viewModel.selectedPageIndex)
        return StoryPageView(
            page: pageKind,
            summary: summary,
            image: viewModel.storyImage(for: pageKind),
            loadedImages: viewModel.loadedImages,
            fullestDay: viewModel.fullestDay,
            currentPageIndex: viewModel.selectedPageIndex,
            totalPageCount: storyPageCount,
            contentTopInset: contentTopInset,
            onSave: allowsExportActions ? onSaveToPhotoLibrary : nil,
            onShareReport: allowsExportActions
                ? {
                    // Renders report image then presents system share sheet (UIActivityViewController).
                    Task {
                        let prepared = await viewModel.prepareShareImage()
                        if prepared, !viewModel.shareItems().isEmpty {
                            isShareSheetPresented = true
                        } else {
                            onShareFailed(viewModel.errorMessage ?? "暂时无法分享，请稍后再试")
                        }
                    }
                }
                : nil,
            showsExportActions: allowsExportActions,
            onReplay: {
                withAnimation(.interactiveSpring(response: 0.36, dampingFraction: 0.86, blendDuration: 0.08)) {
                    viewModel.selectedPageIndex = 0
                }
            },
            onClose: onClose,
            onHorizontalPhotoInteraction: { active in
                suppressVerticalPaging = active
            },
            onVerticalPageRequest: { delta in
                movePage(delta)
            },
            cornerRadius: 0,
            showsShadow: false
        )
        .frame(width: size.width, height: size.height)
    }

    private var showsProgressChrome: Bool {
        viewModel.pageKind(at: viewModel.selectedPageIndex) != .cover
            && viewModel.pageKind(at: viewModel.selectedPageIndex) != .ending
            && viewModel.hasLoaded
    }

    private var storyOverlay: some View {
        VStack(spacing: 0) {
            // Progress (left) + close (right) share one safe-area chrome row — never sit under the clock.
            HStack(alignment: .center, spacing: 12) {
                if showsProgressChrome {
                    StoryProgressBar(
                        currentPageIndex: viewModel.selectedPageIndex,
                        totalPageCount: storyPageCount
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background {
                            #if compiler(>=26)
                            if #available(iOS 26, *) {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .glassEffect(in: .circle)
                            } else {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                            #else
                            Circle()
                                .fill(.ultraThinMaterial)
                            #endif
                        }
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.20), lineWidth: 0.5)
                        }
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("关闭回顾")
            }
            .padding(.top, chromeTopPadding)
            .padding(.horizontal, 16)

            Spacer()

            if viewModel.selectedPageIndex < storyPageCount - 1 {
                swipeHint
                    .padding(.bottom, 42)
            }
        }
    }

    private var swipeHint: some View {
        VStack(spacing: 7) {
            Text("\(viewModel.selectedPageIndex + 1) / \(storyPageCount)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .tracking(0.8)
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.40))
                .offset(y: reduceMotion ? 0 : (swipeHintBounce ? -2 : 2))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: swipeHintBounce
                )
            Text("上滑继续")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(0.5)
        }
        .accessibilityHint("上下滑动翻页")
        .onAppear {
            guard !reduceMotion else { return }
            swipeHintBounce = true
        }
    }

    private var storyDragGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard !suppressVerticalPaging else { return }

                let dx = abs(value.translation.width)
                let dy = abs(value.predictedEndTranslation.height) > abs(value.translation.height)
                    ? abs(value.predictedEndTranslation.height)
                    : abs(value.translation.height)
                // Require clear vertical intent so diagonal / horizontal photo swipes don't flip pages.
                guard dy > 56, dy > dx * 1.45 else { return }

                let predicted = value.predictedEndTranslation.height
                if value.translation.height < -56 || predicted < -140 {
                    movePage(1)
                } else if value.translation.height > 56 || predicted > 140 {
                    movePage(-1)
                }
            }
    }

    private func movePage(_ delta: Int) {
        guard !isPaging else { return }
        let next = min(max(viewModel.selectedPageIndex + delta, 0), storyPageCount - 1)
        guard next != viewModel.selectedPageIndex else { return }
        AppHaptics.lightImpact()
        pageTransitionDirection = delta > 0 ? 1 : -1
        isPaging = true
        withAnimation(AppMotion.storyPageTransition) {
            viewModel.selectedPageIndex = next
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            isPaging = false
        }
    }

}

private struct StoryDepthTransitionModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let yOffset: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .blur(radius: blur)
    }
}

// MARK: - Animated Count Text

struct StoryCountUpText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Int
    var duration: Double = 0.8
    var delay: Double = 0
    var formatter: (Int) -> String = { "\($0)" }

    @State private var displayed = 0
    @State private var isComplete = false

    var body: some View {
        Text(formatter(displayed))
            .contentTransition(.numericText())
            .scaleEffect(isComplete && !reduceMotion ? 1.035 : 1)
            .shadow(color: .white.opacity(isComplete ? 0.24 : 0), radius: isComplete ? 14 : 0)
            .task(id: value) {
                isComplete = false
                guard value > 0, !reduceMotion else {
                    displayed = value
                    isComplete = true
                    return
                }

                displayed = 0
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }

                let totalSteps = min(value, 40)
                let stepTime = duration / Double(totalSteps)
                for step in 1...totalSteps {
                    try? await Task.sleep(nanoseconds: UInt64(stepTime * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    let progress = Double(step) / Double(totalSteps)
                    let eased = 1 - pow(1 - progress, 3)
                    displayed = min(Int(round(eased * Double(value))), value)
                }

                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    isComplete = true
                }
            }
    }

    static func groupedNumber(_ value: Int) -> String {
        groupedNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let groupedNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
}

struct StoryRevealMetric: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    let isAppeared: Bool
    let countDelay: Double
    let numberSize: CGFloat

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 50, height: 50)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            ZStack(alignment: .leading) {
                Circle()
                    .fill(color.opacity(isAppeared ? 0.14 : 0.02))
                    .frame(width: 86, height: 86)
                    .blur(radius: 30)
                    .offset(x: 36)
                    .animation(.easeOut(duration: 0.35), value: isAppeared)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    StoryCountUpText(value: count, duration: 0.75, delay: countDelay)
                        .font(.system(size: numberSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(label)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.50))
                }
            }

            Spacer()
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(x: isAppeared ? 0 : -18, y: isAppeared ? 0 : 4)
    }
}

struct StoryMoneyReveal: View {
    let amount: Int
    let currencySymbol: String
    let subtitle: String
    let numberSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("这一趟花掉的，都是真实走过的日子。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineSpacing(5)

            ZStack(alignment: .leading) {
                Circle()
                    .fill(MemoryColors.glowAmber)
                    .frame(width: 190, height: 190)
                    .blur(radius: 58)
                    .offset(x: 56, y: 4)

                StoryCountUpText(
                    value: amount,
                    duration: 0.95,
                    delay: 0.35,
                    formatter: { "\(currencySymbol)\(StoryCountUpText.groupedNumber($0))" }
                )
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .frame(height: 78)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.50))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StoryOrbitMetric: Identifiable {
    let id = UUID()
    let icon: String
    let value: Int
    let unit: String
    let caption: String
    let color: Color
}

private struct StoryStatsConstellation: View {
    let mainMetric: StoryOrbitMetric
    let orbitMetrics: [StoryOrbitMetric]
    let isAppeared: Bool
    let numberSize: CGFloat

    private let nodePositions: [UnitPoint] = [
        UnitPoint(x: 0.18, y: 0.30),
        UnitPoint(x: 0.78, y: 0.22),
        UnitPoint(x: 0.84, y: 0.72),
        UnitPoint(x: 0.22, y: 0.78)
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

            ZStack {
                Canvas { context, canvasSize in
                    let resolvedCenter = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)

                    for index in orbitMetrics.indices {
                        let point = CGPoint(
                            x: canvasSize.width * nodePositions[index % nodePositions.count].x,
                            y: canvasSize.height * nodePositions[index % nodePositions.count].y
                        )
                        var path = Path()
                        path.move(to: resolvedCenter)
                        path.addQuadCurve(
                            to: point,
                            control: CGPoint(
                                x: (resolvedCenter.x + point.x) / 2,
                                y: min(resolvedCenter.y, point.y) - 22
                            )
                        )
                        context.stroke(
                            path,
                            with: .color(.white.opacity(isAppeared ? 0.14 : 0)),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 7])
                        )
                    }
                }

                ForEach(Array(orbitMetrics.prefix(4).enumerated()), id: \.element.id) { index, metric in
                    orbitNode(metric)
                        .position(
                            x: size.width * nodePositions[index % nodePositions.count].x,
                            y: size.height * nodePositions[index % nodePositions.count].y
                        )
                        .opacity(isAppeared ? 1 : 0)
                        .scaleEffect(isAppeared ? 1 : 0.82)
                        .animation(.easeOut(duration: 0.42).delay(Double(index) * 0.06), value: isAppeared)
                }

                VStack(spacing: 6) {
                    StoryCountUpText(value: mainMetric.value, duration: 0.9, delay: 0.25)
                        .font(.system(size: numberSize + 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)
                    Text(mainMetric.unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mainMetric.color)
                    Text(mainMetric.caption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                        .lineLimit(1)
                }
                .frame(width: 150, height: 150)
                .background {
                    Circle()
                        .fill(.white.opacity(0.08))
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 0.8)
                    Circle()
                        .fill(mainMetric.color.opacity(0.18))
                        .blur(radius: 34)
                }
                .position(center)
                .opacity(isAppeared ? 1 : 0)
                .scaleEffect(isAppeared ? 1 : 0.86)
            }
        }
        .frame(height: 210)
        .accessibilityElement(children: .combine)
    }

    private func orbitNode(_ metric: StoryOrbitMetric) -> some View {
        VStack(spacing: 5) {
            Image(systemName: metric.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(metric.color)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08))
                .clipShape(Circle())
            Text("\(metric.value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
        }
        .frame(width: 58, height: 62)
    }
}

private struct StoryReceiptTexture: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.075))

            VStack(spacing: 14) {
                ForEach(0..<8, id: \.self) { index in
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(.white.opacity(index == 0 ? 0.18 : 0.08))
                            .frame(width: index == 0 ? 74 : 38, height: 3)
                        Capsule()
                            .fill(.white.opacity(0.07))
                            .frame(maxWidth: .infinity)
                            .frame(height: 3)
                    }
                }
            }
            .padding(22)
            .opacity(0.72)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.7)
        }
    }
}

private struct StoryQuotePanel<Content: View>: View {
    let accent: Color
    let content: Content

    init(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.7)
                }

            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 120, height: 120)
                .blur(radius: 36)
                .offset(x: -46, y: -50)

            content
                .padding(22)
        }
    }
}

/// Segment progress for story pages — used in the safe-area chrome row (not page body).
struct StoryProgressBar: View {
    let currentPageIndex: Int
    let totalPageCount: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(totalPageCount, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= currentPageIndex
                        ? MemoryColors.progressDotActive.opacity(0.95)
                        : MemoryColors.progressDotInactive.opacity(0.60))
                    .frame(
                        width: i == currentPageIndex ? 24 : 5,
                        height: i == currentPageIndex ? 3.5 : 3
                    )
                    .shadow(
                        color: i == currentPageIndex ? .white.opacity(0.22) : .clear,
                        radius: 3, x: 0, y: 0
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: currentPageIndex)
            }
        }
        .accessibilityLabel("回顾进度，第\(currentPageIndex + 1)页，共\(totalPageCount)页")
    }
}

struct StoryPageView: View {
    let page: StoryPageKind
    let summary: TripSummaryResponse
    private let narrative: MemoryStoryNarrative
    let image: UIImage?
    let loadedImages: [UIImage]
    let fullestDay: TripSummaryDay?
    let currentPageIndex: Int
    let totalPageCount: Int
    /// Distance from physical top to content — clears status bar + chrome (progress/close).
    var contentTopInset: CGFloat = 108
    var onSave: (() -> Void)?
    var onShareReport: (() -> Void)?
    /// When false, ending page shows browse-only note instead of save/share.
    var showsExportActions: Bool = true
    var onReplay: (() -> Void)?
    var onClose: (() -> Void)?
    /// Photos page: reports horizontal drag sessions so the container can suppress vertical paging.
    var onHorizontalPhotoInteraction: ((Bool) -> Void)?
    /// Photos page: forwards clearly vertical swipes started on the carousel.
    var onVerticalPageRequest: ((Int) -> Void)?
    var cornerRadius: CGFloat = 28
    var showsShadow = true

    init(
        page: StoryPageKind,
        summary: TripSummaryResponse,
        image: UIImage?,
        loadedImages: [UIImage],
        fullestDay: TripSummaryDay?,
        currentPageIndex: Int,
        totalPageCount: Int,
        contentTopInset: CGFloat = 108,
        onSave: (() -> Void)? = nil,
        onShareReport: (() -> Void)? = nil,
        showsExportActions: Bool = true,
        onReplay: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onHorizontalPhotoInteraction: ((Bool) -> Void)? = nil,
        onVerticalPageRequest: ((Int) -> Void)? = nil,
        cornerRadius: CGFloat = 28,
        showsShadow: Bool = true
    ) {
        self.page = page
        self.summary = summary
        self.narrative = MemoryStoryNarrativeBuilder.build(for: summary)
        self.image = image
        self.loadedImages = loadedImages
        self.fullestDay = fullestDay
        self.currentPageIndex = currentPageIndex
        self.totalPageCount = totalPageCount
        self.contentTopInset = contentTopInset
        self.onSave = onSave
        self.onShareReport = onShareReport
        self.showsExportActions = showsExportActions
        self.onReplay = onReplay
        self.onClose = onClose
        self.onHorizontalPhotoInteraction = onHorizontalPhotoInteraction
        self.onVerticalPageRequest = onVerticalPageRequest
        self.cornerRadius = cornerRadius
        self.showsShadow = showsShadow
    }

    @State private var backgroundAppeared = false
    @State private var eyebrowAppeared = false
    @State private var titleAppeared = false
    @State private var infoAppeared = false
    @State private var watermarkAppeared = false
    @State private var statsAppeared = false
    @State private var statsItemAppeared = [Bool](repeating: false, count: 4)
    @State private var placesItemAppeared = [Bool](repeating: false, count: 6)
    @State private var contentAppeared = false
    @State private var kenBurnsScale: CGFloat = 1.0
    @State private var ambientShift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Dynamic Type: scale large text but cap to prevent layout breakage
    @ScaledMetric(relativeTo: .largeTitle) private var coverTitleSize: CGFloat = 42
    @ScaledMetric(relativeTo: .largeTitle) private var statNumberSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var expenseTotalSize: CGFloat = 46
    @ScaledMetric(relativeTo: .title) private var memorableQuoteSize: CGFloat = 28

    private var clampedCoverTitleSize: CGFloat { min(coverTitleSize, 58) }
    private var clampedStatNumberSize: CGFloat { min(statNumberSize, 48) }
    private var clampedExpenseTotalSize: CGFloat { min(expenseTotalSize, 62) }
    private var clampedMemorableQuoteSize: CGFloat { min(memorableQuoteSize, 38) }

    var body: some View {
        ZStack {
            background
                .zIndex(0)
            decorativeLayer
                .zIndex(1)
            if page == .cover {
                coverContent
                    .zIndex(2)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    // Progress lives in container chrome (safe-area row with close).
                    // Body starts below chrome so headers never fight the status-bar clock.
                    pageHeader
                    Spacer(minLength: 8)
                    pageContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    watermark
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.top, contentTopInset)
                .padding(.bottom, max(SafeAreaMetrics.bottom + 56, 106))
                .zIndex(2)
            }
        }
        .onAppear {
            let base = AppMotion.storyStaggerBase
            let step = AppMotion.storyStaggerStep
            let fade = AppMotion.storyElementFade
            let coverFade = AppMotion.storyCoverFade

            if !reduceMotion {
                withAnimation(.easeInOut(duration: 5.6).repeatForever(autoreverses: true)) {
                    ambientShift = true
                }
            }

            if page == .cover {
                withAnimation(coverFade) { backgroundAppeared = true }
                withAnimation(fade.delay(base)) { eyebrowAppeared = true }
                withAnimation(fade.delay(base + step)) { titleAppeared = true }
                withAnimation(fade.delay(base + step * 2)) { infoAppeared = true }
                withAnimation(fade.delay(base + step * 3)) { watermarkAppeared = true }
                if !reduceMotion {
                    withAnimation(.easeOut(duration: 8.0).delay(0.5)) {
                        kenBurnsScale = 1.05
                    }
                }
            } else if page == .stats {
                withAnimation(fade.delay(base)) { eyebrowAppeared = true }
                withAnimation(fade.delay(base + step)) { titleAppeared = true }
                withAnimation(fade.delay(base + step * 2)) { statsAppeared = true }
                for i in 0..<4 {
                    withAnimation(fade.delay(base + step * 3 + Double(i) * step)) {
                        statsItemAppeared[i] = true
                    }
                }
                withAnimation(fade.delay(base + step * 7)) { watermarkAppeared = true }
            } else if page == .places {
                withAnimation(fade.delay(base)) { eyebrowAppeared = true }
                withAnimation(fade.delay(base + step)) { titleAppeared = true }
                for i in 0..<min(visitedPlaces.count, 6) {
                    withAnimation(fade.delay(base + step * 2 + Double(i) * (step * 0.8))) {
                        placesItemAppeared[i] = true
                    }
                }
                withAnimation(fade.delay(base + step * 6)) { watermarkAppeared = true }
            } else if page == .photos {
                withAnimation(fade.delay(base)) { eyebrowAppeared = true }
                withAnimation(fade.delay(base + step)) { titleAppeared = true }
                withAnimation(fade.delay(base + step * 2)) { contentAppeared = true }
                withAnimation(fade.delay(base + step * 3)) { watermarkAppeared = true }
            } else if page == .expenses || page == .memorable || page == .journals {
                withAnimation(fade.delay(base)) { eyebrowAppeared = true }
                withAnimation(fade.delay(base + step)) { titleAppeared = true }
                withAnimation(fade.delay(base + step * 2)) { contentAppeared = true }
                withAnimation(fade.delay(base + step * 3)) { watermarkAppeared = true }
            } else if page == .ending {
                withAnimation(fade.delay(base)) { titleAppeared = true }
                withAnimation(fade.delay(base + step)) { contentAppeared = true }
                withAnimation(fade.delay(base + step * 2)) { watermarkAppeared = true }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .tracciElevation(showsShadow ? .l2 : .l0)
    }

    @ViewBuilder
    private var background: some View {
        switch page {
        case .cover:
            if let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .scaleEffect(kenBurnsScale)
                        .scaleEffect(backgroundAppeared ? 1.0 : 1.02)
                        .animation(.easeOut(duration: 0.9), value: backgroundAppeared)
                        .overlay {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.28), location: 0),
                                    .init(color: .black.opacity(0.08), location: 0.3),
                                    .init(color: .black.opacity(0.06), location: 0.5),
                                    .init(color: .black.opacity(0.45), location: 0.78),
                                    .init(color: .black.opacity(0.62), location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .overlay {
                            RadialGradient(
                                colors: [.clear, .black.opacity(0.18)],
                                center: .center,
                                startRadius: 140,
                                endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                            )
                        }
                }
            } else {
                MemoryGradients.storyDark
            }
        case .places:
            ZStack {
                LinearGradient(colors: [MemoryColors.storyPlacesDark, MemoryColors.storyPlacesMid, MemoryColors.storyDarkNavy], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(MemoryColors.accentGreen.opacity(0.05))
                    .frame(width: 280, height: 280)
                    .blur(radius: 90)
                    .scaleEffect(ambientShift ? 1.08 : 0.96)
                    .offset(x: ambientShift ? -86 : -112, y: ambientShift ? -176 : -150)
            }
        case .photos:
            if let image {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .scaleEffect(ambientShift && !reduceMotion ? 1.035 : 1)
                        .overlay {
                            LinearGradient(
                                colors: [.black.opacity(0.34), .black.opacity(0.58), .black.opacity(0.86)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .overlay {
                            RadialGradient(
                                colors: [.clear, .black.opacity(0.34)],
                                center: .center,
                                startRadius: 120,
                                endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                            )
                        }
                }
            } else {
                MemoryGradients.storyDark
            }
        case .stats:
            ZStack {
                LinearGradient(colors: [MemoryColors.storyStatsDark, MemoryColors.storyStatsMid, MemoryColors.storyStatsDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(AppColors.brandPrimary.opacity(0.06))
                    .frame(width: 320, height: 320)
                    .blur(radius: 100)
                    .scaleEffect(ambientShift ? 1.08 : 0.96)
                    .offset(x: ambientShift ? 116 : 92, y: ambientShift ? -196 : -170)
                Circle()
                    .fill(MemoryColors.accentPurple.opacity(0.04))
                    .frame(width: 260, height: 260)
                    .blur(radius: 80)
                    .scaleEffect(ambientShift ? 0.96 : 1.08)
                    .offset(x: ambientShift ? -136 : -108, y: ambientShift ? 214 : 188)
            }
        case .journals:
            ZStack {
                LinearGradient(colors: [MemoryColors.storyJournalPurple1, MemoryColors.storyJournalPurple2, MemoryColors.storyJournalPurple3], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(MemoryColors.accentPink.opacity(0.05))
                    .frame(width: 260, height: 260)
                    .blur(radius: 80)
                    .scaleEffect(ambientShift ? 1.08 : 0.96)
                    .offset(x: ambientShift ? 136 : 108, y: ambientShift ? 188 : 212)
            }
        case .expenses:
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1A0A2E), Color(hex: 0x16213E), Color(hex: 0x0D1B2A)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(MemoryColors.accentAmber.opacity(0.08))
                    .frame(width: 280, height: 280)
                    .blur(radius: 92)
                    .scaleEffect(ambientShift ? 1.09 : 0.96)
                    .offset(x: ambientShift ? 146 : 118, y: ambientShift ? -204 : -178)
                Circle()
                    .fill(AppColors.brandPrimary.opacity(0.06))
                    .frame(width: 230, height: 230)
                    .blur(radius: 78)
                    .scaleEffect(ambientShift ? 0.96 : 1.08)
                    .offset(x: ambientShift ? -136 : -108, y: ambientShift ? 192 : 170)
            }
        case .memorable:
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2D1B4E), Color(hex: 0x1F1147), Color(hex: 0x0F0A2E)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(MemoryColors.accentPink.opacity(0.08))
                    .frame(width: 280, height: 280)
                    .blur(radius: 92)
                    .scaleEffect(ambientShift ? 1.08 : 0.96)
                    .offset(x: ambientShift ? -136 : -106, y: ambientShift ? -184 : -158)
                Circle()
                    .fill(MemoryColors.accentAmber.opacity(0.06))
                    .frame(width: 220, height: 220)
                    .blur(radius: 72)
                    .scaleEffect(ambientShift ? 0.96 : 1.08)
                    .offset(x: ambientShift ? 144 : 118, y: ambientShift ? 184 : 158)
            }
        case .ending:
            LinearGradient(colors: [MemoryColors.storyDarkNavy, MemoryColors.storyDarkBlue, MemoryColors.storyDarkDeep], startPoint: .top, endPoint: .bottom)
        }
    }

    private var decorativeLayer: some View {
        ZStack {
            if image == nil {
                Circle()
                    .fill(AppColors.brandPrimary.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 80)
                    .scaleEffect(ambientShift ? 1.06 : 0.98)
                    .offset(x: ambientShift ? 136 : 110, y: ambientShift ? -224 : -198)
                Circle()
                    .fill(MemoryColors.accentEmerald.opacity(0.08))
                    .frame(width: 230, height: 230)
                    .blur(radius: 70)
                    .scaleEffect(ambientShift ? 0.98 : 1.06)
                    .offset(x: ambientShift ? -154 : -128, y: ambientShift ? 232 : 208)
            }
        }
    }

    private var hasEntryAnimation: Bool {
        switch page {
        case .stats, .places, .photos, .expenses, .memorable, .journals: return true
        default: return false
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: page == .stats ? 12 : 9) {
            Text(headerEyebrow)
                .font(AppTypography.eyebrow)
                .foregroundStyle(.white.opacity(0.54))
                .tracking(1.8)
                .opacity(hasEntryAnimation ? (eyebrowAppeared ? 1 : 0) : 1)

            Text(headerTitle)
                .font(.system(size: page == .cover ? clampedCoverTitleSize : 28, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .opacity(hasEntryAnimation ? (titleAppeared ? 1 : 0) : 1)
                .offset(y: hasEntryAnimation ? (titleAppeared ? 0 : 10) : 0)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .cover:
            VStack(alignment: .leading, spacing: 12) {
                Label(ExportFormatting.dateRangeText(startDate: summary.trip.startDate, endDate: summary.trip.endDate), systemImage: "calendar")
                Label("\(summary.trip.dayCount) 天旅程", systemImage: "clock")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
        case .stats:
            if MemoryDisplayCopy.isSparse(stats: summary.stats) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(MemoryDisplayCopy.storySparseStatsNarrative(dayCount: summary.stats.dayCount))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineSpacing(6)
                        .opacity(statsAppeared ? 1 : 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    StoryStatsConstellation(
                        mainMetric: primaryStatsMetric,
                        orbitMetrics: orbitStatsMetrics,
                        isAppeared: statsAppeared,
                        numberSize: clampedStatNumberSize
                    )
                    .opacity(statsAppeared ? 1 : 0)
                    .offset(y: statsAppeared ? 0 : 12)

                    Text(statsRevealIntro)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineSpacing(5)
                        .opacity(statsAppeared ? 1 : 0)
                        .offset(y: statsAppeared ? 0 : 8)

                    if summary.stats.dayCount > 0 {
                        storyStatItem(
                            icon: "calendar",
                            count: summary.stats.dayCount,
                            label: "天的旅程",
                            color: MemoryColors.accentBlue,
                            isAppeared: statsItemAppeared[0],
                            countDelay: 0.45
                        )
                    }
                    if visitedPlaceCount > 0 {
                        storyStatItem(
                            icon: "mappin",
                            count: visitedPlaceCount,
                            label: "个目的地",
                            color: MemoryColors.accentGreen,
                            isAppeared: statsItemAppeared[1],
                            countDelay: 0.55
                        )
                    }
                    if summary.stats.photoCount > 0 {
                        storyStatItem(
                            icon: "camera",
                            count: summary.stats.photoCount,
                            label: "张照片记录",
                            color: MemoryColors.accentAmber,
                            isAppeared: statsItemAppeared[2],
                            countDelay: 0.65
                        )
                    }
                    if summary.stats.journalCount > 0 {
                        storyStatItem(
                            icon: "heart",
                            count: summary.stats.journalCount,
                            label: "篇旅行日志",
                            color: MemoryColors.accentPink,
                            isAppeared: statsItemAppeared[3],
                            countDelay: 0.75
                        )
                    }

                }
            }
        case .places:
            placesContent
        case .photos:
            photosContent
                .opacity(contentAppeared ? 1 : 0)
        case .expenses:
            expensesContent
                .opacity(contentAppeared ? 1 : 0)
        case .memorable:
            memorableContent
                .opacity(contentAppeared ? 1 : 0)
        case .journals:
            journalsContent
                .opacity(contentAppeared ? 1 : 0)
        case .ending:
            endingContent
                .opacity(contentAppeared ? 1 : 0)
        }
    }

    // MARK: - Places Page

    @ViewBuilder
    private var placesContent: some View {
        if visitedPlaces.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(.white.opacity(0.30))
                Text("还没记下具体目的地，\n也没关系，路上的痕迹还在。")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                // Map texture area
                ZStack {
                    // Grid pattern
                    Canvas { context, size in
                        let gridSize: CGFloat = 28
                        var x: CGFloat = 0
                        while x < size.width {
                            var y: CGFloat = 0
                            while y < size.height {
                                let path = Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2))
                                context.fill(path, with: .color(MemoryColors.mapGridLine))
                                y += gridSize
                            }
                            x += gridSize
                        }
                    }
                    .frame(height: 120)

                    // Decorative path line
                    Path { path in
                        path.move(to: CGPoint(x: 40, y: 80))
                        path.addCurve(to: CGPoint(x: 160, y: 30), control1: CGPoint(x: 80, y: 60), control2: CGPoint(x: 120, y: 10))
                        path.addCurve(to: CGPoint(x: 280, y: 70), control1: CGPoint(x: 200, y: 50), control2: CGPoint(x: 240, y: 40))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 6]))
                    .foregroundStyle(MemoryColors.mapPathLine)
                    .frame(height: 120)
                }
                .padding(.bottom, 8)

                // 2-column grid of place cards
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(visitedPlaces.prefix(6).enumerated()), id: \.element) { index, place in
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "mappin")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MemoryColors.accentBlue)
                                .frame(width: 36, height: 36)
                                .background(MemoryColors.accentBlue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(place)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.06), lineWidth: 0.6)
                        }
                        .opacity(placesItemAppeared[index] ? 1 : 0)
                        .offset(y: placesItemAppeared[index] ? 0 : 12)
                    }
                }
            }
        }
    }

    // MARK: - Photos Page

    @ViewBuilder
    private var photosContent: some View {
        let photos = summary.featuredPhotos
        if photos.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(.white.opacity(0.30))
                Text("有些风景，留在了眼睛里。")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .frame(maxWidth: .infinity)
        } else {
            PhotosPageCarousel(
                photos: photos,
                images: loadedImages,
                onHorizontalInteraction: onHorizontalPhotoInteraction,
                onVerticalPageRequest: onVerticalPageRequest
            )
        }
    }

    // MARK: - Expenses Page

    @ViewBuilder
    private var expensesContent: some View {
        if summary.stats.totalExpenseValue <= 0 && expenseCategories.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "creditcard")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(.white.opacity(0.30))
                Text("这趟旅行还没有花费记录。")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity)
        } else {
            ZStack {
                StoryReceiptTexture()
                    .offset(y: 18)
                    .opacity(contentAppeared ? 1 : 0)
                    .scaleEffect(contentAppeared ? 1 : 0.96)

                VStack(alignment: .leading, spacing: 26) {
                    StoryMoneyReveal(
                        amount: Int(summary.stats.totalExpenseValue.rounded()),
                        currencySymbol: currencySymbol,
                        subtitle: expenseSubtitle,
                        numberSize: clampedExpenseTotalSize
                    )
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(Array(expenseCategories.prefix(5).enumerated()), id: \.element.id) { index, category in
                            expenseRow(category, index: index)
                                .opacity(contentAppeared ? 1 : 0)
                                .offset(x: contentAppeared ? 0 : 18, y: contentAppeared ? 0 : 8)
                                .animation(.easeOut(duration: 0.42).delay(0.12 + Double(index) * 0.07), value: contentAppeared)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func expenseRow(_ category: TripSummaryExpenseCategory, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Circle()
                    .fill(expenseColor(for: index))
                    .frame(width: 8, height: 8)
                Text(category.categoryName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(ExportFormatting.currencyText(amount: category.amountValue, currency: summary.stats.currency))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.10))
                    Capsule()
                        .fill(expenseColor(for: index))
                        .frame(width: proxy.size.width * min(max(category.percentageValue / 100, 0), 1))
                }
            }
            .frame(height: 9)
        }
        .padding(13)
        .background(.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 0.6)
        }
    }

    // MARK: - Memorable Page

    @State private var breathingGlow = false

    @ViewBuilder
    private var memorableContent: some View {
        if let log = memorableLog {
            ZStack {
                // Breathing glow behind the quote
                Circle()
                    .fill(MemoryColors.glowAmber)
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .scaleEffect(reduceMotion ? 1.0 : (breathingGlow ? 1.2 : 1.0))
                    .opacity(reduceMotion ? 0.35 : (breathingGlow ? 0.55 : 0.25))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
                        value: breathingGlow
                    )

                // Large decorative opening quote
                Text("\u{201C}")
                    .font(.system(size: 130, design: .serif))
                    .foregroundStyle(.white.opacity(0.05))
                    .offset(x: -100, y: -70)
                    .zIndex(0)

                VStack(spacing: 0) {
                    Spacer()

                    StoryQuotePanel(accent: MemoryColors.accentAmber) {
                        VStack(spacing: 22) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(MemoryColors.accentAmber)

                            Text(log.content ?? "")
                                .font(.system(size: clampedMemorableQuoteSize, weight: .medium, design: .serif))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineSpacing(10)
                                .minimumScaleFactor(0.7)
                                .lineLimit(8)

                            // Time + location
                            HStack(spacing: 10) {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [MemoryColors.accentAmber, MemoryColors.accentPink],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(width: 3, height: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(MemoryStoryViewModel.formattedLogTime(log, dayIndex: dayIndex(for: log)))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.72))
                                    let location = log.locationName?.isEmpty == false ? log.locationName : nil
                                    Text(location ?? displayTitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.42))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Large decorative closing quote
                    Text("\u{201D}")
                        .font(.system(size: 130, design: .serif))
                        .foregroundStyle(.white.opacity(0.05))
                        .offset(x: 100, y: 50)
                        .zIndex(0)

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                guard !reduceMotion else { return }
                breathingGlow = true
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(.white.opacity(0.30))
                Text("有些瞬间不用写下来，\n也已经成为这趟旅程的一部分。")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Journals Page

    @ViewBuilder
    private var journalsContent: some View {
        if let log = latestJournalLog {
            StoryQuotePanel(accent: MemoryColors.accentPink) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(MemoryColors.accentPink.opacity(0.70))
                        Spacer()
                        Text(dayLabel(for: log))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.white.opacity(0.08), in: Capsule())
                    }

                    Text(log.content ?? "")
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                        .lineSpacing(7.5)
                        .lineLimit(7)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(MemoryColors.accentPink)
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(LinearGradient(colors: [MemoryColors.accentPink, Color(hex: 0xA855F7).opacity(0.25)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 2, height: summary.stats.journalCount > 1 ? 56 : 30)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(MemoryStoryViewModel.formattedLogTime(log, dayIndex: dayIndex(for: log)))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                            if let location = log.locationName, !location.isEmpty {
                                Text(location)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.42))
                                    .lineLimit(1)
                            }

                            if summary.stats.journalCount > 1 {
                                Text("还有 \(summary.stats.journalCount - 1) 篇日志，记录了其他时刻")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.36))
                                    .padding(.top, 10)
                            }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(.white.opacity(0.30))
                Text("没有写下来的部分，\n也会留在记忆里。")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Ending Page

    private var endingContent: some View {
        ZStack {
            // Sparkle particles behind content
            SparkleParticleView(count: 30)
                .opacity(contentAppeared ? 1 : 0)

            VStack(spacing: 22) {
                // Gently pulsing glow behind the icon
                ZStack {
                    Circle()
                        .fill(AppColors.brandPrimary.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .blur(radius: 40)
                        .scaleEffect(contentAppeared ? 1.2 : 0.8)
                        .opacity(contentAppeared ? 0.6 : 0)
                        .animation(.easeOut(duration: 1.2).delay(0.3), value: contentAppeared)

                    Image(systemName: "mappin")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(
                            LinearGradient(
                                colors: [AppColors.brandPrimary, MemoryColors.accentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .tracciShadow(AppShadow.brand)
                }

                Text(displayTitle)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)

                Text(narrative.endingSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.54))
                    .tracking(0.3)

                Text("这趟旅程的记录都在这里，\n需要时随时回来看。")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                VStack(spacing: 14) {
                    if showsExportActions {
                        Button {
                            AppHaptics.mediumImpact()
                            onSave?()
                        } label: {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MemoryColors.endingButtonText)
                                .padding(.horizontal, 32)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: .white.opacity(0.22), radius: 20, x: 0, y: 8)
                        }
                        .pressableCardStyle()

                        // Share = render report image → system share sheet (UIActivityViewController).
                        // Copy-share-text is deferred until AI share copy is product-ready.
                        Button {
                            AppHaptics.lightImpact()
                            onShareReport?()
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 24)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                                .background(.white.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(.white.opacity(0.14), lineWidth: 0.6)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .pressableCardStyle()
                    } else {
                        Text(DemoReadOnlyCopy.memoryBrowseOnly)
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                            .accessibilityLabel(DemoReadOnlyCopy.memoryBrowseOnly)
                    }

                    Button {
                        AppHaptics.lightImpact()
                        onReplay?()
                    } label: {
                        Label("再看一次", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))
                            .padding(.horizontal, AppSpacing.pageX)
                            .frame(height: 42)
                            .background(.white.opacity(0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous))
                    }
                    .pressableCardStyle()
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var watermark: some View {
        HStack {
            BrandWatermarkView(style: .watermarkLight, logoHeight: 14, wordmarkSize: 12)
            Spacer()
        }
        .opacity(watermarkAppeared ? 1 : 0)
    }

    // MARK: - Cover Page

    private var coverContent: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                Text("TRIP STORY")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(2)
                    .opacity(eyebrowAppeared ? 1 : 0)

                Text(displayTitle)
                    .font(.system(size: clampedCoverTitleSize, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .tracciShadow(AppShadow.textStrong)
                    .opacity(titleAppeared ? 1 : 0)
                    .offset(y: titleAppeared ? 0 : 16)

                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        ExportFormatting.dateRangeText(
                            startDate: summary.trip.startDate,
                            endDate: summary.trip.endDate
                        ),
                        systemImage: "calendar"
                    )
                    Label("\(summary.trip.dayCount) 天旅程", systemImage: "clock")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .labelStyle(.titleAndIcon)
                .opacity(infoAppeared ? 1 : 0)
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack {
                BrandWatermarkView(style: .watermarkLight, logoHeight: 14, wordmarkSize: 12)
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 42)
            .opacity(watermarkAppeared ? 1 : 0)
        }
    }

    private var headerEyebrow: String {
        switch page {
        case .cover: "TRIP STORY"
        case .stats: "YOUR JOURNEY"
        case .places: "PLACES"
        case .photos: "PHOTOS"
        case .expenses: "EXPENSES"
        case .memorable: "MEMORABLE MOMENT"
        case .journals: "JOURNAL"
        case .ending: ""
        }
    }

    private var headerTitle: String {
        switch page {
        case .cover: displayTitle
        case .stats: narrative.stats
        case .places: narrative.places
        case .photos: narrative.photos
        case .expenses: narrative.expenses
        case .memorable: narrative.memorable
        case .journals: narrative.journals
        case .ending: ""
        }
    }

    private var allJournalLogs: [TripSummaryLog] {
        summary.dailyTimeline.flatMap { $0.logs }
    }

    private var latestJournalLog: TripSummaryLog? {
        allJournalLogs
            .filter { ($0.content ?? "").count >= 10 }
            .sorted {
                // Prefer logs with logTime; fall back to content length
                let t0 = $0.logTime ?? ""
                let t1 = $1.logTime ?? ""
                if !t0.isEmpty || !t1.isEmpty { return t0 > t1 }
                return ($0.content ?? "").count > ($1.content ?? "").count
            }
            .first
    }

    private var memorableLog: TripSummaryLog? {
        summary.highlightLogs
            .filter { ($0.content ?? "").count >= 10 }
            .sorted { ($0.content ?? "").count > ($1.content ?? "").count }
            .first ?? latestJournalLog
    }

    private var expenseCategories: [TripSummaryExpenseCategory] {
        summary.expenseSummary?.categoryStats.filter { $0.amountValue > 0 } ?? []
    }

    private var currencySymbol: String {
        summary.stats.currency == "CNY" ? "¥" : summary.stats.currency
    }

    private var expenseSubtitle: String {
        if summary.stats.dayCount > 0 {
            let average = summary.stats.totalExpenseValue / Double(summary.stats.dayCount)
            return "日均 \(ExportFormatting.currencyText(amount: average, currency: summary.stats.currency))"
        }
        return "这是路上花掉的一些"
    }

    private var statsRevealIntro: String {
        if summary.stats.journalCount >= 5 {
            return "下面是这趟留下的一些数字。"
        }
        if summary.stats.photoCount >= 10 {
            return "照片挺多的，先看整体。"
        }
        return "下面是这趟的概况。"
    }

    private var primaryStatsMetric: StoryOrbitMetric {
        let metric = MemoryStoryNarrativeBuilder.primaryHeroMetric(for: summary)
        return StoryOrbitMetric(
            icon: metric.kind.storyIcon,
            value: metric.value,
            unit: metric.unit,
            caption: metric.caption,
            color: metric.color
        )
    }

    private var orbitStatsMetrics: [StoryOrbitMetric] {
        [
            StoryOrbitMetric(
                icon: "calendar",
                value: summary.stats.dayCount,
                unit: "天",
                caption: "旅程长度",
                color: MemoryColors.accentBlue
            ),
            StoryOrbitMetric(
                icon: "mappin",
                value: visitedPlaceCount,
                unit: "处",
                caption: "到达的地方",
                color: MemoryColors.accentGreen
            ),
            StoryOrbitMetric(
                icon: "camera",
                value: summary.stats.photoCount,
                unit: "张",
                caption: "照片记录",
                color: MemoryColors.accentAmber
            ),
            StoryOrbitMetric(
                icon: "book.closed",
                value: summary.stats.journalCount,
                unit: "篇",
                caption: "旅行日志",
                color: MemoryColors.accentPink
            )
        ]
        .filter { $0.value > 0 }
    }

    private var displayTitle: String {
        summary.trip.title
    }

    private var visitedPlaces: [String] {
        MemoryStoryNarrativeBuilder.visitedPlaces(from: summary)
    }

    private var visitedPlaceCount: Int {
        visitedPlaces.count
    }

    private var highlightText: String {
        if let content = summary.highlightLogs.first?.content, !content.isEmpty {
            return content
        }
        if summary.stats.photoCount > 0 {
            return "路上拍下的一些画面。"
        }
        return "还没有照片，可以先看看其他内容。"
    }

    private func dayLabel(for log: TripSummaryLog) -> String {
        let idx = dayIndex(for: log)
        return "第 \(idx) 天"
    }

    private func storyStatItem(
        icon: String,
        count: Int,
        label: String,
        color: Color,
        isAppeared: Bool,
        countDelay: Double
    ) -> some View {
        StoryRevealMetric(
            icon: icon,
            count: count,
            label: label,
            color: color,
            isAppeared: isAppeared,
            countDelay: countDelay,
            numberSize: clampedStatNumberSize
        )
    }

    private func expenseColor(for index: Int) -> Color {
        let colors = [
            MemoryColors.accentAmber,
            MemoryColors.accentBlue,
            MemoryColors.accentPurple,
            MemoryColors.accentEmerald,
            MemoryColors.accentPink
        ]
        return colors[index % colors.count]
    }

    private func dayIndex(for log: TripSummaryLog) -> Int {
        summary.dailyTimeline.first { day in
            day.logs.contains(where: { $0.id == log.id })
        }?.dayIndex ?? 1
    }
}

// MARK: - Photos Page Carousel

struct PhotosPageCarousel: View {
    let photos: [TripSummaryPhoto]
    let images: [UIImage]
    var onHorizontalInteraction: ((Bool) -> Void)?
    var onVerticalPageRequest: ((Int) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var dragAxis: PhotoDragAxis = .undecided
    @State private var dragOffsetX: CGFloat = 0

    private enum PhotoDragAxis {
        case undecided
        case horizontal
        case vertical
    }

    private var crossfadeDuration: Double { reduceMotion ? 0.15 : 0.32 }

    var body: some View {
        VStack(spacing: 12) {
            // Photo display area
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                        photoSlide(photo: photo, index: idx, size: proxy.size)
                            .opacity(idx == currentIndex ? 1 : 0)
                            .offset(x: idx == currentIndex ? dragOffsetX : 0)
                            .animation(
                                .easeInOut(duration: crossfadeDuration),
                                value: currentIndex
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(Rectangle())
                .highPriorityGesture(photoDragGesture)
            }
            // Cap height so tall pages cannot inflate the story chrome into the status bar.
            .aspectRatio(0.75, contentMode: .fit)
            .frame(maxHeight: 420)

            // Photo counter
            HStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.top, 2)

            // Dot indicators
            if photos.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<min(photos.count, 8), id: \.self) { i in
                        Capsule()
                            .fill(i == currentIndex ? .white : .white.opacity(0.28))
                            .frame(width: i == currentIndex ? 20 : 6, height: 4)
                            .animation(.easeInOut(duration: 0.22), value: currentIndex)
                    }
                }
            }
        }
        .task {
            guard photos.count > 1, !reduceMotion else { return }
            startCarousel()
        }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
            onHorizontalInteraction?(false)
        }
        .accessibilityLabel("旅途照片，第\(currentIndex + 1)张，共\(photos.count)张")
        .accessibilityHint(photos.count > 1 ? "左右滑动切换照片，上下滑动翻页" : "")
        .accessibilityAction(named: Text("下一张")) {
            advancePhoto(by: 1, animated: true)
        }
        .accessibilityAction(named: Text("上一张")) {
            advancePhoto(by: -1, animated: true)
        }
    }

    private var photoDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                resolveDragAxisIfNeeded(value.translation)
                switch dragAxis {
                case .horizontal:
                    onHorizontalInteraction?(true)
                    // Light rubber-band at ends.
                    let atStart = currentIndex == 0 && value.translation.width > 0
                    let atEnd = currentIndex == photos.count - 1 && value.translation.width < 0
                    let damped = (atStart || atEnd) ? value.translation.width * 0.28 : value.translation.width
                    dragOffsetX = photos.count > 1 ? damped : 0
                case .vertical:
                    onHorizontalInteraction?(false)
                    dragOffsetX = 0
                case .undecided:
                    break
                }
            }
            .onEnded { value in
                let axis = dragAxis
                dragAxis = .undecided
                dragOffsetX = 0
                onHorizontalInteraction?(false)

                let dx = value.translation.width
                let dy = value.translation.height
                let predictedX = value.predictedEndTranslation.width
                let predictedY = value.predictedEndTranslation.height

                switch axis {
                case .horizontal:
                    guard photos.count > 1 else { return }
                    let effectiveX = abs(predictedX) > abs(dx) ? predictedX : dx
                    if effectiveX < -40 {
                        advancePhoto(by: 1, animated: true)
                    } else if effectiveX > 40 {
                        advancePhoto(by: -1, animated: true)
                    }
                case .vertical:
                    let effectiveY = abs(predictedY) > abs(dy) ? predictedY : dy
                    if effectiveY < -56 {
                        onVerticalPageRequest?(1)
                    } else if effectiveY > 56 {
                        onVerticalPageRequest?(-1)
                    }
                case .undecided:
                    break
                }
            }
    }

    private func resolveDragAxisIfNeeded(_ translation: CGSize) {
        guard dragAxis == .undecided else { return }
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        guard dx > 10 || dy > 10 else { return }
        if dx > dy * 1.15 {
            dragAxis = .horizontal
            onHorizontalInteraction?(true)
            restartCarouselTimer()
        } else if dy > dx * 1.15 {
            dragAxis = .vertical
        }
    }

    private func photoSlide(photo: TripSummaryPhoto, index: Int, size: CGSize) -> some View {
        Group {
            if let image = images[safe: index] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = photo.renderURLs.first {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        photoPlaceholder(size: size)
                    default:
                        ProgressView().tint(.white.opacity(0.4))
                    }
                }
            } else {
                photoPlaceholder(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func photoPlaceholder(size: CGSize) -> some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(width: size.width, height: size.height)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.white.opacity(0.18))
                    .font(.system(size: 32))
            }
    }

    private func advancePhoto(by delta: Int, animated: Bool) {
        guard photos.count > 1 else { return }
        let next = (currentIndex + delta + photos.count) % photos.count
        guard next != currentIndex else { return }
        AppHaptics.lightImpact()
        if animated {
            withAnimation(.easeInOut(duration: crossfadeDuration)) {
                currentIndex = next
            }
        } else {
            currentIndex = next
        }
        restartCarouselTimer()
    }

    private func startCarousel() {
        restartCarouselTimer()
    }

    private func restartCarouselTimer() {
        timerTask?.cancel()
        guard photos.count > 1, !reduceMotion else {
            timerTask = nil
            return
        }
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: crossfadeDuration)) {
                    currentIndex = (currentIndex + 1) % photos.count
                }
            }
        }
    }
}

// MARK: - Sparkle Particle View

struct SparkleParticleView: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [SparkleParticle] = []

    var body: some View {
        Group {
            if reduceMotion {
                sparkleCanvas(date: .distantPast)
            } else {
                TimelineView(.animation) { timeline in
                    sparkleCanvas(date: timeline.date)
                }
            }
        }
        .onAppear {
            particles = generateParticles()
        }
        .allowsHitTesting(false)
    }

    private func sparkleCanvas(date: Date) -> some View {
        Canvas { context, size in
            for particle in particles {
                let x = particle.x * size.width
                let y = particle.y * size.height
                let radius = reduceMotion
                    ? particle.baseRadius
                    : particle.baseRadius * (0.6 + 0.4 * sin(particle.phase + date.timeIntervalSinceReferenceDate * particle.speed))
                let path = Path(ellipseIn: CGRect(
                    x: x - radius, y: y - radius,
                    width: radius * 2, height: radius * 2
                ))
                let resolvedOpacity = particle.opacity * min(radius / particle.baseRadius, 1.2)
                context.fill(path, with: .color(.white.opacity(resolvedOpacity)))
            }
        }
    }

    private func generateParticles() -> [SparkleParticle] {
        (0..<count).map { _ in
            SparkleParticle(
                x: Double.random(in: 0.05...0.95),
                y: Double.random(in: 0.05...0.95),
                baseRadius: Double.random(in: 1.5...4.5),
                opacity: Double.random(in: 0.20...0.55),
                phase: Double.random(in: 0...(2 * .pi)),
                speed: Double.random(in: 0.6...1.8)
            )
        }
    }

    struct SparkleParticle {
        var x: Double
        var y: Double
        var baseRadius: Double
        var opacity: Double
        var phase: Double
        var speed: Double
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
