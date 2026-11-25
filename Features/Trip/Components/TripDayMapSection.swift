import MapKit
import SwiftUI

// MARK: - Day Map

struct TripDayMapSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let nodes: [ItineraryNodeItem]
    let focusedNodeId: String?
    let autoHighlightNodeId: String?
    let onSelectNode: (String) -> Void
    /// Opens system Maps for the selected pin — lives on the map chrome, not a hero card.
    let onNavigateToNode: (ItineraryNodeItem) -> Void
    @Binding var isExpanded: Bool
    let compactHeight: CGFloat
    let expandedHeight: CGFloat

    private var mapHeight: CGFloat {
        isExpanded ? expandedHeight : compactHeight
    }

    private var mapTopShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: TripDetailLayout.routeMapTopRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: TripDetailLayout.routeMapTopRadius,
            style: .continuous
        )
    }

    /// Only user/timeline selection surfaces navigate chrome — not auto day-highlight alone.
    private var selectedNode: ItineraryNodeItem? {
        guard let focusedNodeId else { return nil }
        return nodes.first { $0.id == focusedNodeId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xs) {
                Text("\(nodes.count) 站")
                    .font(TripDetailTypography.railEyebrow)
                    .foregroundStyle(AppColors.textDisabled)

                Spacer(minLength: 0)

                Button {
                    AppHaptics.selection()
                    if reduceMotion {
                        isExpanded.toggle()
                    } else {
                        withAnimation(AppMotion.normal) {
                            isExpanded.toggle()
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(TripDetailTypography.railEyebrow)
                        .foregroundStyle(AppColors.textMuted)
                        .frame(width: 28, height: 28)
                        .background(AppColors.subtleBackground.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "缩小地图" : "放大地图")
            }

            ZStack(alignment: .bottom) {
                TripDayMapView(
                    nodes: nodes,
                    focusedNodeId: focusedNodeId,
                    autoHighlightNodeId: autoHighlightNodeId,
                    reduceMotion: reduceMotion,
                    onSelectNode: onSelectNode
                )
                .frame(height: mapHeight)
                .clipShape(mapTopShape)
                .overlay {
                    mapTopShape
                        .stroke(AppColors.borderSubtle.opacity(0.22), lineWidth: 0.5)
                        .mask(
                            LinearGradient(
                                colors: [.black, .black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            .clear,
                            AppColors.brandPrimary.opacity(0.05),
                            AppColors.brandPrimary.opacity(0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: selectedNode == nil ? 40 : 56)
                    .allowsHitTesting(false)
                }

                if let selectedNode {
                    mapSelectionChrome(for: selectedNode)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.sm)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.98))
                        )
                }
            }
            .animation(
                AppMotion.animation(AppMotion.contextSpring, reduceMotion: reduceMotion),
                value: focusedNodeId
            )
        }
    }

    /// Compact Maps action for the selected pin — replaces the old execution-hero CTA.
    private func mapSelectionChrome(for node: ItineraryNodeItem) -> some View {
        HStack(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayTitle)
                    .font(TripDetailTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.xs) {
                    if let startTime = node.startTime, !startTime.isEmpty {
                        Text(startTime)
                            .font(TripDetailTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                            .monospacedDigit()
                    }
                    // displayTitle 以地点名优先；当 title 存在且与地点名不同时，地点名以副标题展示。
                    if let place = node.locationName, !place.isEmpty, node.locationName != node.displayTitle {
                        Text(place)
                            .font(TripDetailTypography.caption)
                            .foregroundStyle(AppColors.textPlaceholder)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                AppHaptics.lightImpact()
                onNavigateToNode(node)
            } label: {
                Label("导航", systemImage: "location.fill")
                    .font(TripDetailTypography.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.cozy)
                    .frame(minHeight: 36)
                    .background(AppColors.brandPrimary, in: Capsule())
            }
            .buttonStyle(PressableCardStyle(scale: 0.97, opacity: 0.94))
            .accessibilityLabel("开始导航，\(node.displayTitle)")
            .accessibilityHint("在系统地图中打开这个地点")
        }
        .padding(.leading, AppSpacing.cozy)
        .padding(.trailing, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppColors.paperWarmLight.opacity(0.82))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppColors.borderSubtle.opacity(0.45), lineWidth: 0.6)
                }
                .tracciElevation(.l2)
        }
        .accessibilityElement(children: .contain)
    }
}

struct TripDayMapView: UIViewRepresentable {
    let nodes: [ItineraryNodeItem]
    let focusedNodeId: String?
    let autoHighlightNodeId: String?
    let reduceMotion: Bool
    let onSelectNode: (String) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.isPitchEnabled = false
        if #available(iOS 17.0, *) {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = configuration
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let annotations = makeAnnotations()
        let nodesKey = nodes.map(\.id).joined(separator: "|")
        let nodesChanged = nodesKey != context.coordinator.lastNodesKey
        let highlightId = focusedNodeId ?? autoHighlightNodeId

        if nodesChanged {
            context.coordinator.lastNodesKey = nodesKey
            context.coordinator.lastFocusedNodeId = nil
            // Suppress the select-bounce on day switch — the feed slide already carries
            // the motion; the bounce is reserved for explicit node-link taps.
            context.coordinator.lastStyledHighlightNodeId = highlightId

            let previous = mapView.annotations.compactMap { $0 as? DayMapAnnotation }
            mapView.removeAnnotations(previous)
            mapView.removeOverlays(mapView.overlays)
            mapView.addAnnotations(annotations)

            let coordinates = annotations.map(\.coordinate)
            if coordinates.count > 1 {
                addRouteOverlays(to: mapView, coordinates: coordinates)
            }
        }

        context.coordinator.highlightNodeId = highlightId
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.applyMarkerStyles(on: mapView)

        if let focusId = focusedNodeId, focusId != context.coordinator.lastFocusedNodeId {
            context.coordinator.lastFocusedNodeId = focusId
            zoomToNode(focusId, on: mapView, annotations: annotations, animated: !reduceMotion)
        } else if nodesChanged {
            fitAllNodes(on: mapView, annotations: annotations)
        }
    }

    private func makeAnnotations() -> [DayMapAnnotation] {
        nodes.enumerated().compactMap { offset, node in
            guard let latitude = node.location?.latitude,
                  let longitude = node.location?.longitude
            else { return nil }
            return DayMapAnnotation(
                nodeId: node.id,
                sequence: offset + 1,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                subtitle: node.locationName ?? node.title
            )
        }
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

    private func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
            return rect.union(pointRect)
        }
    }

    private func fitAllNodes(on mapView: MKMapView, annotations: [DayMapAnnotation]) {
        let coordinates = annotations.map(\.coordinate)
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let coordinate = coordinates.first {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1400,
                longitudinalMeters: 1400
            )
            mapView.setRegion(region, animated: false)
        } else {
            let rect = mapRect(for: coordinates)
            let padding = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: false)
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
        Coordinator(onSelectNode: onSelectNode)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onSelectNode: (String) -> Void
        var lastNodesKey = ""
        var lastFocusedNodeId: String?
        var highlightNodeId: String?
        var reduceMotion = false
        /// Tracks the previously styled highlight so we only bounce a marker when it is
        /// newly selected, not on every redundant style pass.
        var lastStyledHighlightNodeId: String?

        init(onSelectNode: @escaping (String) -> Void) {
            self.onSelectNode = onSelectNode
        }

        func applyMarkerStyles(on mapView: MKMapView) {
            let isNewHighlight = highlightNodeId != lastStyledHighlightNodeId
            for annotation in mapView.annotations {
                guard let dayAnnotation = annotation as? DayMapAnnotation,
                      let view = mapView.view(for: dayAnnotation) as? MKMarkerAnnotationView
                else { continue }
                let shouldBounce = isNewHighlight && dayAnnotation.nodeId == highlightNodeId
                styleMarkerView(view, annotation: dayAnnotation, animateBounce: shouldBounce)
            }
            lastStyledHighlightNodeId = highlightNodeId
        }

        private func styleMarkerView(
            _ view: MKMarkerAnnotationView,
            annotation: DayMapAnnotation,
            animateBounce: Bool
        ) {
            let isHighlighted = annotation.nodeId == highlightNodeId
            let brand = UIColor(AppColors.brandPrimary)
            view.markerTintColor = isHighlighted ? brand : brand.withAlphaComponent(0.78)
            view.glyphText = "\(annotation.sequence)"
            view.glyphTintColor = .white
            view.displayPriority = isHighlighted ? .required : .defaultHigh

            if animateBounce, isHighlighted, !reduceMotion {
                bounceMarker(view)
            } else {
                view.transform = .identity
            }
        }

        /// Creek memory point (P4): a newly selected marker springs up to 1.15 then
        /// settles back to rest — a tactile "here" cue on the map ↔ timeline link.
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
                        animations: {
                            view.transform = .identity
                        }
                    )
                }
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round

            let brand = UIColor(AppColors.brandPrimary)
            switch TripDayRouteLayer(rawValue: polyline.title ?? "") {
            case .halo:
                renderer.strokeColor = brand.withAlphaComponent(0.05)
                renderer.lineWidth = 14
            case .glow:
                renderer.strokeColor = brand.withAlphaComponent(0.12)
                renderer.lineWidth = 7
            case .line:
                renderer.strokeColor = brand.withAlphaComponent(0.38)
                renderer.lineWidth = 2.8
            case .core:
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.72)
                renderer.lineWidth = 1.1
            case .none:
                renderer.strokeColor = brand.withAlphaComponent(0.26)
                renderer.lineWidth = 1.5
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? DayMapAnnotation else { return nil }

            let identifier = "TripDayMarker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.canShowCallout = false
            styleMarkerView(view, annotation: annotation, animateBounce: false)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? DayMapAnnotation else { return }
            onSelectNode(annotation.nodeId)
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }
}

enum TripDayRouteLayer: String {
    case halo
    case glow
    case line
    case core
}

final class DayMapAnnotation: NSObject, MKAnnotation {
    let nodeId: String
    let sequence: Int
    let coordinate: CLLocationCoordinate2D
    let subtitle: String?
    /// 节点开始时间展示（如 `HH:mm`）；仅 Hero 时间微标使用，与 `subtitle`（地点名）分离。
    let timeText: String?
    /// 全旅程总览用：所属天（1-based）；单日模式为 0，不参与按天着色。
    let dayIndex: Int
    let dayCount: Int

    var title: String? { "\(sequence)" }

    init(
        nodeId: String,
        sequence: Int,
        coordinate: CLLocationCoordinate2D,
        subtitle: String?,
        timeText: String? = nil,
        dayIndex: Int = 0,
        dayCount: Int = 0
    ) {
        self.nodeId = nodeId
        self.sequence = sequence
        self.coordinate = coordinate
        self.subtitle = subtitle
        self.timeText = timeText
        self.dayIndex = dayIndex
        self.dayCount = dayCount
    }
}

