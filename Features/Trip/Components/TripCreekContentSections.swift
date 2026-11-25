import SwiftUI

struct TripExpenseCreekSection: View {
    let expenses: [Expense]
    let trip: Trip
    let selectedDayIndex: Int
    let selectedDayPhase: TripDayPhase
    let selectedDayDate: Date?
    let canEdit: Bool
    var itineraryNodes: [ItineraryNodeItem] = []
    var members: [TripMemberResp] = []
    let onEdit: (Expense) -> Void
    var onDuplicate: ((Expense) -> Void)? = nil
    let onDelete: (Expense) -> Void

    var body: some View {
        Group {
            if expenses.isEmpty {
                emptyPrompt
            } else {
                listWithHeader
            }
        }
    }

    private var emptyPrompt: some View {
        // 当天有其他内容但本 Section 为空：同一空态体系的紧凑变体，文案单源
        TripDayEmptyStateView(
            kind: .expense,
            phase: selectedDayPhase,
            canEdit: canEdit && TripEditPolicy.contentAddOutcome(trip: trip).isAllowed,
            destinationName: trip.destinationName,
            tripStatus: trip.effectiveStatus,
            density: .compact
        )
        .padding(.vertical, AppSpacing.xxs)
    }

    private var listWithHeader: some View {
        let totalAmount = expenses.compactMap(\.amountCnyDecimal).reduce(0, +)
        let dateText = selectedDayDate.map(JournalFormatting.editorialDate) ?? ""

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text("Day \(selectedDayIndex)")
                    .font(AppTypography.editorialMeta)
                    .tracking(0.6)
                    .foregroundStyle(AppColors.textMuted)
                if !dateText.isEmpty {
                    Text("·")
                        .font(AppTypography.editorialMeta)
                        .foregroundStyle(AppColors.textDisabled)
                    Text(dateText)
                        .font(AppTypography.editorialMeta)
                        .tracking(0.4)
                        .foregroundStyle(AppColors.textMuted)
                }
                Text("·")
                    .font(AppTypography.editorialMeta)
                    .foregroundStyle(AppColors.textDisabled)
                Text("小计")
                    .font(AppTypography.editorialMeta)
                    .tracking(0.4)
                    .foregroundStyle(AppColors.textMuted)
                Text("¥\(ExpenseFormatters.money(totalAmount))")
                    .font(AppTypography.editorialNumber)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(selectedDayIndex) 天，\(dateText)，小计 \(ExpenseFormatters.cny(totalAmount))，\(expenses.count) 笔")

            TicketStubDivider()

            VStack(spacing: AppSpacing.tight) {
                ForEach(expenses) { expense in
                    ExpenseListItemView(
                        expense: expense,
                        onTap: { onEdit(expense) },
                        onDuplicate: canEdit ? { onDuplicate?(expense) } : nil,
                        onDelete: { onDelete(expense) },
                        canManage: TripCreekContentPolicy.canManageExpense(
                            trip: trip,
                            canEdit: canEdit
                        ),
                        linkedTitle: expense.linkedTitle(in: itineraryNodes),
                        members: members
                    )
                }
            }
        }
    }
}

private struct TicketStubDivider: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                path,
                with: .color(AppColors.borderSubtle),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

struct TripJournalCreekSection: View {
    let journalDay: JournalDayGroup?
    let trip: Trip
    let selectedDayPhase: TripDayPhase
    let isSelectedDayToday: Bool
    let canEdit: Bool
    let currentUserId: String?
    var isCollaborative: Bool = false
    var weatherItem: TripWeatherDisplayItem? = nil
    let onEdit: (JournalEntry) -> Void
    let onToggleHighlight: (JournalEntry) -> Void
    let onToggleFeaturedPhoto: ((JournalPhoto) -> Void)?
    let onDelete: (JournalEntry) -> Void

    var body: some View {
        Group {
            if let journalDay, !journalDay.entries.isEmpty {
                dayPage(journalDay)
            } else {
                emptyPrompt
            }
        }
    }

    private var emptyPrompt: some View {
        // 当天有其他内容但本 Section 为空：同一空态体系的紧凑变体，文案单源
        TripDayEmptyStateView(
            kind: .journal,
            phase: selectedDayPhase,
            canEdit: canEdit && TripEditPolicy.contentAddOutcome(trip: trip).isAllowed,
            destinationName: trip.destinationName,
            tripStatus: trip.effectiveStatus,
            density: .compact
        )
        .padding(.vertical, AppSpacing.xxs)
    }

    private func dayPage(_ day: JournalDayGroup) -> some View {
        let entries = day.entries
        return AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: AppSpacing.cardSmall) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                dayHeader(day)

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    JournalEntryCard(
                        entry: entry,
                        mood: entry.mood,
                        showsAuthor: isCollaborative,
                        photoDensity: entries.count > 1 && index == 0 ? .compact : .regular,
                        onEdit: { onEdit(entry) },
                        onToggleHighlight: { onToggleHighlight(entry) },
                        onToggleFeaturedPhoto: onToggleFeaturedPhoto,
                        onDelete: { onDelete(entry) },
                        canManage: TripCreekContentPolicy.canManageJournal(
                            entry,
                            trip: trip,
                            canEdit: canEdit,
                            currentUserId: currentUserId
                        )
                    )

                    if index < entries.count - 1 {
                        Rectangle()
                            .fill(AppColors.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.vertical, AppSpacing.xxs)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dayHeaderAccessibility(day))
    }

    private func dayHeader(_ day: JournalDayGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text(headerText(day))
                .font(AppTypography.editorialMeta)
                .tracking(0.7)
                .foregroundStyle(AppColors.textMuted)
                .textCase(nil)

            Spacer(minLength: AppSpacing.xs)

            if isSelectedDayToday, let weatherItem {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: weatherItem.sfSymbolName)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    if let temp = weatherItem.compactTemperatureText {
                        Text(temp)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel(weatherItem.weather)
            }
        }
    }

    private func headerText(_ day: JournalDayGroup) -> String {
        var parts = [
            JournalFormatting.editorialDate(day.date),
            JournalFormatting.editorialWeekday(day.date)
        ]
        if let destination = trip.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !destination.isEmpty {
            parts.append(destination)
        }
        parts.append("\(day.entries.count) 篇")
        return parts.joined(separator: " · ")
    }

    private func dayHeaderAccessibility(_ day: JournalDayGroup) -> String {
        headerText(day)
    }
}

enum TripCreekContentPolicy {
    static func canManageJournal(
        _ entry: JournalEntry,
        trip: Trip,
        canEdit: Bool,
        currentUserId: String?
    ) -> Bool {
        guard canEdit,
              TripEditPolicy.contentEditOutcome(trip: trip).isAllowed,
              let currentUserId
        else { return false }
        return entry.authorId == currentUserId
    }

    static func canManageExpense(trip: Trip, canEdit: Bool) -> Bool {
        canEdit && TripEditPolicy.contentEditOutcome(trip: trip).isAllowed
    }
}
