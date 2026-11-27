import MapKit
import Observation
import SwiftUI
import TracciNetworking

// MARK: - Search state

/// Owns destination search for the embedded Create flow.
/// Generation checks prevent an older MapKit response from replacing a newer query.
@MainActor
@Observable
final class TripCreateDestinationSearchModel {
    let configuration: TracciPlaceSearchConfiguration

    private(set) var query: String
    private(set) var results: [TracciPlaceSearchResult] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private var requestGeneration = 0

    init(configuration: TracciPlaceSearchConfiguration) {
        self.configuration = configuration
        query = configuration.initialQuery
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func load() {
        scheduleSearch(for: query)
    }

    func updateQuery(_ value: String) {
        query = value
        scheduleSearch(for: value)
    }

    func performSearch() {
        startSearch(keyword: trimmedQuery, debounced: false)
    }

    func cancel() {
        requestGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    private func scheduleSearch(for value: String) {
        startSearch(
            keyword: value.trimmingCharacters(in: .whitespacesAndNewlines),
            debounced: true
        )
    }

    private func startSearch(keyword: String, debounced: Bool) {
        requestGeneration += 1
        let generation = requestGeneration
        searchTask?.cancel()

        guard keyword.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            searchTask = nil
            return
        }

        searchTask = Task { [weak self] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(360))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(keyword: keyword, generation: generation)
        }
    }

    private func runSearch(keyword: String, generation: Int) async {
        guard generation == requestGeneration else { return }
        isSearching = true
        errorMessage = nil

        do {
            let response = try await TracciPlaceSearchEngine.search(
                keyword: keyword,
                configuration: configuration
            )
            guard !Task.isCancelled, generation == requestGeneration else { return }
            results = response
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            results = []
            errorMessage = configuration.style == .destination
                ? "请稍后再试，或先手动填写目的地。"
                : "请稍后再试，或先手动填写地点名称。"
        }

        if generation == requestGeneration {
            isSearching = false
            searchTask = nil
        }
    }
}

// MARK: - Embeddable destination search surface

/// Embeddable destination search surface for the V2 Create flow.
///
/// Unlike `TracciPlaceSearchSheet`, this view owns no `NavigationStack` and presents
/// no child sheets — it is dropped directly into the Create Task host's content. The
/// search field is the primary entry and a manual-entry card lets users fall back to
/// a typed name. Each search option resolves to a `TripDestination` reported through
/// `onSelect`; Saved Places intentionally belong only to Add Itinerary Node.
///
/// Reuses the same MapKit engine and result row as the standalone sheets — only the
/// presentation host changes.
struct TripCreateDestinationSearchView: View {
    let configuration: TracciPlaceSearchConfiguration
    let onSelect: (TripDestination) -> Void
    let onUseManual: (String) -> Void
    let onCancel: (() -> Void)?

    @State private var model: TripCreateDestinationSearchModel
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        configuration: TracciPlaceSearchConfiguration = .destination(initialQuery: ""),
        onSelect: @escaping (TripDestination) -> Void,
        onUseManual: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onSelect = onSelect
        self.onUseManual = onUseManual
        self.onCancel = onCancel
        _model = State(
            initialValue: TripCreateDestinationSearchModel(configuration: configuration)
        )
    }

    private var trimmedQuery: String {
        model.trimmedQuery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let onCancel {
                editFlowBackButton(action: onCancel)
            }

            searchField

            if configuration.allowsManualEntry {
                manualEntryCard
            }

            if model.isSearching, model.results.isEmpty {
                searchLoadingState
            } else if let errorMessage = model.errorMessage, model.results.isEmpty {
                searchErrorState(message: errorMessage)
            } else if model.results.isEmpty {
                emptyContent
            } else {
                resultSection
            }
        }
        .task {
            model.load()
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            isSearchFocused = true
        }
        .onDisappear {
            model.cancel()
        }
    }

    private func editFlowBackButton(action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "chevron.left")
                Text("返回旅程信息")
            }
            .font(AppTypography.labelSemibold)
            .foregroundStyle(AppColors.textPrimary)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回旅程信息")
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.buttonTitle)
                .foregroundStyle(
                    isSearchFocused ? AppColors.brandPrimary : AppColors.textPlaceholder
                )

            TextField(configuration.searchPlaceholder, text: searchQueryBinding)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTypography.listBody)
                .submitLabel(.search)
                .onSubmit { model.performSearch() }

            if !model.query.isEmpty {
                Button {
                    model.updateQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.listTitleMedium)
                        .foregroundStyle(AppColors.textDisabled)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.cardSmall)
        .frame(height: 50)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .strokeBorder(
                    isSearchFocused
                        ? AppColors.brandPrimary.opacity(0.38)
                        : AppColors.borderSubtle,
                    lineWidth: isSearchFocused ? 1.2 : 0.8
                )
        }
        .tracciElevation(.l1)
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: isSearchFocused
        )
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { model.query },
            set: { model.updateQuery($0) }
        )
    }

    // MARK: - Manual entry

    private var manualEntryCard: some View {
        Button {
            let value = trimmedQuery.isEmpty ? configuration.initialQuery : trimmedQuery
            guard !value.isEmpty else { return }
            AppHaptics.selection()
            onUseManual(value)
        } label: {
            HStack(spacing: AppSpacing.cozy) {
                Image(systemName: "pencil.line")
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 38, height: 38)
                    .background(AppColors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(manualEntryTitle)
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(trimmedQuery.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)
                        .lineLimit(1)
                    Text(configuration.manualEntrySubtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                Spacer()
            }
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .tracciElevation(.l0)
        }
        .disabled(trimmedQuery.isEmpty && configuration.initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .pressableCardStyle(scale: 0.985, opacity: 0.94)
    }

    private var manualEntryTitle: String {
        if trimmedQuery.isEmpty {
            return configuration.style == .destination ? "手动输入目的地" : "手动输入地点"
        }
        return "使用“\(trimmedQuery)”"
    }

    // MARK: - Results

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(configuration.resultSectionTitle)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)

            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        AppHaptics.selection()
                        onSelect(TripDestination(placeSearchResult: result))
                    } label: {
                        TracciPlaceSearchResultRow(result: result)
                    }
                    .pressableCardStyle(scale: 0.985, opacity: 0.94)
                    .fadeSlideIn(index: index)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if trimmedQuery.count >= 2 {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.cozy) {
            Image(systemName: configuration.emptyIconNoResults)
                .font(AppFont.system(30, weight: .medium))
                .foregroundStyle(AppColors.textDisabled)
            Text(configuration.emptyTitleNoResults)
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(AppColors.textMuted)
            Text(configuration.emptySubtitleNoResults)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }

    private var searchLoadingState: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
                .tint(AppColors.brandPrimary)
            Text(configuration.loadingMessage)
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.pageTop)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private func searchErrorState(message: String) -> some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: 20) {
            VStack(spacing: AppSpacing.cozy) {
                Image(systemName: "cloud.slash")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textDisabled)
                Text(configuration.errorTitle)
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                Button("重新搜索") {
                    model.performSearch()
                }
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.interactiveText)
            }
            .frame(maxWidth: .infinity)
        }
    }

}

// MARK: - Preview

#if DEBUG
#Preview("TripCreate Destination Search") {
    TripCreateDestinationSearchView(
        onSelect: { _ in },
        onUseManual: { _ in }
    )
    .padding()
    .background(AppColors.cardBackground)
}
#endif
