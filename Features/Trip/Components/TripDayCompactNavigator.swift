import SwiftUI

/// Lightweight date context for non-itinerary tabs — prev/next stepper, not a second day rail.
struct TripDayCompactNavigator: View {
    @Binding var selectedDayIndex: Int
    let totalDays: Int
    let tripStartDate: String

    private var canGoPrevious: Bool { selectedDayIndex > 1 }
    private var canGoNext: Bool { selectedDayIndex < totalDays }

    var body: some View {
        HStack(spacing: AppSpacing.cozy) {
            stepButton(
                systemName: "chevron.left",
                label: "前一天",
                enabled: canGoPrevious
            ) {
                selectedDayIndex -= 1
            }

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(dateLabel)
                    .font(TripDetailTypography.compactDate)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.xxs) {
                    Text(weekdayLabel)
                        .font(TripDetailTypography.compactWeekday)
                        .foregroundStyle(AppColors.textMuted)

                    if isToday {
                        Text("今天")
                            .font(TripDetailTypography.dayBadge)
                            .foregroundStyle(AppColors.brandPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppColors.brandPrimaryBackground.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            Spacer(minLength: 8)

            stepButton(
                systemName: "chevron.right",
                label: "后一天",
                enabled: canGoNext
            ) {
                selectedDayIndex += 1
            }
        }
        .padding(.horizontal, TripDetailLayout.pageInset)
        .padding(.vertical, AppSpacing.xxs)
    }

    private func stepButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard enabled else { return }
            AppHaptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(TripDetailTypography.chromeIcon)
                .foregroundStyle(enabled ? AppColors.textMuted : AppColors.textDisabled.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(AppColors.subtleBackground.opacity(enabled ? 0.55 : 0.25))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var isToday: Bool {
        TripDayRail.isToday(dayIndex: selectedDayIndex, tripStartDate: tripStartDate)
    }

    private var dateLabel: String {
        formattedString(format: "MM.dd") ?? "--"
    }

    private var weekdayLabel: String {
        formattedString(format: "EEE") ?? ""
    }

    private var accessibilityLabel: String {
        if isToday {
            return "今天，\(dateLabel)，\(weekdayLabel)"
        }
        return "\(dateLabel)，\(weekdayLabel)"
    }

    private func formattedString(format: String) -> String? {
        guard let startDate = TripDateFormatting.date(from: tripStartDate),
              let date = TracciDateContext.calendar.date(
                  byAdding: .day,
                  value: selectedDayIndex - 1,
                  to: TracciDateContext.startOfBusinessDay(for: startDate)
              )
        else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = TracciDateContext.calendar
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

