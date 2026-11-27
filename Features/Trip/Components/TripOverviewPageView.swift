import SwiftUI

// MARK: - 总览页

/// 旅程总览 Tab 内容 — 仅展示每日行程总览（按天节点列表）。
///
/// 数据全部来自已加载的 `ItineraryViewModel.groupedNodes`，不发起新请求。
/// 页面贡献自然内容高度，由旅程详情的唯一纵向 ScrollView 统一滚动。
struct TripOverviewPageView: View {
    let groupedNodes: [ItineraryDayGroup]
    let totalDays: Int
    let tripStartDate: String
    let onSelectDay: (Int) -> Void

    var body: some View {
        TripDailyOverviewSection(
            groupedNodes: groupedNodes,
            totalDays: totalDays,
            tripStartDate: tripStartDate,
            onSelectDay: { dayIndex in
                AppHaptics.selection()
                onSelectDay(dayIndex)
            }
        )
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - 每日行程总览

/// 按天展示全部行程节点。每天一段：天头（可点跳）+ 有节点时展开列表。
/// 空天只保留可跳转的天头，不重复「0 站 / 还没安排」类文案。
private struct TripDailyOverviewSection: View {
    let groupedNodes: [ItineraryDayGroup]
    let totalDays: Int
    let tripStartDate: String
    let onSelectDay: (Int) -> Void

    private var scheduledDayCount: Int {
        groupedNodes.filter { !$0.nodes.isEmpty }.count
    }

    private var totalNodeCount: Int {
        groupedNodes.reduce(0) { $0 + $1.nodes.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            sectionHeader
                .padding(.horizontal, TripDetailLayout.pageInset)

            VStack(spacing: AppSpacing.tight) {
                ForEach(1...max(totalDays, 1), id: \.self) { dayIndex in
                    dayCard(dayIndex)
                }
            }
        }
        .padding(.top, AppSpacing.xs)
    }

    /// 工具向区头：功能名 + 事实密度，无文艺句。
    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text("每日行程")
                .font(AppTypography.sectionEyebrow)
                .tracking(0.6)
                .foregroundStyle(AppColors.textMuted)

            Spacer(minLength: 8)

            Text(headerMeta)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }

    private var headerMeta: String {
        let days = max(totalDays, 1)
        if totalNodeCount > 0 {
            return "共 \(days) 天 · \(totalNodeCount) 站"
        }
        return "共 \(days) 天"
    }

    private func dayCard(_ dayIndex: Int) -> some View {
        let group = groupedNodes.first { $0.dayIndex == dayIndex }
        // 按开始时间升序展示，无时间的排最后。
        let nodes = group?.nodes.sorted { $0.overviewSortKey < $1.overviewSortKey } ?? []
        let dateString = group?.date ?? dateString(for: dayIndex)
        let isToday = TripDayRail.isToday(dayIndex: dayIndex, tripStartDate: tripStartDate)
        let hasNodes = !nodes.isEmpty

        return Button {
            onSelectDay(dayIndex)
        } label: {
            AppElevationCard(
                level: isToday ? .l1 : .l0,
                role: .content,
                radius: AppRadius.medium,
                padding: 0,
                showsBorder: true
            ) {
                HStack(alignment: .top, spacing: 0) {
                    // 左侧细条：有内容 / 今天 略强调，空天更轻。
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(dayAccentColor(isToday: isToday, hasNodes: hasNodes))
                        .frame(width: 3)
                        .padding(.vertical, 10)

                    VStack(alignment: .leading, spacing: 0) {
                        dayHeader(
                            dayIndex,
                            dateString: dateString,
                            nodeCount: nodes.count,
                            isToday: isToday
                        )
                        .padding(.horizontal, AppSpacing.cardSmall)
                        .padding(.vertical, AppSpacing.cozy)

                        if hasNodes {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                                    nodeRow(node)
                                    if index < nodes.count - 1 {
                                        AppCreekDivider()
                                            .padding(.leading, AppSpacing.cardSmall)
                                    }
                                }
                            }
                            .padding(.bottom, AppSpacing.cozy)
                        }
                    }
                }
            }
            .padding(.horizontal, TripDetailLayout.pageInset)
            .opacity(hasNodes || isToday ? 1 : 0.88)
        }
        .buttonStyle(PressableCardStyle(scale: 0.99, opacity: 0.94))
        .frame(minHeight: AppControlMetrics.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dayAccessibilityLabel(dayIndex, dateString: dateString, nodeCount: nodes.count, isToday: isToday))
        .accessibilityHint("点按跳转到这一天的行程")
        .accessibilityAddTraits(.isButton)
    }

    private func dayAccentColor(isToday: Bool, hasNodes: Bool) -> Color {
        if isToday { return AppColors.brandPrimary.opacity(0.85) }
        if hasNodes { return AppColors.brandPrimary.opacity(0.28) }
        return AppColors.borderSubtle.opacity(0.55)
    }

    private func dayHeader(
        _ dayIndex: Int,
        dateString: String?,
        nodeCount: Int,
        isToday: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.tight) {
            Text("第 \(dayIndex) 天")
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()

            if isToday {
                Text("今天")
                    .font(TripDetailTypography.dayBadge)
                    .foregroundStyle(AppColors.interactiveText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColors.brandPrimaryBackground)
                    .clipShape(Capsule())
            }

            if let dateString, !dateString.isEmpty {
                Text(ItineraryTimeFormatting.weekday(dateString))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                Text(ItineraryTimeFormatting.displayDate(dateString))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .monospacedDigit()
            }

            // Only surface count when there is content — empty days stay quiet.
            if nodeCount > 0 {
                Text("\(nodeCount) 站")
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.subtleBackground.opacity(0.9))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(TripDetailTypography.microChevron)
                .foregroundStyle(AppColors.textPlaceholder)
                .accessibilityHidden(true)
        }
    }

    /// Resolve calendar date for empty days that have no itinerary group yet.
    private func dateString(for dayIndex: Int) -> String? {
        guard let start = TripDateFormatting.date(from: tripStartDate) else { return nil }
        let day = TracciDateContext.calendar.date(
            byAdding: .day,
            value: dayIndex - 1,
            to: TracciDateContext.startOfBusinessDay(for: start)
        )
        return day.map(TripDateFormatting.apiString(from:))
    }

    private func nodeRow(_ node: ItineraryNodeItem) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            // 时间列
            Group {
                if let startTime = node.startTime, !startTime.isEmpty {
                    Text(startTime)
                        .font(TripDetailTypography.nodeMetaMedium)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(TripDetailTypography.nodeMetaMedium)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayTitle)
                    .font(TripDetailTypography.nodeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let place = node.locationName, !place.isEmpty {
                    Text(place)
                        .font(TripDetailTypography.nodeMeta)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppSpacing.cardSmall)
        .padding(.vertical, AppSpacing.tight)
    }

    private func dayAccessibilityLabel(
        _ dayIndex: Int,
        dateString: String?,
        nodeCount: Int,
        isToday: Bool
    ) -> String {
        var parts: [String] = []
        if isToday { parts.append("今天") }
        parts.append("第 \(dayIndex) 天")
        if let dateString, !dateString.isEmpty {
            let weekday = ItineraryTimeFormatting.weekday(dateString)
            let date = ItineraryTimeFormatting.displayDate(dateString)
            if !weekday.isEmpty { parts.append(weekday) }
            parts.append(date)
        }
        if nodeCount > 0 {
            parts.append("\(nodeCount) 个行程点")
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - 节点排序（按开始时间）

private extension ItineraryNodeItem {
    /// 用于总览列表的排序键：有开始时间的按时间升序，无时间的排最后。
    var overviewSortKey: Int {
        ItineraryTimeFormatting.minutes(from: startTime) ?? Int.max
    }
}

#if DEBUG
@MainActor
private struct TripOverviewPagePreview: View {
    var body: some View {
        ScrollView {
            TripOverviewPageView(
                groupedNodes: [],
                totalDays: 3,
                tripStartDate: "2026-08-01",
                onSelectDay: { _ in }
            )
        }
        .tracciAtmosphere(.paper)
    }
}

#Preview("总览页 · 空数据") {
    TripOverviewPagePreview()
}
#endif
