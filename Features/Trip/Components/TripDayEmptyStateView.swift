import SwiftUI

enum TripDayPhase {
    case today
    case upcoming
    case past
}

/// Empty-state copy for the three day view modes only (行程 / 日志 / 开支).
/// Mixed「全部」overview is no longer a product surface.
enum TripDayEmptyKind {
    case itinerary
    case expense
    case journal

    var systemImage: String {
        switch self {
        case .itinerary: "signpost.right"
        case .expense: "wallet.pass"
        case .journal: "book.pages"
        }
    }
}

// MARK: - Empty-state guidance

extension TripDayEmptyKind {
    /// Eyebrow label for the companion card — stage-tinted when the journey itself differs.
    func eyebrowLabel(tripStatus: TripStatus = .unknown) -> String {
        switch (self, tripStatus) {
        case (.itinerary, .planning): return "行程"
        case (.itinerary, .completed): return "行程"
        case (.itinerary, _): return "行程"
        case (.expense, .completed): return "花费"
        case (.expense, _): return "开支"
        case (.journal, .completed): return "日志"
        case (.journal, .planning): return "备忘"
        case (.journal, _): return "日志"
        }
    }

    /// Companion **scene** line: light narrative + clear status.
    /// Stage (planning / ongoing / completed) × day phase × destination.
    func sceneText(
        destination: String?,
        phase: TripDayPhase,
        tripStatus: TripStatus,
        canEdit: Bool
    ) -> String {
        let place = Self.compactPlace(destination)
        let daySubject = place.map { "\($0)的这一天" } ?? "这一天"
        let todaySubject = place.map { "今天在\($0)" } ?? "今天"

        // 已结束优先于 canEdit：展示锁定文案，避免「只读」泛化句掩盖「已锁定」语义
        if tripStatus == .completed {
            return completedScene(place: place, daySubject: daySubject)
        }

        guard canEdit else {
            switch self {
            case .itinerary: return "\(daySubject)还没有行程安排。"
            case .expense: return "\(daySubject)还没有花费记录。"
            case .journal: return "\(daySubject)还没有日志。"
            }
        }

        // Journey-stage: planning / ongoing
        switch tripStatus {
        case .planning:
            return planningScene(place: place)
        case .completed:
            return completedScene(place: place, daySubject: daySubject)
        case .ongoing, .unknown:
            return ongoingScene(
                place: place,
                phase: phase,
                daySubject: daySubject,
                todaySubject: todaySubject
            )
        }
    }

    /// Backward-compatible alias for call sites / a11y still using supportingText.
    func supportingText(
        destination: String?,
        phase: TripDayPhase,
        canEdit: Bool,
        tripStatus: TripStatus = .unknown
    ) -> String {
        sceneText(
            destination: destination,
            phase: phase,
            tripStatus: tripStatus,
            canEdit: canEdit
        )
    }

    /// Explicitly points to the existing FAB instead of implying a non-existent card action.
    func actionHint(canEdit: Bool, tripStatus: TripStatus = .unknown) -> String? {
        guard canEdit else { return nil }
        // 已结束旅程内容锁定：不再引导去 FAB 补充
        if tripStatus == .completed { return nil }
        switch (self, tripStatus) {
        case (.itinerary, .planning):
            return "点击右下角 +，添加第一站"
        case (.itinerary, _):
            return "点击右下角 + 添加行程"
        case (.expense, .planning):
            return "点击右下角 +，先记一笔预算"
        case (.expense, _):
            return "点击右下角 + 记一笔"
        case (.journal, .planning):
            return "点击右下角 +，写下行前备忘"
        case (.journal, _):
            return "点击右下角 + 写日志"
        }
    }

    // MARK: Scene builders

    private func planningScene(place: String?) -> String {
        switch self {
        case .itinerary:
            if let place {
                return "\(place)这一天的行程还空着，可以先加上想去的地方。"
            }
            return "这一天还没有行程，添加第一站即可。"
        case .expense:
            if let place {
                return "去\(place)之前，可以先记下预计花费，方便心里有数。"
            }
            return "出行前可以先记一笔预算。"
        case .journal:
            if let place {
                return "出发前关于\(place)的想法，可以先写在这里。"
            }
            return "行前备忘可以写在这里，出发时方便查看。"
        }
    }

    private func ongoingScene(
        place: String?,
        phase: TripDayPhase,
        daySubject: String,
        todaySubject: String
    ) -> String {
        switch (self, phase) {
        case (.itinerary, .today):
            return "\(todaySubject)，行程还空着。可以加一个地点。"
        case (.itinerary, .upcoming):
            return "\(daySubject)还没有安排，可以先放好想去的地方。"
        case (.itinerary, .past):
            return "\(daySubject)没有行程记录，需要时可以补上。"
        case (.expense, .today):
            return "\(todaySubject)还没有花费。记一笔，方便回看这一天。"
        case (.expense, .upcoming):
            return "\(daySubject)还没有预计花费，可以提前记一笔。"
        case (.expense, .past):
            return "\(daySubject)还没有花费记录，补记也来得及。"
        case (.journal, .today):
            return "\(todaySubject)还没有日志。一句话或一张照片就很好。"
        case (.journal, .upcoming):
            return "\(daySubject)还没有备忘，可以先写一点想做的事。"
        case (.journal, .past):
            return "\(daySubject)还没有日志。补写几句，方便以后回看。"
        }
    }

    private func completedScene(place: String?, daySubject: String) -> String {
        // 已结束旅程内容已锁定，不再提示"可以补"
        switch self {
        case .itinerary:
            return "\(daySubject)还没有行程记录。"
        case .expense:
            return "\(daySubject)还没有花费记录。"
        case .journal:
            return "\(daySubject)还没有日志。"
        }
    }

    private static func compactPlace(_ destination: String?) -> String? {
        guard var value = destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "未设置目的地"
        else { return nil }

        for suffix in ["特别行政区", "自治区", "省", "市"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            break
        }
        return value.isEmpty ? nil : value
    }
}

/// Empty-state presentation density — both share `TripDayEmptyKind` copy and card system.
/// - `full`: the day has no content at all → companion card (context + optional insight).
/// - `compact`: the day has journal/expense but this tab is empty → in-feed small card, same
///   icon / eyebrow / scene modules, without context or insight.
enum TripDayEmptyDensity {
    case full
    case compact
}

/// Tab-specific empty state for a day with no content on the trip detail feed.
/// Uses AppCompanionCard for friendly guidance. Add actions via FAB.
struct TripDayEmptyStateView: View {
    let kind: TripDayEmptyKind
    let phase: TripDayPhase
    let canEdit: Bool
    var dayIndex: Int = 0
    var destinationName: String? = nil
    var startDate: Date? = nil
    /// Journey stage drives blueprint / memory tone beyond calendar day phase.
    var tripStatus: TripStatus = .unknown
    var density: TripDayEmptyDensity = .full

    private var sceneCopy: String {
        kind.sceneText(
            destination: destinationName,
            phase: phase,
            tripStatus: tripStatus,
            canEdit: canEdit
        )
    }

    private var insightCopy: String? {
        kind.actionHint(canEdit: canEdit, tripStatus: tripStatus)
    }

    private var eyebrowCopy: String {
        kind.eyebrowLabel(tripStatus: tripStatus)
    }

    /// 「第 N 天 · 周X」上下文标签。旅程详情天序号从 1 起。
    private var contextLabel: String {
        let dayNumber = max(dayIndex, 1)
        guard let startDate,
              let dayDate = TracciDateContext.calendar.date(
                  byAdding: .day,
                  value: dayNumber - 1,
                  to: TracciDateContext.startOfBusinessDay(for: startDate)
              )
        else { return "第 \(dayNumber) 天" }
        let weekday = TracciCalendarFormatting.weekday(dayDate)
        return "第 \(dayNumber) 天 · \(weekday)"
    }

    var body: some View {
        Group {
            if density == .compact {
                compactCard
            } else {
                fullCard
            }
        }
        .padding(.horizontal, AppSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrowCopy)空态，\(sceneCopy)")
    }

    private var fullCard: some View {
        AppCompanionCard(
            symbol: kind.systemImage,
            eyebrow: eyebrowCopy,
            context: contextLabel,
            scene: sceneCopy,
            insight: insightCopy,
            leftBar: true
        )
    }

    /// In-feed small card for days that already have journal/expense but not this tab's content.
    /// Same icon / eyebrow / scene copy as `fullCard`; drops context and insight.
    private var compactCard: some View {
        AppElevationCard(level: .l1, role: .hero, radius: AppRadius.medium, padding: AppSpacing.cardSmall) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: kind.systemImage)
                    .font(AppFont.system(15, weight: .light))
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        AppColors.brandPrimary.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    )
                    .accessibilityHidden(true)
                    .tracciTextsReveal(index: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrowCopy)
                        .font(AppTypography.editorialMeta)
                        .foregroundStyle(AppColors.textMuted)
                        .tracking(0.6)
                        .tracciTextsReveal(index: 1)

                    Text(sceneCopy)
                        .font(AppTypography.narrativeBody)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(4)
                        .tracciTextsReveal(index: 2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("行程 · 今天 · 进行中") {
    TripDayEmptyStateView(
        kind: .itinerary, phase: .today, canEdit: true,
        dayIndex: 2, destinationName: "东京",
        startDate: Calendar.current.date(byAdding: .day, value: -1, to: .now),
        tripStatus: .ongoing
    )
    .padding(.horizontal, AppSpacing.pageX)
    .tracciAtmosphere(.creekOngoing)
}

#Preview("行程 · 规划中") {
    TripDayEmptyStateView(
        kind: .itinerary, phase: .upcoming, canEdit: true,
        dayIndex: 1, destinationName: "京都",
        startDate: Calendar.current.date(byAdding: .day, value: 10, to: .now),
        tripStatus: .planning
    )
    .padding(.horizontal, AppSpacing.pageX)
    .tracciAtmosphere(.creek)
}

#Preview("日志 · 已结束") {
    TripDayEmptyStateView(
        kind: .journal, phase: .past, canEdit: true,
        dayIndex: 3, destinationName: "大阪",
        startDate: Calendar.current.date(byAdding: .day, value: -10, to: .now),
        tripStatus: .completed
    )
    .padding(.horizontal, AppSpacing.pageX)
    .tracciAtmosphere(.creekCompleted)
}

#Preview("开支 · 未来") {
    TripDayEmptyStateView(
        kind: .expense, phase: .upcoming, canEdit: true,
        dayIndex: 3, destinationName: "京都", startDate: .now,
        tripStatus: .ongoing
    )
    .padding(.horizontal, AppSpacing.pageX)
}

#Preview("日志 · 仅查看") {
    TripDayEmptyStateView(
        kind: .journal, phase: .past, canEdit: false,
        dayIndex: 1, destinationName: "大阪",
        startDate: Calendar.current.date(byAdding: .day, value: -5, to: .now),
        tripStatus: .completed
    )
    .padding(.horizontal, AppSpacing.pageX)
}

#Preview("行程 · 紧凑（当天有日志/开支）") {
    TripDayEmptyStateView(
        kind: .itinerary, phase: .past, canEdit: true,
        destinationName: "厦门",
        tripStatus: .ongoing,
        density: .compact
    )
    .padding(.horizontal, AppSpacing.pageX)
}

#Preview("开支 · 紧凑 · 已结束") {
    TripDayEmptyStateView(
        kind: .expense, phase: .past, canEdit: true,
        destinationName: "重庆",
        tripStatus: .completed,
        density: .compact
    )
    .padding(.horizontal, AppSpacing.pageX)
}
