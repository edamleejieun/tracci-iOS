import MapKit
import SwiftUI

// MARK: - Result

struct TracciPlaceSearchResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let meta: String?
    let address: String?
    let country: String?
    let provinceName: String?
    let cityName: String?
    let districtName: String?
    let latitude: Double
    let longitude: Double
    let providerPlaceId: String?
    let category: String?

    init(mapItem: MKMapItem, style: TracciPlaceSearchConfiguration.Style) {
        let placemark = mapItem.placemark
        let fallbackName = placemark.locality ?? placemark.administrativeArea ?? placemark.name ?? mapItem.name ?? "未命名地点"
        name = mapItem.name ?? fallbackName
        address = Self.address(from: placemark, excluding: name)
        country = placemark.country
        provinceName = placemark.administrativeArea
        cityName = placemark.locality
        districtName = placemark.subLocality
        latitude = placemark.coordinate.latitude
        longitude = placemark.coordinate.longitude
        providerPlaceId = Self.providerPlaceId(from: mapItem)
        category = mapItem.pointOfInterestCategory?.displayName

        switch style {
        case .destination:
            let region = [cityName, country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            subtitle = placemark.title != name ? placemark.title : nil
            meta = region.isEmpty ? nil : region
        case .scopedPlace:
            subtitle = address
            meta = [category, cityName, districtName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }

    private static func address(from placemark: MKPlacemark, excluding name: String) -> String? {
        let title = placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty, title != name {
            return title
        }

        let parts = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0 != name }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func providerPlaceId(from mapItem: MKMapItem) -> String? {
        if #available(iOS 18.0, *) {
            return mapItem.identifier?.rawValue
        }
        return nil
    }
}

enum TracciPlaceSearchEngine {
    static func search(
        keyword: String,
        configuration: TracciPlaceSearchConfiguration
    ) async throws -> [TracciPlaceSearchResult] {
        let request = MKLocalSearch.Request()
        if let searchContext = configuration.searchContext {
            request.naturalLanguageQuery = searchContext.scopedKeyword(keyword)
            if let region = searchContext.searchRegion {
                request.region = region
            }
            request.resultTypes = [.pointOfInterest, .address]
            let response = try await MKLocalSearch(request: request).start()
            try Task.checkCancellation()
            return response.mapItems
                .filter { searchContext.matches($0) }
                .prefix(12)
                .map { TracciPlaceSearchResult(mapItem: $0, style: configuration.style) }
        }

        // 旅程目的地：限定为国内市/县级别行政区划。
        request.naturalLanguageQuery = keyword
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKMapItem.chinaSearchRegion
        let response = try await MKLocalSearch(request: request).start()
        try Task.checkCancellation()
        return response.mapItems
            .filter { $0.isChinaAdministrativeArea }
            .prefix(12)
            .map { TracciPlaceSearchResult(mapItem: $0, style: configuration.style) }
    }
}

// MARK: - Configuration

struct TracciPlaceSearchConfiguration: Equatable {
    enum Style: Equatable {
        case destination
        case scopedPlace
    }

    let style: Style
    let navigationTitle: String
    let searchPlaceholder: String
    let resultSectionTitle: String
    let allowsManualEntry: Bool
    let manualEntrySubtitle: String
    let emptyIconBeforeSearch: String
    let emptyIconNoResults: String
    let emptyTitleBeforeSearch: String
    let emptyTitleNoResults: String
    let emptySubtitleBeforeSearch: String
    let emptySubtitleNoResults: String
    let errorTitle: String
    let loadingMessage: String
    let categoryHint: String?
    let searchContext: PlaceSearchContext?
    let initialQuery: String

    static func destination(initialQuery: String) -> Self {
        Self(
            style: .destination,
            navigationTitle: "选择目的地",
            searchPlaceholder: "搜索城市、地区或地标",
            resultSectionTitle: "Apple 地图结果",
            allowsManualEntry: true,
            manualEntrySubtitle: "没有坐标时天气卡片会等待后端补充",
            emptyIconBeforeSearch: "map",
            emptyIconNoResults: "magnifyingglass",
            emptyTitleBeforeSearch: "输入至少 2 个字开始搜索",
            emptyTitleNoResults: "没有找到相关目的地",
            emptySubtitleBeforeSearch: "可以搜索城市、地区或代表性地标",
            emptySubtitleNoResults: "可以换个关键词，或手动输入目的地",
            errorTitle: "暂时无法搜索目的地",
            loadingMessage: "正在搜索 Apple 地图",
            categoryHint: nil,
            searchContext: nil,
            initialQuery: initialQuery
        )
    }

    static func scopedPlace(
        context: PlaceSearchContext,
        initialQuery: String = "",
        allowsManualEntry: Bool = true
    ) -> Self {
        Self(
            style: .scopedPlace,
            navigationTitle: "选择地点",
            searchPlaceholder: "搜索地点、餐厅、景点",
            resultSectionTitle: "搜索结果",
            allowsManualEntry: allowsManualEntry,
            manualEntrySubtitle: "不选择地图地点也可以保存",
            emptyIconBeforeSearch: "mappin.and.ellipse",
            emptyIconNoResults: "magnifyingglass",
            emptyTitleBeforeSearch: "搜索地点",
            emptyTitleNoResults: "没有找到这个地点",
            emptySubtitleBeforeSearch: "选择地点后可自动补全城市、地址与天气",
            emptySubtitleNoResults: "换个关键词试试，例如景点、餐厅或城市名",
            errorTitle: "暂时无法搜索地点",
            loadingMessage: "正在搜索地点",
            categoryHint: "选择地点后会自动建议节点类型，保存前可以修改",
            searchContext: context,
            initialQuery: initialQuery
        )
    }
}

// MARK: - Sheet

struct TracciPlaceSearchSheet: View {
    let configuration: TracciPlaceSearchConfiguration
    let onSelect: (TracciPlaceSearchResult) -> Void
    let onUseManual: ((String) -> Void)?
    let onCancel: () -> Void

    @State private var query: String
    @State private var results: [TracciPlaceSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchClearSnapshot: String?
    @State private var searchClearProgress: CGFloat = 0

    init(
        configuration: TracciPlaceSearchConfiguration,
        onSelect: @escaping (TracciPlaceSearchResult) -> Void,
        onUseManual: ((String) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onSelect = onSelect
        self.onUseManual = onUseManual
        self.onCancel = onCancel
        _query = State(initialValue: configuration.initialQuery)
    }

    init(
        destinationInitialQuery: String,
        onSelect: @escaping (TracciPlaceSearchResult) -> Void,
        onUseManual: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            configuration: .destination(initialQuery: destinationInitialQuery),
            onSelect: onSelect,
            onUseManual: onUseManual,
            onCancel: onCancel
        )
    }

    init(
        scopedPlaceContext: PlaceSearchContext,
        initialQuery: String = "",
        allowsManualEntry: Bool = true,
        onSelect: @escaping (TracciPlaceSearchResult) -> Void,
        onUseManual: ((String) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            configuration: .scopedPlace(
                context: scopedPlaceContext,
                initialQuery: initialQuery,
                allowsManualEntry: allowsManualEntry
            ),
            onSelect: onSelect,
            onUseManual: onUseManual,
            onCancel: onCancel
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    searchField
                    contextHint

                    if configuration.allowsManualEntry, onUseManual != nil {
                        manualEntryCard
                    }

                    Group {
                        if isSearching, results.isEmpty {
                            searchLoadingState
                        } else if let errorMessage, results.isEmpty {
                            searchErrorState(message: errorMessage)
                        } else if results.isEmpty {
                            emptyState
                        } else {
                            resultSection
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.pageBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.pageBackground)
            .navigationTitle(configuration.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .onAppear {
                scheduleSearch(for: query)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(260))
                    isSearchFocused = true
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
        .tracciDismissKeyboardOnBlankTap()
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppTypography.buttonTitle)
                .foregroundStyle(AppColors.textPlaceholder)

            TextField(configuration.searchPlaceholder, text: $query)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppTypography.listBody)
                .submitLabel(.search)
                .onSubmit { performSearch() }

            if !query.isEmpty {
                Button {
                    TracciClearDissolve.play(
                        text: $query,
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
        .frame(height: 46)
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

    @ViewBuilder
    private var contextHint: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            if let displayName = configuration.searchContext?.displayName {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "scope")
                        .font(AppTypography.chipSemibold)
                    Text("仅显示 \(displayName) 附近的地点")
                        .font(AppTypography.captionMedium)
                }
            }

            if let categoryHint = configuration.categoryHint {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "tag")
                        .font(AppTypography.chipSemibold)
                    Text(categoryHint)
                        .font(AppTypography.caption)
                }
            }
        }
        .foregroundStyle(AppColors.textPlaceholder)
        .padding(.horizontal, AppSpacing.xxs)
    }

    private var manualEntryCard: some View {
        Button {
            let value = trimmedQuery.isEmpty ? configuration.initialQuery : trimmedQuery
            guard !value.isEmpty else { return }
            AppHaptics.selection()
            onUseManual?(value)
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

                if configuration.style == .scopedPlace {
                    Image(systemName: "arrow.up.forward")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textDisabled)
                }
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

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(configuration.resultSectionTitle)
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textMuted)

            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        AppHaptics.selection()
                        onSelect(result)
                    } label: {
                        TracciPlaceSearchResultRow(result: result)
                    }
                    .pressableCardStyle(scale: 0.985, opacity: 0.94)
                    .fadeSlideIn(index: index)
                }
            }
        }
    }

    private var emptyState: some View {
        let isBeforeSearch = trimmedQuery.count < 2
        return VStack(spacing: AppSpacing.cozy) {
            Image(systemName: isBeforeSearch ? configuration.emptyIconBeforeSearch : configuration.emptyIconNoResults)
                .font(AppFont.system(30, weight: .medium))
                .foregroundStyle(AppColors.textDisabled)
            Text(isBeforeSearch ? configuration.emptyTitleBeforeSearch : configuration.emptyTitleNoResults)
                .font(AppTypography.buttonTitleMedium)
                .foregroundStyle(AppColors.textMuted)
            Text(isBeforeSearch ? configuration.emptySubtitleBeforeSearch : configuration.emptySubtitleNoResults)
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
                    performSearch()
                }
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.brandPrimary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scheduleSearch(for value: String) {
        searchTask?.cancel()
        let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            await runSearch(keyword: keyword)
        }
    }

    private func performSearch() {
        let keyword = trimmedQuery
        guard keyword.count >= 2 else { return }
        searchTask?.cancel()
        searchTask = Task { await runSearch(keyword: keyword) }
    }

    private func runSearch(keyword: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            results = try await TracciPlaceSearchEngine.search(
                keyword: keyword,
                configuration: configuration
            )
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = configuration.style == .destination
                ? "请稍后再试，或先手动填写目的地。"
                : "请稍后再试，或先手动填写地点名称。"
        }
    }
}

// MARK: - 国内行政区划过滤（旅程目的地）

/// 旅程目的地一般为市/县级别行政区划。
/// 通过 MapKit 搜索后，按以下规则过滤：
/// 1. 仅保留国内（isoCountryCode == "CN"）
/// 2. 排除街道门牌（thoroughfare != nil）
/// 3. 名称需匹配市/区/县/省之一，排除商业 POI（如餐厅、门店）
///
/// MKLocalSearch.Request.region 仅作为排序偏好，不能严格限定国境，
/// 因此需要配合后置过滤确保结果一致。
extension MKMapItem {
    /// 中国行政区划搜索的地理偏好区域（大陆主体）。
    /// 覆盖约 18°N–53°N、73°E–135°E。
    static let chinaSearchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.5, longitude: 104.0),
        span: MKCoordinateSpan(latitudeDelta: 35.0, longitudeDelta: 62.0)
    )

    /// 是否为中国境内市/县级及以上行政区划（不含街道门牌与商业 POI）。
    var isChinaAdministrativeArea: Bool {
        let placemark = placemark
        // 仅保留国内。
        guard placemark.isoCountryCode == "CN" else { return false }

        // 排除街道门牌（有 thoroughfare 说明是具体路段地址）。
        if placemark.thoroughfare != nil { return false }

        let resultName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resultName.isEmpty else { return false }

        // 名称需与行政区划字段之一匹配（市/区/县/省），排除景点、门店等 POI。
        let adminNames = [
            placemark.locality,
            placemark.subLocality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        // 精确匹配或互相包含（处理"杭州" vs "杭州市"等边界）。
        return adminNames.contains { admin in
            resultName == admin
                || resultName.hasPrefix(admin)
                || admin.hasPrefix(resultName)
        }
    }
}

// MARK: - Result Row

struct TracciPlaceSearchResultRow: View {
    let result: TracciPlaceSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.cozy) {
            Image(systemName: "mappin")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 38, height: 38)
                .background(AppColors.brandPrimaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(result.name)
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if let subtitle = result.subtitle, !subtitle.isEmpty, subtitle != result.name {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(2)
                }

                if let meta = result.meta, !meta.isEmpty {
                    Text(meta)
                        .font(AppTypography.chipRegular)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .tracciElevation(.l0)
    }
}

// MARK: - POI Category Labels

private extension MKPointOfInterestCategory {
    var displayName: String {
        switch self {
        case .airport: "机场"
        case .amusementPark: "游乐园"
        case .aquarium: "水族馆"
        case .atm: "ATM"
        case .bakery: "烘焙"
        case .bank: "银行"
        case .beach: "海滩"
        case .brewery: "酒吧"
        case .cafe: "咖啡"
        case .campground: "营地"
        case .carRental: "租车"
        case .evCharger: "充电"
        case .fireStation: "消防"
        case .fitnessCenter: "健身"
        case .foodMarket: "市场"
        case .gasStation: "加油站"
        case .hospital: "医院"
        case .hotel: "酒店"
        case .laundry: "洗衣"
        case .library: "图书馆"
        case .marina: "码头"
        case .movieTheater: "影院"
        case .museum: "博物馆"
        case .nationalPark: "公园"
        case .nightlife: "夜生活"
        case .park: "公园"
        case .parking: "停车"
        case .pharmacy: "药店"
        case .police: "警察"
        case .postOffice: "邮局"
        case .publicTransport: "公共交通"
        case .restaurant: "餐厅"
        case .restroom: "洗手间"
        case .school: "学校"
        case .stadium: "体育场"
        case .store: "商店"
        case .theater: "剧院"
        case .university: "大学"
        case .winery: "酒庄"
        case .zoo: "动物园"
        default: "地点"
        }
    }
}

// MARK: - Preview

#Preview("Destination Search") {
    TracciPlaceSearchSheet(
        destinationInitialQuery: "东京",
        onSelect: { _ in },
        onUseManual: { _ in },
        onCancel: {}
    )
}

#Preview("Scoped Place Search") {
    TracciPlaceSearchSheet(
        scopedPlaceContext: PlaceSearchContext(
            name: "浅草寺",
            cityName: "东京",
            country: "日本",
            latitude: 35.7148,
            longitude: 139.7967
        ),
        initialQuery: "",
        onSelect: { _ in },
        onCancel: {}
    )
}
