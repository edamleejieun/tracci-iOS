import MapKit
import Observation
import SwiftUI

enum SavedPlaceEditorMode: Identifiable, Equatable {
    case create
    case editNote(SavedPlace)

    var id: String {
        switch self {
        case .create: "create"
        case .editNote(let item): "edit-\(item.id)"
        }
    }
}

@MainActor
@Observable
final class SavedPlaceEditorViewModel {
    let service: any SavedPlaceServicing
    let mode: SavedPlaceEditorMode

    private var scope: PlaceScope = .poi
    private var category: PlaceCategory = .other
    var selectedMapResult: TracciPlaceSearchResult?
    var placeSearchQuery = ""
    var placeSearchResults: [TracciPlaceSearchResult] = []
    var isSearchingPlaces = false
    var placeSearchErrorMessage: String?
    var manualName = ""
    var manualAddress = ""
    var manualCityName = ""
    var note = ""
    var isSubmitting = false
    var errorMessage: String?
    private var placeSearchTask: Task<Void, Never>?
    private var placeSearchGeneration = 0

    init(service: any SavedPlaceServicing, mode: SavedPlaceEditorMode) {
        self.service = service
        self.mode = mode
        if case .editNote(let item) = mode {
            scope = item.place.placeScope
            category = item.place.category
            manualName = item.place.name
            manualAddress = item.place.address ?? ""
            manualCityName = item.place.cityName ?? ""
            note = item.note ?? ""
        }
    }

    var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    var title: String { isCreateMode ? "收藏地点" : "编辑备注" }
    var displayedName: String { selectedMapResult?.name ?? manualName }
    var displayedAddress: String? { selectedMapResult?.address ?? manualAddress.nilIfBlank }
    var trimmedPlaceSearchQuery: String {
        placeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        if isCreateMode {
            return !displayedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && PlaceCategory.allowed(for: scope).contains(category)
        }
        return note.count <= 500
    }

    func selectMapResult(_ result: TracciPlaceSearchResult) {
        let classification = SavedPlaceClassification.infer(
            name: result.name,
            mapCategory: result.category,
            cityName: result.cityName,
            provinceName: result.provinceName
        )
        scope = classification.scope
        category = classification.category
        selectedMapResult = result
        manualName = result.name
        manualAddress = result.address ?? ""
        manualCityName = result.cityName ?? ""
        placeSearchQuery = result.name
        placeSearchResults = []
        placeSearchErrorMessage = nil
        placeSearchGeneration += 1
        placeSearchTask?.cancel()
    }

    func useManualName(_ name: String) {
        scope = SavedPlaceClassification.manual.scope
        category = SavedPlaceClassification.manual.category
        selectedMapResult = nil
        manualName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        manualAddress = ""
        manualCityName = ""
        placeSearchQuery = manualName
        placeSearchResults = []
        placeSearchErrorMessage = nil
        placeSearchGeneration += 1
        placeSearchTask?.cancel()
    }

    func schedulePlaceSearch() {
        placeSearchTask?.cancel()
        placeSearchGeneration += 1
        let generation = placeSearchGeneration
        let keyword = trimmedPlaceSearchQuery

        if selectedMapResult?.name == keyword || (!manualName.isEmpty && manualName == keyword) {
            placeSearchResults = []
            placeSearchErrorMessage = nil
            isSearchingPlaces = false
            return
        }

        selectedMapResult = nil
        manualName = ""
        manualAddress = ""
        manualCityName = ""

        guard keyword.count >= 2 else {
            placeSearchResults = []
            placeSearchErrorMessage = nil
            isSearchingPlaces = false
            return
        }

        placeSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled, let self else { return }
            await self.searchPlaces(keyword: keyword, generation: generation)
        }
    }

    func performPlaceSearch() {
        let keyword = trimmedPlaceSearchQuery
        guard keyword.count >= 2 else { return }
        guard selectedMapResult?.name != keyword, manualName != keyword else { return }
        placeSearchTask?.cancel()
        placeSearchGeneration += 1
        let generation = placeSearchGeneration
        placeSearchTask = Task { [weak self] in
            await self?.searchPlaces(keyword: keyword, generation: generation)
        }
    }

    func cancelPlaceSearch() {
        placeSearchGeneration += 1
        placeSearchTask?.cancel()
    }

    private func searchPlaces(keyword: String, generation: Int) async {
        guard generation == placeSearchGeneration else { return }
        isSearchingPlaces = true
        placeSearchErrorMessage = nil
        defer {
            if generation == placeSearchGeneration {
                isSearchingPlaces = false
            }
        }

        do {
            let results = try await TracciPlaceSearchEngine.search(
                keyword: keyword,
                configuration: .scopedPlace(context: .unscoped, allowsManualEntry: true)
            )
            guard generation == placeSearchGeneration else { return }
            placeSearchResults = results
        } catch is CancellationError {
            // A newer query owns the visible results.
        } catch {
            guard !Task.isCancelled else { return }
            placeSearchResults = []
            placeSearchErrorMessage = "请稍后再试，或直接使用当前输入的地点名称。"
        }
    }

    func submit() async -> Bool {
        guard isValid, !isSubmitting else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            switch mode {
            case .create:
                let input = locationInput
                _ = try await service.create(
                    .locationCandidate(
                        scope: scope,
                        category: category,
                        location: input,
                        note: nil
                    )
                )
            case .editNote(let item):
                _ = try await service.updateNote(savedPlaceId: item.id, note: note.nilIfBlank ?? "")
            }
            return true
        } catch {
            errorMessage = SavedPlaceErrorMessage.resolve(error)
            return false
        }
    }

    private var locationInput: SavedPlaceLocationInput {
        if let result = selectedMapResult {
            return SavedPlaceLocationInput(
                name: result.name,
                address: result.address,
                provider: "APPLE",
                providerPlaceId: result.providerPlaceId,
                country: result.country,
                provinceName: result.provinceName,
                cityName: result.cityName,
                districtName: result.districtName,
                latitude: result.latitude,
                longitude: result.longitude,
                adcode: nil,
                cityCode: nil
            )
        }
        return SavedPlaceLocationInput(
            name: manualName.trimmingCharacters(in: .whitespacesAndNewlines),
            address: manualAddress.nilIfBlank,
            provider: "MANUAL",
            providerPlaceId: nil,
            country: nil,
            provinceName: nil,
            cityName: manualCityName.nilIfBlank,
            districtName: nil,
            latitude: nil,
            longitude: nil,
            adcode: nil,
            cityCode: nil
        )
    }

}

struct SavedPlaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SavedPlaceEditorViewModel
    @State private var showSaveSuccess = false
    let onSuccess: () -> Void

    init(service: any SavedPlaceServicing, mode: SavedPlaceEditorMode = .create, onSuccess: @escaping () -> Void) {
        _model = State(initialValue: SavedPlaceEditorViewModel(service: service, mode: mode))
        self.onSuccess = onSuccess
    }

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: model.title,
                saveTitle: model.isCreateMode ? "收藏" : "保存",
                isSubmitting: model.isSubmitting,
                isSaveEnabled: model.isValid,
                showSaveSuccess: showSaveSuccess,
                onCancel: { dismiss() },
                onSave: submit
            )

            ScrollView {
                VStack(spacing: AppSpacing.formSectionSpacing) {
                    if model.isCreateMode {
                        locationSection
                    } else {
                        placeSummarySection
                        noteSection
                    }
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.vertical, AppSpacing.md)
                .padding(.bottom, AppSpacing.pageBottom)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tracciAtmosphere(.creek)
        .tracciFormSheet()
        .onDisappear { model.cancelPlaceSearch() }
    }

    private var locationSection: some View {
        FormSection("地点", subtitle: "直接搜索并选择；找不到时可使用输入的名称") {
            VStack(spacing: 0) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textPlaceholder)
                    TextField("搜索地点、餐厅、景点", text: $model.placeSearchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onChange(of: model.placeSearchQuery) { _, _ in model.schedulePlaceSearch() }
                        .onSubmit { model.performPlaceSearch() }
                    if !model.placeSearchQuery.isEmpty {
                        Button {
                            model.placeSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColors.textDisabled)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, AppSpacing.cardSmall)
                .frame(minHeight: 48)

                Group {
                    if let selectedResult = model.selectedMapResult {
                        selectedPlaceSummary(name: selectedResult.name, address: selectedResult.address)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if !model.manualName.isEmpty {
                        selectedPlaceSummary(name: model.manualName, address: nil)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if model.isSearchingPlaces {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView().tint(AppColors.brandPrimary)
                            Text("正在搜索地点")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textMuted)
                        }
                        .padding(AppSpacing.cardSmall)
                    } else if let message = model.placeSearchErrorMessage {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(message)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textMuted)
                            Button("重新搜索") { model.performPlaceSearch() }
                                .font(AppTypography.captionSemibold)
                                .foregroundStyle(AppColors.interactiveText)
                        }
                        .padding(AppSpacing.cardSmall)
                    } else if !model.placeSearchResults.isEmpty {
                        VStack(spacing: AppSpacing.sm) {
                            ForEach(model.placeSearchResults) { result in
                                Button {
                                    model.selectMapResult(result)
                                    AppHaptics.selection()
                                } label: {
                                    TracciPlaceSearchResultRow(result: result)
                                }
                                .pressableCardStyle(scale: 0.985, opacity: 0.94)
                            }
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.sm)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if model.trimmedPlaceSearchQuery.count >= 2 {
                        Text("没有找到匹配地点，可以直接使用当前输入")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPlaceholder)
                            .padding(.horizontal, AppSpacing.cardSmall)
                            .padding(.bottom, AppSpacing.sm)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: model.selectedMapResult)

                if model.displayedName.isEmpty, !model.trimmedPlaceSearchQuery.isEmpty {
                    Button {
                        model.useManualName(model.trimmedPlaceSearchQuery)
                        AppHaptics.selection()
                    } label: {
                        Label("使用\"\(model.trimmedPlaceSearchQuery)\"", systemImage: "pencil.line")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.cardSmall)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func selectedPlaceSummary(name: String, address: String?) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.brandPrimary)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(name)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                if let address = address?.nilIfBlank {
                    Text(address)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(AppSpacing.cardSmall)
    }

    private var placeSummarySection: some View {
        FormSection("地点") {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(model.displayedName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                if let address = model.displayedAddress {
                    Text(address)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.cardSmall)
        }
    }

    private var noteSection: some View {
        FormSection("备注", subtitle: "可选，仅自己可见，最多 500 字") {
            TextField("例如：想试试季节限定菜单", text: $model.note, axis: .vertical)
                .font(AppTypography.body)
                .lineLimit(3...7)
                .padding(AppSpacing.cardSmall)
            HStack {
                Spacer()
                Text("\(model.note.count) / 500")
                    .font(AppTypography.caption)
                    .foregroundStyle(model.note.count > 500 ? AppColors.danger : AppColors.textMuted)
            }
            .padding(.horizontal, AppSpacing.cardSmall)
            .padding(.bottom, AppSpacing.sm)
        }
    }

    private func submit() {
        Task {
            guard await model.submit() else { return }
            showSaveSuccess = true
            AppHaptics.success()
            try? await Task.sleep(for: .milliseconds(260))
            onSuccess()
        }
    }
}


