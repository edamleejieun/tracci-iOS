import MapKit
import Observation
import SwiftUI

// MARK: - Picker

@MainActor
@Observable
final class SavedPlacePickerViewModel {
    let service: any SavedPlaceServicing
    let baseQuery: SavedPlaceListQuery
    var items: [SavedPlace] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var keyword = ""
    private var loadedPage = 0
    private var total = 0
    private var searchTask: Task<Void, Never>?
    private var requestGeneration = 0

    init(service: any SavedPlaceServicing, query: SavedPlaceListQuery, keyword: String = "") {
        self.service = service
        self.baseQuery = query
        self.keyword = keyword
    }

    private enum PickerConfiguration {
        static let minResultsForSearchBar = 8
    }

    var showsSearch: Bool { total > PickerConfiguration.minResultsForSearchBar && !items.isEmpty }

    func load() async {
        searchTask?.cancel()
        await reload()
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let expected = normalizedKeyword
        let generation = incrementGeneration()
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(280))
            } catch { return }
            guard !Task.isCancelled, let self, self.normalizedKeyword == expected else { return }
            await self.requestReload(generation: generation)
        }
    }

    func loadMoreIfNeeded(after item: SavedPlace) async {
        guard item.id == items.last?.id, !isLoading, !isLoadingMore, items.count < total else { return }
        await request(page: loadedPage + 1, replace: false)
    }

    private var normalizedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func incrementGeneration() -> Int {
        requestGeneration += 1
        return requestGeneration
    }

    private func reload() async {
        let generation = incrementGeneration()
        await requestReload(generation: generation)
    }

    private func requestReload(generation: Int) async {
        guard generation == requestGeneration else { return }
        loadedPage = 0
        await request(page: 1, replace: true, generation: generation)
    }

    private func request(page: Int, replace: Bool, generation: Int? = nil) async {
        let currentGeneration = generation ?? requestGeneration
        if replace { isLoading = true } else { isLoadingMore = true }
        defer {
            if replace { isLoading = false } else { isLoadingMore = false }
        }
        var query = baseQuery
        query.page = page
        if !normalizedKeyword.isEmpty {
            query.keyword = normalizedKeyword
        } else {
            query.keyword = nil
        }
        do {
            let response = try await service.list(query)
            guard currentGeneration == requestGeneration else { return }
            total = response.total
            loadedPage = page
            items = replace ? response.list : items + response.list.filter { candidate in
                !items.contains(where: { $0.id == candidate.id })
            }
            errorMessage = nil
        } catch {
            guard currentGeneration == requestGeneration else { return }
            errorMessage = SavedPlaceErrorMessage.resolve(error)
        }
    }
}

// MARK: - Compact Row (shared by Picker & inline search matches)

/// 紧凑选择行：glyph + 名称 + 城市/地址 + 备注 + 旅程使用 chip。
/// Picker 列表与节点搜索页内嵌命中共用，保证两处信息密度一致。
struct SavedPlaceCompactRow: View {
    let item: SavedPlace
    let onSelect: () -> Void

    var body: some View {
        Button {
            AppHaptics.selection()
            onSelect()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                PlaceCategoryGlyph(
                    scope: item.place.placeScope,
                    category: item.place.category,
                    pointSize: 16,
                    containerSize: 32
                )
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(item.place.name)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let location = item.place.cityName?.nilIfBlank ?? item.place.address?.nilIfBlank {
                        Text(location)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textMuted)
                            .lineLimit(1)
                    }
                    if let note = item.note?.nilIfBlank {
                        Text(note)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    if let count = item.usageSummary?.tripCount, count > 0 {
                        SavedPlaceUsageChip(count: count)
                    }
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.textPlaceholder)
            }
            .padding(AppSpacing.cozy)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - City Grouping

enum SavedPlaceGrouping {
    /// 保持首次出现顺序的城市分组；列表页与 Picker 共用。
    static func cityGroups(of items: [SavedPlace]) -> [(city: String, items: [SavedPlace])] {
        var order: [String] = []
        var bucket: [String: [SavedPlace]] = [:]
        for item in items {
            let key = item.groupingCityKey
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(item)
        }
        return order.map { ($0, bucket[$0] ?? []) }
    }
}

/// Shared scrollable body for saved-place picking: search, pagination, and states.
/// Used by both the sheet presentation (`SavedPlacePickerView`) and the pushed
/// page variant (`SavedPlacePickerPage`) hosted inside itinerary form stacks.
private struct SavedPlacePickerList: View {
    @Bindable var model: SavedPlacePickerViewModel
    /// 选择上下文（如「为 京都 · 第 2 天选择地点」），由调用方给出。
    var contextSubtitle: String? = nil
    let onSelect: (SavedPlace) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                if let contextSubtitle {
                    Text(contextSubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.pageX)
                        .padding(.top, AppSpacing.sm)
                }

                if model.showsSearch {
                    pickerSearchField
                        .padding(.horizontal, AppSpacing.pageX)
                        .padding(.top, AppSpacing.sm)
                }

                if model.isLoading, model.items.isEmpty {
                    InlineLoadingStateView(message: "正在加载想去的地点")
                } else if let errorMessage = model.errorMessage, model.items.isEmpty {
                    ErrorStateView(title: "暂时无法加载", message: errorMessage) {
                        Task { await model.load() }
                    }
                } else if model.items.isEmpty {
                    EmptyStateView(
                        title: model.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "没有适用的收藏地点" : "没有匹配的收藏地点",
                        subtitle: model.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "返回后可以继续用地图搜索或手动输入" : "换个关键词，或返回后用地图搜索",
                        buttonTitle: nil,
                        systemImage: "bookmark"
                    )
                } else {
                    let groups = SavedPlaceGrouping.cityGroups(of: model.items)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            if groups.count > 1 {
                                HStack {
                                    Text(group.city)
                                        .font(AppTypography.label)
                                        .foregroundStyle(AppColors.textMuted)
                                    Spacer()
                                    Text("\(group.items.count) 个")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textPlaceholder)
                                }
                            }

                            ForEach(group.items) { item in
                                SavedPlaceCompactRow(item: item) { onSelect(item) }
                                    .onAppear {
                                        if item.id == model.items.last?.id {
                                            Task { await model.loadMoreIfNeeded(after: item) }
                                        }
                                    }
                            }
                        }
                    }
                    if model.isLoadingMore { ProgressView().padding() }
                    if let errorMessage = model.errorMessage, let lastItem = model.items.last {
                        Button("加载更多失败，点击重试") {
                            Task { await model.loadMoreIfNeeded(after: lastItem) }
                        }
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.interactiveText)
                        .accessibilityHint(errorMessage)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.vertical, AppSpacing.md)
        }
        .task { await model.load() }
    }

    private var pickerSearchField: some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textPlaceholder)
            TextField("搜索收藏地点", text: $model.keyword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: model.keyword) { _, _ in model.scheduleSearch() }
                .onSubmit { Task { await model.load() } }
        }
        .font(AppTypography.body)
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: AppControlMetrics.minimumTapTarget)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 0.7)
        }
    }
}

/// Sheet presentation of the saved-place picker (self-contained NavigationStack + cancel).
struct SavedPlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SavedPlacePickerViewModel
    var contextSubtitle: String? = nil
    let onSelect: (SavedPlace) -> Void

    init(
        service: any SavedPlaceServicing,
        query: SavedPlaceListQuery,
        contextSubtitle: String? = nil,
        onSelect: @escaping (SavedPlace) -> Void
    ) {
        _model = State(initialValue: SavedPlacePickerViewModel(service: service, query: query))
        self.contextSubtitle = contextSubtitle
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            SavedPlacePickerList(model: model, contextSubtitle: contextSubtitle) { item in
                onSelect(item)
                dismiss()
            }
            .tracciAtmosphere(.creek)
            .navigationTitle("从想去的地点选择")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

/// Pushed variant for hosts that already own a NavigationStack and cannot present
/// sheets (itinerary create sheet / edit view). Selection and back are routed
/// through callbacks so the host controls its own navigation path.
struct SavedPlacePickerPage: View {
    @State private var model: SavedPlacePickerViewModel
    var contextSubtitle: String? = nil
    let onSelect: (SavedPlace) -> Void
    let onCancel: () -> Void

    init(
        service: any SavedPlaceServicing,
        query: SavedPlaceListQuery,
        keyword: String = "",
        contextSubtitle: String? = nil,
        onSelect: @escaping (SavedPlace) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _model = State(initialValue: SavedPlacePickerViewModel(service: service, query: query, keyword: keyword))
        self.contextSubtitle = contextSubtitle
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            FormSheetTopBar(
                title: "从想去的地点选择",
                cancelTitle: "返回",
                showsSaveButton: false,
                presentation: .pushed,
                onCancel: onCancel
            )

            SavedPlacePickerList(model: model, contextSubtitle: contextSubtitle, onSelect: onSelect)
                .scrollDismissesKeyboard(.interactively)
        }
        .background(AppColors.pageBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}


