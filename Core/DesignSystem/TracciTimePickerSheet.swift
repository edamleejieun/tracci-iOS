import SwiftUI

struct TracciTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    var subtitle: String?
    let date: Date
    var presentation: FormChromePresentation
    var onCancel: (() -> Void)?
    let onConfirm: (Date) -> Void

    @State private var selectedHour: Int
    @State private var selectedMinute: Int

    private let calendar = TracciDateContext.calendar
    private let hours = Array(0...23)
    private let minutes = Array(0...59)
    private let wheelRowHeight: CGFloat = 42
    private let quickTimes: [(label: String, hour: Int, minute: Int)] = [
        ("09:00", 9, 0),
        ("12:00", 12, 0),
        ("14:00", 14, 0),
        ("18:00", 18, 0),
        ("20:00", 20, 0)
    ]

    init(
        title: String = "选择时间",
        subtitle: String? = nil,
        date: Date,
        presentation: FormChromePresentation = .sheet,
        onCancel: (() -> Void)? = nil,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.presentation = presentation
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        let components = TracciDateContext.calendar.dateComponents([.hour, .minute], from: date)
        _selectedHour = State(initialValue: components.hour ?? 0)
        _selectedMinute = State(initialValue: components.minute ?? 0)
    }

    var body: some View {
        Group {
            if presentation == .pushed {
                pushedPage
            } else {
                sheetPage
            }
        }
        .toolbar(presentation == .pushed ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(presentation == .pushed)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sheetPage: some View {
        TracciPickerSheetScaffold(
            title: title,
            subtitle: selectionHint,
            sheetHeight: 580,
            presentation: .sheet,
            onConfirm: confirmSelection,
            headerAccessory: { closeButton }
        ) {
            pickerContent
        }
    }

    /// Full-height destination inside a form sheet. Dock the confirm button and
    /// let the wheel occupy the middle so the page does not look like a short
    /// sheet dropped onto a blank canvas.
    private var pushedPage: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: AppSpacing.md)

            TracciPickerSheetHeader(title: title, subtitle: selectionHint, accessory: { closeButton })
                .tracciPickerHorizontalPadding()

            selectionPreview
                .tracciPickerHorizontalPadding()
                .tracciPickerContentTopSpacing()
                .animation(
                    AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
                    value: selectedHour
                )
                .animation(
                    AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
                    value: selectedMinute
                )

            Spacer(minLength: AppSpacing.md)

            wheelSection
                .tracciPickerHorizontalPadding()
                .transaction { $0.animation = nil }

            Spacer(minLength: AppSpacing.md)

            quickTimeSection
                .tracciPickerHorizontalPadding()
                .padding(.bottom, AppSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.backgroundGrouped)
        .safeAreaInset(edge: .bottom) {
            TracciFixedBottomCTA(backgroundColor: AppColors.backgroundGrouped) {
                PrimaryButton(title: "确定", action: confirmSelection)
            }
        }
    }

    private var pickerContent: some View {
        VStack(spacing: 0) {
            selectionPreview
                .tracciPickerHorizontalPadding()
                .tracciPickerContentTopSpacing()
                .animation(
                    AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
                    value: selectedHour
                )
                .animation(
                    AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
                    value: selectedMinute
                )

            wheelSection
                .tracciPickerHorizontalPadding()
                .padding(.top, AppSpacing.pickerSectionGap)
                .transaction { $0.animation = nil }

            quickTimeSection
                .tracciPickerHorizontalPadding()
                .padding(.top, AppSpacing.md)
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if presentation == .pushed || onCancel != nil {
            Button(action: close) {
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
    }

    // MARK: - Preview Card

    private var selectionPreview: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选")
                    .font(AppTypography.chipSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)

                Text("\(formattedHour):\(formattedMinute)")
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Text(periodLabel)
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
        .accessibilityLabel("当前选择 \(formattedHour) 点 \(formattedMinute) 分，\(periodLabel)")
    }

    // MARK: - Wheel

    private var wheelSection: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: 0) {
                Text("时")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .frame(maxWidth: .infinity)

                Text("分")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, AppSpacing.sm)

            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(AppColors.brandPrimary.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                            .stroke(AppColors.brandPrimary.opacity(0.14), lineWidth: 1)
                    }
                    .frame(height: wheelRowHeight)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    TracciWheelPicker(
                        selection: $selectedHour,
                        values: hours,
                        format: { String(format: "%02d", $0) },
                        chrome: .embedded
                    )
                    .frame(maxWidth: .infinity)

                    Text(":")
                        .font(AppFont.system(22, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textDisabled)
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    TracciWheelPicker(
                        selection: $selectedMinute,
                        values: minutes,
                        format: { String(format: "%02d", $0) },
                        chrome: .embedded
                    )
                    .frame(maxWidth: .infinity)
                }
                .tracciWheelFadeMask()
            }
            .frame(height: wheelRowHeight * 5)
        }
        .padding(AppSpacing.md)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    // MARK: - Quick Times

    private var quickTimeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("常用时间")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPlaceholder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(quickTimes, id: \.label) { item in
                        quickTimeChip(item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func quickTimeChip(_ item: (label: String, hour: Int, minute: Int)) -> some View {
        let isSelected = selectedHour == item.hour && selectedMinute == item.minute

        return Button {
            AppHaptics.selection()
            // Update selection without wrapping the wheel ScrollView in an implicit
            // animation — wheel re-snaps via TracciWheelPicker's own scrollTo.
            selectedHour = item.hour
            selectedMinute = item.minute
        } label: {
            Text(item.label)
                .font(AppFont.system(13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textMuted)
                .padding(.horizontal, AppSpacing.md)
                .frame(height: 36)
                .background(
                    isSelected ? AppColors.brandPrimaryBackground : AppColors.cardBackground,
                    in: Capsule()
                )
                .overlay {
                    if isSelected {
                        Capsule()
                            .stroke(AppColors.brandPrimary.opacity(0.22), lineWidth: 1)
                    } else {
                        Capsule()
                            .stroke(AppColors.borderSubtle, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(PressableCardStyle(scale: 0.97, opacity: 0.94))
    }

    // MARK: - Helpers

    private var selectionHint: String {
        if let subtitle, !subtitle.isEmpty { return subtitle }
        return "滑动滚轮选择时分，或轻点下方常用时间快速填入。"
    }

    private var formattedHour: String {
        String(format: "%02d", selectedHour)
    }

    private var formattedMinute: String {
        String(format: "%02d", selectedMinute)
    }

    private var periodLabel: String {
        switch selectedHour {
        case 5..<9: "早上"
        case 9..<11: "上午"
        case 11..<13: "中午"
        case 13..<18: "下午"
        case 18..<21: "傍晚"
        default: "夜间"
        }
    }

    private func confirmSelection() {
        AppHaptics.success()
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = selectedHour
        components.minute = selectedMinute
        components.second = 0
        let result = calendar.date(from: components) ?? date
        onConfirm(result)
        close()
    }

    private func close() {
        if presentation == .pushed, let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }
}

#Preview("Time Picker") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TracciTimePickerSheet(
                title: "开始时间",
                date: Date()
            ) { _ in }
        }
}

#Preview("Time Picker Pushed") {
    NavigationStack {
        TracciTimePickerSheet(
            title: "开始时间",
            subtitle: "滑动滚轮选择时分，或轻点常用时间快速填入。",
            date: Date(),
            presentation: .pushed,
            onCancel: {}
        ) { _ in }
    }
}
