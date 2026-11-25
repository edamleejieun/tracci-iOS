import MapKit
import SwiftUI

/// 旅程详情「大地图沉浸」Surface。
///
/// 与 browse 叠层常驻：MKMapView 不在切换时销毁。
/// `presentationProgress` 0→1 驱动分层转场（Hero 裁剪展开、dock 上滑、浮层出现）。
struct TripMapExploreSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let trip: Trip
    let routeProvider: any TripRouteProviding
    let heroMapData: TripHeroMapData
    let dayLabel: String
    let totalDays: Int
    let tripStartDate: String
    let carouselNodes: [ItineraryNodeItem]
    let dayDate: Date?
    let autoHighlightNodeId: String?
    let safeAreaTop: CGFloat
    /// 封面 Hero 在 `TripMapExploreCoordinateSpace.root` 下的 frame。
    let sourceHeroFrame: CGRect
    /// 0 = 收起，1 = 完全展开。
    let presentationProgress: CGFloat
    /// 是否接收触摸（仅 presented）。
    let isInteractive: Bool
    /// 是否驱动地图数据/呼吸动画（含预热与转场）。
    let isMapVisible: Bool
    /// 转场中关闭镜头动画。
    let suppressCameraAnimation: Bool
    /// 全旅程总览时 dock 的摘要文案（单日模式不使用）。
    let fullTripSummaryText: String

    @Binding var selectedDayIndex: Int
    @Binding var linkedNodeId: String?
    @Binding var mapViewport: TripHeroMapViewport
    @Binding var heroMode: TripHeroMode

    let onSelectNode: (String) -> Void
    let onNavigateToNode: (ItineraryNodeItem) -> Void
    let onNavigateAnnotation: (TripHeroMapData.HeroMapAnnotation) -> Void
    let onSelectDay: (Int) -> Void
    /// 选择「全程」：切换到全旅程路线总览。
    let onSelectFullTrip: () -> Void
    let onDismiss: () -> Void

    @State private var dismissDragOffset: CGFloat = 0
    @State private var containerFrameInRoot: CGRect = .zero
    @State private var bottomDockHeight: CGFloat = 0
    @State private var showDismissHint = false
    @State private var dismissHintTask: Task<Void, Never>?

    private let floatingControlsDockGap: CGFloat = 14

    private var chromeProgress: CGFloat {
        min(1, max(0, (presentationProgress - 0.08) / 0.92))
    }

    private var localHeroSource: CGRect {
        guard containerFrameInRoot.width > 1, sourceHeroFrame.width > 1 else {
            return .zero
        }
        return CGRect(
            x: sourceHeroFrame.minX - containerFrameInRoot.minX,
            y: sourceHeroFrame.minY - containerFrameInRoot.minY,
            width: sourceHeroFrame.width,
            height: sourceHeroFrame.height
        )
    }

    var body: some View {
        // ZStack 全屏：地图垫底全出血，dock/控件叠在上面。
        // 避免 VStack 把 map 挤在安全区下方，顶部露出 page 灰底。
        ZStack(alignment: .bottom) {
            fullBleedMapLayer

            statusBarReadabilityScrim
                .opacity(Double(max(chromeProgress, presentationProgress > 0.5 ? 1 : chromeProgress)))
                .allowsHitTesting(false)

            // 左上返回 + 右下浮层
            VStack(spacing: 0) {
                HStack {
                    dismissButton
                        .opacity(Double(chromeProgress))
                        .scaleEffect(0.92 + 0.08 * chromeProgress)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, TripDetailLayout.pageInset)
                .padding(.top, safeAreaTop + 8)

                Spacer(minLength: 0)

                HStack {
                    if let selected = selectedAnnotation, chromeProgress > 0.55 {
                        TripHeroNodeCard(
                            title: selected.title,
                            timeText: selected.timeText,
                            locationName: nil,
                            onNavigate: { onNavigateAnnotation(selected) }
                        )
                        .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    mapFloatingControls
                        .opacity(Double(chromeProgress))
                        .offset(y: (1 - chromeProgress) * 12)
                }
                .padding(.horizontal, TripDetailLayout.pageInset)
                // 浮层与 bottomDock 是同级叠放；按 Dock 实际高度避让，
                // 避免路线总览 / 模式切换器被下方行程内容覆盖。
                .padding(.bottom, bottomDockHeight + floatingControlsDockGap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomDock
                .offset(y: dockHiddenOffset + max(0, dismissDragOffset))
                .opacity(Double(chromeProgress))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(presentationProgress < 0.05)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TripMapExploreContainerFramePreferenceKey.self,
                    value: proxy.frame(in: .named(TripMapExploreCoordinateSpace.root))
                )
            }
        }
        .onPreferenceChange(TripMapExploreContainerFramePreferenceKey.self) { frame in
            containerFrameInRoot = frame
        }
        .onPreferenceChange(TripMapExploreBottomDockHeightPreferenceKey.self) { height in
            guard height > 0, abs(bottomDockHeight - height) > 0.5 else { return }
            bottomDockHeight = height
        }
        .modifier(
            MapExploreClipModifier(
                enabled: presentationProgress > 0.001,
                progress: reduceMotion ? (presentationProgress > 0.5 ? 1 : 0) : presentationProgress,
                source: localHeroSource
            )
        )
        .opacity(presentationProgress <= 0 ? 0 : 1)
        .onChange(of: isInteractive) { _, interactive in
            if interactive {
                scheduleDismissHintIfNeeded()
            } else {
                hideDismissHint(markSeen: true)
            }
        }
        .onDisappear {
            dismissHintTask?.cancel()
        }
    }

    // MARK: - Full-bleed map

    /// 地图铺满含状态栏/home indicator；用 GeometryReader 强制尺寸含 safeAreaInsets。
    private var fullBleedMapLayer: some View {
        GeometryReader { geo in
            let totalSize = CGSize(
                width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )
            TripHeroMapView(
                annotations: heroMapData.annotationNodes,
                destinationCoordinate: heroMapData.destinationCoordinate,
                focusedNodeId: linkedNodeId,
                viewport: mapViewport,
                autoHighlightNodeId: autoHighlightNodeId,
                reduceMotion: reduceMotion,
                tripStatus: trip.effectiveStatus,
                routeLoader: TripHeroRouteLoader(routeProvider: routeProvider),
                isMapVisible: isMapVisible,
                suppressCameraAnimation: suppressCameraAnimation,
                isFullTripOverview: heroMapData.isFullTripOverview,
                daySegments: heroMapData.daySegments,
                fullTripDayCount: heroMapData.fullTripDayCount,
                onSelectNode: onSelectNode,
                onDeselect: {
                    linkedNodeId = nil
                    if case .focusedNode = mapViewport {
                        mapViewport = .userExploring
                    }
                },
                onUserExplore: {
                    mapViewport = .userExploring
                }
            )
            .transaction { $0.animation = nil }
            .frame(width: totalSize.width, height: totalSize.height)
            // 向上/向左抵消 safe area，使 MKMapView 真正画进状态栏区域。
            .offset(
                x: -geo.safeAreaInsets.leading,
                y: -geo.safeAreaInsets.top
            )
        }
        .ignoresSafeArea()
    }

    /// 仅遮住状态栏/灵动岛一带，向下快速淡出；用深色透明叠在地图上，不是灰底。
    private var statusBarReadabilityScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.32),
                    Color.black.opacity(0.10),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: max(safeAreaTop + 20, 44))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private var dismissButton: some View {
        Button {
            hideDismissHint(markSeen: true)
            onDismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .tracciMediaChromeGlass(in: Circle(), wash: .black.opacity(0.22))
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("返回")
        .accessibilityHint("返回旅程详情")
    }

    private var mapFloatingControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if mapViewport != .routeOverview, !heroMapData.annotationNodes.isEmpty {
                Button {
                    AppHaptics.selection()
                    linkedNodeId = nil
                    mapViewport = .routeOverview
                } label: {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 44, height: 36)
                        } else {
                            Label("路线总览", systemImage: "arrow.up.left.and.arrow.down.right")
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                        }
                    }
                    .font(TripDetailTypography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracciMediaChromeGlass(in: Capsule(), wash: .black.opacity(0.28))
                }
                .buttonStyle(TracciPressableButtonStyle(scales: false))
                .accessibilityLabel(
                    heroMapData.isFullTripOverview
                        ? "显示全程路线总览"
                        : "显示当前日期的路线总览"
                )
            }

            TripHeroModeToggle(currentMode: $heroMode)
        }
    }

    // MARK: - Bottom dock

    private var bottomDock: some View {
        VStack(spacing: 0) {
            dismissHandle

            if showDismissHint {
                dismissHintChip
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 4)
            }

            TripMapDayTabRail(
                selectedDayIndex: $selectedDayIndex,
                totalDays: totalDays,
                tripStartDate: tripStartDate,
                showsFullTripEntry: totalDays > 1,
                isFullTripSelected: heroMapData.isFullTripOverview,
                onSelectFullTrip: onSelectFullTrip,
                onSelectDay: onSelectDay
            )
            .padding(.horizontal, AppSpacing.sm)
            .padding(.bottom, 4)

            if heroMapData.isFullTripOverview {
                fullTripSummaryRow
                    .padding(.horizontal, TripDetailLayout.pageInset)
                    .padding(.bottom, 10)
            } else if carouselNodes.isEmpty {
                emptyCarouselHint
                    .padding(.horizontal, TripDetailLayout.pageInset)
                    .padding(.bottom, 10)
            } else {
                TripNodeCarouselView(
                    nodes: carouselNodes,
                    dayDate: dayDate,
                    linkedNodeId: $linkedNodeId,
                    style: .compact,
                    onSelectNode: onSelectNode,
                    onNavigateToNode: onNavigateToNode,
                    reduceMotion: reduceMotion
                )
                .frame(height: carouselHeight)
                .padding(.bottom, 8)
            }
        }
        .padding(.bottom, max(SafeAreaMetrics.bottom, 6))
        .background {
            dockBackground
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TripMapExploreBottomDockHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("行程，\(dayLabel)")
    }

    private var dockHiddenOffset: CGFloat {
        (1 - chromeProgress) * 200
    }

    private var dockBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 20,
            style: .continuous
        )
        .fill(.ultraThinMaterial)
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            .fill(AppColors.cardBackground.opacity(0.72))
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .tracciShadow(AppShadow.dockLift(progress: chromeProgress))
        .ignoresSafeArea(edges: .bottom)
    }

    private var dismissHandle: some View {
        Capsule()
            .fill(AppColors.textPlaceholder.opacity(0.55))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        guard isInteractive else { return }
                        dismissDragOffset = max(0, -value.translation.height)
                        if value.translation.height < -12 {
                            hideDismissHint(markSeen: true)
                        }
                    }
                    .onEnded { value in
                        guard isInteractive else {
                            dismissDragOffset = 0
                            return
                        }
                        let upward = -value.translation.height
                        let velocity = value.predictedEndTranslation.height - value.translation.height
                        let shouldDismiss = upward > 56 || velocity < -220
                        if shouldDismiss {
                            hideDismissHint(markSeen: true)
                            onDismiss()
                        }
                        withAnimation(reduceMotion ? nil : AppMotion.quick) {
                            dismissDragOffset = 0
                        }
                    }
            )
            .onTapGesture {
                guard isInteractive else { return }
                hideDismissHint(markSeen: true)
                onDismiss()
            }
            .accessibilityLabel("退出地图")
            .accessibilityHint("上推或点按，返回旅程详情")
            .accessibilityAddTraits(.isButton)
    }

    private var dismissHintChip: some View {
        Text("上推或点按把手，返回详情")
            .font(TripDetailTypography.caption.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.subtleBackground.opacity(0.95), in: Capsule())
            .overlay {
                Capsule().stroke(AppColors.borderSubtle.opacity(0.4), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    private var emptyCarouselHint: some View {
        Text("当天还没有可在地图上展示的行程点")
            .font(TripDetailTypography.nodeMeta)
            .foregroundStyle(AppColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    /// 全旅程总览的 dock 摘要：替代单日横滑卡片，说明如何回到某天。
    private var fullTripSummaryRow: some View {
        HStack(spacing: 6) {
            Text(fullTripSummaryText)
                .font(TripDetailTypography.nodeMeta)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: 8)

            Text(Self.fullTripDayHint)
                .font(TripDetailTypography.nodeMeta)
                .foregroundStyle(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private static let fullTripDayHint = "点上方日期可看单日路线"

    private var selectedAnnotation: TripHeroMapData.HeroMapAnnotation? {
        guard let linkedNodeId else { return nil }
        return heroMapData.annotationNodes.first { $0.id == linkedNodeId }
    }

    private var carouselHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 118 : 96
    }

    // MARK: - First-run dismiss hint

    private func scheduleDismissHintIfNeeded() {
        guard !TripMapExploreHintStore.hasSeenDismissHint else { return }
        guard !reduceMotion else {
            // Reduce Motion 用户仍给一次短提示，但不动画。
            showDismissHint = true
            dismissHintTask?.cancel()
            dismissHintTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                hideDismissHint(markSeen: true)
            }
            return
        }

        dismissHintTask?.cancel()
        dismissHintTask = Task { @MainActor in
            // 等展开完成再出现，避免与 dock 动画抢注意力。
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, isInteractive else { return }
            withAnimation(AppMotion.quick) {
                showDismissHint = true
            }
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            hideDismissHint(markSeen: true)
        }
    }

    private func hideDismissHint(markSeen: Bool) {
        dismissHintTask?.cancel()
        dismissHintTask = nil
        if showDismissHint {
            withAnimation(reduceMotion ? nil : AppMotion.quick) {
                showDismissHint = false
            }
        } else {
            showDismissHint = false
        }
        if markSeen {
            TripMapExploreHintStore.hasSeenDismissHint = true
        }
    }
}

private struct TripMapExploreBottomDockHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Conditional expand clip

private struct MapExploreClipModifier: ViewModifier {
    let enabled: Bool
    let progress: CGFloat
    let source: CGRect

    func body(content: Content) -> some View {
        if enabled {
            content.clipShape(TripMapExpandingClip(progress: progress, source: source))
        } else {
            content
        }
    }
}
