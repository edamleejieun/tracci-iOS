import SwiftUI

struct TripDateRangePicker: View {
    let startDate: Date?
    let endDate: Date?
    var startError: String?
    var endError: String?
    var rangeError: String?
    let onStartDateChange: (Date) -> Void
    let onEndDateChange: (Date) -> Void

    @State private var showingRangePicker = false

    private var hasSelection: Bool {
        startDate != nil || endDate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "calendar")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
                Text("旅行日期")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)
            }

            HStack(spacing: AppSpacing.sm) {
                dateButton(
                    title: TripDateFormatting.displayString(from: startDate),
                    subtitle: "出发",
                    hasError: startError != nil || rangeError != nil,
                    isFilled: startDate != nil
                ) {
                    showingRangePicker = true
                }

                connector

                dateButton(
                    title: TripDateFormatting.displayString(from: endDate),
                    subtitle: "返回",
                    hasError: endError != nil || rangeError != nil,
                    isFilled: endDate != nil
                ) {
                    showingRangePicker = true
                }
            }

            if let rangeError {
                errorText(rangeError)
            } else if let startError {
                errorText(startError)
            } else if let endError {
                errorText(endError)
            }
        }
        .sheet(isPresented: $showingRangePicker) {
            TracciDateRangePickerSheet(
                title: "你想去多久？",
                startDate: startDate,
                endDate: endDate
            ) { start, end in
                onStartDateChange(start)
                onEndDateChange(end)
            }
        }
    }

    private var connector: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
                .font(AppTypography.microSemibold)
                .foregroundStyle(hasSelection ? AppColors.brandPrimary.opacity(0.7) : AppColors.textDisabled)
            Text("至")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textDisabled)
        }
        .frame(width: 20)
        .accessibilityHidden(true)
    }

    private func dateButton(
        title: String,
        subtitle: String,
        hasError: Bool,
        isFilled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(AppTypography.chipSemibold)
                    .foregroundStyle(AppColors.textPlaceholder)

                Text(title)
                    .font(AppFont.system(14, weight: isFilled ? .semibold : .medium))
                    .foregroundStyle(isFilled ? AppColors.textPrimary : AppColors.textPlaceholder)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 52)
            .background(backgroundColor(hasError: hasError, isFilled: isFilled))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                if hasError {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppColors.danger.opacity(0.35), lineWidth: 1.5)
                } else if isFilled {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.18), lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableCardStyle(scale: 0.98, opacity: 0.94))
        .accessibilityLabel("\(subtitle)，\(title)")
        .accessibilityHint("打开日期区间选择器")
    }

    private func backgroundColor(hasError: Bool, isFilled: Bool) -> Color {
        if hasError { return AppColors.dangerBackground }
        if isFilled { return AppColors.brandPrimaryBackground.opacity(0.45) }
        return AppColors.subtleBackground
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.danger)
    }
}

#Preview("Empty") {
    TripDateRangePicker(
        startDate: nil,
        endDate: nil,
        onStartDateChange: { _ in },
        onEndDateChange: { _ in }
    )
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Selected") {
    let calendar = TracciDateContext.calendar
    let start = calendar.startOfDay(for: Date())
    let end = calendar.date(byAdding: .day, value: 4, to: start)!

    return TripDateRangePicker(
        startDate: start,
        endDate: end,
        onStartDateChange: { _ in },
        onEndDateChange: { _ in }
    )
    .padding()
    .background(AppColors.backgroundPrimary)
}