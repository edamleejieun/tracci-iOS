import SwiftUI
import TracciNetworking

// MARK: - Editorial entry (optional compact row; detail uses title-line entry)

/// Compact insight entry row — kept for reuse; detail workspace uses “洞察 ›”.
struct TripInsightEntryRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isLoading: Bool = false
    var showsSoftDot: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(TripDetailTypography.inlineIcon)
                        .foregroundStyle(AppColors.brandPrimary.opacity(0.88))
                        .frame(width: 22, height: 22)

                    if showsSoftDot, !isLoading {
                        Circle()
                            .fill(AppColors.brandPrimary)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -2)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.editorialMeta)
                        .tracking(0.45)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: AppSpacing.xs) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(AppColors.textMuted)
                        }
                        Text(subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(TripDetailTypography.microChevron)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle(scale: 0.99, opacity: 0.92))
        .frame(minHeight: AppControlMetrics.minimumTapTarget)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Insight Sheet workspace

/// Journey insight sheet body.
///
/// Skeleton (top → bottom):
/// 1. Light header — meta line + one conclusion (no stacked scene/insight)
/// 2. Evidence — non-zero facts + lightweight chart enrichment
/// 3. Primary action (0–1)
/// 4. Soft suggestion (ongoing only) — journal / expense CTAs + snooze
struct TripInsightWorkspaceSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var viewModel: TripInsightViewModel
    let onSelectDate: (String) -> Void
    let onAddJournal: (String?) -> Void
    /// Add an expense for the suggestion date (or today when nil). Insight evidence includes spend.
    let onAddExpense: (String?) -> Void
    let onOpenMemory: () -> Void
    var usesPageInset: Bool = true
    /// Expense create is not in stage-overview permissions; parent gates via trip role.
    var canAddExpense: Bool = true
    /// When false, hide suggestion snooze / “稍后再说” (Demo read-only).
    var allowsSuggestionDismiss: Bool = true
    var tripNodeCount: Int = 0
    var tripJournalCount: Int = 0
    var tripExpenseText: String = "¥0"

    /// Chart band stays secondary enrichment — short enough not to dominate the sheet.
    private let chartBandHeight: CGFloat = 44
    private let chartBarMaxHeight: CGFloat = 30

    var body: some View {
        Group {
            if viewModel.isLoading, viewModel.overview == nil {
                loadingSkeleton
                    .tracciRevealTransition(reduceMotion: reduceMotion)
            } else if let overview = viewModel.overview {
                contentStack(overview)
                    .tracciRevealTransition(reduceMotion: reduceMotion)
            } else if let errorMessage = viewModel.errorMessage {
                errorCard(errorMessage)
                    .tracciRevealTransition(reduceMotion: reduceMotion)
            }
        }
        .animation(
            AppMotion.animation(AppMotion.skeletonReveal, reduceMotion: reduceMotion),
            value: viewModel.isLoading && viewModel.overview == nil
        )
        .padding(.horizontal, usesPageInset ? TripDetailLayout.pageInset : 0)
        .padding(.top, usesPageInset ? AppSpacing.cardSmall : 0)
    }

    // MARK: - Stack

    private func contentStack(_ overview: TripStageOverview) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            insightHeader

            evidenceSection(overview)

            if let primary = primaryAction(for: overview) {
                primaryActionButton(primary)
            }

            if overview.phase == .ongoing,
               let suggestion = viewModel.activeSuggestion {
                let canJournal = overview.permissions?.canAddJournal == true
                    && suggestion.action == "ADD_MEMORY"
                    && allowsSuggestionDismiss
                suggestionCard(
                    suggestion,
                    canAddJournal: canJournal,
                    canAddExpense: canAddExpense && allowsSuggestionDismiss
                )
            }
        }
    }

    // MARK: - 1. Light header (one conclusion)

    private var insightHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(viewModel.headerMetaLine)
                .font(AppTypography.editorialMeta)
                .tracking(0.5)
                .foregroundStyle(AppColors.textMuted)

            if let conclusion = viewModel.companionConclusion {
                Text(conclusion)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.cardSmall)
        .padding(.vertical, AppSpacing.card)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .fill(AppColors.paperWarmLight.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppColors.borderSubtle.opacity(0.4), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2. Evidence

    @ViewBuilder
    private func evidenceSection(_ overview: TripStageOverview) -> some View {
        switch overview.phase {
        case .planning:
            if let planning = overview.planning {
                evidenceCard(title: "安排节奏") {
                    factMetaRow(planningFacts(planning))

                    if !planning.dailyNodeCounts.isEmpty {
                        densityBars(planning.dailyNodeCounts, unplanned: Set(planning.unplannedDates))
                            .padding(.top, AppSpacing.sm)
                    }

                    if let weatherNote = viewModel.planningWeatherNote {
                        Label(weatherNote, systemImage: "cloud.sun")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                            .padding(.top, AppSpacing.sm)
                    }
                }
            }

        case .ongoing:
            evidenceCard(title: "概况") {
                factMetaRow(tripTotalsFacts)

                if let ongoing = overview.ongoing {
                    if !tripTotalsFacts.isEmpty {
                        AppCreekDivider()
                            .padding(.vertical, AppSpacing.sm)
                    }

                    StatsRhythmDots(
                        itineraryCount: ongoing.today.itineraryCount,
                        journalCount: ongoing.today.journalCount,
                        photoCount: ongoing.today.photoCount,
                        expenseText: viewModel.ongoingExpenseText,
                        showsCard: false,
                        title: "今天"
                    )
                }
            }

        case .completed:
            if let completed = overview.completed {
                evidenceCard(title: "花费与记录") {
                    evidenceGrid(completedFacts(completed, memory: overview.memory))

                    if hasSpendTrend(completed.dailyTrend) {
                        spendBars(completed.dailyTrend)
                            .padding(.top, AppSpacing.sm)
                    } else if !completed.dailyTrend.isEmpty {
                        footprintBars(completed.dailyTrend)
                            .padding(.top, AppSpacing.sm)
                    }

                    if !completed.categoryStats.isEmpty {
                        categoryBars(completed.categoryStats)
                            .padding(.top, AppSpacing.sm)
                    }
                }
            }

        case .noTrip:
            EmptyView()
        }
    }

    private func evidenceCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: AppSpacing.cardSmall) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.editorialMeta)
                    .tracking(0.5)
                    .foregroundStyle(AppColors.textMuted)
                content()
            }
        }
    }

    // MARK: Fact meta row (no nested mini-cards; zeros stay silent)

    private struct InsightFact: Identifiable {
        let label: String
        let value: String
        var id: String { label + value }
    }

    private func planningFacts(_ planning: TripStagePlanning) -> [InsightFact] {
        var facts: [InsightFact] = []
        if planning.totalDays > 0 {
            facts.append(InsightFact(label: "天", value: "\(planning.totalDays)"))
        }
        if planning.density.nodeCount > 0 {
            facts.append(InsightFact(label: "行程点", value: "\(planning.density.nodeCount)"))
        }
        let unplanned = planning.unplannedDates.count
        if unplanned > 0 {
            facts.append(InsightFact(label: "待安排", value: "\(unplanned)"))
        } else if planning.departureDays > 0 {
            facts.append(InsightFact(label: "天后出发", value: "\(planning.departureDays)"))
        }
        return facts
    }

    private var tripTotalsFacts: [InsightFact] {
        var facts: [InsightFact] = []
        if isMeaningfulExpense(tripExpenseText) {
            facts.append(InsightFact(label: "总花费", value: tripExpenseText))
        }
        if tripNodeCount > 0 {
            facts.append(InsightFact(label: "行程", value: "\(tripNodeCount)"))
        }
        if tripJournalCount > 0 {
            facts.append(InsightFact(label: "日志", value: "\(tripJournalCount)"))
        }
        return facts
    }

    private func completedFacts(
        _ completed: TripStageCompleted,
        memory: TripStageMemory?
    ) -> [InsightFact] {
        var facts: [InsightFact] = []
        let expense = expenseText(completed.totalExpenseAmount)
        if expense != "—" {
            facts.append(InsightFact(label: "总花费", value: expense))
        }
        let trendNodes = completed.dailyTrend.map(\.itineraryCount).reduce(0, +)
        let nodes = tripNodeCount > 0 ? tripNodeCount : trendNodes
        if nodes > 0 {
            facts.append(InsightFact(label: "行程点", value: "\(nodes)"))
        }
        let journals = memory?.journalCount ?? tripJournalCount
        let photos = memory?.photoCount ?? 0
        if journals > 0 {
            facts.append(InsightFact(label: "日志", value: "\(journals)"))
        }
        if photos > 0 {
            facts.append(InsightFact(label: "照片", value: "\(photos)"))
        }
        return facts
    }

    @ViewBuilder
    private func factMetaRow(_ facts: [InsightFact]) -> some View {
        if facts.isEmpty {
            EmptyView()
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                ForEach(facts) { fact in
                    factMetaItem(fact)
                }
            }
            .padding(.top, AppSpacing.xs)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    factMetaItem(fact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if index < facts.count - 1 {
                        Rectangle()
                            .fill(AppColors.borderSubtle.opacity(0.45))
                            .frame(width: 1, height: 28)
                    }
                }
            }
            .padding(.top, AppSpacing.xs)
        }
    }

    private func factMetaItem(_ fact: InsightFact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fact.value)
                .font(AppTypography.editorialNumber)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(fact.label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fact.label) \(fact.value)")
    }

    // MARK: Completed evidence grid (big number + quiet label; zeros stay silent)

    /// Completed-state facts read best as a scannable 大数字 + 小标签 grid.
    /// Two flexible columns at normal type sizes; single column for
    /// accessibility sizes. Facts are pre-filtered, so empty renders nothing.
    @ViewBuilder
    private func evidenceGrid(_ facts: [InsightFact]) -> some View {
        if facts.isEmpty {
            EmptyView()
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                ForEach(facts) { fact in
                    evidenceGridItem(fact)
                }
            }
            .padding(.top, AppSpacing.xs)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.cozy, alignment: .leading),
                    GridItem(.flexible(), spacing: AppSpacing.cozy, alignment: .leading)
                ],
                alignment: .leading,
                spacing: AppSpacing.cozy
            ) {
                ForEach(facts) { fact in
                    evidenceGridItem(fact)
                }
            }
            .padding(.top, AppSpacing.xs)
        }
    }

    private func evidenceGridItem(_ fact: InsightFact) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(fact.value)
                .font(AppTypography.evidenceNumber)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(fact.label)
                .font(AppTypography.editorialMeta)
                .tracking(0.5)
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fact.label) \(fact.value)")
    }

    private func isMeaningfulExpense(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—", trimmed != "¥0", trimmed != "¥0.00" else {
            return false
        }
        return true
    }

    // MARK: Lightweight charts (secondary enrichment)

    private func densityBars(
        _ days: [TripStageDailyNodeCount],
        unplanned: Set<String>
    ) -> some View {
        let maxCount = max(days.map(\.nodeCount).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("每日站点数")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days) { day in
                    let isEmpty = day.nodeCount == 0 || unplanned.contains(day.date)
                    Button {
                        AppHaptics.selection()
                        onSelectDate(day.date)
                    } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(
                                    isEmpty
                                        ? AppColors.stagePlanning.opacity(0.2)
                                        : AppColors.stageOngoing.opacity(
                                            0.45 + 0.4 * CGFloat(day.nodeCount) / CGFloat(maxCount)
                                        )
                                )
                                .frame(
                                    height: isEmpty
                                        ? 5
                                        : max(8, chartBarMaxHeight * CGFloat(day.nodeCount) / CGFloat(maxCount))
                                )
                            Text("\(day.dayIndex)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textPlaceholder)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("第 \(day.dayIndex) 天，\(day.nodeCount) 站")
                    .accessibilityHint(isEmpty ? "空日，点按跳转安排" : "点按跳转到这一天")
                }
            }
            .frame(height: chartBandHeight, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
    }

    private func hasSpendTrend(_ trend: [TripStageDailyTrend]) -> Bool {
        trend.contains { day in
            guard let amount = ExpenseFormatters.decimal(from: day.expenseAmount) else { return false }
            return amount > 0
        }
    }

    private func spendBars(_ trend: [TripStageDailyTrend]) -> some View {
        let amounts = trend.map { ExpenseFormatters.decimal(from: $0.expenseAmount) ?? 0 }
        let maxAmount = max(amounts.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("每日花费")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(trend.enumerated()), id: \.element.id) { index, day in
                    let amount = amounts[index]
                    let ratio = amount > 0
                        ? cgFloat(amount) / max(cgFloat(maxAmount), 0.01)
                        : 0
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                amount > 0
                                    ? AppColors.dawnGold.opacity(0.4 + 0.4 * ratio)
                                    : AppColors.borderSubtle.opacity(0.4)
                            )
                            .frame(height: amount > 0 ? max(6, chartBarMaxHeight * ratio) : 4)
                        Text("\(day.dayIndex)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPlaceholder)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("第 \(day.dayIndex) 天，花费 \(expenseText(day.expenseAmount))")
                }
            }
            .frame(height: chartBandHeight, alignment: .bottom)
        }
    }

    private func cgFloat(_ value: Decimal) -> CGFloat {
        CGFloat(truncating: value as NSDecimalNumber)
    }

    private func footprintBars(_ trend: [TripStageDailyTrend]) -> some View {
        let maxCount = max(trend.map(\.itineraryCount).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("每日行程")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(trend) { day in
                    let ratio = CGFloat(day.itineraryCount) / CGFloat(maxCount)
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                day.itineraryCount > 0
                                    ? AppColors.stageCompleted.opacity(0.35 + 0.4 * ratio)
                                    : AppColors.borderSubtle.opacity(0.4)
                            )
                            .frame(height: day.itineraryCount > 0 ? max(6, chartBarMaxHeight * ratio) : 4)
                        Text("\(day.dayIndex)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPlaceholder)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("第 \(day.dayIndex) 天，\(day.itineraryCount) 站")
                }
            }
            .frame(height: chartBandHeight, alignment: .bottom)
        }
    }

    private func categoryBars(_ stats: [TripStageExpenseCategory]) -> some View {
        let top = Array(stats.prefix(3))
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("花费构成")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)

            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                ForEach(top) { item in
                    let ratio = categoryRatio(item.percentage)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.categoryName)
                                .font(AppTypography.captionMedium)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(categoryPercentLabel(item.percentage))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textMuted)
                                .monospacedDigit()
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppColors.borderSubtle.opacity(0.45))
                                Capsule()
                                    .fill(categoryColor(for: item.category).opacity(0.72))
                                    .frame(width: max(4, proxy.size.width * ratio))
                            }
                        }
                        .frame(height: 5)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.categoryName) 占比 \(categoryPercentLabel(item.percentage))")
                }
            }
        }
    }

    private func categoryRatio(_ percentage: String) -> CGFloat {
        let cleaned = percentage.replacingOccurrences(of: "%", with: "")
        guard let value = Double(cleaned) else { return 0 }
        return min(max(CGFloat(value / 100), 0), 1)
    }

    private func categoryPercentLabel(_ percentage: String) -> String {
        if percentage.contains("%") { return percentage }
        if let value = Double(percentage) {
            return String(format: "%.0f%%", value)
        }
        return percentage
    }

    private func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case "food", "dining", "restaurant", "meal", "餐饮":
            return AppColors.catFood
        case "hotel", "lodging", "stay", "accommodation", "住宿":
            return AppColors.catHotel
        case "transport", "traffic", "flight", "train", "交通":
            return AppColors.catTransport
        case "ticket", "attraction", "scenic", "activity", "门票", "景点":
            return AppColors.catAttraction
        case "shopping", "retail", "购物":
            return AppColors.catShopping
        default:
            return AppColors.catOther
        }
    }

    // MARK: - 3. Primary action

    private struct PrimaryAction {
        let title: String
        let systemImage: String
        let run: () -> Void
    }

    private func primaryAction(for overview: TripStageOverview) -> PrimaryAction? {
        switch overview.phase {
        case .planning:
            guard let date = overview.planning?.unplannedDates.first else { return nil }
            return PrimaryAction(title: "去安排这一天", systemImage: "arrow.right") {
                onSelectDate(date)
            }
        case .ongoing:
            return nil
        case .completed:
            return PrimaryAction(title: "查看回忆", systemImage: "arrow.up.right") {
                onOpenMemory()
            }
        case .noTrip:
            return nil
        }
    }

    private func primaryActionButton(_ action: PrimaryAction) -> some View {
        Button {
            AppHaptics.selection()
            action.run()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(action.title)
                    .font(AppTypography.buttonTitleMedium)
                Spacer(minLength: 8)
                Image(systemName: action.systemImage)
                    .font(AppTypography.captionSemibold)
            }
            .foregroundStyle(AppColors.brandPrimary)
            .padding(.horizontal, AppSpacing.card)
            .frame(maxWidth: .infinity, minHeight: AppControlMetrics.minimumTapTarget)
            .background(
                AppColors.brandPrimaryBackground.opacity(0.92),
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(AppColors.brandPrimary.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(PressableCardStyle(scale: 0.985, opacity: 0.94))
        .accessibilityLabel(action.title)
    }

    // MARK: - 4. Suggestion (ongoing) — journal / expense CTAs, snooze separated

    private func suggestionCard(
        _ suggestion: TripStageSuggestion,
        canAddJournal: Bool,
        canAddExpense: Bool
    ) -> some View {
        let prompt: String = {
            switch (canAddJournal, canAddExpense) {
            case (true, true): return "有空可以写日志或记一笔"
            case (true, false): return "有空可以补一条日志"
            case (false, true): return "有空可以记一笔开支"
            case (false, false): return "今天的记录可以稍后再补"
            }
        }()

        return AppElevationCard(level: .l0, role: .utility, radius: AppRadius.medium, padding: AppSpacing.cardSmall) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(prompt)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                suggestionPrimaryActions(
                    suggestion,
                    canAddJournal: canAddJournal,
                    canAddExpense: canAddExpense
                )

                // Secondary dismiss: divider + quieter text, not peer to create CTAs.
                // Demo (and other read-only hosts) hide “稍后再说” entirely.
                if allowsSuggestionDismiss {
                    if canAddJournal || canAddExpense {
                        AppCreekDivider()
                            .padding(.top, AppSpacing.xxs)
                    }

                    Button {
                        AppHaptics.selection()
                        viewModel.snoozeSuggestion(suggestion)
                    } label: {
                        Text("稍后再说")
                            .font(AppTypography.captionMedium)
                            .foregroundStyle(AppColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: AppControlMetrics.minimumTapTarget)
                    .accessibilityLabel("稍后再说")
                    .accessibilityHint("暂时收起这条提示")
                }
            }
            .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: allowsSuggestionDismiss)
        }
    }

    /// Create actions only — journal + expense sit as peers; snooze lives on its own row below.
    @ViewBuilder
    private func suggestionPrimaryActions(
        _ suggestion: TripStageSuggestion,
        canAddJournal: Bool,
        canAddExpense: Bool
    ) -> some View {
        if canAddJournal || canAddExpense {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if canAddJournal {
                        journalCTA(date: suggestion.targetDate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if canAddExpense {
                        expenseCTA(date: suggestion.targetDate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                HStack(spacing: AppSpacing.sm) {
                    if canAddJournal {
                        journalCTA(date: suggestion.targetDate)
                    }
                    if canAddExpense {
                        expenseCTA(date: suggestion.targetDate)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func journalCTA(date: String?) -> some View {
        Button {
            AppHaptics.selection()
            onAddJournal(date)
        } label: {
            Text("写日志")
                .font(AppTypography.captionSemibold)
                .padding(.horizontal, 2)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(AppColors.brandPrimary)
        // Visual is compact; keep ≥44pt hit via padding so taps stay comfortable.
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityLabel("写日志")
    }

    private func expenseCTA(date: String?) -> some View {
        Button {
            AppHaptics.selection()
            onAddExpense(date)
        } label: {
            Text("记一笔")
                .font(AppTypography.captionSemibold)
                .padding(.horizontal, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(AppColors.brandPrimary)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityLabel("记一笔")
        .accessibilityHint("添加一笔开支")
    }

    // MARK: - Loading / error

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .fill(AppColors.borderSubtle.opacity(0.35))
                .frame(height: 72)
                .redacted(reason: .placeholder)

            AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: AppSpacing.cardSmall) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    RoundedRectangle(cornerRadius: AppRadius.pill).frame(width: 64, height: 10)
                    RoundedRectangle(cornerRadius: AppRadius.small).frame(height: 36)
                    RoundedRectangle(cornerRadius: AppRadius.small).frame(height: chartBandHeight)
                }
                .foregroundStyle(AppColors.borderSubtle)
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("正在加载旅程概况")
    }

    private func errorCard(_ message: String) -> some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.large, padding: AppSpacing.cardSmall) {
            HStack(spacing: AppSpacing.cozy) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(AppColors.textMuted)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("重试") { Task { await viewModel.refresh() } }
                    .font(AppTypography.buttonTitleMedium)
            }
        }
    }

    private func expenseText(_ rawValue: String) -> String {
        guard let amount = ExpenseFormatters.decimal(from: rawValue), amount > 0 else { return "—" }
        return ExpenseFormatters.cny(amount)
    }
}

#if DEBUG
private struct TripInsightLoadingPreview: View {
    @State private var viewModel = {
        let apiClient = APIClient()
        let vm = TripInsightViewModel(
            tripId: "preview-trip",
            tripService: TripService(
                apiClient: apiClient,
                fileUploadService: FileUploadService(apiClient: apiClient)
            )
        )
        vm.configureForPreview(isLoading: true)
        return vm
    }()

    var body: some View {
        ScrollView {
            TripInsightWorkspaceSection(
                viewModel: viewModel,
                onSelectDate: { _ in },
                onAddJournal: { _ in },
                onAddExpense: { _ in },
                onOpenMemory: {}
            )
            .padding()
        }
        .tracciAtmosphere(.creek)
    }
}

#Preview("旅程洞察 · 加载中") {
    TripInsightLoadingPreview()
}

/// Completed-state fixtures decoded from JSON — previews never touch the network.
private enum TripInsightPreviewFixtures {
    static func completedOverview(json: String) -> TripStageOverview {
        let data = Data(json.utf8)
        guard let overview = try? JSONDecoder().decode(TripStageOverview.self, from: data) else {
            preconditionFailure("Preview fixture JSON 无法解码为 TripStageOverview，请检查字段是否与 StatsModels 一致")
        }
        return overview
    }

    static let completedFull = """
    {
      "generatedDate": "2026-08-04",
      "timeZone": "Asia/Shanghai",
      "timeZoneFallbackApplied": false,
      "phase": "COMPLETED",
      "focusTrip": {
        "id": "preview-trip",
        "title": "杭州三日",
        "destinationName": "杭州",
        "startDate": "2026-07-20",
        "endDate": "2026-07-22",
        "totalDays": 3
      },
      "permissions": { "canAddJournal": false, "canFeaturePhoto": false },
      "selection": { "mode": "TRIP", "reason": "PREVIEW", "candidateCount": 1 },
      "memory": {
        "journalCount": 2,
        "photoCount": 18,
        "userFeaturedJournalCount": 0,
        "userFeaturedPhotoCount": 0,
        "systemRecommendedPhotoCount": 0,
        "dailyMaterials": [],
        "recentFragments": [],
        "cover": { "available": false, "source": "NONE" },
        "displayableContent": { "sections": [], "presentation": "NONE" }
      },
      "completed": {
        "totalExpenseAmount": "3250.50",
        "averageDailyExpense": "1083.50",
        "currency": "CNY",
        "categoryStats": [
          { "category": "hotel", "categoryName": "住宿", "amount": "1500.00", "percentage": "46%", "count": 2 },
          { "category": "food", "categoryName": "餐饮", "amount": "1200.00", "percentage": "37%", "count": 8 },
          { "category": "transport", "categoryName": "交通", "amount": "550.50", "percentage": "17%", "count": 5 }
        ],
        "dailyTrend": [
          { "date": "2026-07-20", "dayIndex": 1, "itineraryCount": 4, "journalCount": 1, "photoCount": 6, "expenseAmount": "980.00", "paceLevel": "MODERATE" },
          { "date": "2026-07-21", "dayIndex": 2, "itineraryCount": 5, "journalCount": 1, "photoCount": 8, "expenseAmount": "1450.50", "paceLevel": "BUSY" },
          { "date": "2026-07-22", "dayIndex": 3, "itineraryCount": 3, "journalCount": 0, "photoCount": 4, "expenseAmount": "820.00", "paceLevel": "RELAXED" }
        ],
        "pace": { "level": "MODERATE", "busiestDate": "2026-07-21", "busiestDayNodeCount": 5, "ruleVersion": "1" }
      },
      "actions": []
    }
    """

    static let completedSparse = """
    {
      "generatedDate": "2026-08-04",
      "timeZone": "Asia/Shanghai",
      "timeZoneFallbackApplied": false,
      "phase": "COMPLETED",
      "focusTrip": {
        "id": "preview-trip",
        "title": "周末古镇",
        "destinationName": "西塘",
        "startDate": "2026-07-25",
        "endDate": "2026-07-26",
        "totalDays": 2
      },
      "permissions": { "canAddJournal": false, "canFeaturePhoto": false },
      "selection": { "mode": "TRIP", "reason": "PREVIEW", "candidateCount": 1 },
      "memory": {
        "journalCount": 1,
        "photoCount": 0,
        "userFeaturedJournalCount": 0,
        "userFeaturedPhotoCount": 0,
        "systemRecommendedPhotoCount": 0,
        "dailyMaterials": [],
        "recentFragments": [],
        "cover": { "available": false, "source": "NONE" },
        "displayableContent": { "sections": [], "presentation": "NONE" }
      },
      "completed": {
        "totalExpenseAmount": "0",
        "averageDailyExpense": "0",
        "currency": "CNY",
        "categoryStats": [],
        "dailyTrend": [
          { "date": "2026-07-25", "dayIndex": 1, "itineraryCount": 2, "journalCount": 1, "photoCount": 0, "expenseAmount": "0", "paceLevel": "RELAXED" },
          { "date": "2026-07-26", "dayIndex": 2, "itineraryCount": 1, "journalCount": 0, "photoCount": 0, "expenseAmount": "0", "paceLevel": "RELAXED" }
        ],
        "pace": { "level": "RELAXED", "busiestDate": null, "busiestDayNodeCount": 2, "ruleVersion": "1" }
      },
      "actions": []
    }
    """
}

private struct TripInsightCompletedPreview: View {
    let json: String
    let nodeCount: Int
    let journalCount: Int

    @State private var viewModel: TripInsightViewModel

    init(json: String, nodeCount: Int, journalCount: Int) {
        self.json = json
        self.nodeCount = nodeCount
        self.journalCount = journalCount
        _viewModel = State(initialValue: {
            let apiClient = APIClient()
            let vm = TripInsightViewModel(
                tripId: "preview-trip",
                tripService: TripService(
                    apiClient: apiClient,
                    fileUploadService: FileUploadService(apiClient: apiClient)
                )
            )
            let overview = TripInsightPreviewFixtures.completedOverview(json: json)
            vm.applyDemoOverview(overview)
            return vm
        }())
    }

    var body: some View {
        ScrollView {
            TripInsightWorkspaceSection(
                viewModel: viewModel,
                onSelectDate: { _ in },
                onAddJournal: { _ in },
                onAddExpense: { _ in },
                onOpenMemory: {},
                tripNodeCount: nodeCount,
                tripJournalCount: journalCount,
                tripExpenseText: "¥0"
            )
            .padding()
        }
        .tracciAtmosphere(.creekCompleted)
    }
}

#Preview("旅程洞察 · 已结束 · 完整证据") {
    TripInsightCompletedPreview(
        json: TripInsightPreviewFixtures.completedFull,
        nodeCount: 12,
        journalCount: 2
    )
}

#Preview("旅程洞察 · 已结束 · 稀疏数据") {
    TripInsightCompletedPreview(
        json: TripInsightPreviewFixtures.completedSparse,
        nodeCount: 3,
        journalCount: 1
    )
}
#endif
