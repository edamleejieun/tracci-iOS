import SwiftUI

struct TripDayRail: View {
    @Binding var selectedDayIndex: Int
    let totalDays: Int
    let tripStartDate: String
    let isOverviewSelected: Bool
    let onSelectDay: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesCompactLayout: Bool {
        totalDays <= TripDetailLayout.dayRailCompactMaxDays
    }

    var body: some View {
        Group {
            if usesCompactLayout {
                compactDayRail
            } else {
                scrollableDayRail
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("日期范围，共 \(totalDays) 天")
    }

    private var compactDayRail: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            ForEach(1...totalDays, id: \.self) { dayIndex in
                dayRailItem(dayIndex, distributesWidth: true)
            }
        }
        .padding(.bottom, AppSpacing.sm)
        .background(alignment: .bottom) {
            dayStreamTrack
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, 2)
        }
        .padding(.vertical, AppSpacing.tight)
        .padding(.horizontal, AppSpacing.tight)
        .background {
            dayRailTrackBackground
        }
        .overlay {
            dayRailStroke
        }
    }

    private var scrollableDayRail: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: AppSpacing.tight) {
                    Color.clear
                        .frame(width: 4)
                        .id("day-rail-leading")

                    ForEach(1...totalDays, id: \.self) { dayIndex in
                        dayRailItem(dayIndex, distributesWidth: false)
                    }

                    Color.clear
                        .frame(width: 4)
                        .id("day-rail-trailing")
                }
                .padding(.bottom, AppSpacing.sm)
                .background(alignment: .bottom) {
                    dayStreamTrack
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.bottom, 2)
                }
                .padding(.vertical, AppSpacing.tight)
                .padding(.horizontal, AppSpacing.xs)
            }
            .background {
                dayRailTrackBackground
            }
            .overlay(alignment: .leading) {
                dayRailLeadingEdgeFade
            }
            .overlay(alignment: .trailing) {
                dayRailTrailingEdgeFade
            }
            .overlay {
                dayRailStroke
            }
            .onAppear {
                scrollToSelectedDay(scrollProxy, animated: false)
            }
            .onChange(of: selectedDayIndex) { _, _ in
                // Directional scroll: later days move content left, earlier days right.
                // Avoid re-centering with a fixed .center — that flips left/right mid-rail.
                scrollToSelectedDay(scrollProxy, animated: true)
            }
        }
    }

    private var dayRailStroke: some View {
        RoundedRectangle(cornerRadius: TripDetailLayout.railTrackRadius, style: .continuous)
            .stroke(AppColors.borderSubtle.opacity(0.35), lineWidth: 0.5)
    }

    private var dayStreamTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.borderSubtle.opacity(0.72))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.stageCompleted.opacity(0.54), AppColors.stageOngoing.opacity(0.76)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * dayStreamProgress)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : AppMotion.milestoneSpring, value: selectedDayIndex)
    }

    private var dayStreamProgress: CGFloat {
        guard !isOverviewSelected else { return 0 }
        guard totalDays > 1 else { return 1 }
        return CGFloat(selectedDayIndex - 1) / CGFloat(totalDays - 1)
    }

    /// Left → right: journey start to later days; very subtle brand warmth on the trailing edge.
    private var dayRailTrackBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TripDetailLayout.railTrackRadius, style: .continuous)
                .fill(AppColors.paperWarmLight.opacity(0.74))

            RoundedRectangle(cornerRadius: TripDetailLayout.railTrackRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: AppColors.creekMistTop.opacity(0.62), location: 0),
                            .init(color: Color.clear, location: 0.38),
                            .init(color: AppColors.stageOngoingBackground.opacity(0.20), location: 0.72),
                            .init(color: AppColors.brandPrimary.opacity(0.05), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    /// Soft leading fade — time already passed / earlier days.
    private var dayRailLeadingEdgeFade: some View {
        LinearGradient(
            colors: [
                AppColors.pageBackground.opacity(0.65),
                AppColors.pageBackground.opacity(0.18),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 14)
        .allowsHitTesting(false)
    }

    /// Soft trailing fade — more days ahead.
    private var dayRailTrailingEdgeFade: some View {
        LinearGradient(
            colors: [
                .clear,
                AppColors.brandPrimaryBackground.opacity(0.12),
                AppColors.brandPrimary.opacity(0.04)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 18)
        .allowsHitTesting(false)
    }

    /// Scrolls the selected day into a stable, edge-aware position.
    ///
    /// Previous logic used `.leading` for day ≤ 2 and `.center` otherwise. Crossing
    /// that boundary (and re-centering mid-rail items that were already visible)
    /// made adjacent day switches animate left or right inconsistently.
    ///
    /// Strategy (matches content-feed day direction: later → left, earlier → right):
    /// - Day 1 pins to the leading edge
    /// - Last day pins to the trailing edge
    /// - Middle days use a progressive horizontal anchor so scroll offset moves
    ///   monotonically with day index (no leading↔center flip)
    private func scrollToSelectedDay(_ scrollProxy: ScrollViewProxy, animated: Bool) {
        let target = selectedDayIndex
        guard totalDays > 0, (1...totalDays).contains(target) else { return }

        let scrollAction = {
            if target <= 1 {
                scrollProxy.scrollTo("day-rail-leading", anchor: .leading)
                return
            }

            if target >= totalDays {
                scrollProxy.scrollTo("day-rail-trailing", anchor: .trailing)
                return
            }

            // Progressive anchor: early days sit near leading, late days near trailing.
            // UnitPoint.x in [0, 1] keeps forward/backward selection spatially consistent.
            let progress = CGFloat(target - 1) / CGFloat(max(totalDays - 1, 1))
            scrollProxy.scrollTo(target, anchor: UnitPoint(x: progress, y: 0.5))
        }

        if animated, !reduceMotion {
            withAnimation(AppMotion.daySwitch) {
                scrollAction()
            }
        } else {
            scrollAction()
        }
    }

    private func dayRailItem(_ dayIndex: Int, distributesWidth: Bool) -> some View {
        let isSelected = !isOverviewSelected && selectedDayIndex == dayIndex
        let isToday = Self.isToday(dayIndex: dayIndex, tripStartDate: tripStartDate)
        let dateLabel = dateString(for: dayIndex)
        let weekdayLabel = weekdayString(for: dayIndex)

        return Button {
            guard isOverviewSelected || selectedDayIndex != dayIndex else { return }
            AppHaptics.selection()
            onSelectDay(dayIndex)
        } label: {
            VStack(spacing: 2) {
                Text(dateLabel)
                    .font(isSelected ? TripDetailTypography.dayDateSelected : TripDetailTypography.dayDate)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(weekdayLabel)
                    .font(isSelected ? TripDetailTypography.dayWeekdaySelected : TripDetailTypography.dayWeekday)
                    .foregroundStyle(
                        isSelected
                            ? AppColors.brandPrimary.opacity(0.9)
                            : AppColors.textMuted
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isToday {
                    Text("今天")
                        .font(TripDetailTypography.dayBadge)
                        .foregroundStyle(isSelected ? .white : AppColors.brandPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .frame(minHeight: 16)
                        .background(
                            isSelected
                                ? AppColors.brandPrimary
                                : AppColors.brandPrimaryBackground
                        )
                        .clipShape(Capsule())
                } else {
                    Color.clear
                        .frame(height: 16)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: distributesWidth ? .infinity : nil)
            .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textSecondary)
            .padding(.horizontal, distributesWidth ? 6 : 12)
            .padding(.vertical, isToday ? 7 : 8)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(backgroundColor(isSelected: isSelected, isToday: isToday))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.35), lineWidth: 1)
                }
            }
            .tracciElevation(isSelected ? .l1 : .l0)
            .overlay(alignment: .bottom) {
                dayStreamMarker(dayIndex: dayIndex, isSelected: isSelected)
                    .offset(y: AppSpacing.xs + 1)
            }
            .id(dayIndex)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(PressableCardStyle(scale: AppMotion.pressScale, opacity: AppMotion.pressOpacity))
        .accessibilityLabel(accessibilityLabel(dateLabel: dateLabel, weekdayLabel: weekdayLabel, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func backgroundColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return AppColors.brandPrimaryBackground.opacity(0.88)
        }
        if isToday {
            return AppColors.brandPrimaryBackground.opacity(0.22)
        }
        return .clear
    }

    private func dayStreamMarker(dayIndex: Int, isSelected: Bool) -> some View {
        Circle()
            .fill(
                isSelected
                    ? AppColors.stageOngoing
                    : (!isOverviewSelected && dayIndex < selectedDayIndex
                        ? AppColors.stageCompleted
                        : AppColors.paperWarmLight)
            )
            .overlay {
                Circle()
                    .stroke(
                        isSelected ? Color.white.opacity(0.92) : AppColors.stagePlanning.opacity(0.62),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .frame(width: isSelected ? 10 : 8, height: isSelected ? 10 : 8)
            .tracciElevation(isSelected ? .l1 : .l0)
            .accessibilityHidden(true)
    }

    private func accessibilityLabel(dateLabel: String, weekdayLabel: String, isToday: Bool) -> String {
        if isToday {
            return "今天，\(dateLabel)，\(weekdayLabel)"
        }
        return "\(dateLabel)，\(weekdayLabel)"
    }

    static func isToday(dayIndex: Int, tripStartDate: String) -> Bool {
        guard let startDate = TripDateFormatting.date(from: tripStartDate) else { return false }
        let today = TracciDateContext.today()
        return TracciDateContext.dayIndex(for: today, startDate: startDate) == dayIndex
    }

    private func dateForDay(_ dayIndex: Int) -> Date? {
        guard let startDate = TripDateFormatting.date(from: tripStartDate) else { return nil }
        return TracciDateContext.calendar.date(
            byAdding: .day,
            value: dayIndex - 1,
            to: TracciDateContext.startOfBusinessDay(for: startDate)
        )
    }

    private func dateString(for dayIndex: Int) -> String {
        formattedString(for: dayIndex, format: "MM.dd") ?? "--"
    }

    private func weekdayString(for dayIndex: Int) -> String {
        formattedString(for: dayIndex, format: "EEE") ?? ""
    }

    private func formattedString(for dayIndex: Int, format: String) -> String? {
        guard let date = dateForDay(dayIndex) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
