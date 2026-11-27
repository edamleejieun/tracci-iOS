import SwiftUI
import TracciNetworking
import UIKit

struct ItineraryNodeEditView: View {
    @Bindable var itinerary: ItineraryViewModel
    let onUpdated: () -> Void
    let onClose: () -> Void

    @State private var model: ItineraryNodeEditViewModel
    @State private var path: [Route] = []
    @State private var titleDraft: String
    @State private var noteDraft: String
    @State private var showingDiscardConfirmation = false
    @FocusState private var focusedField: FocusedField?
    @FocusState private var isNoteFocused: Bool

    private let nodeTypes: [ItineraryNodeType] = [
        .attraction, .restaurant, .transport, .hotel, .shopping, .other
    ]

    init(
        mode: ItineraryNodeFormMode,
        itinerary: ItineraryViewModel,
        onUpdated: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.itinerary = itinerary
        self.onUpdated = onUpdated
        self.onClose = onClose

        let node: ItineraryNodeItem
        let isNoteOnly: Bool
        switch mode {
        case let .edit(item):
            node = item
            isNoteOnly = false
        case let .editNote(item):
            node = item
            isNoteOnly = true
        case .create:
            preconditionFailure("ItineraryNodeEditView does not handle create")
        }

        _model = State(
            initialValue: ItineraryNodeEditViewModel(
                node: node,
                isNoteOnly: isNoteOnly,
                itinerary: itinerary
            )
        )
        _titleDraft = State(initialValue: node.title)
        _noteDraft = State(initialValue: node.note ?? "")
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                FormSheetTopBar(
                    title: model.isNoteOnly ? "行程详情" : "编辑行程",
                    cancelTitle: "关闭",
                    isCancelEnabled: !model.isMutating,
                    showsSaveButton: false,
                    presentation: .sheet,
                    onCancel: requestClose
                )

                if let mutationError = model.mutationError {
                    Text(mutationError)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.pageX)
                        .padding(.bottom, AppSpacing.sm)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.sectionSpacingCompact) {
                        if model.isNoteOnly {
                            lockedHint
                        }

                        daySection
                        typeSection
                        placeSection
                        if model.form.type == .transport || model.form.type == .hotel {
                            detailsEntry
                        }
                        if model.form.type != .hotel {
                            timeSection
                        }
                        if model.form.type != .transport {
                            titleEditor
                        }
                        noteEditor
                    }
                    .padding(.horizontal, AppSpacing.pageX)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.pageBottom)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(AppColors.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .placeSearch:
                    placeSearchDestination
                case let .savedPlacePicker(keyword):
                    savedPlacePickerDestination(keyword: keyword)
                case .transportDetails:
                    detailsDestination(kind: .transport)
                case .hotelDetails:
                    detailsDestination(kind: .hotel)
                case let .timePicker(field):
                    timePickerDestination(field)
                }
            }
        }
        .tracciDismissKeyboardOnBlankTap()
        .tracciInteractiveDismissDisabled(hasUnsavedDraft || model.isMutating) {
            requestClose()
        }
        .overlay {
            TracciConfirmSheet(
                isPresented: $showingDiscardConfirmation,
                tone: .destructive,
                title: "放弃未保存的修改？",
                message: "标题或备注还没保存。",
                cancelTitle: "继续编辑",
                confirmTitle: "放弃",
                onConfirm: onClose
            )
        }
        .onChange(of: model.form.title) { _, title in
            guard focusedField != .title else { return }
            titleDraft = title
        }
        .onChange(of: model.form.note) { _, note in
            guard !isNoteFocused else { return }
            noteDraft = note
        }
    }

    private var hasUnsavedDraft: Bool {
        titleDraft != model.form.title || noteDraft != model.form.note
    }

    private var formBinding: Binding<ItineraryNodeFormState> {
        Binding(get: { model.form }, set: { model.replaceForm($0) })
    }

    private var lockedHint: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: "lock.fill")
                .font(AppTypography.caption)
                .padding(.top, 1)
            Text("旅程已结束，行程内容已锁定，只能改备注。")
                .font(AppTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppColors.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var daySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("所属天数")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(itinerary.days, id: \.dayIndex) { day in
                        compactChoice(
                            title: "第 \(day.dayIndex) 天",
                            subtitle: ItineraryTimeFormatting.displayDate(day.date),
                            isSelected: model.form.dayIndex == day.dayIndex
                        ) {
                            Task {
                                if await model.updateDay(day.dayIndex) {
                                    onUpdated()
                                }
                            }
                        }
                    }
                }
            }
        }
        .disabled(model.isMutating || model.isNoteOnly)
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("类型")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(nodeTypes, id: \.self) { type in
                        compactChoice(
                            title: type.label,
                            icon: type.icon,
                            isSelected: model.form.type == type
                        ) {
                            Task {
                                if await model.updateType(type) {
                                    onUpdated()
                                }
                            }
                        }
                    }
                }
            }
        }
        .disabled(model.isMutating || model.isNoteOnly)
    }

    private var placeSection: some View {
        TracciSettingsSection(title: "地点") {
            TracciSettingsRow(
                label: model.form.type == .hotel ? "酒店地点" : "地点",
                value: model.locationDisplayName.isEmpty ? "未填写" : model.locationDisplayName,
                systemImage: "mappin.and.ellipse",
                action: model.isNoteOnly ? nil : {
                    dismissKeyboard()
                    path.append(.placeSearch)
                }
            )
        }
        .disabled(model.isMutating || model.isNoteOnly)
    }

    private var detailsEntry: some View {
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
                    Text(detailsSummaryText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
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
        .disabled(model.isMutating)
    }

    private var detailsSummaryText: String {
        if let summary = model.node.detailsSummary, !summary.isEmpty {
            return summary
        }
        return model.form.type == .transport ? "班次、出发地、座位等" : "离店日期、确认号、入住时间等"
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
        }
        .disabled(model.isMutating || model.isNoteOnly)
    }

    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            TracciFocusableFormField(
                label: model.form.type == .hotel ? "住宿名称" : "行程标题",
                systemImage: "textformat",
                placeholder: model.form.type == .hotel ? "留空则使用酒店名称" : "留空则使用地点名称",
                text: $titleDraft,
                errorMessage: nil,
                isOptional: true,
                focus: .title,
                focusedField: $focusedField,
                submitLabel: .done,
                onSubmit: { submitTitleIfNeeded() }
            )

            if !model.isNoteOnly, titleDraft != model.form.title {
                Button("保存") { submitTitleIfNeeded() }
                    .font(AppTypography.labelSemibold)
                    .foregroundStyle(AppColors.interactiveText)
                    .frame(minHeight: 44)
                    .disabled(model.isMutating)
            }
        }
        .disabled(model.isNoteOnly)
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            TracciFormTextArea(
                label: "备注",
                systemImage: "note.text",
                placeholder: "补充安排细节",
                text: $noteDraft,
                errorMessage: model.activeMutation == .note ? model.mutationError : nil,
                isOptional: true,
                contentFocus: $isNoteFocused,
                minHeight: 92,
                maxLength: 500,
                showsCharacterCount: true
            )

            if noteDraft != model.form.note {
                Button("保存") { submitNoteIfNeeded() }
                    .font(AppTypography.labelSemibold)
                    .foregroundStyle(AppColors.interactiveText)
                    .frame(minHeight: 44)
                    .disabled(model.isMutating)
            }
        }
    }

    private var placeSearchDestination: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: "更换地点",
                cancelTitle: "返回",
                showsSaveButton: false,
                presentation: .pushed,
                onCancel: { path.removeLast() }
            )

            ScrollView {
                ItineraryNodePlaceSearchView(
                    configuration: .scopedPlace(context: itinerary.placeSearchContext),
                    savedPlaces: itinerary.matchingSavedPlaces,
                    savedPlaceCount: itinerary.matchingSavedPlaceCount,
                    isLoadingSavedPlaces: itinerary.isLoadingMatchingPlaces,
                    savedPlacesErrorMessage: itinerary.matchingSavedPlacesErrorMessage,
                    onRetrySavedPlaces: { Task { await itinerary.loadMatchingSavedPlaces() } },
                    onSearchSavedPlaces: { keyword in
                        await itinerary.searchMatchingSavedPlaces(keyword: keyword)
                    },
                    onSelectResult: { result in
                        Task {
                            if await model.updatePlace(from: result) {
                                onUpdated()
                                path.removeAll()
                            }
                        }
                    },
                    onUseManual: { name in
                        Task {
                            if await model.updateManualPlace(name) {
                                onUpdated()
                                path.removeAll()
                            }
                        }
                    },
                    onOpenSavedPlaces: { keyword in
                        path.append(.savedPlacePicker(keyword))
                    },
                    onSelectSavedPlace: { savedPlace in
                        Task {
                            if await model.updateSavedPlace(savedPlace) {
                                onUpdated()
                                path.removeAll()
                            }
                        }
                    }
                )
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.pageBottom)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppColors.pageBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await itinerary.loadMatchingSavedPlaces() }
    }

    @ViewBuilder
    private func savedPlacePickerDestination(keyword: String) -> some View {
        if let service = itinerary.savedPlaceServiceForPicker, !itinerary.isDemoMode {
            SavedPlacePickerPage(
                service: service,
                query: SavedPlaceListQuery(usage: .itineraryNode, tripId: itinerary.tripId),
                keyword: keyword,
                contextSubtitle: itinerary.savedPlacePickerContextSubtitle(dayIndex: model.form.dayIndex),
                onSelect: { savedPlace in
                    Task {
                        if await model.updateSavedPlace(savedPlace) {
                            onUpdated()
                            path.removeAll()
                        }
                    }
                },
                onCancel: { path.removeLast() }
            )
        }
    }

    private func detailsDestination(kind: ItineraryNodeOptionalDetailsView.Kind) -> some View {
        ItineraryNodeOptionalDetailsView(
            kind: kind,
            form: formBinding,
            days: itinerary.days,
            isReadOnly: model.isNoteOnly,
            onSelectTime: { field in
                guard !model.isNoteOnly else { return }
                path.append(.timePicker(field))
            },
            onDone: {
                if model.isNoteOnly {
                    popRoute()
                    return
                }
                Task {
                    if await model.commitDetails() {
                        onUpdated()
                        if !path.isEmpty { path.removeLast() }
                    }
                }
            }
        )
    }

    private func timePickerDestination(_ field: ItineraryNodeTimeField) -> some View {
        TracciTimePickerSheet(
            title: field.pickerTitle,
            subtitle: "滑动滚轮选择时分，或轻点常用时间快速填入。",
            date: model.form.initialTimeDate(for: field),
            presentation: .pushed,
            onCancel: popRoute
        ) { selectedTime in
            Task {
                if isEditingDetails {
                    model.applyTimeLocally(selectedTime, for: field)
                } else if await model.updateTime(selectedTime, for: field) {
                    onUpdated()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
                        Task {
                            if await model.clearTime(field) {
                                onUpdated()
                            }
                        }
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

    private func compactChoice(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.caption)
                    }
                }
            }
            .font(AppTypography.label)
            .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textMuted)
            .padding(.horizontal, AppSpacing.cozy)
            .frame(minHeight: 38)
            .background(isSelected ? AppColors.brandPrimary.opacity(0.1) : AppColors.subtleBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var isEditingDetails: Bool {
        path.contains { route in
            switch route {
            case .transportDetails, .hotelDetails: true
            default: false
            }
        }
    }

    private func requestClose() {
        guard !model.isMutating else { return }
        if hasUnsavedDraft {
            showingDiscardConfirmation = true
        } else {
            onClose()
        }
    }

    private func submitTitleIfNeeded() {
        focusedField = nil
        guard titleDraft != model.form.title else { return }
        Task {
            if await model.updateTitle(titleDraft) {
                onUpdated()
            }
        }
    }

    private func submitNoteIfNeeded() {
        isNoteFocused = false
        guard noteDraft != model.form.note else { return }
        Task {
            if await model.updateNote(noteDraft) {
                onUpdated()
            }
        }
    }

    private func popRoute() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private func dismissKeyboard() {
        focusedField = nil
        isNoteFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    private enum Route: Hashable {
        case placeSearch
        case savedPlacePicker(String)
        case transportDetails
        case hotelDetails
        case timePicker(ItineraryNodeTimeField)
    }

    private enum FocusedField: Hashable {
        case title
    }
}

#if DEBUG
#Preview("Edit Itinerary") {
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
    let node = ItineraryNodeItem(
        dto: try! JSONDecoder().decode(
            ItineraryNodeDTO.self,
            from: Data(#"{"id":"preview-node","title":"鼓浪屿","type":"attraction","startTime":"09:30","endTime":"12:00","location":{"name":"鼓浪屿","provider":"APPLE"}}"#.utf8)
        ),
        tripId: trip.id,
        dayId: "day-1",
        dayIndex: 1
    )
    ItineraryNodeEditView(
        mode: .edit(node),
        itinerary: ItineraryViewModel(
            tripId: trip.id,
            trip: trip,
            itineraryService: ItineraryService(apiClient: APIClient()),
            routeProvider: RouteCacheService()
        ),
        onUpdated: {},
        onClose: {}
    )
    .tracciFormSheet()
}
#endif
