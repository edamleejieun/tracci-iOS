import Observation
import SwiftUI

// MARK: - View Model

/// 「加入行程」选择器：先选旅程、再选日期，确认后追加节点。
///
/// 仅当存在规划中 / 进行中旅程时显示；两段式选择在同一 sheet 内完成，
/// 避免多次跳转。选中日期后点底部确认提交，成功后自动关闭。
@MainActor
@Observable
final class SavedPlaceAddToTripViewModel {
    let place: SavedPlace
    private let provider: any SavedPlaceTripProviding

    var trips: [SavedPlaceTripSummary] = []
    var days: [SavedPlaceTripDay] = []
    var selectedTripId: String?
    var selectedDayId: String?
    var isLoadingTrips = false
    var isLoadingDays = false
    var isSubmitting = false
    var errorMessage: String?
    var justAddedTripId: String?

    /// 防止快速切换旅程时，旧的 `loadDays` 回写覆盖当前选择。
    private var daysRequestGeneration = 0

    init(place: SavedPlace, provider: any SavedPlaceTripProviding) {
        self.place = place
        self.provider = provider
    }

    var canSubmit: Bool {
        selectedTripId != nil && selectedDayId != nil && !isSubmitting
    }

    /// 当前选中旅程与收藏地点的城市/目的地是否可能不一致（用于轻提示，不拦截提交）。
    var selectedTripDestinationMismatchHint: String? {
        guard let tripId = selectedTripId,
              let trip = trips.first(where: { $0.id == tripId }),
              !Self.destinationLikelyMatches(place: place, trip: trip)
        else { return nil }
        return "这个地点可能与旅程目的地不一致，加入时可能会失败"
    }

    func load() async {
        isLoadingTrips = true
        errorMessage = nil
        defer { isLoadingTrips = false }
        do {
            let loaded = try await provider.loadActiveTrips()
            trips = Self.sortedTrips(loaded, for: place)
            if trips.isEmpty {
                errorMessage = SavedPlaceAddToTripError.noActiveTrips.message
            }
        } catch {
            errorMessage = SavedPlaceAddToTripError.addFailed(error).message
        }
    }

    /// 目的地更可能匹配的旅程排前面，降低误选后撞 42243 的概率。
    private static func sortedTrips(
        _ trips: [SavedPlaceTripSummary],
        for place: SavedPlace
    ) -> [SavedPlaceTripSummary] {
        trips.sorted { lhs, rhs in
            let lhsMatch = destinationLikelyMatches(place: place, trip: lhs)
            let rhsMatch = destinationLikelyMatches(place: place, trip: rhs)
            if lhsMatch != rhsMatch { return lhsMatch && !rhsMatch }
            return lhs.startDate < rhs.startDate
        }
    }

    static func destinationLikelyMatches(place: SavedPlace, trip: SavedPlaceTripSummary) -> Bool {
        let tripDestination = trip.destinationName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tripDestination.isEmpty else { return true }

        let placeCity: String = {
            if let city = place.place.cityName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !city.isEmpty {
                return city
            }
            if place.place.placeScope == .destination {
                return place.place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }()
        guard !placeCity.isEmpty else { return true }
        return tripDestination.contains(placeCity) || placeCity.contains(tripDestination)
    }

    func selectTrip(_ trip: SavedPlaceTripSummary) {
        // 再次点同一旅程：收起日期列表。
        if selectedTripId == trip.id {
            daysRequestGeneration += 1
            selectedTripId = nil
            selectedDayId = nil
            days = []
            isLoadingDays = false
            errorMessage = nil
            return
        }

        selectedTripId = trip.id
        selectedDayId = nil
        days = []
        daysRequestGeneration += 1
        let generation = daysRequestGeneration
        Task { await loadDays(tripId: trip.id, generation: generation) }
    }

    func selectDay(_ day: SavedPlaceTripDay) {
        selectedDayId = day.id
        AppHaptics.selection()
    }

    private func loadDays(tripId: String, generation: Int) async {
        isLoadingDays = true
        errorMessage = nil
        defer {
            if generation == daysRequestGeneration {
                isLoadingDays = false
            }
        }
        do {
            let loaded = try await provider.loadTripDays(tripId: tripId)
            guard generation == daysRequestGeneration else { return }
            days = loaded
            if days.isEmpty {
                errorMessage = SavedPlaceAddToTripError.noDays.message
            }
        } catch {
            guard generation == daysRequestGeneration else { return }
            errorMessage = SavedPlaceAddToTripError.addFailed(error).message
        }
    }

    func submit() async -> Bool {
        guard let tripId = selectedTripId, let dayId = selectedDayId else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await provider.addSavedPlace(place, toTripId: tripId, dayId: dayId)
            justAddedTripId = tripId
            AppHaptics.success()
            return true
        } catch {
            errorMessage = SavedPlaceAddToTripError.addFailed(error).message
            return false
        }
    }
}

// MARK: - Sheet

/// 选择旅程与日期的 sheet。
///
/// 取消与提交成功都走统一的 `onDismiss(didAdd:)`，由调用方清理 presentation 状态并决定是否刷新。
struct SavedPlaceAddToTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SavedPlaceAddToTripViewModel
    let onDismiss: (_ didAdd: Bool) -> Void

    init(
        place: SavedPlace,
        provider: any SavedPlaceTripProviding,
        onDismiss: @escaping (_ didAdd: Bool) -> Void
    ) {
        _model = State(initialValue: SavedPlaceAddToTripViewModel(place: place, provider: provider))
        self.onDismiss = onDismiss
    }

    private var placeName: String { model.place.place.name }

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: "加入行程",
                showsSaveButton: false,
                presentation: .sheet,
                onCancel: { close(didAdd: false) }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    placeHeader

                    if let errorMessage = model.errorMessage, model.trips.isEmpty {
                        EmptyStateView(
                            title: "暂时无法加载旅程",
                            subtitle: errorMessage,
                            buttonTitle: nil,
                            systemImage: "map"
                        )
                    } else if model.isLoadingTrips {
                        InlineLoadingStateView(message: "正在加载旅程")
                    } else if model.trips.isEmpty {
                        EmptyStateView(
                            title: "还没有进行中的旅程",
                            subtitle: "创建旅程后，就可以把收藏地点加入行程了",
                            buttonTitle: nil,
                            systemImage: "bookmark"
                        )
                    } else {
                        tripList
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.vertical, AppSpacing.md)
                .padding(.bottom, AppSpacing.pageBottom)
            }
        }
        .background(AppColors.pageBackground.ignoresSafeArea())
        .task { await model.load() }
        .overlay(alignment: .bottom) {
            if model.canSubmit {
                submitBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppMotion.quick, value: model.canSubmit)
        .animation(AppMotion.quick, value: model.selectedTripId)
    }

    // MARK: - Place Header

    private var placeHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("把")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)
            Text(placeName)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
            Text("加入以下旅程")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xxs)
    }

    // MARK: - Trip List

    private var tripList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("选择旅程")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
                .padding(.horizontal, AppSpacing.xxs)

            ForEach(model.trips) { trip in
                SavedPlaceTripRow(
                    trip: trip,
                    isSelected: trip.id == model.selectedTripId,
                    isShowingDays: trip.id == model.selectedTripId,
                    days: trip.id == model.selectedTripId ? model.days : [],
                    selectedDayId: trip.id == model.selectedTripId ? model.selectedDayId : nil,
                    isLoadingDays: trip.id == model.selectedTripId && model.isLoadingDays,
                    onSelectTrip: { model.selectTrip(trip) },
                    onSelectDay: { day in model.selectDay(day) }
                )
            }

            if let mismatchHint = model.selectedTripDestinationMismatchHint,
               model.errorMessage == nil {
                Text(mismatchHint)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.horizontal, AppSpacing.xxs)
            }

            if let errorMessage = model.errorMessage,
               model.selectedTripId != nil {
                Text(errorMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    // MARK: - Submit Bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)

            Button {
                Task {
                    guard await model.submit() else { return }
                    try? await Task.sleep(for: .milliseconds(360))
                    close(didAdd: true)
                }
            } label: {
                Group {
                    if model.isSubmitting {
                        ProgressView()
                            .tint(AppColors.textPrimaryInverse)
                    } else if model.justAddedTripId != nil {
                        Label("已加入", systemImage: "checkmark")
                            .font(AppTypography.buttonTitle)
                            .foregroundStyle(AppColors.textPrimaryInverse)
                    } else {
                        Text("加入行程")
                            .font(AppTypography.buttonTitle)
                            .foregroundStyle(AppColors.textPrimaryInverse)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                        .fill(model.justAddedTripId != nil ? AppColors.success : AppColors.brandPrimary)
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isSubmitting)
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.pageBackground)
        }
    }

    private func close(didAdd: Bool) {
        onDismiss(didAdd)
        dismiss()
    }
}

// MARK: - Trip Row (with inline day picker)

private struct SavedPlaceTripRow: View {
    let trip: SavedPlaceTripSummary
    let isSelected: Bool
    let isShowingDays: Bool
    let days: [SavedPlaceTripDay]
    let selectedDayId: String?
    let isLoadingDays: Bool
    let onSelectTrip: () -> Void
    let onSelectDay: (SavedPlaceTripDay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelectTrip) {
                HStack(spacing: AppSpacing.md) {
                    ZStack {
                        AppColors.brandPrimaryBackground
                        Image(systemName: "map.fill")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.brandPrimary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(trip.title)
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        tripMeta
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TripStatusBadge(status: trip.status)

                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .padding(AppSpacing.cozy)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(isSelected ? AppColors.brandPrimary : AppColors.borderSubtle, lineWidth: isSelected ? 1.2 : 0.7)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("旅程：\(trip.title)")
            .accessibilityHint(isSelected ? "已展开日期列表" : "点按展开日期列表")

            if isShowingDays {
                daySection
                    .padding(.top, AppSpacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var tripMeta: some View {
        HStack(spacing: AppSpacing.xs) {
            if let destination = trip.destinationName {
                Text(destination)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Text("·")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textDisabled)
            }
            Text(dateRange)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)
        }
        .lineLimit(1)
    }

    private var dateRange: String {
        let start = ItineraryTimeFormatting.displayDate(trip.startDate) ?? trip.startDate
        let end = ItineraryTimeFormatting.displayDate(trip.endDate) ?? trip.endDate
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private var daySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("选择日期")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)
                .padding(.horizontal, AppSpacing.xxs)

            if isLoadingDays {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .tint(AppColors.brandPrimary)
                        .scaleEffect(0.8)
                    Text("正在加载日期")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }
                .padding(AppSpacing.cozy)
            } else {
                ForEach(days) { day in
                    SavedPlaceDayRow(
                        day: day,
                        isSelected: day.id == selectedDayId,
                        onSelect: { onSelectDay(day) }
                    )
                }
            }
        }
        .padding(.leading, AppSpacing.lg)
    }
}

// MARK: - Day Row

private struct SavedPlaceDayRow: View {
    let day: SavedPlaceTripDay
    let isSelected: Bool
    let onSelect: () -> Void

    private var dayLabel: String {
        let weekday = ItineraryTimeFormatting.weekday(day.date)
        let date = ItineraryTimeFormatting.displayDate(day.date) ?? day.date
        // dayIndex 契约从 1 开始，与行程页「第 N 天」一致。
        var label = "第 \(day.dayIndex) 天 · \(date)"
        if !weekday.isEmpty { label += " \(weekday)" }
        return label
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    isSelected ? AppColors.brandPrimaryBackground : AppColors.subtleBackground
                    Text("\(day.dayIndex)")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textSecondary)
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                Text(dayLabel)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if day.nodeCount > 0 {
                    Text("\(day.nodeCount) 个节点")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.textMuted)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.cozy)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(isSelected ? AppColors.brandPrimary : Color.clear, lineWidth: 1.2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "已选中，可点底部加入行程" : "点按选中这一天")
    }
}

// MARK: - Status Badge

private struct TripStatusBadge: View {
    let status: TripStatus

    var body: some View {
        Text(status.label)
            .font(AppTypography.micro)
            .foregroundStyle(status.statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(status.statusColor.opacity(0.12))
            )
    }
}
