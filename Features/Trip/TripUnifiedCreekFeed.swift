import SwiftUI
import MapKit
import UIKit

// MARK: - Day Feed Content

enum TripDayCreekItem: Identifiable {
    case itinerary(ItineraryNodeItem)
    case journal(JournalEntry)
    case expense(Expense)

    var id: String {
        switch self {
        case .itinerary(let node): "itinerary-\(node.id)"
        case .journal(let entry): "journal-\(entry.id)"
        case .expense(let expense): "expense-\(expense.id)"
        }
    }

    fileprivate var timeMinutes: Int? {
        switch self {
        case .itinerary(let node):
            Self.minutes(from: node.startTime)
        case .journal(let entry):
            entry.occurredDate.flatMap(Self.minutes(from:))
        case .expense(let expense):
            expense.spentAtDate.flatMap(Self.minutes(from:))
        }
    }

    private var kindOrder: Int {
        switch self {
        case .itinerary: 0
        case .journal: 1
        case .expense: 2
        }
    }

    private var fallbackOrder: Int {
        switch self {
        case .itinerary(let node): node.sortOrder ?? .max
        case .journal, .expense: 0
        }
    }

    fileprivate static func ordered(
        nodes: [ItineraryNodeItem],
        journals: [JournalEntry],
        expenses: [Expense]
    ) -> [TripDayCreekItem] {
        let items = nodes.map(Self.itinerary)
            + journals.map(Self.journal)
            + expenses.map(Self.expense)

        return items.sorted { lhs, rhs in
            switch (lhs.timeMinutes, rhs.timeMinutes) {
            case let (lhsMinutes?, rhsMinutes?) where lhsMinutes != rhsMinutes:
                return lhsMinutes < rhsMinutes
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.kindOrder != rhs.kindOrder {
                    return lhs.kindOrder < rhs.kindOrder
                }
                if lhs.fallbackOrder != rhs.fallbackOrder {
                    return lhs.fallbackOrder < rhs.fallbackOrder
                }
                return lhs.id < rhs.id
            }
        }
    }

    private static func minutes(from value: String?) -> Int? {
        guard let value else { return nil }
        let components = value.split(separator: ":", maxSplits: 2).compactMap { Int($0) }
        guard components.count >= 2,
              (0...23).contains(components[0]),
              (0...59).contains(components[1])
        else { return nil }
        return components[0] * 60 + components[1]
    }

    private static func minutes(from date: Date) -> Int? {
        let components = TracciDateContext.calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * 60 + minute
    }
}
struct TripUnifiedCreekFeed: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedDayIndex: Int
    let selectedTab: TripDetailTab
    let trip: Trip
    let isItineraryLoading: Bool
    let itineraryErrorMessage: String?
    let itineraryGroups: [ItineraryDayGroup]
    let isJournalLoading: Bool
    let journalErrorMessage: String?
    let expenses: [Expense]
    let journalDayGroups: [JournalDayGroup]
    let isExpenseLoading: Bool
    let expenseErrorMessage: String?
    let weatherState: TripWeatherCardState
    let executionSnapshot: TripDayExecutionSnapshot?
    let onRefreshWeather: () -> Void
    let onRetryItinerary: () -> Void
    let onRetryJournal: () -> Void
    let onRetryExpense: () -> Void

    let onAddNode: () -> Void
    let onEditNode: (ItineraryNodeItem) -> Void
    /// 仅编辑备注（已结束旅程的节点）：打开备注-only 表单。
    let onEditNodeNote: (ItineraryNodeItem) -> Void
    let onDeleteNode: (ItineraryNodeItem) -> Void
    let onOpenNodePlace: (ItineraryNodeItem) -> Void

    let onAddExpense: () -> Void
    var onAddExpenseForNode: ((ItineraryNodeItem) -> Void)? = nil
    let onEditExpense: (Expense) -> Void
    var onDuplicateExpense: ((Expense) -> Void)? = nil
    let onDeleteExpense: (Expense) -> Void
    /// Trip-level AA settlement entry (not day-scoped). Nil hides the control.
    var onOpenSettlement: (() -> Void)? = nil
    /// True when the trip has any expense records (trip-wide, not current day only).
    var hasTripExpenses: Bool = false
    var members: [TripMemberResp] = []
    var currentUserMemberId: String? = nil
    var settlement: ExpenseSettlement? = nil

    let onAddJournal: () -> Void
    let onAddPhotoJournal: () -> Void
    let onEditJournal: (JournalEntry) -> Void
    let onToggleHighlight: (JournalEntry) -> Void
    let onToggleFeaturedPhoto: ((JournalPhoto) -> Void)?
    let onDeleteJournal: (JournalEntry) -> Void
    let onNavigateToNode: (ItineraryNodeItem) -> Void
    let canEdit: Bool
    let currentUserId: String?
    let topSafeInset: CGFloat
    let emptyStateMinHeight: CGFloat
    /// Id of a node created moments ago — receives the milestone entrance (P2).
    var newlyCreatedNodeId: String? = nil
    @Binding var scrollToNodeId: String?

    /// Hero map state (lifted to TripDetailView).
    var showMapSection: Bool = true
    /// Whether the detail Hero is currently presenting its map surface.
    var isHeroMapVisible: Bool = false
    var linkedNodeId: String? = nil
    var onLinkNode: ((String, Bool) -> Void)?

    // MARK: Same-day node reorder (narrow mode)
    var isNodeReorderMode: Bool = false
    var onEnterNodeReorder: (() -> Void)?
    var onCancelNodeReorder: (() -> Void)?
    var onCommitNodeReorder: (() -> Void)?
    var onMoveNode: ((String, String) -> Void)?
    var isReorderSubmitting: Bool = false

    @State private var isMapExpanded = false
    @State private var itinerarySpineReveal: CGFloat = 1
    @State private var lastSpineRevealDayIndex: Int?
    @State private var draggedNodeId: String?
    @State private var lastReorderTargetNodeId: String?
    @State private var draggedNodeCenterY: CGFloat?
    @State private var dragTouchOffsetY: CGFloat?
    @State private var nodeReorderFrames: [String: CGRect] = [:]
    /// 上一次渲染时所选 Day 的行 id 集合与所属 Day —— 用于识别「同一天内单行插入」，
    /// 给新增日志/开支行补上里程碑入场（计划 005 去掉逐行交错后的兜底）。
    @State private var unifiedRowIDBaseline: [String] = []
    @State private var unifiedRowIDBaselineDay: Int?
    /// 正在播放里程碑入场的行 id，短延时后清除，避免滚动回收重播。
    @State private var milestoneRowID: String?

    private static let nodeReorderCoordinateSpace = "trip-itinerary-node-reorder"

    static func nodeScrollAnchorID(for nodeId: String) -> String {
        "trip-itinerary-node-\(nodeId)"
    }

    private var timelineGutterWidth: CGFloat { TripDetailLayout.timelineGutter }
    private let timelineDotTopInset: CGFloat = 14
    private let compactMapHeight: CGFloat = 158
    private let expandedMapHeight: CGFloat = 268

    private var selectedItineraryDay: ItineraryDayGroup? {
        itineraryGroups.first { $0.dayIndex == selectedDayIndex }
    }

    private var selectedJournalDay: JournalDayGroup? {
        journalDayGroups.first { $0.dayIndex == selectedDayIndex }
    }

    private var dayExpenses: [Expense] {
        expenses.filter { expense in
            dayIndexForExpense(expense) == selectedDayIndex
        }
    }

    private var hasItineraryNodes: Bool {
        (selectedItineraryDay?.nodeCount ?? 0) > 0
    }

    private var hasJournalEntries: Bool {
        !(selectedJournalDay?.entries.isEmpty ?? true)
    }

    private var hasContent: Bool {
        hasItineraryNodes || !dayExpenses.isEmpty || hasJournalEntries
    }

    private var unifiedItems: [TripDayCreekItem] {
        TripDayCreekItem.ordered(
            nodes: selectedItineraryDay?.nodes ?? [],
            journals: selectedJournalDay?.entries ?? [],
            expenses: dayExpenses
        )
    }

    private var currentUnifiedRowIDs: [String] { unifiedItems.map(\.id) }

    private var overviewLoadFailures: [String] {
        var failures: [String] = []
        if itineraryErrorMessage != nil { failures.append("行程") }
        if journalErrorMessage != nil { failures.append("日志") }
        if expenseErrorMessage != nil { failures.append("开支") }
        return failures
    }

    private var isOverviewLoadingWithoutContent: Bool {
        !hasContent && (isItineraryLoading || isJournalLoading || isExpenseLoading)
    }

    private var selectedDayPhase: TripDayPhase {
        guard let startDate = TripDateFormatting.date(from: trip.startDate),
              let dayDate = dateForDayIndex(selectedDayIndex, startDate: startDate)
        else { return .upcoming }

        let today = TracciDateContext.startOfBusinessDay(for: TracciDateContext.today())
        let day = TracciDateContext.startOfBusinessDay(for: dayDate)
        if day == today { return .today }
        if day > today { return .upcoming }
        return .past
    }

    var body: some View {
        VStack(spacing: TripDetailLayout.moduleSpacing) {
            // Product surface is itinerary / journal / expense only.
            // `.overview` is rendered by TripOverviewPageView and never reaches this feed,
            // but the switch must stay exhaustive on TripDetailTab.
            switch selectedTab {
            case .overview:
                EmptyView()
            case .itinerary:
                if isItineraryLoading && !hasItineraryNodes {
                    loadingState(label: "正在加载这一天的安排")
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                } else if let itineraryErrorMessage, !hasItineraryNodes {
                    ErrorStateView(title: "行程加载失败", message: itineraryErrorMessage, retryTitle: "再试一次") {
                        onRetryItinerary()
                    }
                    .tracciRevealTransition(reduceMotion: reduceMotion)
                } else {
                    itineraryTabContent
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                }
            case .expense:
                if isExpenseLoading && dayExpenses.isEmpty {
                    loadingState(label: "正在加载这一天的开支")
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                } else if let expenseErrorMessage, dayExpenses.isEmpty {
                    ErrorStateView(title: "开支加载失败", message: expenseErrorMessage, retryTitle: "再试一次") {
                        onRetryExpense()
                    }
                    .tracciRevealTransition(reduceMotion: reduceMotion)
                } else {
                    expenseTabContent
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                }
            case .journal:
                if isJournalLoading && !hasJournalEntries {
                    loadingState(label: "正在加载这一天的日志")
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                } else if let journalErrorMessage, !hasJournalEntries {
                    ErrorStateView(title: "日志加载失败", message: journalErrorMessage, retryTitle: "再试一次") {
                        onRetryJournal()
                    }
                    .tracciRevealTransition(reduceMotion: reduceMotion)
                } else {
                    journalTabContent
                        .tracciRevealTransition(reduceMotion: reduceMotion)
                }
            }
        }
        .animation(
            AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion),
            value: creekLoadSignature
        )
        .padding(.horizontal, TripDetailLayout.pageInset)
        .onChange(of: selectedDayIndex) { _, _ in
            scrollToNodeId = nil
            clearNodeDragState()
            applySelectedTab(animated: false)
            if hasItineraryNodes {
                triggerItineraryGrowthAnimation()
            }
            // 换 Day 即重置基线：新一天的整体呈现不是「单行新增」。
            unifiedRowIDBaseline = currentUnifiedRowIDs
            unifiedRowIDBaselineDay = selectedDayIndex
        }
        .onChange(of: selectedTab) { _, _ in
            applySelectedTab(animated: true)
        }
        .onChange(of: isNodeReorderMode) { _, isReordering in
            if !isReordering {
                clearNodeDragState()
            }
        }
        .onAppear {
            applySelectedTab(animated: false)
            unifiedRowIDBaseline = currentUnifiedRowIDs
            unifiedRowIDBaselineDay = selectedDayIndex
        }
        .onChange(of: hasItineraryNodes) { oldValue, newValue in
            guard !oldValue, newValue else { return }
            triggerItineraryGrowthAnimation()
        }
        .onChange(of: currentUnifiedRowIDs) { _, newIDs in
            let oldSet = Set(unifiedRowIDBaseline)
            let newSet = Set(newIDs)
            let added = newIDs.filter { !oldSet.contains($0) }
            let removed = unifiedRowIDBaseline.filter { !newSet.contains($0) }
            let sameDay = unifiedRowIDBaselineDay == selectedDayIndex
            unifiedRowIDBaseline = newIDs
            unifiedRowIDBaselineDay = selectedDayIndex
            // 同一天内「单行插入」才视为新增内容；Day/Tab 切换与多行变化不触发。
            guard sameDay, added.count == 1, removed.isEmpty else { return }
            let rowID = added[0]
            milestoneRowID = rowID
            let clearDelay: TimeInterval = reduceMotion ? 0.05 : 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) {
                if milestoneRowID == rowID {
                    milestoneRowID = nil
                }
            }
        }
    }

    private var emptyStateExitTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.97))
    }

    private var contentGrowthTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98))
    }

    private var creekLoadSignature: String {
        switch selectedTab {
        case .overview:
            return "overview"
        case .itinerary:
            if isItineraryLoading && !hasItineraryNodes { return "itinerary-loading" }
            if itineraryErrorMessage != nil && !hasItineraryNodes { return "itinerary-error" }
            return "itinerary-content"
        case .expense:
            if isExpenseLoading && dayExpenses.isEmpty { return "expense-loading" }
            if expenseErrorMessage != nil && dayExpenses.isEmpty { return "expense-error" }
            return "expense-content"
        case .journal:
            if isJournalLoading && !hasJournalEntries { return "journal-loading" }
            if journalErrorMessage != nil && !hasJournalEntries { return "journal-error" }
            return "journal-content"
        }
    }

    private func loadingState(label: String) -> some View {
        ContentBlockSkeletonView(rowCount: 3, accessibilityLabelText: label)
            .padding(.vertical, AppSpacing.sm)
    }

    @ViewBuilder
    private var itineraryTabContent: some View {
        // Order: weather (context) → node section header + creek timeline.
        // Navigation lives on the day map selection chrome — no separate execution hero.
        Group {
            if shouldShowWeatherMeta {
                weatherMetaLine
            }

            if hasItineraryNodes {
                VStack(alignment: .leading, spacing: 0) {
                    nodeSectionHeader
                    itinerarySection()
                        .transition(contentGrowthTransition)
                }
            } else if hasContent {
                // 当天有日志/开支但没有行程：同一空态体系的紧凑变体
                tabEmptyState(kind: .itinerary, density: .compact)
                    .transition(emptyStateExitTransition)
            } else {
                tabEmptyState(kind: .itinerary)
                    .transition(emptyStateExitTransition)
            }
        }
        .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: itineraryTabPresentation)
    }

    @ViewBuilder
    private var nodeSectionHeader: some View {
        let nodeCount = selectedItineraryDay?.nodeCount ?? 0
        let canShowEntry = canEdit && nodeCount >= 2 && !isNodeReorderMode && TripEditPolicy.contentEditOutcome(trip: trip).isAllowed
        if nodeCount > 0 {
            HStack(spacing: AppSpacing.sm) {
                if isNodeReorderMode {
                    Text("拖动调整当天顺序")
                        .font(TripDetailTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("取消") {
                        AppHaptics.selection()
                        onCancelNodeReorder?()
                    }
                    .font(TripDetailTypography.bodyMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .disabled(isReorderSubmitting)
                    .frame(minHeight: 44)

                    Button(isReorderSubmitting ? "保存中…" : "完成") {
                        AppHaptics.lightImpact()
                        onCommitNodeReorder?()
                    }
                    .font(TripDetailTypography.bodyMedium)
                    .foregroundStyle(AppColors.brandPrimary)
                    .disabled(isReorderSubmitting)
                    .frame(minHeight: 44)
                } else {
                    HStack(spacing: AppSpacing.xs) {
                        Text("当天行程")
                            .font(TripDetailTypography.captionMedium)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("\(nodeCount) 项")
                            .font(TripDetailTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    if canShowEntry {
                        Button {
                            AppHaptics.selection()
                            onEnterNodeReorder?()
                        } label: {
                            Label("调整顺序", systemImage: "arrow.up.arrow.down")
                                .font(TripDetailTypography.captionMedium)
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xs)
                                .background(AppColors.subtleBackground)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityLabel("调整顺序")
                        .accessibilityHint("进入当天行程节点排序")
                    }
                }
            }
            .padding(.leading, TripDetailLayout.timelineContentLeading)
        }
    }

    private var itineraryTabPresentation: String {
        if hasItineraryNodes { "nodes" }
        else if hasContent { "hint" }
        else { "empty" }
    }

    @ViewBuilder
    private var expenseTabContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // AA is trip-scoped; keep entry visible even when the selected day has no rows.
            if hasTripExpenses, onOpenSettlement != nil {
                settlementEntryRow
            }

            Group {
                if dayExpenses.isEmpty {
                    if hasContent || hasTripExpenses {
                        TripExpenseCreekSection(
                            expenses: [],
                            trip: trip,
                            selectedDayIndex: selectedDayIndex,
                            selectedDayPhase: selectedDayPhase,
                            selectedDayDate: selectedDayDate,
                            canEdit: canEdit,
                            itineraryNodes: itineraryGroups.flatMap(\.nodes),
                            members: members,
                            onEdit: onEditExpense,
                            onDuplicate: onDuplicateExpense,
                            onDelete: onDeleteExpense
                        )
                    } else {
                        tabEmptyState(kind: .expense)
                            .transition(emptyStateExitTransition)
                    }
                } else {
                    TripExpenseCreekSection(
                        expenses: dayExpenses,
                        trip: trip,
                        selectedDayIndex: selectedDayIndex,
                        selectedDayPhase: selectedDayPhase,
                        selectedDayDate: selectedDayDate,
                        canEdit: canEdit,
                        itineraryNodes: itineraryGroups.flatMap(\.nodes),
                        members: members,
                        onEdit: onEditExpense,
                        onDuplicate: onDuplicateExpense,
                        onDelete: onDeleteExpense
                    )
                        .transition(contentGrowthTransition)
                }
            }
        }
        .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: expenseTabPresentation)
    }

    /// Compact trip-level CTA into `SettlementView` (live API or Demo hydrate).
    private var settlementEntryRow: some View {
        let fact = settlement.flatMap {
            ExpenseSettlementFact.headline(settlement: $0, currentUserMemberId: currentUserMemberId)
        }
        let title = fact?.title ?? "AA 结算"
        let detail = fact?.detail ?? "查看成员分摊与转账明细"

        return Button {
            AppHaptics.lightImpact()
            onOpenSettlement?()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "banknote")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.brandPrimary.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.captionMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(AppTypography.chipRegular)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, AppSpacing.cardSmall)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(AppColors.brandPrimary.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(AppColors.brandPrimary.opacity(0.12), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private var expenseTabPresentation: String {
        if dayExpenses.isEmpty {
            hasContent ? "prompt" : "empty"
        } else {
            "list"
        }
    }

    @ViewBuilder
    private var journalTabContent: some View {
        Group {
            if hasJournalEntries {
                TripJournalCreekSection(
                    journalDay: selectedJournalDay,
                    trip: trip,
                    selectedDayPhase: selectedDayPhase,
                    isSelectedDayToday: isSelectedDayToday,
                    canEdit: canEdit,
                    currentUserId: currentUserId,
                    isCollaborative: members.count >= 2,
                    weatherItem: journalDayWeatherItem,
                    onEdit: onEditJournal,
                    onToggleHighlight: onToggleHighlight,
                    onToggleFeaturedPhoto: onToggleFeaturedPhoto,
                    onDelete: onDeleteJournal
                )
                    .transition(contentGrowthTransition)
            } else if hasContent {
                TripJournalCreekSection(
                    journalDay: nil,
                    trip: trip,
                    selectedDayPhase: selectedDayPhase,
                    isSelectedDayToday: isSelectedDayToday,
                    canEdit: canEdit,
                    currentUserId: currentUserId,
                    isCollaborative: members.count >= 2,
                    weatherItem: journalDayWeatherItem,
                    onEdit: onEditJournal,
                    onToggleHighlight: onToggleHighlight,
                    onToggleFeaturedPhoto: onToggleFeaturedPhoto,
                    onDelete: onDeleteJournal
                )
            } else {
                tabEmptyState(kind: .journal)
                    .transition(emptyStateExitTransition)
            }
        }
        .animation(AppMotion.animation(AppMotion.normal, reduceMotion: reduceMotion), value: journalTabPresentation)
    }

    private var journalTabPresentation: String {
        if hasJournalEntries { "list" }
        else if hasContent { "prompt" }
        else { "empty" }
    }

    private func triggerItineraryGrowthAnimation() {
        guard !reduceMotion, lastSpineRevealDayIndex != selectedDayIndex else { return }
        lastSpineRevealDayIndex = selectedDayIndex
        itinerarySpineReveal = AppMotion.daySpineInitialScale
        withAnimation(AppMotion.contextSpring) {
            itinerarySpineReveal = 1
        }
    }

    private func tabEmptyState(kind: TripDayEmptyKind, density: TripDayEmptyDensity = .full) -> some View {
        // 空态 canEdit 表示「能否引导去添加」：角色可写 + 旅程未锁定
        let canAdd = canEdit && TripEditPolicy.contentAddOutcome(trip: trip).isAllowed
        let state = TripDayEmptyStateView(
            kind: kind,
            phase: selectedDayPhase,
            canEdit: canAdd,
            dayIndex: selectedDayIndex,
            destinationName: trip.destinationName,
            startDate: TripDateFormatting.date(from: trip.startDate),
            tripStatus: trip.effectiveStatus,
            density: density
        )

        return Group {
            if density == .compact {
                state
                    .padding(.top, AppSpacing.xxs)
            } else {
                // Top-align so 行程 / 日志 / 开支 and all trip stages share the same
                // card origin. Vertical centering made shorter completed cards
                // (no insight / preview) sit noticeably lower in the same box.
                state
                    .frame(maxWidth: .infinity, minHeight: emptyStateMinHeight, alignment: .top)
            }
        }
    }

    private func applySelectedTab(animated _: Bool) {
        // Day page / ticket lists no longer collapse; tab change is only a content swap.
    }

    private var selectedDayDate: Date? {
        guard let startDate = TripDateFormatting.date(from: trip.startDate) else { return nil }
        return dateForDayIndex(selectedDayIndex, startDate: startDate)
    }

    private var journalDayWeatherItem: TripWeatherDisplayItem? {
        guard isSelectedDayToday else { return nil }
        guard case .available(let display) = weatherState else { return nil }
        guard let day = weatherDayGroup else { return display.items.first }
        return display.items.first { $0.date == day.date } ?? display.items.first
    }

    // MARK: - Weather Banner

    /// Synthetic day group for weather display, decoupled from itinerary.
    private var weatherDayGroup: ItineraryDayGroup? {
        guard let startDate = TripDateFormatting.date(from: trip.startDate),
              let dayDate = dateForDayIndex(selectedDayIndex, startDate: startDate)
        else { return nil }
        let f = DateFormatter()
        f.calendar = TracciDateContext.calendar
        f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: dayDate)
        return ItineraryDayGroup(
            id: "weather-\(selectedDayIndex)",
            dayId: "",
            dayIndex: selectedDayIndex,
            date: dateStr,
            nodes: []
        )
    }

    private func dateForDayIndex(_ dayIndex: Int, startDate: Date) -> Date? {
        TracciDateContext.calendar.date(
            byAdding: .day,
            value: dayIndex - 1,
            to: TracciDateContext.startOfBusinessDay(for: startDate)
        )
    }

    /// Whether the selected day index is today.
    private var isSelectedDayToday: Bool {
        guard let startDate = TripDateFormatting.date(from: trip.startDate) else { return false }
        let today = TracciDateContext.today()
        return TracciDateContext.dayIndex(for: today, startDate: startDate) == selectedDayIndex
    }

    /// Quiet meta row — never a competing content card in the creek.
    private var shouldShowWeatherMeta: Bool {
        switch selectedDayPhase {
        case .today, .upcoming:
            switch weatherState {
            case .available, .failed, .loading:
                return true
            case .idle, .unavailable:
                return false
            }
        case .past:
            return false
        }
    }

    @ViewBuilder
    private var weatherMetaLine: some View {
        if let day = weatherDayGroup {
            ItineraryDayWeatherHeader(
                day: day,
                state: weatherState,
                style: .compact,
                onRefresh: onRefreshWeather
            )
            .opacity(0.92)
        }
    }

    // MARK: - Itinerary Section (map + timeline spine)

    private func nodesWithCoordinate(in nodes: [ItineraryNodeItem]) -> [ItineraryNodeItem] {
        nodes.filter { nodeHasCoordinate($0) }
    }

    private func nodeHasCoordinate(_ node: ItineraryNodeItem) -> Bool {
        node.location?.latitude != nil && node.location?.longitude != nil
    }

    private func routeSequence(for node: ItineraryNodeItem, in nodes: [ItineraryNodeItem]) -> Int? {
        guard nodeHasCoordinate(node) else { return nil }
        var sequence = 0
        for candidate in nodes {
            guard nodeHasCoordinate(candidate) else { continue }
            sequence += 1
            if candidate.id == node.id {
                return sequence
            }
        }
        return nil
    }

    private func autoHighlightedRouteNodeId(in nodes: [ItineraryNodeItem], dayDate: String) -> String? {
        nodes.first { node in
            nodeHasCoordinate(node) &&
            ItineraryTimeFormatting.displayStatus(for: node, dayDate: dayDate) == .current
        }?.id
    }

    private func linkToNode(id: String, scroll: Bool) {
        guard isMapInteractionAvailable else { return }
        // Map ↔ stream memory moment: light impact when scrolling the feed into place.
        if scroll {
            AppHaptics.lightImpact()
        } else {
            AppHaptics.selection()
        }
        onLinkNode?(id, scroll)
        if scroll {
            scrollToNodeId = id
        }
    }

    private var isMapInteractionAvailable: Bool {
        isHeroMapVisible || showMapSection
    }

    @ViewBuilder
    private func itinerarySection() -> some View {
        let day = selectedItineraryDay
        let nodes = day?.nodes ?? []
        let coordinatedNodes = nodesWithCoordinate(in: nodes)
        // Map-linked tap is only active when the map section is actually shown.
        let showsMap = showMapSection && !coordinatedNodes.isEmpty
        let usesTimelineRail = showsMap || !nodes.isEmpty
        let showsSpine = usesTimelineRail
        let autoHighlightNodeId = day.map { autoHighlightedRouteNodeId(in: nodes, dayDate: $0.date) } ?? nil

        VStack(alignment: .leading, spacing: 0) {
            mapRouteHead(
                nodes: nodes,
                coordinatedNodes: coordinatedNodes,
                autoHighlightNodeId: autoHighlightNodeId,
                usesTimelineRail: usesTimelineRail
            )

            // A quiet creek-line pause between the route map and the node stream.
            if showsMap && !nodes.isEmpty {
                AppCreekDivider(
                    leadingInset: usesTimelineRail ? TripDetailLayout.timelineContentLeading : 0,
                    trailingInset: 8
                )
                .padding(.top, TripDetailLayout.routeMapToTimelineSpacing)
            }

            if let day {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        let status = ItineraryTimeFormatting.displayStatus(for: node, dayDate: day.date)
                        let sequence = routeSequence(for: node, in: nodes)
                        let isLinked = linkedNodeId == node.id
                        itineraryNodeRow(
                            node: node,
                            status: status,
                            sequence: sequence,
                            isLinked: isLinked,
                            isExecutionFocus: isExecutionFocusNode(node),
                            growthIndex: index
                        )
                        .id(Self.nodeScrollAnchorID(for: node.id))
                    }
                }
                .coordinateSpace(name: Self.nodeReorderCoordinateSpace)
                .onPreferenceChange(ItineraryNodeReorderFramePreferenceKey.self) { frames in
                    nodeReorderFrames = frames
                }
                .padding(.top, showsMap ? AppSpacing.sm : 6)
            }
        }
        .overlay(alignment: .leading) {
            if showsSpine {
                dayRouteSpine(anchorsFromMap: showsMap)
                    .scaleEffect(y: itinerarySpineReveal, anchor: .top)
            }
        }
        .id("day-route-\(selectedDayIndex)")
    }

    private var unifiedCreekSection: some View {
        let day = selectedItineraryDay
        let nodes = day?.nodes ?? []
        let coordinatedNodes = nodesWithCoordinate(in: nodes)
        // Map-linked tap is only active when the map section is actually shown.
        let showsMap = showMapSection && !coordinatedNodes.isEmpty
        let autoHighlightNodeId = day.map { autoHighlightedRouteNodeId(in: nodes, dayDate: $0.date) } ?? nil

        return VStack(alignment: .leading, spacing: 0) {
            mapRouteHead(
                nodes: nodes,
                coordinatedNodes: coordinatedNodes,
                autoHighlightNodeId: autoHighlightNodeId,
                usesTimelineRail: true
            )

            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                ForEach(Array(unifiedItems.enumerated()), id: \.element.id) { index, item in
                    unifiedCreekRow(
                        item,
                        day: day,
                        routeNodes: nodes,
                        growthIndex: index
                    )
                }
            }
            .padding(.top, showsMap ? TripDetailLayout.routeMapToTimelineSpacing : AppSpacing.xs)
        }
        .overlay(alignment: .leading) {
            dayRouteSpine(anchorsFromMap: showsMap)
                .scaleEffect(y: itinerarySpineReveal, anchor: .top)
        }
        .id("unified-day-creek-\(selectedDayIndex)")
    }

    @ViewBuilder
    private func unifiedCreekRow(
        _ item: TripDayCreekItem,
        day: ItineraryDayGroup?,
        routeNodes: [ItineraryNodeItem],
        growthIndex: Int
    ) -> some View {
        switch item {
        case .itinerary(let node):
            let status = day.map { ItineraryTimeFormatting.displayStatus(for: node, dayDate: $0.date) } ?? .upcoming
            let sequence = routeSequence(for: node, in: routeNodes)
            itineraryNodeRow(
                node: node,
                status: status,
                sequence: sequence,
                isLinked: linkedNodeId == node.id,
                isExecutionFocus: isExecutionFocusNode(node),
                growthIndex: growthIndex
            )
            .id(Self.nodeScrollAnchorID(for: node.id))

        case .journal(let entry):
            unifiedContentRow(markerColor: AppColors.memoryViolet) {
                JournalEntryCard(
                    entry: entry,
                    mood: entry.mood,
                    showsAuthor: members.count >= 2,
                    onEdit: { onEditJournal(entry) },
                    onToggleHighlight: { onToggleHighlight(entry) },
                    onToggleFeaturedPhoto: onToggleFeaturedPhoto,
                    onDelete: { onDeleteJournal(entry) },
                    canManage: TripCreekContentPolicy.canManageJournal(
                        entry,
                        trip: trip,
                        canEdit: canEdit,
                        currentUserId: currentUserId
                    )
                )
            }
            .fadeSlideIn(index: growthIndex, offset: 10, animation: AppMotion.enter, active: false)
            .milestoneEntrance(active: milestoneRowID == item.id)

        case .expense(let expense):
            unifiedContentRow(markerColor: AppColors.dawnGold) {
                ExpenseListItemView(
                    expense: expense,
                    onTap: { onEditExpense(expense) },
                    onDuplicate: canEdit ? { onDuplicateExpense?(expense) } : nil,
                    onDelete: { onDeleteExpense(expense) },
                    canManage: TripCreekContentPolicy.canManageExpense(
                        trip: trip,
                        canEdit: canEdit
                    ),
                    linkedTitle: expense.linkedTitle(in: itineraryGroups.flatMap(\.nodes)),
                    members: members
                )
            }
            .fadeSlideIn(index: growthIndex, offset: 10, animation: AppMotion.enter, active: false)
            .milestoneEntrance(active: milestoneRowID == item.id)
        }
    }

    private func unifiedContentRow<Content: View>(
        markerColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: TripDetailLayout.timelineDotSpacing) {
            Circle()
                .fill(markerColor)
                .overlay {
                    Circle().stroke(AppColors.cardBackground, lineWidth: 2)
                }
                .frame(width: 10, height: 10)
                .frame(width: timelineGutterWidth, alignment: .center)
                .padding(.top, timelineDotTopInset)
                .accessibilityHidden(true)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func reorderableNodeCard(
        node: ItineraryNodeItem,
        status: ItineraryNodeDisplayStatus,
        sequence: Int?,
        isLinked: Bool,
        isExecutionFocus: Bool
    ) -> some View {
        let card = HStack(alignment: .center, spacing: AppSpacing.xs) {
            if isNodeReorderMode {
                Image(systemName: "line.3.horizontal")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .gesture(nodeReorderDragGesture(for: node.id))
                    .accessibilityLabel("拖动排序")
                    .accessibilityHint("上下拖动以调整当天顺序")
                    .accessibilityAdjustableAction { direction in
                        moveNodeForAccessibility(nodeId: node.id, direction: direction)
                    }
            }

            // 已结束旅程的节点：仅允许编辑备注，结构与时间锁定。
            let noteOnly = trip.effectiveStatus == .completed
            ItineraryNodeCard(
                node: node,
                status: status,
                style: .timeline,
                isRouteLinked: isLinked && !isNodeReorderMode,
                isExecutionFocus: isExecutionFocus && !isNodeReorderMode,
                onOpenPlaceDetail: node.location?.placeId == nil ? nil : { onOpenNodePlace(node) },
                onEdit: { noteOnly ? onEditNodeNote(node) : onEditNode(node) },
                onAddExpense: (canEdit && !noteOnly) ? { onAddExpenseForNode?(node) } : nil,
                onDelete: { onDeleteNode(node) },
                allowsLongPressActions: canEdit && !isNodeReorderMode
                    && TripEditPolicy.allowsContentInteraction(trip: trip),
                allowsTapInteraction: !isNodeReorderMode,
                noteOnly: noteOnly
            )
        }

        card
    }

    private func nodeReorderDragGesture(for nodeId: String) -> some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(Self.nodeReorderCoordinateSpace)
        )
        .onChanged { value in
            guard isNodeReorderMode,
                  let sourceFrame = nodeReorderFrames[nodeId]
            else { return }

            if draggedNodeId != nodeId {
                draggedNodeId = nodeId
                lastReorderTargetNodeId = nodeId
                dragTouchOffsetY = value.startLocation.y - sourceFrame.midY
            }

            let centerY = value.location.y - (dragTouchOffsetY ?? 0)
            draggedNodeCenterY = centerY
            updateNodeReorderTarget(sourceId: nodeId, draggedCenterY: centerY)
        }
        .onEnded { _ in
            if reduceMotion {
                clearNodeDragState()
            } else {
                withAnimation(AppMotion.quick) {
                    clearNodeDragState()
                }
            }
        }
    }

    private func updateNodeReorderTarget(sourceId: String, draggedCenterY: CGFloat) {
        let orderedNodeIds = selectedItineraryDay?.nodes.map(\.id) ?? []
        guard let targetId = orderedNodeIds.first(where: { nodeId in
            nodeReorderFrames[nodeId]?.contains(
                CGPoint(x: nodeReorderFrames[nodeId]?.midX ?? 0, y: draggedCenterY)
            ) == true
        }) else { return }

        guard targetId != lastReorderTargetNodeId else { return }
        lastReorderTargetNodeId = targetId
        guard targetId != sourceId else { return }

        if reduceMotion {
            onMoveNode?(sourceId, targetId)
        } else {
            withAnimation(AppMotion.quick) {
                onMoveNode?(sourceId, targetId)
            }
        }
        AppHaptics.selection()
    }

    private func nodeReorderOffset(for nodeId: String) -> CGFloat {
        guard draggedNodeId == nodeId,
              let draggedNodeCenterY,
              let frame = nodeReorderFrames[nodeId]
        else { return 0 }
        return draggedNodeCenterY - frame.midY
    }

    private func moveNodeForAccessibility(
        nodeId: String,
        direction: AccessibilityAdjustmentDirection
    ) {
        let orderedNodeIds = selectedItineraryDay?.nodes.map(\.id) ?? []
        guard let sourceIndex = orderedNodeIds.firstIndex(of: nodeId) else { return }

        let targetIndex: Int
        switch direction {
        case .increment:
            targetIndex = sourceIndex + 1
        case .decrement:
            targetIndex = sourceIndex - 1
        @unknown default:
            return
        }

        guard orderedNodeIds.indices.contains(targetIndex) else { return }
        onMoveNode?(nodeId, orderedNodeIds[targetIndex])
        AppHaptics.selection()
    }

    private func clearNodeDragState() {
        draggedNodeId = nil
        lastReorderTargetNodeId = nil
        draggedNodeCenterY = nil
        dragTouchOffsetY = nil
    }

    @ViewBuilder
    private func itineraryNodeRow(
        node: ItineraryNodeItem,
        status: ItineraryNodeDisplayStatus,
        sequence: Int?,
        isLinked: Bool,
        isExecutionFocus: Bool,
        growthIndex: Int
    ) -> some View {
        let isNewlyCreated = node.id == newlyCreatedNodeId
        let row = HStack(alignment: .top, spacing: TripDetailLayout.timelineDotSpacing) {
            Button {
                guard !isNodeReorderMode, isMapInteractionAvailable, sequence != nil else { return }
                linkToNode(id: node.id, scroll: false)
            } label: {
                timelineDot(
                    status: status,
                    routeSequence: sequence,
                    isLinked: isLinked,
                    isExecutionFocus: isExecutionFocus
                )
            }
            .buttonStyle(.plain)
            .disabled(isNodeReorderMode || !isMapInteractionAvailable || sequence == nil)
            .accessibilityLabel(
                sequence.map {
                    isMapInteractionAvailable ? "第 \($0) 站，定位到地图" : "第 \($0) 站"
                } ?? "无坐标站点"
            )

            reorderableNodeCard(
                node: node,
                status: status,
                sequence: sequence,
                isLinked: isLinked,
                isExecutionFocus: isExecutionFocus
            )
        }
        .fadeSlideIn(
            index: growthIndex,
            offset: growthIndex == 0 ? 14 : 10,
            animation: AppMotion.enter,
            active: false
        )
        .milestoneEntrance(active: isNewlyCreated)

        if isNodeReorderMode {
            ZStack {
                row
                    .offset(y: nodeReorderOffset(for: node.id))
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ItineraryNodeReorderFramePreferenceKey.self,
                        value: [
                            node.id: proxy.frame(
                                in: .named(Self.nodeReorderCoordinateSpace)
                            )
                        ]
                    )
                }
            }
            .zIndex(draggedNodeId == node.id ? 10 : 0)
        } else {
            row
        }
    }

    @ViewBuilder
    private func feedContentRow<Content: View>(
        usesTimelineRail: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if usesTimelineRail {
            HStack(alignment: .top, spacing: TripDetailLayout.timelineDotSpacing) {
                Color.clear
                    .frame(width: timelineGutterWidth)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func mapRouteHead(
        nodes: [ItineraryNodeItem],
        coordinatedNodes: [ItineraryNodeItem],
        autoHighlightNodeId: String?,
        usesTimelineRail: Bool
    ) -> some View {
        Group {
            if showMapSection {
                feedContentRow(usesTimelineRail: usesTimelineRail) {
                    Group {
                        if !coordinatedNodes.isEmpty {
                            TripDayMapSection(
                                nodes: coordinatedNodes,
                                focusedNodeId: linkedNodeId,
                                autoHighlightNodeId: autoHighlightNodeId,
                                onSelectNode: { linkToNode(id: $0, scroll: true) },
                                onNavigateToNode: onNavigateToNode,
                                isExpanded: $isMapExpanded,
                                compactHeight: compactMapHeight,
                                expandedHeight: expandedMapHeight
                            )
                        } else if !nodes.isEmpty {
                            mapCoordinateEmptyHint
                        }
                    }
                    .padding(.bottom, coordinatedNodes.isEmpty ? 0 : 4)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var mapCoordinateEmptyHint: some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Image(systemName: "map")
                .font(TripDetailTypography.inlineIcon)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.top, 1)

            Text("补充地点坐标后，会在这里显示当天路线。")
                .font(TripDetailTypography.caption)
                .foregroundStyle(AppColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

// MARK: - Timeline Components

    /// Journey-stage spine: planning = dashed blueprint; ongoing = solid creek;
    /// completed = warm archive fade. Keeps one visual language across the feed.
    private func dayRouteSpine(anchorsFromMap: Bool) -> some View {
        Group {
            switch trip.effectiveStatus {
            case .planning:
                GeometryReader { proxy in
                    Path { path in
                        let x = timelineGutterWidth / 2
                        path.move(to: CGPoint(x: x, y: 4))
                        path.addLine(to: CGPoint(x: x, y: max(proxy.size.height, 8)))
                    }
                    .stroke(
                        AppColors.stagePlanning.opacity(anchorsFromMap ? 0.52 : 0.40),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 5])
                    )
                }
                .frame(width: timelineGutterWidth)
                .frame(maxHeight: .infinity, alignment: .top)

            case .completed:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.stageCompleted.opacity(0.38),
                                AppColors.stageCompleted.opacity(0.22),
                                AppColors.dawnGold.opacity(0.10),
                                AppColors.borderDefault.opacity(0.14),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .offset(x: timelineGutterWidth / 2 - 0.5, y: 4)

            default:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: anchorsFromMap
                                ? [
                                    AppColors.stageOngoing.opacity(0.42),
                                    AppColors.stageOngoing.opacity(0.22),
                                    AppColors.stageOngoing.opacity(0.10),
                                    AppColors.borderDefault.opacity(0.28),
                                    AppColors.borderDefault.opacity(0.12),
                                    .clear
                                ]
                                : [
                                    AppColors.stageOngoing.opacity(0.30),
                                    AppColors.borderDefault.opacity(0.34),
                                    AppColors.borderDefault.opacity(0.14),
                                    .clear
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .offset(x: timelineGutterWidth / 2 - 0.5, y: 4)
            }
        }
    }

    private func timelineDot(
        status: ItineraryNodeDisplayStatus,
        routeSequence: Int?,
        isLinked: Bool,
        isExecutionFocus: Bool
    ) -> some View {
        let isStatusHighlighted = status == .current || status == .today
        let isHighlighted = isLinked || isExecutionFocus || isStatusHighlighted
        let isNodeCompleted = status == .completed
        let isBlueprint = trip.effectiveStatus == .planning
        let isMemoryArchive = trip.effectiveStatus == .completed

        let baseColor: Color = {
            if isMemoryArchive { return AppColors.stageCompleted }
            if isBlueprint { return AppColors.stagePlanning }
            if isNodeCompleted { return AppColors.textDisabled }
            return AppColors.stageOngoing
        }()

        return Group {
            // Planning: hollow / open circles read as "to-be-confirmed" blueprint markers.
            if isBlueprint, !isHighlighted {
                ZStack {
                    Circle()
                        .fill(AppColors.paperWarmLight.opacity(0.55))
                    Circle()
                        .stroke(baseColor.opacity(0.48), lineWidth: 1.15)
                    if let routeSequence {
                        Text("\(routeSequence)")
                            .font(TripDetailTypography.timelineSequence)
                            .foregroundStyle(baseColor.opacity(0.78))
                    }
                }
                .frame(
                    width: routeSequence == nil
                        ? TripDetailLayout.timelineHollowDotSize + 2
                        : TripDetailLayout.timelineSequenceDotSize,
                    height: routeSequence == nil
                        ? TripDetailLayout.timelineHollowDotSize + 2
                        : TripDetailLayout.timelineSequenceDotSize
                )
            } else if let routeSequence {
                ZStack {
                    Circle()
                        .fill(
                            isHighlighted
                                ? (isMemoryArchive ? AppColors.stageCompleted : AppColors.stageOngoing)
                                : AppColors.paperWarmLight
                        )
                    Circle()
                        .stroke(
                            baseColor.opacity(isHighlighted ? 0.9 : (isNodeCompleted || isMemoryArchive ? 0.28 : 0.34)),
                            lineWidth: 1
                        )
                    Text("\(routeSequence)")
                        .font(TripDetailTypography.timelineSequence)
                        .foregroundStyle(isHighlighted ? .white : baseColor)
                }
                .frame(
                    width: TripDetailLayout.timelineSequenceDotSize,
                    height: TripDetailLayout.timelineSequenceDotSize
                )
            } else {
                Circle()
                    .stroke(
                        baseColor.opacity(isStatusHighlighted || isExecutionFocus ? 0.55 : 0.24),
                        lineWidth: 1
                    )
                    .frame(
                        width: TripDetailLayout.timelineHollowDotSize,
                        height: TripDetailLayout.timelineHollowDotSize
                    )
            }
        }
        .frame(width: timelineGutterWidth, alignment: .center)
        .padding(.top, timelineDotTopInset)
    }

    /// Timeline soft-highlight for the day's live or next focus node (even when hero is hidden).
    private func isExecutionFocusNode(_ node: ItineraryNodeItem) -> Bool {
        guard let snapshot = executionSnapshot,
              snapshot.focus == .current || snapshot.focus == .next,
              let focusId = snapshot.focusNode?.id
        else { return false }
        return focusId == node.id
    }

    private func dayIndexForExpense(_ expense: Expense) -> Int? {
        guard let spentDate = expense.spentAtDate,
              let startDate = TripDateFormatting.date(from: trip.startDate)
        else { return nil }
        return TracciDateContext.dayIndex(for: spentDate, startDate: startDate)
    }
}
private struct ItineraryNodeReorderFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}
