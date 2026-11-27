import MapKit
import Observation
import SwiftUI

// MARK: - List

@MainActor
@Observable
final class SavedPlacesViewModel {
    let service: any SavedPlaceServicing

    var items: [SavedPlace] = []
    var keyword = ""
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var loadMoreErrorMessage: String?
    var operationErrorMessage: String?

    private var loadedPage = 0
    private var total = 0
    private var queryGeneration = 0
    private var searchTask: Task<Void, Never>?

    init(service: any SavedPlaceServicing) {
        self.service = service
    }

    var hasActiveQuery: Bool {
        !normalizedKeyword.isEmpty
    }

    // MARK: - Display Groups

    /// Groups for the list UI and page header subtitle.
    ///
    /// 目的地保持一组；POI 按城市聚合，无城市 POI 归入「其他地点」。
    var displayGroups: [(label: String, count: Int, items: [SavedPlace])] {
        var groups: [(String, Int, [SavedPlace])] = []
        let destinations = items.filter { $0.place.placeScope == .destination }
        let pois = items.filter { $0.place.placeScope == .poi }

        if !destinations.isEmpty {
            groups.append((label: "目的地", count: destinations.count, items: destinations))
        }
        for cityGroup in SavedPlaceGrouping.cityGroups(of: pois) {
            groups.append((label: cityGroup.city, count: cityGroup.items.count, items: cityGroup.items))
        }
        return groups
    }

    var pageHeaderSubtitle: String {
        let count = total > 0 ? total : items.count
        if count == 0 {
            return "收藏想去的地方，规划时快速选用"
        }
        let groups = displayGroups
        if groups.count <= 1 {
            return "收藏想去的地方，规划时快速选用"
        }
        return "共 \(count) 个收藏，包含目的地和地点"
    }

    func load() async {
        await reload()
    }

    func refresh() async {
        searchTask?.cancel()
        await reload()
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let expectedKeyword = normalizedKeyword
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.normalizedKeyword == expectedKeyword else { return }
            await self.reload()
        }
    }

    func loadMoreIfNeeded(after item: SavedPlace) async {
        guard item.id == items.last?.id,
              !isLoading,
              !isLoadingMore,
              items.count < total
        else { return }

        let generation = queryGeneration
        await request(page: loadedPage + 1, replace: false, generation: generation)
    }

    func updateNote(of item: SavedPlace, note: String) async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String? = trimmed.isEmpty ? nil : trimmed
        guard resolved != item.note?.nilIfBlank else { return }
        guard trimmed.count <= 500 else {
            operationErrorMessage = "备注不能超过 500 字"
            return
        }
        do {
            let updated = try await service.updateNote(savedPlaceId: item.id, note: resolved)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
            }
            operationErrorMessage = nil
        } catch {
            operationErrorMessage = SavedPlaceErrorMessage.resolve(error)
        }
    }

    func delete(_ item: SavedPlace) async -> Bool {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        items.remove(at: index)
        total = max(0, total - 1)
        do {
            try await service.delete(savedPlaceId: item.id)
            operationErrorMessage = nil
            return true
        } catch {
            items.insert(item, at: min(index, items.count))
            total += 1
            operationErrorMessage = SavedPlaceErrorMessage.resolve(error)
            return false
        }
    }

    private var normalizedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reload() async {
        queryGeneration += 1
        let generation = queryGeneration
        loadedPage = 0
        await request(page: 1, replace: true, generation: generation)
    }

    private func request(page: Int, replace: Bool, generation: Int) async {
        if replace { isLoading = true } else { isLoadingMore = true }
        let query = SavedPlaceListQuery(
            keyword: normalizedKeyword,
            page: page,
            pageSize: 20
        )

        do {
            let response = try await service.list(query)
            guard generation == queryGeneration else { return }
            total = response.total
            loadedPage = page
            items = replace ? response.list : items + response.list.filter { candidate in
                !items.contains(where: { $0.id == candidate.id })
            }
            if replace { errorMessage = nil } else { loadMoreErrorMessage = nil }
        } catch is CancellationError {
            // A newer query owns the visible state.
        } catch {
            guard generation == queryGeneration else { return }
            if replace {
                errorMessage = SavedPlaceErrorMessage.resolve(error)
            } else {
                loadMoreErrorMessage = SavedPlaceErrorMessage.resolve(error)
            }
        }

        guard generation == queryGeneration else { return }
        if replace { isLoading = false } else { isLoadingMore = false }
    }
}

struct SavedPlacesView: View {
    @State private var model: SavedPlacesViewModel
    @State private var editorMode: SavedPlaceEditorMode?
    @State private var editingNoteId: String?
    @State private var noteDraft = ""
    @FocusState private var isNoteFocused: Bool
    let onOpenDetail: (String) -> Void

    init(
        service: any SavedPlaceServicing,
        onOpenDetail: @escaping (String) -> Void
    ) {
        _model = State(initialValue: SavedPlacesViewModel(service: service))
        self.onOpenDetail = onOpenDetail
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                AppPageHeader(title: "想去的地点", subtitle: model.pageHeaderSubtitle)

                searchField

                if let operationErrorMessage = model.operationErrorMessage {
                    Text(operationErrorMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                        .padding(.horizontal, AppSpacing.pageX)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Group {
                    if model.isLoading, model.items.isEmpty {
                        SavedPlacesListSkeletonView()
                            .padding(.horizontal, AppSpacing.pageX)
                    } else if let errorMessage = model.errorMessage, model.items.isEmpty {
                        ErrorStateView(title: "暂时无法加载", message: errorMessage) {
                            Task { await model.refresh() }
                        }
                        .padding(.horizontal, AppSpacing.pageX)
                    } else if model.items.isEmpty {
                        savedPlacesEmptyState
                            .padding(.horizontal, AppSpacing.pageX)
                    } else {
                        savedPlaceGroupedList
                    }
                }
            }
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracciDismissKeyboardOnBlankTap()
        .tracciAtmosphere(.creek)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    commitNoteIfNeeded()
                    editorMode = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("收藏地点")
            }
        }
        .sheet(item: $editorMode) { mode in
            SavedPlaceEditorView(service: model.service, mode: mode) {
                editorMode = nil
                Task { await model.refresh() }
            }
            .tracciSheetPresentation(.subSheetFraction(0.92))
        }
        .task { await model.load() }
        .refreshable { await model.refresh() }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textPlaceholder)
            TextField("搜索地点或备注", text: $model.keyword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: model.keyword) { _, _ in model.scheduleSearch() }
                .onSubmit { Task { await model.refresh() } }
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
        .padding(.horizontal, AppSpacing.pageX)
    }

    // MARK: - Empty State

    private var savedPlacesEmptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            CreekDivider(
                style: .quiet,
                opacity: 0.16,
                height: 36,
                lineWidth: 1.1,
                showsMidDot: true
            )

            EmptyStateView(
                title: model.hasActiveQuery ? "没有找到匹配地点" : "还没有收藏地点",
                subtitle: model.hasActiveQuery ? "可以换个关键词再试试" : "搜索地点或备注，创建行程时快速选用",
                buttonTitle: model.hasActiveQuery ? nil : "收藏地点",
                systemImage: model.hasActiveQuery ? "magnifyingglass" : "bookmark.fill",
                action: model.hasActiveQuery ? nil : { editorMode = .create }
            )
        }
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Grouped List

    private var savedPlaceGroupedList: some View {
        LazyVStack(spacing: AppSpacing.md) {
            let groups = model.displayGroups

            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                savedPlaceSection(
                    title: group.label,
                    count: group.count,
                    items: group.items
                )
            }

            if model.isLoadingMore {
                ProgressView()
                    .tint(AppColors.brandPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
            }
            if let loadMoreErrorMessage = model.loadMoreErrorMessage,
               let lastItem = model.items.last {
                Button("加载更多失败，点击重试") {
                    Task { await model.loadMoreIfNeeded(after: lastItem) }
                }
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.interactiveText)
                .accessibilityHint(loadMoreErrorMessage)
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
    }

    private func savedPlaceSection(title: String, count: Int, items: [SavedPlace]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sectionHeaderBottom) {
            SectionHeader(title, trailingText: "\(count) 个")

            TracciGroupedSurface {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            TracciSettingsDivider(leadingInset: AppSpacing.settingsRowHorizontalPadding)
                        }
                        SavedPlaceSimpleRow(
                            item: item,
                            isEditingNote: editingNoteId == item.id,
                            noteDraft: $noteDraft,
                            isNoteFocused: $isNoteFocused,
                            onOpen: {
                                commitNoteIfNeeded()
                                onOpenDetail(item.placeId)
                            },
                            onBeginEditNote: {
                                beginEditingNote(item)
                            },
                            onCommitNote: {
                                commitNoteIfNeeded()
                            }
                        )
                        .onAppear {
                            Task { await model.loadMoreIfNeeded(after: item) }
                        }
                    }
                }
            }
        }
    }

    private func beginEditingNote(_ item: SavedPlace) {
        if editingNoteId != item.id {
            commitNoteIfNeeded()
            editingNoteId = item.id
            noteDraft = item.note ?? ""
        }
        isNoteFocused = true
    }

    private func commitNoteIfNeeded() {
        guard let editingNoteId,
              let item = model.items.first(where: { $0.id == editingNoteId })
        else {
            isNoteFocused = false
            return
        }
        isNoteFocused = false
        self.editingNoteId = nil
        Task { await model.updateNote(of: item, note: noteDraft) }
    }
}

// MARK: - Simple List Row

/// 列表只保留地名和行内备注。点地名进详情；点备注在本页拉起键盘。
/// 两个区域各自满 44pt，互不吞掉对方的点击。
private struct SavedPlaceSimpleRow: View {
    let item: SavedPlace
    let isEditingNote: Bool
    @Binding var noteDraft: String
    var isNoteFocused: FocusState<Bool>.Binding
    let onOpen: () -> Void
    let onBeginEditNote: () -> Void
    let onCommitNote: () -> Void

    private var hasNote: Bool {
        item.note?.nilIfBlank != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Text(item.place.name)
                        .font(AppTypography.settingsRowLabel)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: AppControlMetrics.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.place.name)
            .accessibilityHint("查看地点详情")

            noteControl
        }
        .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var noteControl: some View {
        if isEditingNote {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 20, height: 20)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                TextField("写一句备注", text: $noteDraft, axis: .vertical)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1...3)
                    .focused(isNoteFocused)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(onCommitNote)
                    .onChange(of: isNoteFocused.wrappedValue) { _, focused in
                        if !focused {
                            onCommitNote()
                        }
                    }
                    .accessibilityLabel("备注")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: AppControlMetrics.minimumTapTarget, alignment: .top)
            .background(AppColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.brandPrimary.opacity(0.28), lineWidth: 1)
            }
        } else {
            Button(action: onBeginEditNote) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: hasNote ? "square.and.pencil" : "plus")
                        .font(AppTypography.caption)
                        .foregroundStyle(hasNote ? AppColors.textMuted : AppColors.brandPrimary)
                        .frame(width: 20, height: 20)
                        .padding(.top, 1)
                        .accessibilityHidden(true)

                    Text(hasNote ? (item.note ?? "") : "添加备注")
                        .font(AppTypography.caption)
                        .foregroundStyle(hasNote ? AppColors.textSecondary : AppColors.textPlaceholder)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: AppControlMetrics.minimumTapTarget, alignment: .top)
                .background(AppColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasNote ? "编辑备注" : "添加备注")
            .accessibilityValue(item.note ?? "")
            .accessibilityHint("在当前页编辑备注")
        }
    }
}

// MARK: - Usage Chip

struct SavedPlaceUsageChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bookmark.fill")
                .font(AppTypography.micro)
            Text("已加入 \(count) 趟旅程")
                .font(AppTypography.chipSemibold)
        }
        .foregroundStyle(AppColors.interactiveText)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minHeight: 24)
        .background(
            Capsule()
                .fill(AppColors.brandPrimaryBackground)
        )
    }
}

// MARK: - Editor

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
