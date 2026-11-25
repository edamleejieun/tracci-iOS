import MapKit
import SwiftUI

/// Hero 区全幅地图，适配自 TripDayMapView。
/// 支持 pan/pinch 浏览；竖向拖动由 MapKit 内部手势优先处理。
struct TripHeroMapView: UIViewRepresentable {
    let annotations: [TripHeroMapData.HeroMapAnnotation]
    let destinationCoordinate: CLLocationCoordinate2D?
    let focusedNodeId: String?
    let viewport: TripHeroMapViewport
    let autoHighlightNodeId: String?
    let reduceMotion: Bool
    let tripStatus: TripStatus
    let routeLoader: TripHeroRouteLoader
    /// 地图是否可见（封面模式下为 false）。用于管理动画生命周期，避免不可见时主线程空转。
    let isMapVisible: Bool
    /// 转场期间关闭镜头动画，避免与 Surface 展开/收起抢主线程。
    var suppressCameraAnimation: Bool = false
    /// 全旅程总览模式（显式）：按天分色绘制每日路线段，不做已走/未走分段，
    /// 也不把各天连成一条线（不虚构跨天移动）。
    var isFullTripOverview: Bool = false
    /// 全旅程总览的按天路线段；可能为空（每天 ≤1 个坐标节点时）。
    var daySegments: [TripHeroMapData.DayRouteSegment] = []
    /// 全旅程总览的总天数：色板阶梯与 marker 着色按真实天数定位。
    var fullTripDayCount: Int = 0
    let onSelectNode: (String) -> Void
    let onDeselect: () -> Void
    let onUserExplore: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.isScrollEnabled = true
        mapView.showsCompass = false
        // 避免瓦片未到时露出系统浅灰底（状态栏下尤其明显）。
        mapView.backgroundColor = .clear
        mapView.isOpaque = false
        if #available(iOS 17.0, *) {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = configuration
        }

        // 点击空白处取消选中节点
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)
        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // 封面模式下地图逻辑不可见：仅同步可见性标记，不触发 annotation/overlay
        // 变更，避免在 CAMetalLayer drawable 可能已被释放时操作 MKMapView。
        context.coordinator.isMapVisible = isMapVisible
        guard isMapVisible else {
            context.coordinator.highlightNodeId = focusedNodeId ?? autoHighlightNodeId
            context.coordinator.reduceMotion = reduceMotion
            context.coordinator.tripStatus = tripStatus
            return
        }

        let mapAnnotations = makeAnnotations()

        let isFullTrip = isFullTripOverview
        // 绘制键覆盖所有会改变 annotation / overlay / 镜头的输入。
        // 全程 marker 降级后 annotations 只保留每天起点，因此路线段必须使用完整坐标，
        // 不能只取前几个点做摘要，否则后段节点改位不会触发重建。
        let renderContentKey = Self.makeRenderContentKey(
            annotations: annotations,
            destinationCoordinate: destinationCoordinate,
            daySegments: daySegments,
            isFullTripOverview: isFullTrip,
            fullTripDayCount: fullTripDayCount,
            tripStatus: tripStatus
        )
        let renderContentChanged = renderContentKey != context.coordinator.lastRenderContentKey
        let viewportChanged = viewport != context.coordinator.lastViewport
        let highlightId = focusedNodeId ?? autoHighlightNodeId

        // P1 修复：路线进度应基于执行状态（autoHighlightNodeId = 最后完成节点），
        // 而非用户临时选中。focusedNodeId 仅代表地图/时间线当前选中，不代表完成进度。
        // 全旅程总览不做已走/未走分段（那是单日语义）。
        let passedNodeId = isFullTrip ? nil : autoHighlightNodeId
        let passedKey = passedNodeId ?? "__none__"
        let passedChanged = passedKey != context.coordinator.lastPassedKey

        if renderContentChanged || passedChanged {
            // 重建前先取消任何在途路线任务：本次重建若不再产生新路线
            // （如切到只有 1 个节点的日期），旧任务也不得补画过期 overlay。
            context.coordinator.routeTask?.cancel()
            context.coordinator.routeTask = nil
            context.coordinator.lastRenderContentKey = renderContentKey
            context.coordinator.lastPassedKey = passedKey
            context.coordinator.lastFocusedNodeId = nil
            context.coordinator.lastStyledHighlightNodeId = highlightId

            let previous = mapView.annotations.compactMap { $0 as? DayMapAnnotation }
            mapView.removeAnnotations(previous)
            mapView.removeOverlays(mapView.overlays)

            // P3：无节点但有目的地时，添加目的地锚点
            if mapAnnotations.isEmpty, let destAnnotation = makeDestinationAnnotation() {
                mapView.addAnnotation(destAnnotation)
            } else {
                mapView.addAnnotations(mapAnnotations)
            }

            let coordinates = mapAnnotations.map(\.coordinate)
            if isFullTrip {
                // 全旅程总览：按天分色的直线段；各天之间不连线。
                for segment in daySegments where segment.coordinates.count > 1 {
                    addDayRouteOverlays(to: mapView, segment: segment, dayCount: overviewDayCount)
                }

                // 段数较少时才逐段请求真实道路路径，控制 MKDirections 成本；
                // 超出阈值全程直线占位（视觉上仍是清晰的每日轨迹）。
                let totalSegments = daySegments.reduce(0) { $0 + max(0, $1.coordinates.count - 1) }
                if totalSegments > 0, totalSegments <= TripHeroMapData.fullTripRealRouteMaxSegments {
                    context.coordinator.routeTask = Task { @MainActor in
                        await routeLoader.loadFullTripRoutes(
                            daySegments: daySegments,
                            onRouteLoaded: { loadedRoute in
                                guard !Task.isCancelled else { return }
                                Self.applyFullTripRealRoute(
                                    mapView: mapView,
                                    loadedRoute: loadedRoute,
                                    dayCount: overviewDayCount
                                )
                            }
                        )
                    }
                }
            } else if coordinates.count > 1 {
                // P1：仅进行中旅程区分已走/未走路线，基于执行状态而非选中态
                let passedIndex: Int? = (tripStatus == .ongoing && passedNodeId != nil)
                    ? mapAnnotations.firstIndex(where: { $0.nodeId == passedNodeId })
                    : nil

                // 先添加直线占位（保持即时视觉反馈）
                if let passedIndex {
                    addSegmentedRouteOverlays(
                        to: mapView,
                        coordinates: coordinates,
                        passedIndex: passedIndex
                    )
                } else {
                    addRouteOverlays(to: mapView, coordinates: coordinates)
                }

                // 异步加载真实路径，完成后替换直线占位
                context.coordinator.routeTask = Task { @MainActor in
                        guard let loadedRoute = await routeLoader.loadRoute(
                            coordinates: coordinates,
                            passedIndex: passedIndex
                        ) else { return }
                        guard !Task.isCancelled else { return }
                        Self.applyRealRoute(
                            mapView: mapView,
                            loadedRoute: loadedRoute
                        )
                }
            }
        }

        context.coordinator.highlightNodeId = highlightId
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.tripStatus = tripStatus
        context.coordinator.isMapVisible = isMapVisible
        context.coordinator.isFullTripOverview = isFullTrip
        context.coordinator.applyMarkerStyles(on: mapView)
        context.coordinator.updateAnimationLifecycle(for: mapView)

        if viewportChanged || renderContentChanged {
            let hadPreviousViewport = context.coordinator.lastViewport != nil
            context.coordinator.lastViewport = viewport
            let cameraAnimated = !reduceMotion && !suppressCameraAnimation && hadPreviousViewport

            switch viewport {
            case .routeOverview:
                // Day / scope / 路线内容切换会触发重建：仍允许短镜头动画，与 Tab 节奏对齐。
                fitRegion(
                    on: mapView,
                    annotations: mapAnnotations,
                    animated: cameraAnimated
                )
            case .focusedNode(let nodeId):
                // 节点不在当前 Day（切 Day 竞态 / 列表刷新）时回退总览，避免落到错误地址。
                if mapAnnotations.contains(where: { $0.nodeId == nodeId }) {
                    context.coordinator.lastFocusedNodeId = nodeId
                    zoomToNode(
                        nodeId,
                        on: mapView,
                        annotations: mapAnnotations,
                        animated: cameraAnimated
                    )
                } else {
                    context.coordinator.lastFocusedNodeId = nil
                    fitRegion(
                        on: mapView,
                        annotations: mapAnnotations,
                        animated: cameraAnimated
                    )
                }
            case .userExploring:
                break
            }
        }
    }

    /// 构造地图绘制内容键。保持为纯函数，便于覆盖全程降级、scope 切换等回归场景。
    static func makeRenderContentKey(
        annotations: [TripHeroMapData.HeroMapAnnotation],
        destinationCoordinate: CLLocationCoordinate2D?,
        daySegments: [TripHeroMapData.DayRouteSegment],
        isFullTripOverview: Bool,
        fullTripDayCount: Int,
        tripStatus: TripStatus
    ) -> String {
        let annotationKey = annotations.map { item in
            [
                item.id,
                "\(item.coordinate.latitude),\(item.coordinate.longitude)",
                item.title,
                item.timeText ?? "",
                "\(item.index)",
                "\(item.dayIndex)"
            ].joined(separator: ":")
        }.joined(separator: "|")

        let destinationKey = destinationCoordinate.map {
            "\($0.latitude),\($0.longitude)"
        } ?? "none"

        let segmentKey = daySegments.map { segment in
            let coordinates = segment.coordinates.map {
                "\($0.latitude),\($0.longitude)"
            }.joined(separator: ";")
            return "\(segment.dayIndex):\(coordinates)"
        }.joined(separator: "|")

        return [
            isFullTripOverview ? "fullTrip" : "day",
            "days=\(fullTripDayCount)",
            "status=\(tripStatus.rawValue)",
            "destination=\(destinationKey)",
            "annotations=\(annotationKey)",
            "segments=\(segmentKey)"
        ].joined(separator: "#")
    }

    // MARK: - Private

    private func makeAnnotations() -> [DayMapAnnotation] {
        let dayCount = overviewDayCount
        return annotations.map { item in
            DayMapAnnotation(
                nodeId: item.id,
                sequence: item.index,
                coordinate: item.coordinate,
                subtitle: item.title,
                timeText: item.timeText,
                dayIndex: item.dayIndex,
                dayCount: dayCount
            )
        }
    }

    /// 全旅程总览的总天数：优先使用数据侧显式传入的真实天数，
    /// 保证色板阶梯不被「某天无节点」压缩；兜底取 annotations 与
    /// daySegments 的最大 dayIndex（节点降级后依然成立）。
    private var overviewDayCount: Int {
        if fullTripDayCount > 0 {
            return fullTripDayCount
        }
        return max(
            annotations.map(\.dayIndex).max() ?? 0,
            daySegments.map(\.dayIndex).max() ?? 0
        )
    }

    /// P3：无节点但有目的地时，生成一个特殊的目的地锚点 annotation。
    private func makeDestinationAnnotation() -> DayMapAnnotation? {
        guard annotations.isEmpty, let dest = destinationCoordinate else { return nil }
        return DayMapAnnotation(
            nodeId: "__destination__",
            sequence: 0,
            coordinate: dest,
            subtitle: nil
        )
    }

    private func addRouteOverlays(to mapView: MKMapView, coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count > 1 else { return }
        let halo = MKPolyline(coordinates: coordinates, count: coordinates.count)
        halo.title = TripDayRouteLayer.halo.rawValue
        let glow = MKPolyline(coordinates: coordinates, count: coordinates.count)
        glow.title = TripDayRouteLayer.glow.rawValue
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        line.title = TripDayRouteLayer.line.rawValue
        let core = MKPolyline(coordinates: coordinates, count: coordinates.count)
        core.title = TripDayRouteLayer.core.rawValue
        mapView.addOverlays([halo, glow, line, core], level: .aboveRoads)
    }

    /// P1：路线分段 — 已走过（高亮实线）vs 未走过（低调暗线）。
    /// 仅在进行中旅程时调用。passedIndex 为最后一个"已走过"的节点 index。
    private func addSegmentedRouteOverlays(
        to mapView: MKMapView,
        coordinates: [CLLocationCoordinate2D],
        passedIndex: Int
    ) {
        guard coordinates.count > 1 else { return }

        // 已走过段 [0...passedIndex]
        if passedIndex > 0 {
            let passedCoords = Array(coordinates[0...passedIndex])
            addRouteSegment(to: mapView, coordinates: passedCoords, isPassed: true)
        }

        // 未走过段 [passedIndex...]
        if passedIndex < coordinates.count - 1 {
            let upcomingCoords = Array(coordinates[max(passedIndex, 0)...])
            addRouteSegment(to: mapView, coordinates: upcomingCoords, isPassed: false)
        }
    }

    private func addRouteSegment(
        to mapView: MKMapView,
        coordinates: [CLLocationCoordinate2D],
        isPassed: Bool
    ) {
        guard coordinates.count > 1 else { return }
        let suffix = isPassed ? "" : ".upcoming"

        let halo = MKPolyline(coordinates: coordinates, count: coordinates.count)
        halo.title = TripDayRouteLayer.halo.rawValue + suffix
        let glow = MKPolyline(coordinates: coordinates, count: coordinates.count)
        glow.title = TripDayRouteLayer.glow.rawValue + suffix
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        line.title = TripDayRouteLayer.line.rawValue + suffix
        let core = MKPolyline(coordinates: coordinates, count: coordinates.count)
        core.title = TripDayRouteLayer.core.rawValue + suffix
        mapView.addOverlays([halo, glow, line, core], level: .aboveRoads)
    }

    // MARK: - Full-Trip Overview Overlays

    /// 全旅程总览：为某一天的路线段添加 4 层品牌 overlay（按天着色）。
    private func addDayRouteOverlays(
        to mapView: MKMapView,
        segment: TripHeroMapData.DayRouteSegment,
        dayCount: Int
    ) {
        guard segment.coordinates.count > 1 else { return }
        let halo = DayRoutePolylineMetadata.makePolyline(
            coordinates: segment.coordinates,
            dayIndex: segment.dayIndex,
            dayCount: dayCount,
            layer: .halo
        )
        let glow = DayRoutePolylineMetadata.makePolyline(
            coordinates: segment.coordinates,
            dayIndex: segment.dayIndex,
            dayCount: dayCount,
            layer: .glow
        )
        let line = DayRoutePolylineMetadata.makePolyline(
            coordinates: segment.coordinates,
            dayIndex: segment.dayIndex,
            dayCount: dayCount,
            layer: .line
        )
        let core = DayRoutePolylineMetadata.makePolyline(
            coordinates: segment.coordinates,
            dayIndex: segment.dayIndex,
            dayCount: dayCount,
            layer: .core
        )
        mapView.addOverlays([halo, glow, line, core], level: .aboveRoads)
    }

    // MARK: - Real Route Loading

    /// 用已加载的真实道路坐标替换直线占位 overlay。
    private static func applyRealRoute(
        mapView: MKMapView,
        loadedRoute: TripHeroLoadedRoute
    ) {
        // 移除占位 overlay
        mapView.removeOverlays(mapView.overlays)

        if loadedRoute.passedCoordinates.count > 1 {
            addRealRouteOverlays(
                to: mapView,
                coordinates: loadedRoute.passedCoordinates,
                isPassed: true
            )
        }
        if loadedRoute.upcomingCoordinates.count > 1 {
            addRealRouteOverlays(
                to: mapView,
                coordinates: loadedRoute.upcomingCoordinates,
                isPassed: false
            )
        }
    }

    /// 用真实路径坐标构建 4 层品牌 overlay。
    private static func addRealRouteOverlays(
        to mapView: MKMapView,
        coordinates: [CLLocationCoordinate2D],
        isPassed: Bool
    ) {
        guard coordinates.count > 1 else { return }
        let suffix = isPassed ? "" : ".upcoming"

        let halo = MKPolyline(coordinates: coordinates, count: coordinates.count)
        halo.title = TripDayRouteLayer.halo.rawValue + suffix
        let glow = MKPolyline(coordinates: coordinates, count: coordinates.count)
        glow.title = TripDayRouteLayer.glow.rawValue + suffix
        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        line.title = TripDayRouteLayer.line.rawValue + suffix
        let core = MKPolyline(coordinates: coordinates, count: coordinates.count)
        core.title = TripDayRouteLayer.core.rawValue + suffix
        mapView.addOverlays([halo, glow, line, core], level: .aboveRoads)
    }

    /// 全旅程总览：用 loader 返回的按天路线替换对应直线 overlay。
    private static func applyFullTripRealRoute(
        mapView: MKMapView,
        loadedRoute: TripHeroLoadedDayRoute,
        dayCount: Int
    ) {
        let resolvedDayCount = max(dayCount, 1)

        let stale = mapView.overlays.filter { overlay in
            guard let polyline = overlay as? MKPolyline,
                  let metadata = DayRoutePolylineMetadata(title: polyline.title)
            else { return false }
            return metadata.dayIndex == loadedRoute.dayIndex
        }
        mapView.removeOverlays(stale)

        let halo = DayRoutePolylineMetadata.makePolyline(
            coordinates: loadedRoute.coordinates,
            dayIndex: loadedRoute.dayIndex,
            dayCount: resolvedDayCount,
            layer: .halo
        )
        let glow = DayRoutePolylineMetadata.makePolyline(
            coordinates: loadedRoute.coordinates,
            dayIndex: loadedRoute.dayIndex,
            dayCount: resolvedDayCount,
            layer: .glow
        )
        let line = DayRoutePolylineMetadata.makePolyline(
            coordinates: loadedRoute.coordinates,
            dayIndex: loadedRoute.dayIndex,
            dayCount: resolvedDayCount,
            layer: .line
        )
        let core = DayRoutePolylineMetadata.makePolyline(
            coordinates: loadedRoute.coordinates,
            dayIndex: loadedRoute.dayIndex,
            dayCount: resolvedDayCount,
            layer: .core
        )
        mapView.addOverlays([halo, glow, line, core], level: .aboveRoads)
    }

    private func fitRegion(
        on mapView: MKMapView,
        annotations: [DayMapAnnotation],
        animated: Bool
    ) {
        // 全旅程总览：以完整路线坐标拟合（节点可能已降级为每天起点）。
        var coordinates = annotations.map(\.coordinate)
        if !daySegments.isEmpty {
            let segmentCoordinates = daySegments.flatMap(\.coordinates)
            if !segmentCoordinates.isEmpty {
                coordinates = segmentCoordinates
            }
        }

        if coordinates.isEmpty {
            // 无节点路线 → 以目的地为中心
            if let dest = destinationCoordinate {
                let region = MKCoordinateRegion(
                    center: dest,
                    latitudinalMeters: 3000,
                    longitudinalMeters: 3000
                )
                mapView.setRegion(region, animated: animated)
            }
            return
        }

        if coordinates.count == 1, let coordinate = coordinates.first {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1400,
                longitudinalMeters: 1400
            )
            mapView.setRegion(region, animated: animated)
        } else {
            let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
                let point = MKMapPoint(coordinate)
                return partial.union(MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1))
            }
            let padding = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
        }
    }

    private func zoomToNode(
        _ nodeId: String,
        on mapView: MKMapView,
        annotations: [DayMapAnnotation],
        animated: Bool
    ) {
        guard let annotation = annotations.first(where: { $0.nodeId == nodeId }) else { return }
        let point = MKMapPoint(annotation.coordinate)
        let rect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
        let padding = UIEdgeInsets(top: 44, left: 44, bottom: 44, right: 44)
        mapView.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectNode: onSelectNode,
            onDeselect: onDeselect,
            onUserExplore: onUserExplore
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let onSelectNode: (String) -> Void
        let onDeselect: () -> Void
        let onUserExplore: () -> Void
        var lastRenderContentKey = ""
        var lastPassedKey = "__none__"
        var lastFocusedNodeId: String?
        var lastViewport: TripHeroMapViewport?
        var highlightNodeId: String?
        var reduceMotion = false
        var lastStyledHighlightNodeId: String?
        var tripStatus: TripStatus = .planning
        var isMapVisible = true
        /// 全旅程总览模式：关闭呼吸光（进度光晕是单日语义），marker 按天着色。
        var isFullTripOverview = false
        weak var mapView: MKMapView?

        /// 当前真实路径加载任务（切换 Day 时 cancel 旧任务）。
        var routeTask: Task<Void, Never>?

        // P1：呼吸光动画状态
        private var glowAnimationTimer: Timer?
        private var glowAnimationPhase: CGFloat = 0

        init(
            onSelectNode: @escaping (String) -> Void,
            onDeselect: @escaping () -> Void,
            onUserExplore: @escaping () -> Void
        ) {
            self.onSelectNode = onSelectNode
            self.onDeselect = onDeselect
            self.onUserExplore = onUserExplore
        }

        deinit {
            routeTask?.cancel()
            glowAnimationTimer?.invalidate()
        }

        /// P1：统一管理动画生命周期 — 仅在进行中旅程 + 非 reduceMotion + 地图可见时运行。
        /// 全旅程总览不跑呼吸光：进度光晕属于单日路线语义。
        func updateAnimationLifecycle(for mapView: MKMapView) {
            let shouldGlow = tripStatus == .ongoing && !reduceMotion && isMapVisible && !isFullTripOverview
            if shouldGlow {
                startGlowAnimationIfNeeded(for: mapView)
            } else {
                stopGlowAnimation()
            }
        }

        /// 全旅程总览：按天着色 marker；单日模式返回 nil 保持品牌主色。
        private func dayTint(for annotation: DayMapAnnotation) -> UIColor? {
            guard annotation.dayIndex > 0, annotation.dayCount > 1 else { return nil }
            return TripHeroDayPalette.uiColor(
                dayIndex: annotation.dayIndex,
                dayCount: annotation.dayCount
            )
        }

        /// P1：启动 glow 呼吸动画（围绕实色主线的轻底晕，幅度克制）
        private func startGlowAnimationIfNeeded(for mapView: MKMapView) {
            guard glowAnimationTimer == nil else { return }
            glowAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.glowAnimationPhase += 0.018
                // 基准贴近 renderer 的 glow 层（~0.22），轻微起伏，避免冲淡主线实色感
                let opacity = 0.18 + 0.08 * (0.5 + 0.5 * sin(self.glowAnimationPhase))
                self.updateGlowOpacity(CGFloat(opacity), on: mapView)
            }
        }

        func stopGlowAnimation() {
            glowAnimationTimer?.invalidate()
            glowAnimationTimer = nil
        }

        private func updateGlowOpacity(_ opacity: CGFloat, on mapView: MKMapView) {
            for overlay in mapView.overlays {
                guard let polyline = overlay as? MKPolyline,
                      let title = polyline.title,
                      (title == TripDayRouteLayer.glow.rawValue || title.hasSuffix(".glow"))
                else { continue }
                if let renderer = mapView.renderer(for: polyline) as? MKPolylineRenderer {
                    renderer.strokeColor = UIColor(AppColors.brandPrimary).withAlphaComponent(opacity)
                    renderer.setNeedsDisplay()
                }
            }
        }

        /// P1 修复：同时处理自定义 TripHeroAnnotationView 和兜底 MKMarkerAnnotationView。
        /// 当 highlightNodeId 变化时，遍历所有可见 annotation view 重新 configure，
        /// 确保编号点高亮、时间标签、动画跟随焦点变化。
        func applyMarkerStyles(on mapView: MKMapView) {
            let isNewHighlight = highlightNodeId != lastStyledHighlightNodeId
            for annotation in mapView.annotations {
                guard let dayAnnotation = annotation as? DayMapAnnotation else { continue }
                let isHighlighted = dayAnnotation.nodeId == highlightNodeId

                if let customView = mapView.view(for: dayAnnotation) as? TripHeroAnnotationView {
                    customView.configure(
                        sequence: dayAnnotation.sequence,
                        timeText: dayAnnotation.timeText,
                        isHighlighted: isHighlighted,
                        reduceMotion: reduceMotion,
                        dayTint: dayTint(for: dayAnnotation)
                    )
                    if isNewHighlight, isHighlighted, !reduceMotion {
                        customView.animateSelection()
                    }
                } else if let markerView = mapView.view(for: dayAnnotation) as? MKMarkerAnnotationView {
                    styleMarkerView(markerView, annotation: dayAnnotation, animateBounce: isNewHighlight && isHighlighted)
                }
            }
            lastStyledHighlightNodeId = highlightNodeId
        }

        private func styleMarkerView(
            _ view: MKMarkerAnnotationView,
            annotation: DayMapAnnotation,
            animateBounce: Bool
        ) {
            let isHighlighted = annotation.nodeId == highlightNodeId
            let brand = dayTint(for: annotation) ?? UIColor(AppColors.brandPrimary)
            // 与竞品一致：未选中也用实色编号点，靠缩放区分焦点
            view.markerTintColor = brand
            view.glyphText = "\(annotation.sequence)"
            view.glyphTintColor = .white
            view.displayPriority = isHighlighted ? .required : .defaultHigh

            if animateBounce, isHighlighted, !reduceMotion {
                bounceMarker(view)
            } else {
                view.transform = .identity
            }
        }

        private func bounceMarker(_ view: MKMarkerAnnotationView) {
            view.layer.removeAllAnimations()
            view.transform = .identity
            UIView.animate(
                withDuration: AppMotion.mapMarkerBounceDuration,
                delay: 0,
                usingSpringWithDamping: AppMotion.mapMarkerBounceDamping,
                initialSpringVelocity: 0.5,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    view.transform = CGAffineTransform(
                        scaleX: AppMotion.mapMarkerSelectedScale,
                        y: AppMotion.mapMarkerSelectedScale
                    )
                },
                completion: { _ in
                    UIView.animate(
                        withDuration: AppMotion.mapMarkerSettleDuration,
                        delay: 0,
                        options: [.curveEaseInOut, .allowUserInteraction],
                        animations: { view.transform = .identity }
                    )
                }
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            if let metadata = DayRoutePolylineMetadata(title: polyline.title) {
                return renderer(for: polyline, metadata: metadata)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round

            let brand = UIColor(AppColors.brandPrimary)
            let rawTitle = polyline.title ?? ""
            let isUpcoming = rawTitle.hasSuffix(".upcoming")
            // 提取基础 layer 名称（去掉 .upcoming 后缀）
            let baseTitle = isUpcoming
                ? String(rawTitle.dropLast(".upcoming".count))
                : rawTitle

            // 浅色标准底图 + 实色主线（对齐 itinerary 竞品可读性；不做暗蒙）。
            // 结构：轻底晕 → 软边 → 近不透明主线 → 略密芯线，权重集中在 line。
            switch TripDayRouteLayer(rawValue: baseTitle) {
            case .halo:
                renderer.strokeColor = isUpcoming
                    ? brand.withAlphaComponent(0.06)
                    : brand.withAlphaComponent(0.12)
                renderer.lineWidth = 10
            case .glow:
                renderer.strokeColor = isUpcoming
                    ? brand.withAlphaComponent(0.12)
                    : brand.withAlphaComponent(0.22)
                renderer.lineWidth = 6.5
            case .line:
                renderer.strokeColor = isUpcoming
                    ? brand.withAlphaComponent(0.52)
                    : brand.withAlphaComponent(0.95)
                renderer.lineWidth = 4.0
            case .core:
                // 浅底上不用白芯（会发灰）；用同色略密芯增强实体感
                renderer.strokeColor = isUpcoming
                    ? brand.withAlphaComponent(0.70)
                    : brand.withAlphaComponent(1.0)
                renderer.lineWidth = 2.2
            case .none:
                renderer.strokeColor = brand.withAlphaComponent(0.85)
                renderer.lineWidth = 3.5
            }
            return renderer
        }

        /// 全旅程总览的按天路线渲染：与单日路线同构（4 层），颜色取自当日色板。
        private func renderer(
            for polyline: MKPolyline,
            metadata: DayRoutePolylineMetadata
        ) -> MKPolylineRenderer {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round

            let base = TripHeroDayPalette.uiColor(
                dayIndex: metadata.dayIndex,
                dayCount: metadata.dayCount
            )
            switch metadata.layer {
            case .halo:
                renderer.strokeColor = base.withAlphaComponent(0.10)
                renderer.lineWidth = 9
            case .glow:
                renderer.strokeColor = base.withAlphaComponent(0.20)
                renderer.lineWidth = 6
            case .line:
                renderer.strokeColor = base.withAlphaComponent(0.88)
                renderer.lineWidth = 3.6
            case .core:
                renderer.strokeColor = base
                renderer.lineWidth = 2.0
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let dayAnnotation = annotation as? DayMapAnnotation else { return nil }

            // P3：目的地锚点（无节点时）
            if dayAnnotation.nodeId == "__destination__" {
                let identifier = DestinationAnchorView.reuseID
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? DestinationAnchorView
                    ?? DestinationAnchorView(annotation: dayAnnotation, reuseIdentifier: identifier)
                view.annotation = dayAnnotation
                view.canShowCallout = false
                view.configure(reduceMotion: reduceMotion)
                return view
            }

            // P2：使用自定义品牌风格 Marker
            let identifier = TripHeroAnnotationView.reuseID
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? TripHeroAnnotationView
                ?? TripHeroAnnotationView(annotation: dayAnnotation, reuseIdentifier: identifier)
            view.annotation = dayAnnotation
            view.canShowCallout = false

            let isHighlighted = dayAnnotation.nodeId == highlightNodeId
            view.configure(
                sequence: dayAnnotation.sequence,
                timeText: dayAnnotation.timeText,
                isHighlighted: isHighlighted,
                reduceMotion: reduceMotion,
                dayTint: dayTint(for: dayAnnotation)
            )

            // 选中时触发弹跳动画
            if isHighlighted, highlightNodeId != lastStyledHighlightNodeId, !reduceMotion {
                view.animateSelection()
            }

            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? DayMapAnnotation else { return }
            onSelectNode(annotation.nodeId)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard isMapVisible, hasActiveUserGesture(in: mapView) else { return }
            guard lastViewport != .userExploring else { return }
            lastViewport = .userExploring
            onUserExplore()
        }

        // MARK: 点击空白处取消选中

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let point = gesture.location(in: mapView)
            guard let mapView else { return }
            // P1 修复：遍历完整 superview 链，避免嵌套子视图（badge/label）被误判为空白区域
            let hitView = mapView.hitTest(point, with: nil)
            if !isAnnotationViewOrDescendant(hitView) {
                onDeselect()
            }
        }

        /// 递归检查 view 或其任意 superview 是否为 MKAnnotationView。
        private func isAnnotationViewOrDescendant(_ view: UIView?) -> Bool {
            guard let view else { return false }
            if view is MKAnnotationView { return true }
            return isAnnotationViewOrDescendant(view.superview)
        }

        private func hasActiveUserGesture(in view: UIView) -> Bool {
            if view.gestureRecognizers?.contains(where: {
                $0.state == .began || $0.state == .changed
            }) == true {
                return true
            }
            return view.subviews.contains(where: hasActiveUserGesture)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // 允许与地图的滚动手势共存
            return true
        }
    }
}

// MARK: - Custom Hero Marker (P2 — 品牌风格 annotation view)

/// 自定义品牌风格地图标记：圆形编号 badge + 底部光晕 + 选中时时间微标。
/// 替代系统 MKMarkerAnnotationView，彻底摆脱"系统控件"质感。
final class TripHeroAnnotationView: MKAnnotationView {
    static let reuseID = "TripHeroCustomMarker"

    private let badgeSize: CGFloat = 28
    private let badgeView = UIView()
    private let numberLabel = UILabel()
    private let haloView = UIView()
    private let timeLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func setupViews() {
        frame = CGRect(x: 0, y: 0, width: badgeSize, height: badgeSize + 22)
        centerOffset = CGPoint(x: 0, y: -(badgeSize) / 2)

        // 底部光晕
        haloView.frame = CGRect(x: 4, y: badgeSize - 2, width: badgeSize - 8, height: 6)
        haloView.layer.cornerRadius = 3
        addSubview(haloView)

        // 圆形编号 badge
        badgeView.frame = CGRect(x: 0, y: 0, width: badgeSize, height: badgeSize)
        badgeView.layer.cornerRadius = badgeSize / 2
        badgeView.layer.borderWidth = 2.5
        badgeView.layer.borderColor = UIColor.white.cgColor
        badgeView.layer.shadowColor = UIColor.black.cgColor
        badgeView.layer.shadowOffset = CGSize(width: 0, height: 2)
        badgeView.layer.shadowRadius = 4
        badgeView.layer.shadowOpacity = 0.18
        addSubview(badgeView)

        // 编号文字
        numberLabel.frame = badgeView.bounds
        numberLabel.textAlignment = .center
        numberLabel.textColor = .white
        numberLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        badgeView.addSubview(numberLabel)

        // 时间微标（仅选中时显示）
        timeLabel.frame = CGRect(x: -20, y: badgeSize + 2, width: badgeSize + 40, height: 14)
        timeLabel.textAlignment = .center
        timeLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        timeLabel.font = UIFont.systemFont(ofSize: 9, weight: .medium)
        timeLabel.layer.shadowColor = UIColor.black.cgColor
        timeLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        timeLabel.layer.shadowRadius = 2
        timeLabel.layer.shadowOpacity = 0.3
        timeLabel.isHidden = true
        addSubview(timeLabel)
    }

    func configure(
        sequence: Int,
        timeText: String?,
        isHighlighted: Bool,
        reduceMotion: Bool,
        dayTint: UIColor? = nil
    ) {
        numberLabel.text = "\(sequence)"
        let tint = dayTint ?? UIColor(AppColors.brandPrimary)
        badgeView.backgroundColor = tint

        // 时间微标：仅选中时显示
        if isHighlighted, let timeText, !timeText.isEmpty {
            timeLabel.text = timeText
            timeLabel.isHidden = false
        } else {
            timeLabel.isHidden = true
        }

        // 选中态：实色编号点始终不透明（对齐竞品），用缩放 + 底晕区分焦点
        UIView.animate(
            withDuration: reduceMotion ? 0.15 : 0.35,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.5,
            options: [.allowUserInteraction],
            animations: {
                self.transform = isHighlighted
                    ? CGAffineTransform(scaleX: 1.15, y: 1.15)
                    : .identity
                self.badgeView.alpha = 1.0
                self.haloView.backgroundColor = isHighlighted
                    ? tint.withAlphaComponent(0.28)
                    : tint.withAlphaComponent(0.14)
                self.haloView.transform = isHighlighted
                    ? CGAffineTransform(scaleX: 1.4, y: 0.7)
                    : .identity
            }
        )
    }

    /// 选中时的弹跳动画（P2 — 关键交互记忆点）
    func animateSelection() {
        transform = .identity
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            },
            completion: { _ in
                UIView.animate(
                    withDuration: 0.28,
                    delay: 0,
                    options: [.curveEaseInOut, .allowUserInteraction],
                    animations: {
                        self.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                    }
                )
            }
        )
    }
}

// MARK: - Destination Anchor (P3 — 无节点时的 pulse 锚点)

/// 目的地锚点自定义 view：带 pulse 动画的圆环 + 中心点。
/// 当无行程节点但有目的地坐标时显示，提示用户"旅程的目的地在这里"。
final class DestinationAnchorView: MKAnnotationView {
    static let reuseID = "DestinationAnchor"

    private let outerRing = UIView()
    private let innerDot = UIView()
    private var reduceMotion = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        centerOffset = CGPoint(x: 0, y: -18)

        outerRing.frame = bounds
        outerRing.layer.cornerRadius = 18
        outerRing.layer.borderWidth = 2
        outerRing.layer.borderColor = UIColor(AppColors.brandPrimary).withAlphaComponent(0.4).cgColor
        outerRing.backgroundColor = UIColor(AppColors.brandPrimary).withAlphaComponent(0.12)
        addSubview(outerRing)

        innerDot.frame = CGRect(x: 14, y: 14, width: 8, height: 8)
        innerDot.layer.cornerRadius = 4
        innerDot.backgroundColor = UIColor(AppColors.brandPrimary)
        addSubview(innerDot)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// P2 修复：外部传入 reduceMotion，控制是否启动无限 pulse 动画。
    func configure(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        if reduceMotion {
            // Reduce Motion：静止状态，无动画
            outerRing.layer.removeAllAnimations()
            outerRing.transform = .identity
            outerRing.alpha = 0.7
        } else {
            startPulse()
        }
    }

    private func startPulse() {
        outerRing.layer.removeAllAnimations()
        UIView.animate(
            withDuration: 2.0, delay: 0,
            options: [.repeat, .autoreverse, .allowUserInteraction],
            animations: {
                self.outerRing.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
                self.outerRing.alpha = 0.4
            }
        )
    }
}

// MARK: - Full-Trip Overview Palette & Overlay

/// 全旅程总览的同日同色色板：单一品牌色相的明度阶梯，
/// Day 1 最深、逐日变浅（最多过渡到 62%，保证末天仍可辨识）；不做彩虹色。
enum TripHeroDayPalette {

    static func uiColor(dayIndex: Int, dayCount: Int) -> UIColor {
        guard dayCount > 1, dayIndex > 0 else { return UIColor(AppColors.brandPrimary) }
        let t = CGFloat(dayIndex - 1) / CGFloat(dayCount - 1) * 0.62
        return blend(UIColor(AppColors.brandPrimary), UIColor(AppColors.brandPrimaryLight), t: t)
    }

    private static func blend(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
        let (r1, g1, b1, a1) = rgba(a)
        let (r2, g2, b2, a2) = rgba(b)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }

    private static func rgba(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (r, g, b, a)
        }
        // 非 RGB 色彩空间兜底（如 P3 定义的动态色）。
        guard
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = color.cgColor.converted(
                to: sRGB,
                intent: .defaultIntent,
                options: nil
            ),
            let comps = converted.components,
            comps.count >= 4
        else { return (0, 0, 0, 1) }
        return (comps[0], comps[1], comps[2], comps[3])
    }
}

/// 全旅程总览路线元数据。使用标准 MKPolyline 并编码独立前缀，避免继承
/// MKPolyline 时触发 Swift 6.3.2 Release / WMO ownership 编译器崩溃。
struct DayRoutePolylineMetadata: Equatable {
    private static let titlePrefix = "tracci.fullTripRoute"

    let dayIndex: Int
    let dayCount: Int
    let layer: TripDayRouteLayer

    init(dayIndex: Int, dayCount: Int, layer: TripDayRouteLayer) {
        self.dayIndex = dayIndex
        self.dayCount = dayCount
        self.layer = layer
    }

    init?(title: String?) {
        guard let title else { return nil }
        let components = title.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == Self.titlePrefix,
              let dayIndex = Int(components[1]),
              let dayCount = Int(components[2]),
              let layer = TripDayRouteLayer(rawValue: String(components[3]))
        else { return nil }

        self.init(dayIndex: dayIndex, dayCount: dayCount, layer: layer)
    }

    var title: String {
        "\(Self.titlePrefix):\(dayIndex):\(dayCount):\(layer.rawValue)"
    }

    static func makePolyline(
        coordinates: [CLLocationCoordinate2D],
        dayIndex: Int,
        dayCount: Int,
        layer: TripDayRouteLayer
    ) -> MKPolyline {
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        polyline.title = Self(dayIndex: dayIndex, dayCount: dayCount, layer: layer).title
        return polyline
    }
}
