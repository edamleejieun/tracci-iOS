import SwiftUI

/// 大地图沉浸态专用的 Day 选择器。
///
/// 视觉权重让给地图：无轨道底、无溪流进度、无填充选中块；
/// 形态接近内容 Tab——选中项下方一根品牌小横条。
///
/// 多天旅程额外提供「全程」入口：全旅程路线总览（按天分色）。
struct TripMapDayTabRail: View {
    @Binding var selectedDayIndex: Int
    let totalDays: Int
    let tripStartDate: String
    /// 是否显示「全程」入口（仅多天旅程）。
    var showsFullTripEntry: Bool = false
    /// 「全程」是否选中；为 true 时所有日期 Tab 均不处于选中态。
    var isFullTripSelected: Bool = false
    var onSelectFullTrip: (() -> Void)? = nil
    let onSelectDay: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    /// 「全程」Tab 的滚动锚点 id（与日期 1...N 区分）。
    private let fullTripTabID = 0

    private var effectiveItemCount: Int {
        totalDays + (showsFullTripEntry ? 1 : 0)
    }

    private var usesCompactLayout: Bool {
        effectiveItemCount <= TripDetailLayout.dayRailCompactMaxDays
    }

    private var scrollTargetID: Int {
        isFullTripSelected ? fullTripTabID : selectedDayIndex
    }

    var body: some View {
        Group {
            if usesCompactLayout {
                HStack(spacing: 0) {
                    if showsFullTripEntry {
                        fullTripTab(flexible: true)
                    }
                    ForEach(1...totalDays, id: \.self) { dayIndex in
                        dayTab(dayIndex, flexible: true)
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            if showsFullTripEntry {
                                fullTripTab(flexible: false)
                                    .id(fullTripTabID)
                            }
                            ForEach(1...totalDays, id: \.self) { dayIndex in
                                dayTab(dayIndex, flexible: false)
                                    .id(dayIndex)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .onAppear {
                        proxy.scrollTo(scrollTargetID, anchor: .center)
                    }
                    .onChange(of: scrollTargetID) { _, newValue in
                        withAnimation(reduceMotion ? nil : AppMotion.mapExploreDayCamera) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            showsFullTripEntry
                ? "全程及日期，共 \(totalDays) 天"
                : "日期，共 \(totalDays) 天"
        )
    }

    /// 「全程」Tab：全旅程路线总览入口；与日期 Tab 共享下划线选中语言。
    private func fullTripTab(flexible: Bool) -> some View {
        Button {
            guard !isFullTripSelected else { return }
            AppHaptics.selection()
            onSelectFullTrip?()
        } label: {
            VStack(spacing: 5) {
                Text("全程")
                    .font(
                        isFullTripSelected
                            ? TripDetailTypography.modeOptionSelected
                            : TripDetailTypography.modeOption
                    )
                    .foregroundStyle(
                        isFullTripSelected ? AppColors.brandPrimary : AppColors.textSecondary
                    )
                    .lineLimit(1)

                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 18, height: 2.5)

                    if isFullTripSelected {
                        Capsule()
                            .fill(AppColors.brandPrimary)
                            .frame(width: 18, height: 2.5)
                            .matchedGeometryEffect(id: "map-day-tab-underline", in: selectionNamespace)
                    }
                }
            }
            .frame(maxWidth: flexible ? .infinity : nil)
            .padding(.horizontal, flexible ? 4 : 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("全程路线总览")
        .accessibilityHint("查看整个旅程的按天路线")
        .accessibilityAddTraits(isFullTripSelected ? .isSelected : [])
    }

    private func dayTab(_ dayIndex: Int, flexible: Bool) -> some View {
        let isSelected = selectedDayIndex == dayIndex && !isFullTripSelected
        let isToday = TripDayRail.isToday(dayIndex: dayIndex, tripStartDate: tripStartDate)
        let dateLabel = dateString(for: dayIndex)

        return Button {
            guard selectedDayIndex != dayIndex || isFullTripSelected else { return }
            AppHaptics.selection()
            onSelectDay(dayIndex)
        } label: {
            VStack(spacing: 5) {
                Text(dateLabel)
                    .font(
                        isSelected
                            ? TripDetailTypography.modeOptionSelected
                            : TripDetailTypography.modeOption
                    )
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textSecondary)
                    .monospacedDigit()

                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 18, height: 2.5)

                    if isSelected {
                        Capsule()
                            .fill(AppColors.brandPrimary)
                            .frame(width: 18, height: 2.5)
                            .matchedGeometryEffect(id: "map-day-tab-underline", in: selectionNamespace)
                    } else if isToday {
                        Capsule()
                            .fill(AppColors.brandPrimary.opacity(0.28))
                            .frame(width: 10, height: 2)
                    }
                }
            }
            .frame(maxWidth: flexible ? .infinity : nil)
            .padding(.horizontal, flexible ? 4 : 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isToday ? "今天，\(dateLabel)" : dateLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dateString(for dayIndex: Int) -> String {
        guard let startDate = TripDateFormatting.date(from: tripStartDate) else { return "--" }
        guard let date = TracciDateContext.calendar.date(
            byAdding: .day,
            value: dayIndex - 1,
            to: TracciDateContext.startOfBusinessDay(for: startDate)
        ) else { return "--" }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "MM.dd"
        return formatter.string(from: date)
    }
}
