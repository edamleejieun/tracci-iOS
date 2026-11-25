import SwiftUI

/// Birth date picker with side-by-side year + month wheels.
/// Much faster than a calendar grid for selecting dates far in the past.
struct TracciBirthDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let initialDate: Date?
    let onConfirm: (Date) -> Void

    @State private var draftYear: Int
    @State private var draftMonth: Int

    private let yearRange: [Int]
    private let monthRange: [Int] = Array(1...12)
    private let calendar = Calendar(identifier: .gregorian)

    init(
        initialDate: Date?,
        onConfirm: @escaping (Date) -> Void
    ) {
        self.initialDate = initialDate
        self.onConfirm = onConfirm

        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())

        if let date = initialDate {
            let y = Calendar(identifier: .gregorian).component(.year, from: date)
            let m = Calendar(identifier: .gregorian).component(.month, from: date)
            _draftYear = State(initialValue: y)
            _draftMonth = State(initialValue: m)
        } else {
            _draftYear = State(initialValue: 2000)
            _draftMonth = State(initialValue: 6)
        }

        yearRange = Array(1930...currentYear)
    }

    var body: some View {
        TracciPickerSheetScaffold(
            title: "选择出生年月",
            subtitle: "用于生成个性化旅行报告",
            sheetHeight: 520,
            onConfirm: confirmSelection
        ) {
            VStack(spacing: 0) {
                selectionPreview
                    .tracciPickerHorizontalPadding()
                    .tracciPickerContentTopSpacing()

                wheelArea
                    .padding(.top, AppSpacing.pickerSectionGap)
            }
        }
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: draftYear
        )
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: draftMonth
        )
    }

    // MARK: - Selection Preview

    private var selectionPreview: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选")
                    .font(AppTypography.chipSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)
                Text("\(String(draftYear))年\(draftMonth)月")
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer(minLength: 0)

            if let age = computedAge {
                Text("\(age)岁")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.brandPrimary)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(height: 30)
                    .background(AppColors.brandPrimaryBackground)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    /// Estimated age for display — approximate since we only have year + month.
    private var computedAge: Int? {
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        var age = currentYear - draftYear
        if draftMonth > currentMonth {
            age -= 1
        }
        return max(0, age)
    }

    // MARK: - Wheel Area

    private var wheelArea: some View {
        HStack(spacing: AppSpacing.lg) {
            // Year wheel
            VStack(spacing: AppSpacing.xs) {
                Text("年")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)

                TracciWheelPicker(
                    selection: $draftYear,
                    values: yearRange,
                    format: { "\($0)" },
                    chrome: .standalone
                )
            }

            // Month wheel
            VStack(spacing: AppSpacing.xs) {
                Text("月")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)

                TracciWheelPicker(
                    selection: $draftMonth,
                    values: monthRange,
                    format: { String(format: "%02d", $0) },
                    chrome: .standalone
                )
                .frame(width: 100)
            }
        }
        .frame(maxWidth: .infinity)
        .tracciPickerHorizontalPadding()
    }

    // MARK: - Confirm

    private func confirmSelection() {
        AppHaptics.success()
        var components = DateComponents()
        components.year = draftYear
        components.month = draftMonth
        components.day = 1
        if let date = calendar.date(from: components) {
            onConfirm(date)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview("Birth Date Picker") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TracciBirthDatePickerSheet(initialDate: nil) { _ in }
        }
}
