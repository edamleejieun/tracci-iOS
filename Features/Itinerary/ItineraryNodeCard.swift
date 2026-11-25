import SwiftUI

enum ItineraryNodeCardStyle {
    case card
    case timeline
}

struct ItineraryNodeCard: View {
    let node: ItineraryNodeItem
    var status: ItineraryNodeDisplayStatus = .upcoming
    var style: ItineraryNodeCardStyle = .card
    var isRouteLinked: Bool = false
    /// The node currently promoted by the ongoing-day execution snapshot (current or next).
    var isExecutionFocus: Bool = false
    var onOpenPlaceDetail: (() -> Void)? = nil
    let onEdit: () -> Void
    var onAddExpense: (() -> Void)? = nil
    let onDelete: () -> Void
    /// Long-press action menu. Disabled in reorder mode.
    var allowsLongPressActions: Bool = true
    /// Tap-to-edit / select. Disabled in reorder mode.
    var allowsTapInteraction: Bool = true
    /// 仅编辑备注模式（已结束旅程的节点）：菜单只展示「编辑备注」，不展示「删除」。
    var noteOnly: Bool = false

    /// Opacity of the brief brand-blue flash fired when this node is linked from the map (P4).
    @State private var linkPulseOpacity: Double = 0

    private var isHighlighted: Bool {
        status == .current
    }

    private var isCompleted: Bool {
        status == .completed
    }

    /// Whether this node is the visual focus of the creek stream (current or map-linked).
    private var isStreamFocus: Bool {
        isHighlighted || isRouteLinked || isExecutionFocus
    }

    // MARK: Timeline depth layering (P3)
    // Three tiers: stream focus (L2-like, gradient + dual shadow) → upcoming (L1 content)
    // → completed (archive, recedes with lowered opacity + hairline).

    private var timelineBackground: some ShapeStyle {
        if isStreamFocus {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppColors.cardBackground, AppColors.stageOngoingBackground.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        if isCompleted {
            return AnyShapeStyle(AppColors.stageCompletedBackground.opacity(0.42))
        }
        return AnyShapeStyle(AppColors.paperWarmLight.opacity(0.74))
    }

    private var timelineAccentColor: Color {
        if isStreamFocus { return AppColors.brandPrimary }
        return nodeTypeColor
    }

    private var timelineAccentOpacity: Double {
        if isStreamFocus { return 0.90 }
        if isCompleted { return 0.38 }
        return 0.58
    }

    private var timelineCardOpacity: Double {
        isCompleted ? TripDetailLayout.timelineCompletedOpacity : 1
    }

    private var nodeActions: [TracciActionItem] {
        if noteOnly {
            return [TracciActionItem(title: "查看详情", systemImage: "doc.text", action: onEdit)]
        }
        // 中间夜投影：仍暴露删除入口，由上层确认框解释「不可单独删」
        let deleteTitle = node.isHotelStayPrimary ? "删除整段住宿" : "删除"
        var actions = [TracciActionItem(title: "编辑", systemImage: "pencil", action: onEdit)]
        if let onAddExpense {
            actions.append(TracciActionItem(title: "记一笔", systemImage: "yensign.circle", action: onAddExpense))
        }
        actions.append(TracciActionItem(title: deleteTitle, systemImage: "trash", role: .destructive, action: onDelete))
        return actions
    }

    private func handleTap() {
        guard allowsTapInteraction else { return }

        if let onOpenPlaceDetail {
            AppHaptics.lightImpact()
            onOpenPlaceDetail()
            return
        }

        // Timeline cards normally defer edit to the menu. Completed trips have no
        // place-detail target and still need a tap path into the read-only node sheet.
        guard style == .card || noteOnly else { return }
        AppHaptics.lightImpact()
        onEdit()
    }

    var body: some View {
        cardCore
            .onChange(of: isRouteLinked) { _, isLinked in
                guard isLinked else { return }
                runLinkPulse()
            }
    }

    @ViewBuilder
    private var cardCore: some View {
        let base = Group {
            switch style {
            case .card:
                cardBody
            case .timeline:
                timelineBody
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(perform: handleTap)

        let accessibleBase = placeDetailAccessibility(base)

        if allowsLongPressActions {
            accessibleBase.tracciLongPressActions(title: node.displayTitle, actions: nodeActions)
        } else {
            accessibleBase
        }
    }

    @ViewBuilder
    private func placeDetailAccessibility<Content: View>(_ content: Content) -> some View {
        if allowsTapInteraction, onOpenPlaceDetail != nil {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("轻点查看地点详情")
                .accessibilityAction(.default, handleTap)
        } else if allowsTapInteraction, noteOnly {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("轻点查看行程详情")
                .accessibilityAction(.default, handleTap)
        } else {
            content
        }
    }

    /// Brief brand-blue flash (P4) — the timeline card's answer to the map marker bounce.
    private func runLinkPulse() {
        withAnimation(.easeIn(duration: AppMotion.timelineLinkPulseInDuration)) {
            linkPulseOpacity = 1
        } completion: {
            withAnimation(.easeOut(duration: AppMotion.timelineLinkPulseOutDuration)) {
                linkPulseOpacity = 0
            }
        }
    }

    private var cornerRadius: CGFloat {
        style == .card ? AppRadius.large : AppRadius.small
    }

    private var cardBody: some View {
        AppElevationCard(level: isHighlighted ? .l2 : .l1, role: cardRole, radius: AppRadius.large, padding: AppSpacing.cozy) {
            nodeContent(spacing: 8)
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppColors.brandPrimary.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var timelineBody: some View {
        nodeContent(spacing: 5)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(timelineBackground)
            .clipShape(RoundedRectangle(cornerRadius: TripDetailLayout.timelineNodeRadius, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(timelineAccentColor.opacity(timelineAccentOpacity))
                    .frame(width: TripDetailLayout.timelineAccentBarWidth)
                    .padding(.vertical, AppSpacing.xs)
            }
            .overlay {
                if isCompleted {
                    RoundedRectangle(cornerRadius: TripDetailLayout.timelineNodeRadius, style: .continuous)
                        .stroke(AppColors.borderSubtle.opacity(0.36), lineWidth: 0.5)
                } else if isStreamFocus {
                    RoundedRectangle(cornerRadius: TripDetailLayout.timelineNodeRadius, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.16), lineWidth: 0.7)
                }
            }
            .overlay {
                // P4 link pulse: brief brand-blue flash when linked from the map.
                RoundedRectangle(cornerRadius: TripDetailLayout.timelineNodeRadius, style: .continuous)
                    .fill(AppColors.brandPrimaryBackground.opacity(linkPulseOpacity))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .opacity(timelineCardOpacity)
            .tracciElevation(isStreamFocus ? .l2 : (isCompleted ? .l0 : .l1))
    }

    private func nodeContent(spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            headerRow
            titleAndLocation
            if let detailsSummary = node.detailsSummary {
                Text(detailsSummary)
                    .font(TripDetailTypography.nodeMeta)
                    .foregroundStyle(isCompleted ? AppColors.textDisabled : AppColors.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = node.note, !note.isEmpty {
                Text(note)
                    .font(TripDetailTypography.nodeMeta)
                    .foregroundStyle(isCompleted ? AppColors.textDisabled : AppColors.textMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: AppSpacing.xs) {
            if let timeText = ItineraryTimeFormatting.displayRange(start: node.startTime, end: node.endTime) {
                Text(timeText)
                    .font(TripDetailTypography.nodeMetaMedium)
                    .foregroundStyle(isHighlighted ? AppColors.brandPrimary : AppColors.textMuted)
            }

            typeTag

            if style != .timeline, status == .current || status == .today {
                currentTag
            }

            Spacer(minLength: 4)

            TracciActionMenuButton(actions: nodeActions) {
                Image(systemName: "ellipsis")
                    .font(TripDetailTypography.inlineIcon)
                    .foregroundStyle(AppColors.textPlaceholder.opacity(style == .timeline ? 0.85 : 1))
                    .frame(width: style == .timeline ? 24 : 28, height: style == .timeline ? 24 : 28)
                    .background(style == .timeline ? Color.clear : AppColors.subtleBackground)
                    .clipShape(Circle())
                    // Preserve the compact visual treatment while expanding
                    // the actual button label to the platform tap-target size.
                    .frame(
                        width: AppControlMetrics.minimumTapTarget,
                        height: AppControlMetrics.minimumTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多操作")
            .accessibilityHint(noteOnly ? "查看行程详情" : "编辑或删除这个行程节点")
        }
    }

    // MARK: - Title & Location

    private var titleAndLocation: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(node.displayTitle)
                .font(style == .timeline ? TripDetailTypography.nodeTitle : TripDetailTypography.contentTitle)
                .foregroundStyle(isCompleted ? AppColors.textMuted : AppColors.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let locationName = node.locationName, node.locationName != node.displayTitle {
                // displayTitle 以地点名优先；当 title 存在且与地点名不同时，地点名以副标题展示。
                HStack(alignment: .top, spacing: AppSpacing.xxs) {
                    Image(systemName: "mappin")
                        .font(AppTypography.micro)
                        .padding(.top, 2)
                    Text(locationName)
                        .font(TripDetailTypography.nodeMeta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(isCompleted ? AppColors.textDisabled : AppColors.textPlaceholder)
                .lineLimit(2)
            }

            if let addressText {
                Text(addressText)
                    .font(TripDetailTypography.caption)
                    .foregroundStyle(AppColors.textDisabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var addressText: String? {
        guard let address = node.displayAddress else { return nil }
        let locationName = node.location?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address != locationName else { return nil }
        return address
    }

    private var typeTag: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: node.typeIcon)
                .font(AppTypography.microSemibold)
            Text(node.typeLabel)
                .font(TripDetailTypography.nodeTag)
        }
        .foregroundStyle(nodeTypeColor)
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, AppSpacing.xxs)
        .background(nodeTypeColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var currentTag: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: statusIcon)
                .font(AppTypography.microSemibold)
            Text(status.label)
                .font(TripDetailTypography.nodeTag)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, AppSpacing.xxs)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusIcon: String {
        switch status {
        case .completed: "checkmark"
        case .current: "clock"
        case .upcoming: "calendar"
        case .today: "sun.max"
        }
    }

    private var statusColor: Color {
        switch status {
        case .completed:
            return AppColors.textDisabled
        case .current, .today:
            return AppColors.brandPrimary
        case .upcoming:
            return AppColors.textMuted
        }
    }

    private var nodeTypeColor: Color {
        switch node.type {
        case .attraction:
            return AppColors.itineraryAttraction
        case .restaurant:
            return AppColors.itineraryRestaurant
        case .transport:
            return AppColors.itineraryTransport
        case .hotel:
            return AppColors.itineraryHotel
        case .shopping:
            return AppColors.itineraryShopping
        case .other:
            return AppColors.itineraryOther
        }
    }

    private var cardRole: AppCardRole {
        if isHighlighted { return .active }
        if isCompleted { return .archive }
        return .content
    }
}
