import SwiftUI

struct TracciDateRangePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    var subtitle: String?
    let startDate: Date?
    let endDate: Date?
    var minimumDate: Date?
    var maximumDate: Date?
    var presentation: FormChromePresentation
    var isSubmitting: Bool
    let onConfirm: (Date, Date) -> Void
    /// Optional close affordance. When provided (e.g. the calendar is pushed inside a
    /// NavigationStack), a leading close button is shown in the header. Consumers that
    /// present the picker as a stand-alone sheet leave this nil and keep drag-to-dismiss.
    var onCancel: (() -> Void)?

    @State private var draftStartDate: Date?
    @State private var draftEndDate: Date?
    @State private var displayedMonth: Date
    @State private var monthTransitionDirection: Int = 0

    private let calendar = TracciDateContext.calendar

    init(
        title: String = "你想去多久？",
        subtitle: String? = nil,
        startDate: Date?,
        endDate: Date?,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        presentation: FormChromePresentation = .sheet,
        isSubmitting: Bool = false,
        onConfirm: @escaping (Date, Date) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.startDate = startDate
        self.endDate = endDate
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.presentation = presentation
        self.isSubmitting = isSubmitting
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _draftStartDate = State(initialValue: startDate)
        _draftEndDate = State(initialValue: endDate)
        _displayedMonth = State(initialValue: calendarStartOfMonth(for: startDate ?? Date()))
    }

    var body: some View {
        TracciPickerSheetScaffold(
            title: title,
            subtitle: selectionHint,
            sheetHeight: 700,
            isConfirmEnabled: draftStartDate != nil && !isSubmitting,
            presentation: presentation,
            onConfirm: confirmSelection,
            headerAccessory: {
                HStack(spacing: AppSpacing.sm) {
                    if let onCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(AppTypography.labelSemibold)
                                .foregroundStyle(AppColors.textMuted)
                                .frame(width: 28, height: 28)
                                .background(AppColors.subtleBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭")
                    }
                    if let start = draftStartDate {
                        daysBadge(start: start, end: draftEndDate ?? start)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
            }
        ) {
            VStack(spacing: 0) {
                selectionPreview
                    .tracciPickerHorizontalPadding()
                    .tracciPickerContentTopSpacing()

                calendarHeader
                    .tracciPickerHorizontalPadding()
                    .padding(.top, AppSpacing.pickerSectionGap)

                weekdayRow
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.top, AppSpacing.md)

                monthGrid
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.top, AppSpacing.sm)
                    .id(displayedMonth)
                    .transition(monthTransition)
            }
        }
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: selectionHint)
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: draftStartDate
        )
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: draftEndDate
        )
    }

    private var selectionPreview: some View {
        HStack(spacing: AppSpacing.sm) {
            previewChip(
                label: "出发",
                date: draftStartDate,
                isActive: draftStartDate != nil,
                isPlaceholder: draftStartDate == nil
            )

            Image(systemName: "arrow.right")
                .font(AppTypography.chipSemibold)
                .foregroundStyle(AppColors.textDisabled)

            previewChip(
                label: "返回",
                date: draftEndDate,
                isActive: draftEndDate != nil,
                isPlaceholder: draftEndDate == nil && draftStartDate != nil
            )

            Spacer(minLength: 0)

            if draftStartDate != nil {
                Button {
                    clearSelection()
                } label: {
                    Text("清除")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除已选日期")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var calendarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(monthTitle(displayedMonth))
                .font(AppFont.system(26, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .contentTransition(.numericText())
                .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: displayedMonth)

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                monthButton(systemImage: "chevron.left", isEnabled: canMoveMonth(-1)) {
                    moveMonth(-1)
                }
                monthButton(systemImage: "chevron.right", isEnabled: canMoveMonth(1)) {
                    moveMonth(1)
                }
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { item in
                Text(item)
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: AppSpacing.sm
        ) {
            ForEach(TracciCalendarFormatting.gridCells(for: displayedMonth)) { cell in
                if let date = cell.date {
                    dayCell(date)
                } else {
                    Color.clear
                        .frame(height: 46)
                }
            }
        }
    }

    // MARK: - Cells

    private func previewChip(label: String, date: Date?, isActive: Bool, isPlaceholder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.chipSemibold)
                .foregroundStyle(AppColors.textPlaceholder)

            Text(chipDateText(for: date, isPlaceholder: isPlaceholder))
                .font(AppFont.system(14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textDisabled)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: date)
    }

    private func daysBadge(start: Date, end: Date) -> some View {
        Text("\(daysCount(start: start, end: end)) 天")
            .font(AppTypography.label)
            .foregroundStyle(AppColors.brandPrimary)
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: 32)
            .background(AppColors.brandPrimaryBackground)
            .clipShape(Capsule())
    }

    private func dayCell(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let disabled = isDisabled(date)
        let rangeRole = role(for: date)
        let isToday = calendar.isDateInToday(date)

        return Button {
            select(date)
        } label: {
            ZStack {
                rangeBackground(for: rangeRole, date: date)

                Circle()
                    .fill(circleFill(for: rangeRole, isToday: isToday))
                    .frame(width: 42, height: 42)

                VStack(spacing: -2) {
                    Text("\(day)")
                        .font(AppTypography.cardTitle)
                    if isToday {
                        Text("今")
                            .font(AppFont.system(9, weight: .bold))
                    }
                }
                .foregroundStyle(textColor(for: rangeRole, isToday: isToday, disabled: disabled))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(TracciDayCellButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.28 : 1)
        .accessibilityLabel(dayAccessibilityLabel(for: date, role: rangeRole, isToday: isToday))
        .accessibilityAddTraits(rangeRole == .none ? [] : .isSelected)
    }

    @ViewBuilder
    private func rangeBackground(for role: DateRangeRole, date: Date) -> some View {
        let intervalColor = AppColors.brandPrimary.opacity(0.12)
        let height: CGFloat = 34
        let radius = height / 2
        let caps = rangeTrackCaps(for: role, date: date)

        switch role {
        case .middle:
            GeometryReader { proxy in
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: caps.leading ? radius : 0,
                        bottomLeading: caps.leading ? radius : 0,
                        bottomTrailing: caps.trailing ? radius : 0,
                        topTrailing: caps.trailing ? radius : 0
                    ),
                    style: .continuous
                )
                .fill(intervalColor)
                .frame(width: proxy.size.width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(height: 46)
        case .start:
            GeometryReader { proxy in
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: 0,
                        bottomLeading: 0,
                        bottomTrailing: caps.trailing ? radius : 0,
                        topTrailing: caps.trailing ? radius : 0
                    ),
                    style: .continuous
                )
                .fill(intervalColor)
                .frame(width: proxy.size.width / 2, height: height)
                .position(x: proxy.size.width * 0.75, y: proxy.size.height / 2)
            }
            .frame(height: 46)
        case .end:
            GeometryReader { proxy in
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: caps.leading ? radius : 0,
                        bottomLeading: caps.leading ? radius : 0,
                        bottomTrailing: 0,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
                .fill(intervalColor)
                .frame(width: proxy.size.width / 2, height: height)
                .position(x: proxy.size.width * 0.25, y: proxy.size.height / 2)
            }
            .frame(height: 46)
        case .single, .none:
            EmptyView()
        }
    }

    private func monthButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppTypography.labelSemibold)
                .foregroundStyle(isEnabled ? AppColors.textMuted : AppColors.textDisabled)
                .frame(width: 44, height: 44)
                .background(isEnabled ? AppColors.subtleBackground : AppColors.subtleBackground.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(PressableCardStyle(scale: 0.94, opacity: 0.88))
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "chevron.left" ? "上个月" : "下个月")
    }

    // MARK: - Logic

    private var selectionHint: String {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }
        if draftStartDate == nil {
            return "轻触日历选择出发日期，旅程会从这里开始被记录。"
        }
        if draftEndDate == nil {
            return "再选一天作为返回日期，或点确定视为单日旅程。"
        }
        return "区间已选好，确认后旅程日期就会落定。"
    }

    private var monthTransition: AnyTransition {
        let offset: CGFloat = reduceMotion ? 0 : 18 * CGFloat(monthTransitionDirection)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: offset)),
            removal: .opacity.combined(with: .offset(x: -offset))
        )
    }

    private func select(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        AppHaptics.selection()

        guard let start = draftStartDate else {
            draftStartDate = day
            draftEndDate = nil
            return
        }

        if draftEndDate != nil {
            draftStartDate = day
            draftEndDate = nil
        } else if day < start {
            draftStartDate = day
            draftEndDate = start
        } else {
            draftEndDate = day
        }
    }

    private func clearSelection() {
        AppHaptics.lightImpact()
        draftStartDate = nil
        draftEndDate = nil
    }

    private func confirmSelection() {
        guard let start = draftStartDate, !isSubmitting else { return }
        let end = draftEndDate ?? start
        AppHaptics.success()
        onConfirm(min(start, end), max(start, end))
        // Pushed editors own navigation. Auto-dismissing here would pop
        // TripDateEditorView before its status-change confirmation can stay on screen.
        if TracciDateRangePickerDismissPolicy.shouldDismissAfterConfirm(presentation) {
            dismiss()
        }
    }

    private func role(for date: Date) -> DateRangeRole {
        let day = calendar.startOfDay(for: date)
        guard let start = draftStartDate.map(calendar.startOfDay(for:)) else { return .none }
        let end = draftEndDate.map(calendar.startOfDay(for:))

        guard let end else {
            return calendar.isDate(day, inSameDayAs: start) ? .single : .none
        }

        if calendar.isDate(start, inSameDayAs: end), calendar.isDate(day, inSameDayAs: start) {
            return .single
        }
        if calendar.isDate(day, inSameDayAs: start) { return .start }
        if calendar.isDate(day, inSameDayAs: end) { return .end }
        if day > start && day < end { return .middle }
        return .none
    }

    private func rangeTrackCaps(for role: DateRangeRole, date: Date) -> (leading: Bool, trailing: Bool) {
        guard role != .none, role != .single else {
            return (false, false)
        }

        let components = calendar.dateComponents([.day, .weekday], from: date)
        let day = components.day ?? 0
        let weekday = components.weekday ?? 0
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 31

        let beginsVisibleSegment = weekday == 1 || day == 1
        let endsVisibleSegment = weekday == 7 || day == daysInMonth

        switch role {
        case .start:
            return (false, endsVisibleSegment)
        case .end:
            return (beginsVisibleSegment, false)
        case .middle:
            return (beginsVisibleSegment, endsVisibleSegment)
        case .none, .single:
            return (false, false)
        }
    }

    private func circleFill(for role: DateRangeRole, isToday: Bool) -> Color {
        switch role {
        case .start, .end, .single:
            AppColors.brandPrimary
        case .middle:
            .clear
        case .none:
            isToday ? AppColors.brandPrimaryBackground : .clear
        }
    }

    private func textColor(for role: DateRangeRole, isToday: Bool, disabled: Bool) -> Color {
        if disabled { return AppColors.textDisabled }
        switch role {
        case .start, .end, .single, .middle:
            return role == .middle ? AppColors.textPrimary : Color.white
        case .none:
            return isToday ? AppColors.brandPrimary : AppColors.textPrimary
        }
    }

    private func isDisabled(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let minimumDate, day < calendar.startOfDay(for: minimumDate) {
            return true
        }
        if let maximumDate, day > calendar.startOfDay(for: maximumDate) {
            return true
        }
        return false
    }

    private func canMoveMonth(_ offset: Int) -> Bool {
        guard let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return false }
        let nextMonth = calendarStartOfMonth(for: next)

        if offset < 0, let minimumDate {
            let minMonth = calendarStartOfMonth(for: minimumDate)
            return nextMonth >= minMonth
        }
        if offset > 0, let maximumDate {
            let maxMonth = calendarStartOfMonth(for: maximumDate)
            return nextMonth <= maxMonth
        }
        return true
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func chipDateText(for date: Date?, isPlaceholder: Bool) -> String {
        guard let date else {
            return isPlaceholder ? "待选择" : "—"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func moveMonth(_ offset: Int) {
        guard canMoveMonth(offset), let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        AppHaptics.selection()
        monthTransitionDirection = offset
        withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
            displayedMonth = calendarStartOfMonth(for: next)
        }
    }

    private func daysCount(start: Date, end: Date) -> Int {
        let count = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, count + 1)
    }

    private func dayAccessibilityLabel(for date: Date, role: DateRangeRole, isToday: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        var label = formatter.string(from: date)
        if isToday { label += "，今天" }
        switch role {
        case .start: label += "，出发日"
        case .end: label += "，返回日"
        case .single: label += "，单日旅程"
        case .middle: label += "，旅程中"
        case .none: break
        }
        return label
    }
}

enum TracciDateRangePickerDismissPolicy {
    /// Sheet pickers close themselves. Pushed editors stay so confirmation can be answered.
    static func shouldDismissAfterConfirm(_ presentation: FormChromePresentation) -> Bool {
        presentation == .sheet
    }
}

private enum DateRangeRole {
    case none
    case single
    case start
    case middle
    case end
}

private func calendarStartOfMonth(for date: Date) -> Date {
    let calendar = TracciDateContext.calendar
    let components = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: components) ?? calendar.startOfDay(for: date)
}

// MARK: - Preview

#Preview("Empty") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TracciDateRangePickerSheet(
                startDate: nil,
                endDate: nil
            ) { _, _ in }
        }
}

#Preview("Partial Selection") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TracciDateRangePickerSheet(
                startDate: Date(),
                endDate: nil
            ) { _, _ in }
        }
}

#Preview("Full Range") {
    let calendar = TracciDateContext.calendar
    let start = calendar.startOfDay(for: Date())
    let end = calendar.date(byAdding: .day, value: 5, to: start)!

    return Color.clear
        .sheet(isPresented: .constant(true)) {
            TracciDateRangePickerSheet(
                startDate: start,
                endDate: end
            ) { _, _ in }
        }
}
