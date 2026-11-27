import SwiftUI

struct ItineraryNodePlaceSearchView: View {
    let configuration: TracciPlaceSearchConfiguration
    let savedPlaces: [SavedPlace]
    let savedPlaceCount: Int
    let isLoadingSavedPlaces: Bool
    let savedPlacesErrorMessage: String?
    let onRetrySavedPlaces: () -> Void
    let onSearchSavedPlaces: (String) async -> Void
    let onSelectResult: (TracciPlaceSearchResult) -> Void
    let onUseManual: (String) -> Void
    let onOpenSavedPlaces: (String) -> Void
    /// 搜索词命中收藏时，原位点击某条收藏直接选用（与 Picker 选中同效）。
    let onSelectSavedPlace: (SavedPlace) -> Void

    @State private var model: TripCreateDestinationSearchModel
    @State private var savedPlaceSearchTask: Task<Void, Never>?
    @State private var hasAutoFocused = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchClearSnapshot: String?
    @State private var searchClearProgress: CGFloat = 0

    init(
        configuration: TracciPlaceSearchConfiguration,
        savedPlaces: [SavedPlace],
        savedPlaceCount: Int,
        isLoadingSavedPlaces: Bool,
        savedPlacesErrorMessage: String?,
        onRetrySavedPlaces: @escaping () -> Void,
        onSearchSavedPlaces: @escaping (String) async -> Void,
        onSelectResult: @escaping (TracciPlaceSearchResult) -> Void,
        onUseManual: @escaping (String) -> Void,
        onOpenSavedPlaces: @escaping (String) -> Void,
        onSelectSavedPlace: @escaping (SavedPlace) -> Void
    ) {
        self.configuration = configuration
        self.savedPlaces = savedPlaces
        self.savedPlaceCount = savedPlaceCount
        self.isLoadingSavedPlaces = isLoadingSavedPlaces
        self.savedPlacesErrorMessage = savedPlacesErrorMessage
        self.onRetrySavedPlaces = onRetrySavedPlaces
        self.onSearchSavedPlaces = onSearchSavedPlaces
        self.onSelectResult = onSelectResult
        self.onUseManual = onUseManual
        self.onOpenSavedPlaces = onOpenSavedPlaces
        self.onSelectSavedPlace = onSelectSavedPlace
        _model = State(initialValue: TripCreateDestinationSearchModel(configuration: configuration))
    }

    private var trimmedQuery: String { model.trimmedQuery }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            searchField
            searchContextHint

            if !trimmedQuery.isEmpty {
                manualEntryCard
            }

            savedPlacesSection

            searchContent
        }
        .task {
            // Re-appear after popping the saved-place picker must not pull the keyboard back up.
            guard !hasAutoFocused else { return }
            hasAutoFocused = true
            model.load()
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            isSearchFocused = true
        }
        .onDisappear {
            model.cancel()
            savedPlaceSearchTask?.cancel()
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.buttonTitle)
                .foregroundStyle(AppColors.textPlaceholder)

            TextField(configuration.searchPlaceholder, text: searchQueryBinding)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTypography.listBody)
                .submitLabel(.search)
                .onSubmit { model.performSearch() }

            if !model.query.isEmpty {
                Button {
                    TracciClearDissolve.play(
                        text: searchQueryBinding,
                        snapshot: $searchClearSnapshot,
                        progress: $searchClearProgress,
                        reduceMotion: reduceMotion
                    )
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.listTitleMedium)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: 48)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(alignment: .leading) {
            TracciClearDissolveLayer(
                text: searchClearSnapshot,
                progress: searchClearProgress,
                leadingInset: 44
            )
        }
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: updateSearchQuery
        )
    }

    private func updateSearchQuery(_ value: String) {
        model.updateQuery(value)
        scheduleSavedPlaceSearch(value)
    }

    @ViewBuilder
    private var searchContextHint: some View {
        if let displayName = configuration.searchContext?.displayName {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "scope")
                Text("优先显示 \(displayName) 附近的地点")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textPlaceholder)
            .padding(.horizontal, AppSpacing.xxs)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if model.isSearching, model.results.isEmpty {
            InlineLoadingStateView(message: configuration.loadingMessage)
        } else if let errorMessage = model.errorMessage, model.results.isEmpty {
            AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: 20) {
                VStack(spacing: AppSpacing.sm) {
                    Text(configuration.errorTitle)
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(errorMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                    Button("重新搜索") { model.performSearch() }
                        .font(AppTypography.labelSemibold)
                        .foregroundStyle(AppColors.interactiveText)
                }
                .frame(maxWidth: .infinity)
            }
        } else if !model.results.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("搜索结果")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textMuted)

                ForEach(model.results) { result in
                    Button {
                        AppHaptics.selection()
                        onSelectResult(result)
                    } label: {
                        TracciPlaceSearchResultRow(result: result)
                    }
                    .pressableCardStyle(scale: 0.985, opacity: 0.94)
                }
            }
        } else if trimmedQuery.count >= 2 {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(AppFont.system(28, weight: .medium))
                    .foregroundStyle(AppColors.textDisabled)
                Text("没有找到这个地点")
                    .font(AppTypography.buttonTitleMedium)
                    .foregroundStyle(AppColors.textMuted)
                Text("可以换个关键词，或使用手动地点")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
        }
    }

    private var manualEntryCard: some View {
        Button {
            AppHaptics.selection()
            onUseManual(trimmedQuery)
        } label: {
            HStack(spacing: AppSpacing.cozy) {
                Image(systemName: "pencil.line")
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 38, height: 38)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("使用“\(trimmedQuery)”")
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("手动地点不会包含地图坐标")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .tracciElevation(.l0)
        }
        .buttonStyle(.plain)
    }

    /// 想去的地点区块：
    /// - 无搜索词：单条入口行（计数 + 进 Picker）；
    /// - 有搜索词且命中：原位展开前 3 条 +「查看全部 N 个」；
    /// - 有搜索词无命中：一句提示，引导继续用地图搜索或手动填写。
    @ViewBuilder
    private var savedPlacesSection: some View {
        if isLoadingSavedPlaces, savedPlaces.isEmpty {
            InlineLoadingStateView(message: "正在加载想去的地点")
        } else if let savedPlacesErrorMessage, savedPlaces.isEmpty {
            HStack(spacing: AppSpacing.sm) {
                Text("暂时无法加载")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                Button("重试", action: onRetrySavedPlaces)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.interactiveText)
                    .accessibilityHint(savedPlacesErrorMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if savedPlaces.isEmpty {
            Text(
                trimmedQuery.isEmpty
                    ? "当前目的地没有可用收藏，仍可直接搜索地点"
                    : "没有匹配的想去地点，仍可直接搜索或手动填写"
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textPlaceholder)
        } else if trimmedQuery.isEmpty {
            savedPlacesEntryRow
        } else {
            savedPlacesInlineSection
        }
    }

    private var savedPlacesInlineSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("想去的地点 · \(savedPlacesTotalCount) 个匹配")
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)

            ForEach(Array(savedPlaces.prefix(3))) { item in
                SavedPlaceCompactRow(item: item) { onSelectSavedPlace(item) }
            }

            if savedPlacesTotalCount > 3 {
                savedPlacesSeeAllRow
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private var savedPlacesSeeAllRow: some View {
        Button {
            AppHaptics.selection()
            onOpenSavedPlaces(trimmedQuery)
        } label: {
            HStack {
                Text("查看全部 \(savedPlacesTotalCount) 个")
                    .font(AppTypography.labelSemibold)
                    .foregroundStyle(AppColors.interactiveText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看全部 \(savedPlacesTotalCount) 个想去的地点")
    }

    private var savedPlacesTotalCount: Int {
        max(savedPlaceCount, savedPlaces.count)
    }

    private var savedPlacesEntryRow: some View {
        Button {
            AppHaptics.selection()
            onOpenSavedPlaces(trimmedQuery)
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "bookmark.fill")
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppColors.brandPrimaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("从想去的地点选择")
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(savedPlacesEntrySubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textDisabled)
            }
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .tracciElevation(.l0)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开想去的地点列表")
    }

    private var savedPlacesEntrySubtitle: String {
        let total = max(savedPlaceCount, savedPlaces.count)
        if trimmedQuery.isEmpty {
            return "共 \(total) 个想去的地点"
        }
        return "\(total) 个匹配“\(trimmedQuery)”"
    }

    private func scheduleSavedPlaceSearch(_ value: String) {
        savedPlaceSearchTask?.cancel()
        let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines)
        savedPlaceSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(280))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await onSearchSavedPlaces(keyword)
        }
    }
}
