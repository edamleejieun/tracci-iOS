import SwiftUI

// MARK: - Stage Narrative (cover only, local facts)

/// Cover eyebrow + scene line for Creek Editorial Immersion.
/// Built only from existing trip fields — no backend summary required; hide when empty.
///
/// Keep tool-like facts: stage + place + counts. Avoid generative “AI lyric” lines
/// (溪径 / 脚步 / 落幕 / 故事仍在) that compete with destination and date meta below.
enum TripDetailStageNarrative {
    static func eyebrow(
        for trip: Trip,
        currentDayText: String?,
        totalDaysText: String,
        daysUntilDeparture: Int?
    ) -> String {
        switch trip.effectiveStatus {
        case .planning:
            if let daysUntilDeparture {
                return "计划中 · \(daysUntilDeparture) 天后出发"
            }
            return "计划中"
        case .ongoing:
            if let currentDayText {
                return "进行中 · \(currentDayText)"
            }
            return "进行中"
        case .completed:
            return "已结束 · \(totalDaysText)"
        case .unknown:
            return "旅程"
        }
    }

    /// One factual scene line under the title. Returns nil only if nothing useful can be said.
    static func scene(
        for trip: Trip,
        destinationName: String?,
        totalDaysText: String
    ) -> String? {
        let place = destinationName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlace = !(place?.isEmpty ?? true)
        let nodes = trip.nodeCount ?? 0
        let journals = trip.journalCount ?? 0
        let facts = contentFacts(nodes: nodes, journals: journals)

        switch trip.effectiveStatus {
        case .planning:
            if hasPlace, let place {
                return "目的地 \(place)，可先添加行程安排"
            }
            return "可补充目的地，或直接添加行程"
        case .ongoing:
            if hasPlace, let place {
                return "在 \(place)，可记录行程、日志与花费"
            }
            return "旅途进行中，可记录行程、日志与花费"
        case .completed:
            // 完成态去重：眉标已给出「已结束 · 天数」，目的地行已给出地点；
            // 场景句只保留真正增加信息的内容事实，没有事实时整行隐藏。
            return facts
        case .unknown:
            return nil
        }
    }

    /// Compact fact chips for completed trips, e.g. "3 个行程 · 2 篇日志".
    private static func contentFacts(nodes: Int, journals: Int) -> String? {
        var parts: [String] = []
        if nodes > 0 { parts.append("\(nodes) 个行程") }
        if journals > 0 { parts.append("\(journals) 篇日志") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

struct TripDetailHeader: View {
    @Environment(TracciActionSheetPresenterState.self) private var actionSheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var coverPreviewSource: TripCoverPreviewSource?

    let trip: Trip
    let routeProvider: any TripRouteProviding
    let destinationText: String
    let dateRangeText: String
    let totalDaysText: String
    let currentDayText: String?
    var pullOffset: CGFloat = 0
    let safeAreaTop: CGFloat
    var onBack: () -> Void
    var onMembers: (() -> Void)?
    var onShare: (() -> Void)?
    var onSettings: (() -> Void)?
    /// 当前用户是否能改旅程基础信息（仅 owner）
    var canUpdateTrip: Bool = true
    let members: [TripMemberResp]
    /// 阶段氛围样式：接缝色直接从此读取，避免 header 内再做二值映射。
    let atmosphereStyle: AppAtmosphereStyle

    // MARK: Hero map mode
    @Binding var heroMode: TripHeroMode
    let heroMapData: TripHeroMapData
    @Binding var focusedNodeId: String?
    @Binding var mapViewport: TripHeroMapViewport
    let autoHighlightNodeId: String?
    /// 「第 N 天」标签，用于地图态轻量 overlay。
    let dayLabel: String
    var onSelectNode: (String) -> Void = { _ in }
    var onNavigateToNode: (TripHeroMapData.HeroMapAnnotation) -> Void = { _ in }

    // MARK: Map expansion (Phase 2)
    @Binding var mapExpansion: MapExpansionSnapPoint
    @Binding var dragOffset: CGFloat

    init(
        trip: Trip,
        routeProvider: any TripRouteProviding,
        destinationText: String,
        dateRangeText: String,
        totalDaysText: String,
        safeAreaTop: CGFloat,
        onBack: @escaping () -> Void,
        heroMode: Binding<TripHeroMode>,
        heroMapData: TripHeroMapData,
        focusedNodeId: Binding<String?>,
        mapViewport: Binding<TripHeroMapViewport>,
        dayLabel: String,
        mapExpansion: Binding<MapExpansionSnapPoint>,
        dragOffset: Binding<CGFloat>,
        currentDayText: String? = nil,
        pullOffset: CGFloat = 0,
        onMembers: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onSettings: (() -> Void)? = nil,
        canUpdateTrip: Bool = true,
        members: [TripMemberResp] = [],
        atmosphereStyle: AppAtmosphereStyle = .creek,
        autoHighlightNodeId: String? = nil,
        onSelectNode: @escaping (String) -> Void = { _ in },
        onNavigateToNode: @escaping (TripHeroMapData.HeroMapAnnotation) -> Void = { _ in }
    ) {
        self.trip = trip
        self.routeProvider = routeProvider
        self.destinationText = destinationText
        self.dateRangeText = dateRangeText
        self.totalDaysText = totalDaysText
        self.currentDayText = currentDayText
        self.pullOffset = pullOffset
        self.safeAreaTop = safeAreaTop
        self.onBack = onBack
        self.onMembers = onMembers
        self.onShare = onShare
        self.onSettings = onSettings
        self.canUpdateTrip = canUpdateTrip
        self.members = members
        self.atmosphereStyle = atmosphereStyle
        self._heroMode = heroMode
        self.heroMapData = heroMapData
        self._focusedNodeId = focusedNodeId
        self._mapViewport = mapViewport
        self.autoHighlightNodeId = autoHighlightNodeId
        self.dayLabel = dayLabel
        self.onSelectNode = onSelectNode
        self.onNavigateToNode = onNavigateToNode
        self._mapExpansion = mapExpansion
        self._dragOffset = dragOffset
    }

    var body: some View {
        // Metrics band removed: trip-level counts live in 洞察 Sheet so Day Rail
        // is the first chrome after the immersive hero.
        heroRegion
            .padding(.bottom, 0)
            .fullScreenCover(item: $coverPreviewSource) { source in
                TripCoverFullScreenPreview(source: source)
            }
    }

    // MARK: - Hero Region (dual-mode: cover / map)

    private var heroRegion: some View {
        ZStack(alignment: .bottomLeading) {
            // Cover layer — browse 主路径
            coverHeroLayer
                .opacity(heroMode == .cover ? 1 : 0)
                .scaleEffect(heroMode == .cover ? 1 : 0.96)
                .allowsHitTesting(heroMode == .cover)

            // Map layer 仅在 heroMode==map 时创建，避免详情进页就 make MKMapView（Metal SIGABRT）。
            // 大地图沉浸由 TripMapExploreSurface 承载；此处 map 层在 browse 固定 cover 时不会挂载。
            if heroMode == .map {
                mapHeroLayer
                    .transition(.opacity)
            }

            // Toggle 控件：放在 ZStack 内作为 sibling（而非 .overlay），
            // 并赋予高 zIndex，确保在地图模式下能与 MKMapView 的 UIKit
            // gesture recognizer 竞争触摸事件。
            if heroMapData.isMapAvailable {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        heroMapControls
                            .padding(.trailing, TripDetailLayout.pageInset)
                            .padding(.bottom, AppSpacing.cardSmall + 4)
                    }
                }
                .zIndex(10)
            }
        }
        .animation(reduceMotion ? nil : AppMotion.contextSpring, value: heroMode)
        .overlay(alignment: .top) {
            navChrome
        }
    }

    // MARK: Cover Layer (unchanged)

    private var coverHeroLayer: some View {
        ZStack(alignment: .bottomLeading) {
            TripCoverHeroView(
                url: trip.coverHeroURL,
                fallbackURL: trip.coverHeroFallbackURL,
                heroHeight: effectiveHeroHeight,
                pullOffset: heroMode == .cover ? pullOffset : 0,
                safeAreaTop: safeAreaTop
            )
            .overlay {
                // 可读性 scrim 只覆盖到正文区，底部让位给阶段纸雾接缝。
                LinearGradient(
                    stops: [
                        .init(color: scrimColors[0], location: 0),
                        .init(color: scrimColors[1], location: 0.40),
                        .init(color: scrimColors[2], location: 0.78),
                        .init(color: scrimColors[2].opacity(0), location: 0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottom) {
                heroSeamGradient
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                editorialEyebrow
                // 阶段信息由眉标单独承担；标题行不再叠加「已结束」lock 指示，
                // 只读策略文案由 TripEditPolicy 在操作入口给出。
                Text(trip.title)
                    .font(AppTypography.tripTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .tracciShadow(AppShadow.textStrong)

                if let sceneNarrative {
                    Text(sceneNarrative)
                        .font(TripDetailTypography.heroMeta)
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .tracciShadow(AppShadow.textSoft)
                }

                if let displayedDestination {
                    Label(displayedDestination, systemImage: "mappin.and.ellipse")
                        .font(TripDetailTypography.heroMeta)
                        .foregroundStyle(.white.opacity(0.88))
                        .tracciShadow(AppShadow.textSoft)
                }

                HStack(spacing: AppSpacing.cozy) {
                    Label(dateRangeText, systemImage: "calendar")
                    Label(totalDaysText, systemImage: "clock")
                }
                .font(TripDetailTypography.caption)
                .foregroundStyle(.white.opacity(0.80))
            }
            .padding(.horizontal, TripDetailLayout.pageInset)
            .padding(.top, safeAreaTop + 58)
            // 文案整体上移，避开底部接缝渐变带，保证白字对比度。
            .padding(.bottom, heroSeamHeight + 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !trip.coverFullSizeURLs.isEmpty else { return }
            AppHaptics.lightImpact()
            coverPreviewSource = TripCoverPreviewSource(
                urls: trip.coverFullSizeURLs,
                accessibilityLabel: "\(trip.title)的旅程封面"
            )
        }
        .accessibilityHint(trip.coverFullSizeURLs.isEmpty ? "" : "轻点查看封面大图")
        .accessibilityAction(named: "查看封面大图") {
            guard !trip.coverFullSizeURLs.isEmpty else { return }
            coverPreviewSource = TripCoverPreviewSource(
                urls: trip.coverFullSizeURLs,
                accessibilityLabel: "\(trip.title)的旅程封面"
            )
        }
    }

    // MARK: Map Layer

    private var mapHeroLayer: some View {
        ZStack(alignment: .bottomLeading) {
            // MKMapView 固定为展开高度，外层只做裁剪伸缩。
            // 避免 spring/frame 动画直接缩放 CAMetalLayer，触发 SIGABRT。
            Color.clear
                .frame(height: safeAreaTop + effectiveHeroHeight)
                .overlay(alignment: .top) {
                    TripHeroMapView(
                        annotations: heroMapData.annotationNodes,
                        destinationCoordinate: heroMapData.destinationCoordinate,
                        focusedNodeId: focusedNodeId,
                        viewport: mapViewport,
                        autoHighlightNodeId: autoHighlightNodeId,
                        reduceMotion: reduceMotion,
                        tripStatus: trip.effectiveStatus,
                        routeLoader: TripHeroRouteLoader(routeProvider: routeProvider),
                        isMapVisible: heroMode == .map,
                        onSelectNode: onSelectNode,
                        onDeselect: {
                            focusedNodeId = nil
                            if case .focusedNode = mapViewport {
                                mapViewport = .userExploring
                            }
                        },
                        onUserExplore: {
                            mapViewport = .userExploring
                        }
                    )
                    .frame(height: safeAreaTop + mapModeMaxHeight)
                    // 禁止把 SwiftUI 高度动画传到 UIKit Map 视图。
                    .transaction { $0.animation = nil }
                }
                .clipped()

            // 氛围叠加：阶段色调 + 暗角（纯 SwiftUI，不拦截手势）
            mapAtmosphereOverlay
                .frame(height: safeAreaTop + effectiveHeroHeight)
                .allowsHitTesting(false)

            // 顶部 scrim 保证 nav chrome 可读
            LinearGradient(
                colors: [.black.opacity(0.30), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: safeAreaTop + 44)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            // 底部信息：选中节点时显示节点卡片，否则仅在空态时显示目的地标签
            if let selectedAnnotation {
                TripHeroNodeCard(
                    title: selectedAnnotation.title,
                    timeText: selectedAnnotation.timeText,
                    locationName: nil,
                    onNavigate: { onNavigateToNode(selectedAnnotation) }
                )
                .padding(.leading, TripDetailLayout.pageInset)
                .padding(.bottom, AppSpacing.cardSmall + 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if heroMapData.annotationNodes.isEmpty {
                // 仅在无节点时显示目的地信息（有节点时由 carousel 承载）
                mapInfoOverlay
            }

            // 无路线空态
            if heroMapData.annotationNodes.isEmpty, heroMapData.destinationCoordinate != nil {
                VStack(spacing: 8) {
                    Image(systemName: "map.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(emptyStateText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .tracciMediaChromeGlass(in: Capsule(), wash: .black.opacity(0.14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: safeAreaTop + effectiveHeroHeight)
        .clipShape(BottomRoundedShape(radius: AppRadius.extraLarge))
        .overlay(alignment: .bottom) {
            // 封面 / 地图同一过渡逻辑：媒体底部渐入阶段纸雾（替代旧黑色内阴影）。
            heroSeamGradient

            // 拖拽把手（仅地图模式）
            if heroMode == .map {
                mapExpansionHandle
                    .padding(.bottom, 6)
            }
        }
        // 高度变化由 applyMapExpansion / dragOffset 驱动；勿再挂 value:mapExpansion 动画，
        // 避免与 withAnimation 叠加。viewport 切换仍用轻量 quick。
        .animation(reduceMotion ? nil : AppMotion.quick, value: mapViewport)
    }

    // MARK: - Map Expansion Handle

    /// 地图伸缩把手：全宽热区；下拉展开 / 上推收起；点按也可切换。
    ///
    /// SwiftUI `DragGesture.translation.height`：**向下为正、向上为负**。
    /// `dragOffset` 直接存 translation，高度用 `current + dragOffset` 跟手。
    private var mapExpansionHandle: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color(.systemGray3))
                .frame(width: 40, height: 5)
        }
        // 全宽 + 足够高度，避免只能点到细条，并与 ScrollView 竖滑竞争。
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { value in
                    let raw = value.translation.height
                    let maxDrag = MapExpansionSnapPoint.expandedBonus
                    // 正=下拉放大，负=上推缩小（与 SwiftUI 坐标系一致）
                    dragOffset = min(maxDrag, max(-maxDrag, raw))
                }
                .onEnded { value in
                    let offset = value.translation.height
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    let targetSnap = resolveMapExpansionSnap(
                        offset: offset,
                        velocity: velocity,
                        current: mapExpansion
                    )
                    applyMapExpansion(targetSnap)
                }
        )
        .onTapGesture {
            applyMapExpansion(mapExpansion == .expanded ? .compact : .expanded)
        }
        .accessibilityLabel(mapExpansion == .expanded ? "收起地图" : "展开地图")
        .accessibilityHint(mapExpansion == .expanded ? "点按或上推以缩小地图" : "点按或下拉以放大地图")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            applyMapExpansion(mapExpansion == .expanded ? .compact : .expanded)
        }
    }

    /// 吸附规则：下拉放大、上推收起（translation.height：下为正、上为负）。
    private func resolveMapExpansionSnap(
        offset: CGFloat,
        velocity: CGFloat,
        current: MapExpansionSnapPoint
    ) -> MapExpansionSnapPoint {
        // predicted 增量近似速度方向
        if abs(velocity) > 220 {
            return velocity > 0 ? .expanded : .compact
        }
        switch current {
        case .compact:
            // 明显下拉（正）→ 展开
            return offset > 48 ? .expanded : .compact
        case .expanded:
            // 明显上推（负）→ 收起
            return offset < -28 ? .compact : .expanded
        }
    }

    private func applyMapExpansion(_ target: MapExpansionSnapPoint) {
        guard target != mapExpansion || dragOffset != 0 else { return }
        if target != mapExpansion {
            AppHaptics.selection()
        }
        // 用 easeInOut 而非 spring：外层裁剪动画即可，Map 尺寸保持恒定。
        withAnimation(reduceMotion ? nil : AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion)) {
            mapExpansion = target
            dragOffset = 0
        }
    }

    private var heroMapControls: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.sm) {
            if heroMode == .map,
               mapViewport != .routeOverview,
               !heroMapData.annotationNodes.isEmpty {
                // 不用 .transition：在 UIViewRepresentable 全屏覆盖的层级中，
                // transition 会让 heroMapControls 整体进入动画态，导致 hit testing
                // 不稳定（按钮无法响应点击）。用 opacity 显隐即可。
                routeOverviewButton
            }

            TripHeroModeToggle(currentMode: $heroMode)
        }
        // 使控件容器整体参与 hit-testing，防止触摸穿透到下方的 coverHeroLayer
        // 导致「点切换按钮却触发封面预览」的误触问题。
        .contentShape(Rectangle())
        // 双值动画：分别响应 mapViewport 与 heroMode 变化。
        // 注意：在 UIViewRepresentable 全屏覆盖的层级中，动画期间 hit testing
        // 可能不稳定，故此处用较短的 quick 动画，避免长时间动画态。
        .animation(reduceMotion ? nil : AppMotion.quick, value: mapViewport)
        .animation(reduceMotion ? nil : AppMotion.quick, value: heroMode)
    }

    private var routeOverviewButton: some View {
        Button {
            guard mapViewport != .routeOverview else { return }
            AppHaptics.selection()
            focusedNodeId = nil
            mapViewport = .routeOverview
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44)
                } else {
                    Label("路线总览", systemImage: "arrow.up.left.and.arrow.down.right")
                        .padding(.horizontal, 12)
                }
            }
            .font(TripDetailTypography.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(minHeight: 44)
            .tracciMediaChromeGlass(in: Capsule())
            .tracciElevation(.l1)
        }
        // 只保留显式指定的按压样式：离 Button 更近的 plain 样式会覆盖外层
        // 样式，曾使 pressableCardStyle 成为死代码（回归防护见
        // LaunchScreenAndBrandComponentsTests）。
        .contentShape(Capsule())
        .pressableCardStyle(scale: 0.96, opacity: 0.88)
        .accessibilityLabel("显示当前日期的路线总览")
        .accessibilityHint("显示全部行程节点和完整路线")
    }

    private var mapInfoOverlay: some View {
        HStack(spacing: 6) {
            if let destName = heroMapData.destinationName, !destName.isEmpty {
                Text(destName)
                    .font(.subheadline.weight(.semibold))
            }
            if !heroMapData.annotationNodes.isEmpty {
                Text("\(dayLabel) · \(heroMapData.annotationNodes.count) 站")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .tracciMediaChromeGlass(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            wash: .black.opacity(0.2)
        )
        .padding(.leading, TripDetailLayout.pageInset)
        .padding(.bottom, AppSpacing.cardSmall + 4)
    }

    /// 当前选中的 annotation（用于节点信息卡片）。
    private var selectedAnnotation: TripHeroMapData.HeroMapAnnotation? {
        guard let focusedNodeId else { return nil }
        return heroMapData.annotationNodes.first { $0.id == focusedNodeId }
    }

    // MARK: Nav Chrome

    private var navChrome: some View {
        HStack(spacing: AppSpacing.tight) {
            headerIconButton(systemImage: "chevron.left", accessibilityLabel: "返回", action: onBack)
            Spacer()

            if showsMemberShortcut {
                if let onMembers {
                    Button {
                        AppHaptics.lightImpact()
                        onMembers()
                    } label: {
                        memberAvatarStack
                    }
                    .buttonStyle(PressableCardStyle(scale: 0.97, opacity: 0.92))
                    .accessibilityLabel("\(activeMembers.count) 位旅程成员")
                    .accessibilityHint("轻点查看旅程成员")
                } else {
                    memberAvatarStack
                        .accessibilityLabel("\(activeMembers.count) 位旅程成员")
                }
            }

            headerActionsMenu
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .padding(.horizontal, TripDetailLayout.pageInset)
        .padding(.top, safeAreaTop + 10)
    }

    // MARK: - Editorial Hero Content (P0 stage narrative)

    /// 地图模式下 compact 基础高度（不含 expanded 增量）。
    private var mapModeBaseHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 320 : 370
    }

    /// 地图模式下展开态高度；MKMapView 始终按此高度布局，外层再裁剪。
    private var mapModeMaxHeight: CGFloat {
        mapModeBaseHeight + MapExpansionSnapPoint.expandedBonus
    }

    /// Grows slightly when a scene line is present so the cover still breathes.
    /// 动态 hero 高度：基础值 + 伸缩增量 - 拖拽偏移（夹在 compact…expanded 区间内）。
    private var effectiveHeroHeight: CGFloat {
        if heroMode != .map {
            if dynamicTypeSize.isAccessibilitySize { return 320 }
            return sceneNarrative == nil ? 224 : 248
        }

        let base = mapModeBaseHeight
        let expanded = mapModeMaxHeight
        let current = mapExpansion == .expanded ? expanded : base
        // dragOffset = translation.height：正=下拉=放大，负=上推=缩小。允许 ±20 橡皮筋。
        return min(expanded + 20, max(base - 20, current + dragOffset))
    }

    /// Stage / progress eyebrow only — no second status chip row.
    private var editorialEyebrow: some View {
        Text(eyebrowText)
            .font(TripDetailTypography.heroChip)
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.76))
            .tracciShadow(AppShadow.textSoft)
            .accessibilityHidden(true)
    }

    private var eyebrowText: String {
        TripDetailStageNarrative.eyebrow(
            for: trip,
            currentDayText: currentDayText,
            totalDaysText: totalDaysText,
            daysUntilDeparture: daysUntilDeparture
        )
    }

    /// Companion-style scene line derived only from local trip facts (no invented API fields).
    /// Note: only depends on `compactDestinationName` — `displayedDestination` reads this
    /// property for dedup, so this must not read back into it (cycle).
    private var sceneNarrative: String? {
        TripDetailStageNarrative.scene(
            for: trip,
            destinationName: compactDestinationName,
            totalDaysText: totalDaysText
        )
    }

    private var compactDestinationName: String? {
        guard destinationText != "未设置目的地" else { return nil }
        return Self.compactPlaceName(destinationText)
    }

    /// Show location only when it adds information beyond the trip title
    /// and the scene line (planning/ongoing scenes already embed the place).
    private var displayedDestination: String? {
        guard destinationText != "未设置目的地",
              let compactDestination = Self.compactPlaceName(destinationText)
        else { return nil }

        let normalizedDestination = Self.normalizedForComparison(compactDestination)
        guard !normalizedDestination.isEmpty else { return nil }

        let normalizedTitle = Self.normalizedForComparison(trip.title)
        if normalizedTitle.contains(normalizedDestination) { return nil }

        if let scene = sceneNarrative,
           Self.normalizedForComparison(scene).contains(normalizedDestination) {
            return nil
        }
        return compactDestination
    }

    /// Days from today until the trip starts (planning only). Nil if the date is past/unknown.
    private var daysUntilDeparture: Int? {
        guard let startDate = TripDateFormatting.date(from: trip.startDate) else { return nil }
        let today = TracciDateContext.startOfBusinessDay(for: TracciDateContext.today())
        let startDay = TracciDateContext.startOfBusinessDay(for: startDate)
        let days = TracciDateContext.calendar.dateComponents([.day], from: today, to: startDay).day ?? 0
        return days > 0 ? days : nil
    }

    private var heroAccessibilityLabel: String {
        var parts = [eyebrowText, trip.title]
        if let sceneNarrative {
            parts.append(sceneNarrative)
        }
        if let displayedDestination {
            parts.append(displayedDestination)
        }
        parts.append(dateRangeText)
        parts.append(totalDaysText)
        return parts.joined(separator: "，")
    }

    private static func compactPlaceName(_ value: String) -> String? {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return nil }

        for suffix in ["特别行政区", "自治区", "省", "市"] where result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
            break
        }
        return result.isEmpty ? nil : result
    }

    private static func normalizedForComparison(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Trip Members

    private var activeMembers: [TripMemberResp] {
        members
            .filter(\.isActive)
            .sorted { left, right in
                let leftRank = memberRoleRank(left.role)
                let rightRank = memberRoleRank(right.role)
                if leftRank != rightRank { return leftRank < rightRank }
                if left.joinedAt != right.joinedAt {
                    return (left.joinedAt ?? "") < (right.joinedAt ?? "")
                }
                return left.id < right.id
            }
    }

    private var showsMemberShortcut: Bool {
        activeMembers.count >= 2
    }

    private var memberAvatarStack: some View {
        TripMemberAvatarStack(members: activeMembers, size: 28)
            .padding(.horizontal, 7)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(reduceTransparency ? AppColors.textPrimary : Color.black.opacity(0.18))
                    .background {
                        if !reduceTransparency {
                            Capsule().fill(.ultraThinMaterial)
                        }
                    }
                    .clipShape(Capsule())
            }
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(colorSchemeContrast == .increased ? 0.62 : 0.32),
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.6
                    )
            }
            .tracciElevation(.l1)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Capsule())
    }

    private func memberRoleRank(_ role: TripMemberRole) -> Int {
        switch role {
        case .owner: 0
        case .editor: 1
        case .viewer: 2
        }
    }

    // MARK: - Empty State (P3 — 阶段感知文案)

    private var emptyStateText: String {
        switch trip.effectiveStatus {
        case .planning:  return "待规划路线"
        case .ongoing:   return "暂无行程点"
        case .completed: return "行程已结束"
        case .unknown:   return "暂无路线"
        }
    }

    // MARK: - Map Atmosphere (P0 — Creek Editorial atmosphere over MapKit)

    /// 阶段色调 + 暗角叠加层。纯 SwiftUI overlay，不拦截手势。
    private var mapAtmosphereOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // 阶段色调 — 以地图中心为视觉焦点
                RadialGradient(
                    colors: [stageTintColor, .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.62
                )
                .opacity(stageTintOpacity)

                // 暗角 — 顶部和底部淡入，制造"取景框"感
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.06), .clear],
                        startPoint: .top, endPoint: .center
                    )
                    .frame(height: geo.size.height * 0.35)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.04)],
                        startPoint: .center, endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.25)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var stageTintColor: Color {
        switch trip.effectiveStatus {
        case .planning:  return AppColors.brandPrimary.opacity(0.045)
        case .ongoing:   return AppColors.brandPrimary.opacity(0.065)
        case .completed: return AppColors.dawnGold.opacity(0.05)
        case .unknown:   return AppColors.brandPrimary.opacity(0.04)
        }
    }

    private var stageTintOpacity: Double {
        switch trip.effectiveStatus {
        case .planning:  return 0.85
        case .ongoing:   return 1.0
        case .completed: return 0.9
        case .unknown:   return 0.8
        }
    }

    /// Stage-aware cover scrim — completed trips read as warm memory, not cold info.
    private var scrimColors: [Color] {
        if trip.effectiveStatus == .completed {
            let warmInk = AppColors.scrimWarmInk
            return [
                warmInk.opacity(0.10),
                warmInk.opacity(0.20),
                warmInk.opacity(0.55)
            ]
        }
        return [
            .black.opacity(0.08),
            .black.opacity(0.16),
            .black.opacity(0.52)
        ]
    }

    // MARK: - Hero Seam (N3 — 媒体 scrim → 阶段纸雾的连续过渡)

    /// 接缝色直接取自传入的阶段氛围样式，与 `TripDetailView.stageAtmosphere` 一一对应。
    private var heroSeamColor: Color { atmosphereStyle.heroSeamColor }

    /// 接缝渐变带高度：随 hero 高度轻微伸缩，下拉放大时一并延展。
    private var heroSeamHeight: CGFloat {
        max(24, effectiveHeroHeight * 0.11)
    }

    /// 封面 / 地图共用的底部接缝：透明渐变到阶段纸雾，
    /// 让「沉浸媒体 → 查看范围」读起来是同一张连续纸面。
    private var heroSeamGradient: some View {
        LinearGradient(
            colors: [heroSeamColor.opacity(0), heroSeamColor],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: heroSeamHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var headerActionsMenu: some View {
        if !headerActions.isEmpty {
            Button {
                AppHaptics.lightImpact()
                actionSheet.present(
                    title: "旅程操作",
                    subtitle: trip.title,
                    actions: headerActions
                )
            } label: {
                headerChromeIcon(systemImage: "ellipsis")
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .pressableCardStyle(scale: 0.92, opacity: 0.85)
        }
    }

    private var headerActions: [TracciActionItem] {
        var actions: [TracciActionItem] = []
        if let onShare {
            actions.append(
                TracciActionItem(title: "分享旅程", systemImage: "square.and.arrow.up", action: onShare)
            )
        }
        if let onSettings, canUpdateTrip {
            actions.append(
                TracciActionItem(title: "编辑旅程", systemImage: "pencil", action: onSettings)
            )
        }
        return actions
    }

    private func headerIconButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            headerChromeIcon(systemImage: systemImage)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Circle())
        .pressableCardStyle(scale: 0.92, opacity: 0.85)
        .accessibilityLabel(accessibilityLabel)
    }

    private func headerChromeIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(TripDetailTypography.chromeIcon)
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .tracciMediaChromeGlass(in: Circle())
            .tracciElevation(.l1)
    }
}

// MARK: - Bottom-Rounded Shape (P0 — 仅底部圆角，上边缘全出血)

/// 仅底部两个角圆角化的 shape。用于 Hero 地图容器：上边缘延伸到 safe area 保持全出血，
/// 下边缘与工作台形成柔和过渡。
private struct BottomRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addArc(
            center: CGPoint(x: rect.width - radius, y: rect.height - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addArc(
            center: CGPoint(x: radius, y: rect.height - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#if DEBUG
@MainActor
private enum TripDetailHeaderPreviewSupport {
    static func trip(
        status: TripStatus,
        title: String,
        destination: String
    ) -> Trip {
        let offsets: (start: Int, end: Int) = switch status {
        case .planning: (10, 14)
        case .ongoing: (-1, 3)
        case .completed: (-10, -6)
        case .unknown: (0, 2)
        }
        return Trip(
            id: "trip-detail-header-\(status)",
            title: title,
            startDate: dateString(offset: offsets.start),
            endDate: dateString(offset: offsets.end),
            status: status,
            totalDays: 5,
            destination: TripDestination(name: destination),
            totalCny: "3280",
            nodeCount: 12,
            journalCount: 4
        )
    }

    static func dateRangeText(for trip: Trip) -> String {
        let start = TripDateFormatting.date(from: trip.startDate).map(displayFormatter.string(from:)) ?? trip.startDate
        let end = TripDateFormatting.date(from: trip.endDate).map(displayFormatter.string(from:)) ?? trip.endDate
        return "\(start) - \(end)"
    }

    private static func dateString(offset: Int) -> String {
        let date = TracciDateContext.calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}

private struct TripDetailHeaderPreview: View {
    let trip: Trip
    let currentDayText: String?
    @State private var heroMode: TripHeroMode = .cover
    @State private var mapViewport: TripHeroMapViewport = .routeOverview

    var body: some View {
        TripDetailHeader(
            trip: trip,
            routeProvider: RouteCacheService(),
            destinationText: trip.destinationName ?? "未设置目的地",
            dateRangeText: TripDetailHeaderPreviewSupport.dateRangeText(for: trip),
            totalDaysText: "5 天",
            safeAreaTop: 54,
            onBack: {},
            heroMode: $heroMode,
            heroMapData: TripHeroMapData.empty,
            focusedNodeId: .constant(nil),
            mapViewport: $mapViewport,
            dayLabel: "第 1 天",
            mapExpansion: .constant(.compact),
            dragOffset: .constant(0),
            currentDayText: currentDayText,
            onShare: {},
            onSettings: {},
            members: [],
            atmosphereStyle: previewAtmosphereStyle,
            autoHighlightNodeId: nil
        )
        .environment(TracciActionSheetPresenterState())
        .ignoresSafeArea(edges: .top)
    }

    /// 与 TripDetailView.stageAtmosphere 同构：Preview 中接缝色随阶段变化。
    private var previewAtmosphereStyle: AppAtmosphereStyle {
        switch trip.effectiveStatus {
        case .planning: return .creek
        case .ongoing: return .creekOngoing
        case .completed: return .creekCompleted
        case .unknown: return .creek
        }
    }
}

#Preview("详情 Header · 规划中") {
    TripDetailHeaderPreview(
        trip: TripDetailHeaderPreviewSupport.trip(
            status: .planning,
            title: "国庆之旅",
            destination: "京都市"
        ),
        currentDayText: nil
    )
}

#Preview("详情 Header · 进行中去重") {
    TripDetailHeaderPreview(
        trip: TripDetailHeaderPreviewSupport.trip(
            status: .ongoing,
            title: "北京五日",
            destination: "北京市"
        ),
        currentDayText: "第 2 / 5 天"
    )
}

#Preview("详情 Header · 已完成") {
    TripDetailHeaderPreview(
        trip: TripDetailHeaderPreviewSupport.trip(
            status: .completed,
            title: "江南雨季",
            destination: "杭州市"
        ),
        currentDayText: nil
    )
}
#endif
