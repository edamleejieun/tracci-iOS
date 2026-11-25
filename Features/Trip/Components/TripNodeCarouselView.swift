import SwiftUI
import CoreLocation

/// 横排节点轮播卡片 — 地图模式下替代竖排时间线。
/// 滑动卡片与地图 marker 双向联动（通过 `linkedNodeId`）。
struct TripNodeCarouselView: View {
    enum Style {
        /// 标准信息密度（若其它入口复用）。
        case standard
        /// 大地图 dock：单行标题、无备注，压低高度。
        case compact
    }

    let nodes: [ItineraryNodeItem]
    let dayDate: Date?
    @Binding var linkedNodeId: String?
    var style: Style = .standard
    let onSelectNode: (String) -> Void
    let onNavigateToNode: (ItineraryNodeItem) -> Void
    let reduceMotion: Bool

    @State private var visibleNodeId: String?
    /// 程序化对齐滚动时为 true，避免把「Day 切换 / 进入地图」误当成用户选中节点并 zoom。
    @State private var suppressSelectionSync = false

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        carouselItem(node: node, index: index)
                            .containerRelativeFrame(.horizontal, count: 1, spacing: AppSpacing.sm)
                            .scrollTransition(.animated) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : (style == .compact ? 0.96 : 0.92))
                                    .opacity(phase.isIdentity ? 1 : (style == .compact ? 0.78 : 0.7))
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, AppSpacing.sm)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $visibleNodeId)
            .onChange(of: visibleNodeId) { _, newValue in
                // 仅用户横滑停稳时同步 linked + 地图镜头；程序化对齐不触发。
                guard !suppressSelectionSync else { return }
                guard let newValue, newValue != linkedNodeId else { return }
                onSelectNode(newValue)
            }
            .onChange(of: linkedNodeId) { _, newValue in
                guard let newValue, newValue != visibleNodeId else { return }
                let animation: Animation? = reduceMotion
                    ? nil
                    : (style == .compact ? AppMotion.mapExploreDayCamera : AppMotion.softSpring)
                withAnimation(animation) {
                    alignVisibleNode(newValue, programmatic: true)
                    scrollProxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onChange(of: nodes.map(\.id)) { _, ids in
                // Day 切换 / 列表重置：卡片滚到首张（或仍有效的 linked），但地图保持总览，
                // 不自动选中节点、不写入 focusedNode。
                if let linkedNodeId, ids.contains(linkedNodeId) {
                    alignVisibleNode(linkedNodeId, programmatic: true)
                } else if let first = ids.first {
                    alignVisibleNode(first, programmatic: true)
                    // 清除跨天残留 linked；不要改成 first（否则会 zoom 到地址）。
                    if linkedNodeId != nil {
                        linkedNodeId = nil
                    }
                } else {
                    alignVisibleNode(nil, programmatic: true)
                    if linkedNodeId != nil {
                        linkedNodeId = nil
                    }
                }
            }
        }
    }

    /// 更新可见卡片位置；`programmatic == true` 时抑制 onSelectNode → 地图聚焦。
    private func alignVisibleNode(_ nodeId: String?, programmatic: Bool) {
        guard visibleNodeId != nodeId else { return }
        if programmatic {
            suppressSelectionSync = true
            visibleNodeId = nodeId
            Task { @MainActor in
                suppressSelectionSync = false
            }
        } else {
            visibleNodeId = nodeId
        }
    }

    // MARK: - Carousel Item

    @ViewBuilder
    private func carouselItem(node: ItineraryNodeItem, index: Int) -> some View {
        VStack(spacing: style == .compact ? 4 : AppSpacing.tight) {
            NodeCarouselCard(
                node: node,
                sequence: index + 1,
                isLinked: linkedNodeId == node.id,
                dayDate: dayDate,
                style: style,
                onTap: { onSelectNode(node.id) },
                onNavigate: { onNavigateToNode(node) }
            )

            if style != .compact, index < nodes.count - 1 {
                NodeTransitInfo(from: node, to: nodes[index + 1])
            } else if style == .compact, index < nodes.count - 1 {
                // 紧凑态：仅在有明确交通时显示一行小标签，无则极薄占位。
                NodeTransitInfo(from: node, to: nodes[index + 1], compact: true)
            }
        }
        .id(node.id)
    }
}

// MARK: - Node Carousel Card

/// 横排轮播中的单张节点卡片。
private struct NodeCarouselCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let node: ItineraryNodeItem
    let sequence: Int
    let isLinked: Bool
    let dayDate: Date?
    var style: TripNodeCarouselView.Style = .standard
    let onTap: () -> Void
    let onNavigate: () -> Void

    @State private var selectionPulse = false

    private var isCompact: Bool { style == .compact }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(AppColors.brandPrimary)
                    .frame(width: isCompact ? 2 : 2.5)
                    .padding(.vertical, isCompact ? 8 : AppSpacing.cozy)

                if isCompact {
                    compactContent
                        .padding(.leading, 10)
                        .padding(.trailing, 12)
                        .padding(.vertical, 10)
                } else {
                    standardContent
                        .padding(.leading, AppSpacing.sm)
                        .padding(.trailing, AppSpacing.cardSmall)
                        .padding(.vertical, AppSpacing.cozy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? AppRadius.medium : AppRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isCompact ? AppRadius.medium : AppRadius.card, style: .continuous)
                    .stroke(
                        isLinked ? AppColors.brandPrimary.opacity(selectionPulse ? 0.42 : 0.28) : AppColors.borderSubtle.opacity(0.18),
                        lineWidth: isLinked ? (selectionPulse ? 1.4 : 1) : 0.5
                    )
            }
            .tracciElevation(isLinked ? .l1 : .l0)
            .scaleEffect(selectionPulse ? 1.02 : 1)
        }
        .buttonStyle(PressableCardStyle(scale: AppMotion.pressScale, opacity: AppMotion.pressOpacity))
        .contextMenu {
            Button("导航", systemImage: "map") { onNavigate() }
        }
        .accessibilityLabel(accessibilitySummary)
        .onChange(of: isLinked) { _, linked in
            guard linked else {
                selectionPulse = false
                return
            }
            guard !reduceMotion else { return }
            // marker / 横滑选中时短促强调，与地图弹跳同频。
            withAnimation(.easeOut(duration: 0.14)) {
                selectionPulse = true
            }
            withAnimation(.easeInOut(duration: 0.22).delay(0.14)) {
                selectionPulse = false
            }
        }
    }

    /// 紧凑：序号 + 时间 + 标题一行，地点可选次行。
    private var compactContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(sequence)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppColors.brandPrimary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let timeText = ItineraryTimeFormatting.displayRange(start: node.startTime, end: node.endTime) {
                        Text(timeText)
                            .font(TripDetailTypography.nodeMetaMedium)
                            .foregroundStyle(isLinked ? AppColors.brandPrimary : AppColors.textMuted)
                            .lineLimit(1)
                    }
                    Text(node.typeLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(node.type.accentColor)
                        .lineLimit(1)
                }

                Text(node.displayTitle)
                    .font(TripDetailTypography.nodeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if let locationName = node.locationName,
                   !locationName.isEmpty,
                   locationName != node.displayTitle {
                    Text(locationName)
                        .font(TripDetailTypography.nodeMeta)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Text("\(sequence)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(AppColors.brandPrimary, in: Circle())

                if let timeText = ItineraryTimeFormatting.displayRange(start: node.startTime, end: node.endTime) {
                    Text(timeText)
                        .font(TripDetailTypography.nodeMetaMedium)
                        .foregroundStyle(isLinked ? AppColors.brandPrimary : AppColors.textMuted)
                }

                typeTag

                Spacer(minLength: 4)
            }

            Text(node.displayTitle)
                .font(TripDetailTypography.nodeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // displayTitle 以地点名优先；当 title 存在且与地点名不同时，地点名以副标题展示。
            if let locationName = node.locationName, node.locationName != node.displayTitle {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "mappin")
                        .font(AppTypography.micro)
                    Text(locationName)
                        .font(TripDetailTypography.nodeMeta)
                }
                .foregroundStyle(AppColors.textPlaceholder)
                .lineLimit(1)
            }

            if let note = node.note, !note.isEmpty {
                Text(note)
                    .font(TripDetailTypography.nodeMeta)
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if isLinked {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppColors.cardBackground.opacity(isCompact ? 0.92 : 1),
                        AppColors.stageOngoingBackground.opacity(isCompact ? 0.35 : 0.45)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(AppColors.paperWarmLight.opacity(isCompact ? 0.88 : 0.78))
    }

    private var typeTag: some View {
        HStack(spacing: 3) {
            Image(systemName: node.typeIcon)
                .font(.system(size: 9))
            Text(node.typeLabel)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(node.type.accentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(node.type.accentColor.opacity(0.10), in: Capsule())
    }

    private var accessibilitySummary: String {
        var parts = ["第 \(sequence) 站", node.displayTitle]
        if let time = ItineraryTimeFormatting.displayRange(start: node.startTime, end: node.endTime) {
            parts.append(time)
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - Transit Info Between Cards

/// 两张节点卡片之间的交通信息标签。
private struct NodeTransitInfo: View {
    let from: ItineraryNodeItem
    let to: ItineraryNodeItem
    var compact: Bool = false

    var body: some View {
        if let info = transitText {
            Text(info)
                .font(compact ? .system(size: 10, weight: .medium) : .caption2)
                .foregroundStyle(AppColors.textMuted)
                .padding(.horizontal, compact ? 6 : 8)
                .padding(.vertical, compact ? 2 : 3)
                .background(AppColors.subtleBackground.opacity(compact ? 0.9 : 1), in: Capsule())
                .padding(.vertical, compact ? 0 : 2)
        } else if !compact {
            Color.clear.frame(height: 12)
        }
    }

    private var transitText: String? {
        guard let carrier = transportCarrier else { return nil }

        if carrier.mode.isScheduledLongHaul {
            return scheduledLongHaulText(mode: carrier.mode, node: carrier.node)
        }

        return roadStyleTransitText(mode: carrier.mode)
    }

    private var transportCarrier: (mode: TransportMode, node: ItineraryNodeItem)? {
        if to.type == .transport, let mode = to.details?.transportMode {
            return (mode, to)
        }
        if from.type == .transport, let mode = from.details?.transportMode {
            return (mode, from)
        }
        return nil
    }

    private func scheduledLongHaulText(mode: TransportMode, node: ItineraryNodeItem) -> String? {
        let label = mode.label
        guard let duration = scheduledDurationText(start: node.startTime, end: node.endTime) else {
            return label
        }
        return "\(label) · \(duration)"
    }

    private func scheduledDurationText(start: String?, end: String?) -> String? {
        guard
            let startMinutes = ItineraryTimeFormatting.minutes(from: start),
            let endMinutes = ItineraryTimeFormatting.minutes(from: end)
        else { return nil }

        var delta = endMinutes - startMinutes
        if delta < 0 {
            delta += 24 * 60
        }
        guard delta > 0 else { return nil }
        return formatDurationMinutes(delta)
    }

    private func roadStyleTransitText(mode: TransportMode) -> String? {
        guard let fromLat = from.location?.latitude,
              let fromLng = from.location?.longitude,
              let toLat = to.location?.latitude,
              let toLng = to.location?.longitude
        else {
            return mode == .other ? nil : mode.label
        }

        let distance = CLLocation(latitude: fromLat, longitude: fromLng)
            .distance(from: CLLocation(latitude: toLat, longitude: toLng))
        guard distance > 0 else { return mode.label }

        let distanceText: String
        if distance >= 1000 {
            distanceText = String(format: "%.1fkm", distance / 1000)
        } else {
            distanceText = "\(Int(distance))m"
        }

        let timeText = roadEstimatedTimeText(distance: distance, mode: mode)
        if timeText.isEmpty {
            return "\(distanceText) · \(mode.label)"
        }
        return "\(distanceText)\(timeText)"
    }

    private func roadEstimatedTimeText(distance: CLLocationDistance, mode: TransportMode) -> String {
        let kmPerHour: Double
        switch mode {
        case .bus:
            kmPerHour = 60
        case .driving:
            kmPerHour = 50
        case .flight, .train, .hsr, .other:
            return ""
        }

        let minutes = Int((distance / 1000) / kmPerHour * 60)
        guard minutes > 0 else { return "" }
        return " · \(mode.label)\(formatDurationMinutes(minutes))"
    }

    private func formatDurationMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remain = minutes % 60
            return remain > 0 ? "\(hours)h\(remain)min" : "\(hours)h"
        }
        return "\(minutes)min"
    }
}

private extension TransportMode {
    var isScheduledLongHaul: Bool {
        switch self {
        case .flight, .train, .hsr: true
        case .bus, .driving, .other: false
        }
    }
}

// MARK: - Node Type Accent Color

private extension ItineraryNodeType {
    var accentColor: Color {
        switch self {
        case .attraction: AppColors.itineraryAttraction
        case .restaurant: AppColors.itineraryRestaurant
        case .transport: AppColors.itineraryTransport
        case .hotel: AppColors.itineraryHotel
        case .shopping: AppColors.itineraryShopping
        case .other: AppColors.itineraryOther
        }
    }
}
