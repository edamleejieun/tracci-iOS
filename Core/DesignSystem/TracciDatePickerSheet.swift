import SwiftUI

struct TracciDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    var subtitle: String?
    let date: Date
    var minimumDate: Date?
    var maximumDate: Date?
    let onConfirm: (Date) -> Void

    @State private var draftDate: Date
    @State private var displayedMonth: Date
    @State private var monthTransitionDirection: Int = 0

    private let calendar = TracciDateContext.calendar

    init(
        title: String = "选择日期",
        subtitle: String? = nil,
        date: Date,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.onConfirm = onConfirm
        _draftDate = State(initialValue: calendar.startOfDay(for: date))
        _displayedMonth = State(initialValue: TracciCalendarFormatting.startOfMonth(for: date))
    }

    var body: some View {
        TracciPickerSheetScaffold(
            title: title,
            subtitle: selectionHint,
            sheetHeight: 620,
            onConfirm: confirmSelection
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
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: draftDate
        )
    }

    private var selectionPreview: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选")
                    .font(AppTypography.chipSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)
                Text(TracciCalendarFormatting.fullDate(draftDate))
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer(minLength: 0)

            Text(TracciCalendarFormatting.weekday(draftDate))
                .font(AppTypography.label)
                .foregroundStyle(AppColors.brandPrimary)
                .padding(.horizontal, AppSpacing.sm)
                .frame(height: 30)
                .background(AppColors.brandPrimaryBackground)
                .clipShape(Capsule())
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var calendarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(TracciCalendarFormatting.monthTitle(displayedMonth))
                .font(AppFont.system(26, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .contentTransition(.numericText())

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
            ForEach(TracciCalendarFormatting.weekdaySymbols, id: \.self) { item in
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
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let disabled = TracciCalendarFormatting.isDisabled(date, minimumDate: minimumDate, maximumDate: maximumDate)
        let isSelected = calendar.isDate(date, inSameDayAs: draftDate)
        let isToday = calendar.isDateInToday(date)

        return Button {
            select(date)
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? AppColors.brandPrimary : (isToday ? AppColors.brandPrimaryBackground : .clear))
                    .frame(width: 46, height: 46)

                VStack(spacing: -2) {
                    Text("\(day)")
                        .font(AppTypography.cardTitle)
                    if isToday {
                        Text("今")
                            .font(AppFont.system(9, weight: .bold))
                    }
                }
                .foregroundStyle(isSelected ? Color.white : (isToday ? AppColors.brandPrimary : AppColors.textPrimary))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(TracciDayCellButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.28 : 1)
        .accessibilityLabel(dayAccessibilityLabel(for: date, isSelected: isSelected, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionHint: String {
        if let subtitle, !subtitle.isEmpty { return subtitle }
        return "轻触日历选择日期，这一天会留在你的旅程记录里。"
    }

    private var monthTransition: AnyTransition {
        let offset: CGFloat = reduceMotion ? 0 : 18 * CGFloat(monthTransitionDirection)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: offset)),
            removal: .opacity.combined(with: .offset(x: -offset))
        )
    }

    private func select(_ date: Date) {
        AppHaptics.selection()
        draftDate = calendar.startOfDay(for: date)
    }

    private func confirmSelection() {
        AppHaptics.success()
        onConfirm(draftDate)
        dismiss()
    }

    private func canMoveMonth(_ offset: Int) -> Bool {
        TracciCalendarFormatting.canMoveMonth(offset, from: displayedMonth, minimumDate: minimumDate, maximumDate: maximumDate)
    }

    private func moveMonth(_ offset: Int) {
        guard canMoveMonth(offset),
              let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        AppHaptics.selection()
        monthTransitionDirection = offset
        withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
            displayedMonth = TracciCalendarFormatting.startOfMonth(for: next)
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

    private func dayAccessibilityLabel(for date: Date, isSelected: Bool, isToday: Bool) -> String {
        var label = TracciCalendarFormatting.shortDate(date)
        if isToday { label += "，今天" }
        if isSelected { label += "，已选中" }
        return label
    }
}

#Preview("Date Picker") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TracciDatePickerSheet(
                title: "消费日期",
                date: Date()
            ) { _ in }
        }
}