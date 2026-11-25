import SwiftUI
import TracciNetworking
import UIKit

struct ItineraryNodeCreateSheet: View {
    @Bindable var viewModel: ItineraryViewModel
    let onSuccess: (String?) -> Void
    let onCancel: () -> Void

    @State private var model: ItineraryNodeCreateViewModel
    @State private var path: [Route] = []
    @State private var showingDiscardConfirmation = false
    @State private var submitTask: Task<Void, Never>?
    @FocusState private var focusedField: FocusedField?
    @FocusState private var isNoteFocused: Bool

    private let nodeTypes: [ItineraryNodeType] = [
        .attraction, .restaurant, .transport, .hotel, .shopping, .other
    ]

    init(
        defaultDayIndex: Int,
        viewModel: ItineraryViewModel,
        onSuccess: @escaping (String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        _model = State(initialValue: ItineraryNodeCreateViewModel(defaultDayIndex: defaultDayIndex))
    }

    var body: some View {
        NavigationStack(path: $path) {
            TracciTaskSheetScaffold(
                title: "添加行程",
                ctaTitle: "添加至第 \(model.form.dayIndex) 天",
                ctaSystemImage: "plus",
                isCTAEnabled: model.hasLocation,
                isCTALoading: viewModel.isSubmitting,
                errorMessage: viewModel.errorMessage,
                isDirty: model.isDirty,
                onAttemptToDismiss: requestDismiss,
                onCancel: requestDismiss,
                onCTA: startSubmission
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.sectionSpacingCompact) {
                    daySummary

                    if model.hasLocation {
                        selectedLocationCard
                        typeSection
                        optionalFields
                    } else {
                        placeSearch
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .transportDetails:
                    ItineraryNodeOptionalDetailsView(
                        kind: .transport,
                        form: formBinding,
                        days: viewModel.days,
                        onSelectTime: { path.append(.timePicker($0)) },
                        onDone: { path.removeLast() }
                    )
                case .hotelDetails:
                    ItineraryNodeOptionalDetailsView(
                        kind: .hotel,
                        form: formBinding,
                        days: viewModel.days,
                        onSelectTime: { path.append(.timePicker($0)) },
                        onDone: { path.removeLast() }
                    )
                case let .timePicker(field):
                    TracciTimePickerSheet(
                        title: field.pickerTitle,
                        subtitle: "滑动滚轮选择时分，或轻点常用时间快速填入。",
                        date: model.form.initialTimeDate(for: field),
                        presentation: .pushed,
                        onCancel: popRoute
                    ) { selectedTime in
                        var updated = model.form
                        updated.applyTime(selectedTime, for: field)
                        model.replaceForm(updated)
                        clearTimeValidation(for: field)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationBarBackButtonHidden(true)
                case let .savedPlacePicker(keyword):
                    savedPlacePickerDestination(keyword: keyword)
                }
            }
        }
        .task { await viewModel.loadMatchingSavedPlaces() }
        .overlay {
            TracciConfirmSheet(
                isPresented: $showingDiscardConfirmation,
                tone: .destructive,
                title: "放弃添加行程？",
                message: "已选择的地点和填写内容不会保留。",
                cancelTitle: "继续编辑",
                confirmTitle: "放弃",
                onConfirm: onCancel
            )
        }
        .onDisappear {
            submitTask?.cancel()
            submitTask = nil
        }
    }

    private var placeSearch: some View {
        ItineraryNodePlaceSearchView(
            configuration: .scopedPlace(context: viewModel.placeSearchContext),
            savedPlaces: viewModel.matchingSavedPlaces,
            savedPlaceCount: viewModel.matchingSavedPlaceCount,
            isLoadingSavedPlaces: viewModel.isLoadingMatchingPlaces,
            savedPlacesErrorMessage: viewModel.matchingSavedPlacesErrorMessage,
            onRetrySavedPlaces: { Task { await viewModel.loadMatchingSavedPlaces() } },
            onSearchSavedPlaces: { keyword in
                await viewModel.searchMatchingSavedPlaces(keyword: keyword)
            },
            onSelectResult: { result in
                dismissKeyboard()
                model.selectSearchResult(result)
                viewModel.setValidationError(nil, for: .location)
                AppHaptics.success()
            },
            onUseManual: { name in
                dismissKeyboard()
                model.useManualLocation(name)
                viewModel.setValidationError(nil, for: .location)
                AppHaptics.lightImpact()
            },
            onOpenSavedPlaces: { keyword in
                dismissKeyboard()
                path.append(.savedPlacePicker(keyword))
            },
            onSelectSavedPlace: { savedPlace in
                dismissKeyboard()
                model.selectSavedPlace(savedPlace)
                viewModel.setValidationError(nil, for: .location)
                AppHaptics.success()
            }
        )
    }

    private var daySummary: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "calendar")
                .font(AppTypography.buttonTitle)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 40, height: 40)
                .background(AppColors.brandPrimaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("添加到第 \(model.form.dayIndex) 天")
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                if let date = viewModel.days.first(where: { $0.dayIndex == model.form.dayIndex })?.date {
                    Text(ItineraryTimeFormatting.displayDate(date))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }
            }

            Spacer(minLength: 0)

            Text("当前 Day")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
        }
        .padding(AppSpacing.cozy)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .tracciElevation(.l0)
    }

    private var selectedLocationCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: model.form.savedPlaceId == nil ? "mappin.circle.fill" : "bookmark.fill")
                .font(AppTypography.listTitle)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 40, height: 40)
                .background(AppColors.brandPrimaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(model.locationDisplayName)
                    .font(AppTypography.listTitleMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                if let subtitle = model.form.selectedLocation?.address?.nilIfBlank
                    ?? model.form.selectedLocation?.cityName?.nilIfBlank {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(2)
                } else if model.form.selectedLocation == nil {
                    Text("手动地点")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
            }

            Spacer(minLength: 0)

            Button("更换") {
                dismissKeyboard()
                model.resetLocation()
                Task { await viewModel.loadMatchingSavedPlaces() }
            }
            .font(AppTypography.labelSemibold)
            .foregroundStyle(AppColors.brandPrimary)
            .frame(minHeight: 44)
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .tracciElevation(.l1)
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("类型")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(nodeTypes, id: \.self) { type in
                        Button {
                            AppHaptics.selection()
                            model.changeType(type)
                        } label: {
                            Label(type.label, systemImage: type.icon)
                                .font(AppTypography.label)
                                .foregroundStyle(model.form.type == type ? AppColors.brandPrimary : AppColors.textMuted)
                                .padding(.horizontal, AppSpacing.cozy)
                                .frame(minHeight: 38)
                                .background(
                                    model.form.type == type
                                        ? AppColors.brandPrimary.opacity(0.1)
                                        : AppColors.subtleBackground
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("已根据地点建议，可随时修改")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
        }
    }

    @ViewBuilder
    private var optionalFields: some View {
        if model.form.type == .transport || model.form.type == .hotel {
            Button {
                dismissKeyboard()
                path.append(model.form.type == .transport ? .transportDetails : .hotelDetails)
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: model.form.type == .transport ? "tram.fill" : "bed.double.fill")
                        .foregroundStyle(AppColors.brandPrimary)
                        .frame(width: 36, height: 36)
                        .background(AppColors.brandPrimaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(model.form.type == .transport ? "交通信息" : "住宿信息")
                            .font(AppTypography.buttonTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(model.form.type == .transport ? "班次、出发地、座位等" : "离店日期、确认号、入住时间等")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .padding(AppSpacing.cozy)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        if model.form.type != .hotel {
            timeSection
        }

        if model.form.type != .transport {
            TracciFocusableFormField(
                label: model.form.type == .hotel ? "住宿名称" : "行程标题",
                systemImage: "textformat",
                placeholder: model.form.type == .hotel ? "留空则使用酒店名称" : "留空则使用地点名称",
                text: formBinding.title,
                errorMessage: viewModel.validationMessage(for: .title),
                isOptional: true,
                focus: .title,
                focusedField: $focusedField,
                submitLabel: .next,
                onSubmit: {
                    focusedField = nil
                    isNoteFocused = true
                }
            )
        }

        TracciFormTextArea(
            label: "备注",
            systemImage: "note.text",
            placeholder: "补充安排细节",
            text: formBinding.note,
            errorMessage: viewModel.validationMessage(for: .note),
            isOptional: true,
            contentFocus: $isNoteFocused,
            minHeight: 92,
            maxLength: 500,
            showsCharacterCount: true
        )
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(model.form.type == .transport ? "出发与到达" : "时间")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)
            HStack(spacing: AppSpacing.cozy) {
                timePickerField(label: "开始", field: .start)
                timePickerField(label: "结束", field: .end)
            }
            if let message = viewModel.validationMessage(for: .startTime)
                ?? viewModel.validationMessage(for: .endTime) {
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
            }
        }
    }

    private func timePickerField(label: String, field: ItineraryNodeTimeField) -> some View {
        let value = model.form.timeValue(for: field)

        return VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)

            HStack(spacing: AppSpacing.tight) {
                Button {
                    dismissKeyboard()
                    AppHaptics.lightImpact()
                    path.append(.timePicker(field))
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text(value.isEmpty ? "选择时间" : value)
                            .font(value.isEmpty ? AppTypography.formValue : AppTypography.formValueMonospaced)
                            .foregroundStyle(value.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textDisabled)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label)时间，\(value.isEmpty ? "未选择" : value)")
                .accessibilityHint("打开时间选择器")

                if !value.isEmpty {
                    Button {
                        AppHaptics.lightImpact()
                        var updated = model.form
                        updated.clearTime(field)
                        model.replaceForm(updated)
                        clearTimeValidation(for: field)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypography.listTitleMedium)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除\(label)时间")
                }
            }
            .padding(.horizontal, AppSpacing.cozy)
            .frame(minHeight: 48)
            .background(AppColors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var formBinding: Binding<ItineraryNodeFormState> {
        Binding(get: { model.form }, set: { model.replaceForm($0) })
    }

    @ViewBuilder
    private func savedPlacePickerDestination(keyword: String) -> some View {
        if let service = viewModel.savedPlaceServiceForPicker, !viewModel.isDemoMode {
            SavedPlacePickerPage(
                service: service,
                query: SavedPlaceListQuery(usage: .itineraryNode, tripId: viewModel.tripId),
                keyword: keyword,
                contextSubtitle: viewModel.savedPlacePickerContextSubtitle(dayIndex: model.form.dayIndex),
                onSelect: { savedPlace in
                    dismissKeyboard()
                    model.selectSavedPlace(savedPlace)
                    viewModel.setValidationError(nil, for: .location)
                    AppHaptics.success()
                    popRoute()
                },
                onCancel: popRoute
            )
        }
    }

    private func requestDismiss() {
        guard !viewModel.isSubmitting else { return }
        if model.isDirty {
            showingDiscardConfirmation = true
        } else {
            onCancel()
        }
    }

    private func startSubmission() {
        guard submitTask == nil, !viewModel.isSubmitting else { return }
        dismissKeyboard()
        submitTask = Task {
            let createdId = await viewModel.createNode(form: model.form)
            guard !Task.isCancelled else { return }
            if let createdId {
                AppHaptics.success()
                onSuccess(createdId)
            } else {
                AppHaptics.warning()
            }
            submitTask = nil
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        isNoteFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    private enum Route: Hashable {
        case transportDetails
        case hotelDetails
        case timePicker(ItineraryNodeTimeField)
        case savedPlacePicker(String)
    }

    private enum FocusedField: Hashable {
        case title
    }

    private func popRoute() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private func clearTimeValidation(for field: ItineraryNodeTimeField) {
        switch field {
        case .start, .hotelCheckIn:
            viewModel.setValidationError(nil, for: .startTime)
        case .end, .hotelCheckOut:
            viewModel.setValidationError(nil, for: .endTime)
        }
    }
}

#if DEBUG
#Preview("Add Itinerary — Place First") {
    let trip = Trip(
        id: "preview-trip",
        title: "厦门 3 日游",
        startDate: "2026-09-18",
        endDate: "2026-09-20",
        status: .planning,
        totalDays: 3,
        destination: TripDestination(name: "厦门", provider: "APPLE", country: "中国"),
        coverPhoto: nil,
        baseCurrency: "CNY",
        totalCny: nil,
        nodeCount: 0,
        journalCount: 0,
        expenseCount: 0,
        access: TripAccessContext(role: .owner, permissions: [.editContent]),
        createdAt: nil,
        updatedAt: nil
    )
    let apiClient = APIClient()
    ItineraryNodeCreateSheet(
        defaultDayIndex: 1,
        viewModel: ItineraryViewModel(
            tripId: trip.id,
            trip: trip,
            itineraryService: ItineraryService(apiClient: apiClient),
            routeProvider: RouteCacheService()
        ),
        onSuccess: { _ in },
        onCancel: {}
    )
}
#endif
