import SwiftUI

// MARK: - Sheet Chrome

enum TracciPickerChrome {
    static var dragBar: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(AppColors.borderDefault)
            .frame(width: 40, height: 5)
    }

    static func sheetHeight(_ value: CGFloat) -> Set<PresentationDetent> {
        [.height(value)]
    }
}

/// Shared drag bar + top breathing room for all Tracci picker sheets.
struct TracciPickerSheetTopChrome: View {
    var body: some View {
        TracciPickerChrome.dragBar
            .padding(.top, AppSpacing.pickerChromeTop)
            .padding(.bottom, AppSpacing.pickerDragToTitle)
    }
}

/// Title + subtitle header block with consistent hierarchy spacing.
struct TracciPickerSheetHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: () -> Accessory

    init(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.pickerTitleToSubtitle) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.pickerSheetTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: AppSpacing.sm)

                accessory()
            }

            Text(subtitle)
                .font(AppTypography.pickerSheetSubtitle)
                .foregroundStyle(AppColors.textMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared close button for picker / editor sheet headers.
///
/// Visual circle stays 28pt to match shipped chrome; the 44pt frame satisfies
/// the accessibility target-size rule. New sheets should prefer this over
/// hand-rolled `xmark` circles.
struct TracciSheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    /// Custom close action; defaults to dismissing the presentation.
    var action: (() -> Void)?

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark")
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.textMuted)
                .frame(width: 28, height: 28)
                .background(AppColors.subtleBackground)
                .clipShape(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Header HStacks align accessories on the text baseline (view bottom).
        // Shift the guide back by half the hit-area padding so the circle sits
        // exactly where the old 28pt-only buttons did.
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Self.hitAreaPadding }
        .accessibilityLabel("关闭")
    }

    private static let hitAreaPadding: CGFloat = 8
}

enum TracciPickerConfirmPlacement {
    /// Compact sheet detents pin the button to the detent. Pushed time pickers
    /// use a full-page form with a docked bottom CTA instead of a short stack.
    static func usesDockedBottomCTA(_ presentation: FormChromePresentation) -> Bool {
        presentation == .pushed
    }
}

/// Shared picker sheet body — keeps title chrome and content spacing consistent across date/time/range pickers.
struct TracciPickerSheetScaffold<HeaderAccessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    let sheetHeight: CGFloat
    var isConfirmEnabled: Bool = true
    var presentation: FormChromePresentation = .sheet
    /// Sheet pickers pin the confirm button to the detent bottom. Pushed pickers
    /// keep the button under the content so a short page (time) is not hollow.
    var pinsConfirmToBottom: Bool = true
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @ViewBuilder var content: () -> Content
    let onConfirm: () -> Void

    init(
        title: String,
        subtitle: String,
        sheetHeight: CGFloat,
        isConfirmEnabled: Bool = true,
        presentation: FormChromePresentation = .sheet,
        pinsConfirmToBottom: Bool = true,
        onConfirm: @escaping () -> Void,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sheetHeight = sheetHeight
        self.isConfirmEnabled = isConfirmEnabled
        self.presentation = presentation
        self.pinsConfirmToBottom = pinsConfirmToBottom
        self.onConfirm = onConfirm
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentation == .sheet {
                TracciPickerSheetTopChrome()
            } else {
                Color.clear.frame(height: AppSpacing.md)
            }

            TracciPickerSheetHeader(title: title, subtitle: subtitle, accessory: headerAccessory)
                .tracciPickerHorizontalPadding()

            content()

            if pinsConfirmToBottom {
                Spacer(minLength: AppSpacing.sm)
            } else {
                Color.clear.frame(height: AppSpacing.sectionSpacing)
            }

            PrimaryButton(title: "确定", action: onConfirm)
                .opacity(isConfirmEnabled ? 1 : 0.4)
                .disabled(!isConfirmEnabled)
                .tracciPickerHorizontalPadding()
                .padding(.bottom, AppSpacing.pickerFooterBottom)

            if !pinsConfirmToBottom {
                Spacer(minLength: 0)
            }
        }
        .modifier(TracciPickerPresentationModifier(height: sheetHeight, presentation: presentation))
    }
}

private struct TracciPickerPresentationModifier: ViewModifier {
    let height: CGFloat
    let presentation: FormChromePresentation

    func body(content: Content) -> some View {
        switch presentation {
        case .sheet:
            content.tracciPickerSheet(height: height)
        case .pushed:
            content
                .background(AppColors.cardBackground.ignoresSafeArea())
                .preferredColorScheme(.light)
        }
    }
}

extension View {
    /// First content block below the picker header.
    func tracciPickerContentTopSpacing() -> some View {
        padding(.top, AppSpacing.pickerHeaderToContent)
    }

    func tracciPickerSheet(height: CGFloat = 520) -> some View {
        background(AppColors.cardBackground)
            .preferredColorScheme(.light)
            .tracciSheetPresentation(.subSheet(height: height))
    }

    func tracciPickerHorizontalPadding() -> some View {
        padding(.horizontal, AppSpacing.pageX)
    }
}

// MARK: - Trigger Row

/// Tappable row that opens a Tracci picker sheet — matches expense / form field styling.
struct TracciPickerTriggerRow: View {
    let icon: String
    let title: String
    let value: String
    var placeholder: String = "选择"
    var action: () -> Void

    private var isFilled: Bool {
        value != placeholder && !value.isEmpty
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(AppTypography.buttonTitleMedium)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.chipSemibold)
                        .foregroundStyle(AppColors.textPlaceholder)

                    Text(isFilled ? value : placeholder)
                        .font(AppFont.system(15, weight: isFilled ? .semibold : .medium))
                        .foregroundStyle(isFilled ? AppColors.textPrimary : AppColors.textPlaceholder)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle(scale: 0.99, opacity: 0.96))
        .accessibilityLabel("\(title)，\(isFilled ? value : placeholder)")
        .accessibilityHint("打开\(title)选择器")
    }
}

// MARK: - Calendar Formatting

enum TracciCalendarFormatting {
    struct GridCell: Identifiable, Hashable {
        let id: Int
        let date: Date?
    }

    static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
    private static let calendar = TracciDateContext.calendar

    static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func displayDate(_ date: Date) -> String {
        TripDateFormatting.displayString(from: date)
    }

    static func displayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func monthCells(for month: Date) -> [Date?] {
        let interval = calendar.dateInterval(of: .month, for: month)
        guard let start = interval?.start, let end = interval?.end else { return [] }

        let firstWeekday = calendar.component(.weekday, from: start)
        let leadingEmpty = max(0, firstWeekday - 1)
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        let dates = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let cells = Array(repeating: Optional<Date>.none, count: leadingEmpty) + dates.map(Optional.some)
        let trailingEmpty = (7 - (cells.count % 7)) % 7
        return cells + Array(repeating: Optional<Date>.none, count: trailingEmpty)
    }

    /// Calendar padding cells are `nil`. Using `Date?` itself as `ForEach` identity
    /// makes every empty cell share the same ID and trips LazyVGrid warnings.
    static func gridCells(for month: Date) -> [GridCell] {
        monthCells(for: month).enumerated().map { GridCell(id: $0.offset, date: $0.element) }
    }

    static func isDisabled(_ date: Date, minimumDate: Date?, maximumDate: Date?) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let minimumDate, day < calendar.startOfDay(for: minimumDate) {
            return true
        }
        if let maximumDate, day > calendar.startOfDay(for: maximumDate) {
            return true
        }
        return false
    }

    static func canMoveMonth(
        _ offset: Int,
        from displayedMonth: Date,
        minimumDate: Date?,
        maximumDate: Date?
    ) -> Bool {
        guard let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return false }
        let nextMonth = startOfMonth(for: next)

        if offset < 0, let minimumDate {
            return nextMonth >= startOfMonth(for: minimumDate)
        }
        if offset > 0, let maximumDate {
            return nextMonth <= startOfMonth(for: maximumDate)
        }
        return true
    }

    static func mergeDate(_ date: Date, preservingTimeFrom reference: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute, .second], from: reference)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second ?? 0
        return calendar.date(from: components) ?? date
    }

    static func mergeTime(_ time: Date, preservingDateFrom reference: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components) ?? time
    }
}

// MARK: - Day Cell Button Style

struct TracciDayCellButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Wheel Picker

enum TracciWheelPickerChrome {
    case standalone
    case embedded
}

struct TracciWheelPicker: View {
    @Binding var selection: Int
    let values: [Int]
    let format: (Int) -> String
    var chrome: TracciWheelPickerChrome = .standalone

    private let rowHeight: CGFloat = 42
    private let visibleCount = 5

    /// Last value written by `scrollPosition` (user drag / fling).
    /// Used to distinguish scroll-driven updates from programmatic ones
    /// (quick chips, parent binding), so we re-snap only when needed.
    @State private var lastScrollDrivenSelection: Int?

    private var scrollSelection: Binding<Int?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                lastScrollDrivenSelection = newValue
                if selection != newValue {
                    selection = newValue
                }
            }
        )
    }

    var body: some View {
        Group {
            switch chrome {
            case .standalone:
                standaloneBody
            case .embedded:
                wheelScroll
            }
        }
    }

    private var standaloneBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.brandPrimary.opacity(0.08))
                .frame(height: rowHeight)
                .allowsHitTesting(false)

            wheelScroll
        }
        .tracciWheelFadeMask()
    }

    private var wheelScroll: some View {
        let verticalMargin = rowHeight * CGFloat(visibleCount / 2)

        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // Prefer VStack over LazyVStack: hour/minute ranges are tiny, and
                // lazy loading + viewAligned snap commonly leaves the wheel
                // stuck between two rows after a sheet presents.
                VStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        Text(format(value))
                            .font(AppFont.system(
                                22,
                                weight: value == selection ? .bold : .medium,
                                design: .rounded
                            ))
                            // Scale selected digit without changing layout height —
                            // variable row height breaks viewAligned snap.
                            .scaleEffect(value == selection ? 1.12 : 0.86)
                            .foregroundStyle(rowColor(for: value))
                            .frame(height: rowHeight)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .id(value)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: scrollSelection, anchor: .center)
            // Center the first/last row with content margins instead of clear
            // spacer targets — spacers inside scrollTargetLayout can steal snap
            // and leave the wheel resting between two numbers.
            .contentMargins(.vertical, verticalMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .frame(height: rowHeight * CGFloat(visibleCount))
            .clipped()
            .onAppear {
                lastScrollDrivenSelection = selection
                snapToSelection(proxy: proxy, animated: false)
            }
            // Sheet height / safe-area settle after first frame — re-snap once.
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                snapToSelection(proxy: proxy, animated: false)
            }
            .onChange(of: selection) { oldValue, newValue in
                guard oldValue != newValue else { return }
                AppHaptics.selection()
                // User already scrolled here via scrollPosition — do not fight the drag.
                if lastScrollDrivenSelection == newValue {
                    return
                }
                // Programmatic change (quick time chips, external binding).
                snapToSelection(proxy: proxy, animated: true)
                lastScrollDrivenSelection = newValue
            }
        }
    }

    private func snapToSelection(proxy: ScrollViewProxy, animated: Bool) {
        guard values.contains(selection) else { return }
        if animated {
            withAnimation(AppMotion.quick) {
                proxy.scrollTo(selection, anchor: .center)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(selection, anchor: .center)
            }
        }
    }

    private func rowColor(for value: Int) -> Color {
        if value == selection {
            return chrome == .embedded ? AppColors.textPrimary : AppColors.brandPrimary
        }
        return AppColors.textPlaceholder.opacity(0.45)
    }
}

extension View {
    func tracciWheelFadeMask() -> some View {
        mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.2),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview("Trigger Row") {
    VStack(spacing: 0) {
        TracciPickerTriggerRow(icon: "calendar", title: "日期", value: "2026.06.28") {}
        Divider()
        TracciPickerTriggerRow(icon: "clock", title: "时间", value: "选择", placeholder: "选择") {}
    }
    .padding()
    .background(AppColors.cardBackground)
}
