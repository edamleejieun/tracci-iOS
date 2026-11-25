import SwiftUI

struct ActivityLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: ActivityLogViewModel

    init(
        tripId: String,
        collaborationService: CollaborationService,
        demoLogs: [ActivityLogResp]? = nil
    ) {
        let vm = ActivityLogViewModel(
            tripId: tripId,
            collaborationService: collaborationService
        )
        if let demoLogs {
            vm.applyDemoLogs(demoLogs)
        }
        _viewModel = State(initialValue: vm)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.logs.isEmpty {
                ContentBlockSkeletonView(rowCount: 5, accessibilityLabelText: "正在加载旅程动态")
                    .padding(.horizontal, AppSpacing.pageX)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if let error = viewModel.errorMessage, viewModel.logs.isEmpty {
                ErrorStateView(
                    title: "动态加载失败",
                    message: error,
                    retryTitle: "再试一次"
                ) {
                    Task { await viewModel.loadLogs() }
                }
                .padding(.horizontal, AppSpacing.pageX)
            } else if viewModel.logs.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .navigationTitle("旅程动态")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationBarMinimizeOnScroll()
        .tracciNavigationSubpage()
        .task {
            await viewModel.loadLogs()
        }
        .onChange(of: viewModel.logs) { _, newValue in
            if !newValue.isEmpty { AppHaptics.lightImpact() }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AppColors.cardBackground)
                    .frame(width: 88, height: 88)
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppTypography.emptyIcon)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
            VStack(spacing: AppSpacing.tight) {
                Text("还没有旅程动态")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("行程、开支和旅行日志发生变化后\n会在这里留下清晰记录")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(groupedLogs.enumerated()), id: \.element.date) { groupIndex, group in
                    sectionHeader(group.date)

                    ForEach(Array(group.logs.enumerated()), id: \.element.id) { entryIndex, log in
                        let globalIndex = groupedLogs.prefix(groupIndex).reduce(0) { $0 + $1.logs.count } + entryIndex
                        ActivityLogRow(
                            log: log,
                            isLastInGroup: entryIndex == group.logs.count - 1
                        )
                        .padding(.horizontal, AppSpacing.pageX)
                        .fadeSlideIn(index: globalIndex)
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func sectionHeader(_ date: String) -> some View {
        HStack {
            Text(date)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.top, AppSpacing.cozy)
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Grouping

    private var groupedLogs: [(date: String, logs: [ActivityLogResp])] {
        var groups: [(date: String, logs: [ActivityLogResp])] = []
        var currentDate = ""

        for log in viewModel.logs {
            let dateKey = Self.displayDate(log.createdAt)
            if dateKey != currentDate {
                currentDate = dateKey
                groups.append((dateKey, [log]))
            } else {
                groups[groups.count - 1].logs.append(log)
            }
        }

        return groups
    }

    private static func displayDate(_ dateString: String?) -> String {
        guard let dateString,
              let date = ISO8601DateFormatter.parse(dateString)
        else {
            return "未知日期"
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter.string(from: date)
    }
}

// MARK: - Activity Log Row

private struct ActivityLogRow: View {
    let log: ActivityLogResp
    let isLastInGroup: Bool

    private let timelineWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline rail (avatar + connector)
            VStack(spacing: 0) {
                // Avatar dot
                Circle()
                    .fill(MemberPalette.background(for: log.actor.userId))
                    .frame(width: timelineWidth, height: timelineWidth)
                    .overlay {
                        Text(String(log.actor.nickname.prefix(1)))
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(MemberPalette.color(for: log.actor.userId))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // Action type badge
                        actionBadge
                            .offset(x: 2, y: 2)
                    }

                // Vertical connector line to next entry
                if !isLastInGroup {
                    Rectangle()
                        .fill(MemberPalette.color(for: log.actor.userId).opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 8)
                }
            }
            .frame(width: timelineWidth)

            Spacer().frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Actor + action summary
                Text(formattedAction)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineSpacing(2)

                // Field changes — narrative prose style
                if !visibleChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(visibleChanges.indices, id: \.self) { index in
                            narrativeChange(visibleChanges[index])
                        }
                    }
                    .padding(AppSpacing.cozy)
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                }

                // Timestamp row
                HStack(spacing: AppSpacing.tight) {
                    Text(Self.displayTime(log.createdAt))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)

                    if let relative = Self.relativeTime(log.createdAt) {
                        Text("·")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textDisabled)
                        Text(relative)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }
                }
            }
            .padding(.bottom, isLastInGroup ? 6 : 14)

            Spacer()
        }
    }

    // MARK: - Action Badge

    private var actionBadge: some View {
        let (icon, color) = actionBadgeInfo
        return Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay {
                Image(systemName: icon)
                    .font(AppFont.system(8, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle().stroke(.white, lineWidth: 1.5)
            }
    }

    private var actionBadgeInfo: (String, Color) {
        switch log.action {
        case "CREATE":
            return ("plus", AppColors.success)
        case "DELETE":
            return ("minus", AppColors.danger)
        default:
            return ("pencil", AppColors.brandPrimary)
        }
    }

    // MARK: - Formatted Text

    private var formattedAction: String {
        let nickname = log.actor.nickname
        let summary = log.summary
        return "\(nickname) \(summary)"
    }

    private var visibleChanges: [ActivityFieldChangePresentation] {
        log.fieldChanges.compactMap(\.activityPresentation)
    }

    // MARK: - Narrative Change

    @ViewBuilder
    private func narrativeChange(_ change: ActivityFieldChangePresentation) -> some View {
        switch change {
        case let .transition(label, oldValue, newValue):
            HStack(spacing: 0) {
                Text(label)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textSecondary)
                Text("：")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textDisabled)
                Text(oldValue)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textDisabled)
                    .strikethrough()
                Text(" → ")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                Text(newValue)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .lineLimit(2)
        case let .message(message):
            Text(message)
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
        }
    }

    // MARK: - Time Helpers

    private static func displayTime(_ dateString: String?) -> String {
        guard let dateString,
              let date = ISO8601DateFormatter.parse(dateString)
        else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func relativeTime(_ dateString: String?) -> String? {
        guard let dateString,
              let date = ISO8601DateFormatter.parse(dateString)
        else {
            return nil
        }

        let interval = Date().timeIntervalSince(date)
        if interval < 0 { return nil }

        let seconds = Int(interval)
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)小时前" }
        let days = hours / 24
        if days < 7 { return "\(days)天前" }
        return nil
    }
}

// MARK: - ISO8601 Helper

private extension ISO8601DateFormatter {
    /// Try parsing ISO8601 strings: standard, fractional seconds, then DateFormatter fallback.
    static func parse(_ string: String) -> Date? {
        // 1. Standard ISO8601: 2026-06-16T12:00:00Z
        if let date = ISO8601DateFormatter().date(from: string) {
            return date
        }
        // 2. With fractional seconds: 2026-06-16T12:00:00.000Z
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        // 3. DateFormatter fallback
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: string)
    }
}
