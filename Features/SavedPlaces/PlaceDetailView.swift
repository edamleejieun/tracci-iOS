import MapKit
import Observation
import SwiftUI

// MARK: - Detail

@MainActor
@Observable
final class PlaceDetailViewModel {
    let service: any SavedPlaceServicing
    let placeId: String

    var detail: PlaceDetail?
    var isLoading = false
    var isSubmitting = false
    var errorMessage: String?

    init(service: any SavedPlaceServicing, placeId: String) {
        self.service = service
        self.placeId = placeId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await service.placeDetail(placeId: placeId)
            detail = response
        } catch {
            detail = nil
            errorMessage = SavedPlaceErrorMessage.resolve(error)
        }
    }

    func savePlace() async -> Bool {
        guard !isSubmitting else { return false }
        return await submit {
            _ = try await service.create(.existingPlace(placeId: placeId, note: nil))
        }
    }

    func removePlace() async -> Bool {
        guard let savedPlaceId = detail?.userContext?.savedPlaceId, !isSubmitting else { return false }
        return await submit {
            try await service.delete(savedPlaceId: savedPlaceId)
        }
    }

    private func submit(_ operation: () async throws -> Void) async -> Bool {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await operation()
            await load()
            return true
        } catch {
            errorMessage = SavedPlaceErrorMessage.resolve(error)
            return false
        }
    }
}

struct PlaceDetailView: View {
    @State private var model: PlaceDetailViewModel
    @State private var showingRemoveConfirm = false
    @State private var saveSuccessID: UUID?
    @State private var addToTripPlace: SavedPlace?
    @State private var hasActiveTrips = false
    /// Wishlist entries (Profile → 想去的地点) keep the collect/remove actions.
    /// Home's `placeDetail` route is currently itinerary-only; pass false there
    /// so the collect card does not appear on a place already in the trip.
    private let showsCollectAction: Bool
    private let tripProvider: (any SavedPlaceTripProviding)?

    init(
        service: any SavedPlaceServicing,
        placeId: String,
        showsCollectAction: Bool = true,
        tripProvider: (any SavedPlaceTripProviding)? = nil
    ) {
        _model = State(initialValue: PlaceDetailViewModel(service: service, placeId: placeId))
        self.showsCollectAction = showsCollectAction
        self.tripProvider = tripProvider
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if model.isLoading, model.detail == nil {
                    PlaceDetailSkeletonView()
                } else if let detail = model.detail {
                    detailContent(detail)
                } else if let errorMessage = model.errorMessage {
                    ErrorStateView(title: "地点详情暂时不可用", message: errorMessage) {
                        Task { await model.load() }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.vertical, AppSpacing.md)
            .padding(.bottom, AppSpacing.pageBottom)
        }
        .tracciAtmosphere(.creek)
        .navigationTitle("地点详情")
        .navigationBarTitleDisplayMode(.inline)
        .tracciNavigationBarMinimizeOnScroll()
        .overlay {
            TracciConfirmSheet(
                isPresented: $showingRemoveConfirm,
                tone: .destructive,
                title: "取消收藏？",
                message: "不会删除已经创建的旅程或行程节点。",
                cancelTitle: "保留",
                confirmTitle: "取消收藏",
                onConfirmAsync: {
                    _ = await model.removePlace()
                    return true
                }
            )
        }
        .sheet(item: $addToTripPlace) { place in
            if let tripProvider {
                SavedPlaceAddToTripSheet(
                    place: place,
                    provider: tripProvider,
                    onDismiss: { didAdd in
                        addToTripPlace = nil
                        guard didAdd else { return }
                        Task { await model.load() }
                    }
                )
                .tracciSheetPresentation(.subSheetFraction(0.92))
            }
        }
        .task {
            await model.load()
            await refreshActiveTripsAvailability()
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: PlaceDetail) -> some View {
        AppElevationCard(level: .l2, role: .hero, radius: AppRadius.hero, padding: AppSpacing.card) {
            ZStack(alignment: .topTrailing) {
                heroMediaPlaceholder(for: detail)

                HStack(alignment: .top, spacing: AppSpacing.md) {
                    PlaceCategoryGlyph(
                        scope: detail.placeScope,
                        category: detail.category,
                        pointSize: 22,
                        containerSize: 44
                    )
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(detail.name)
                            .font(AppTypography.pageTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 0.5)

                        metaLines(detail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, AppSpacing.cozy)
            }
        }

        if let latitude = detail.latitude, let longitude = detail.longitude {
            ZStack(alignment: .topTrailing) {
                PlaceCoordinateMap(name: detail.name, latitude: latitude, longitude: longitude)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                            .stroke(AppColors.borderSubtle, lineWidth: 0.7)
                    }

                Button {
                    PlaceMapLauncher.open(name: detail.name, latitude: latitude, longitude: longitude)
                } label: {
                    Label("在地图中打开", systemImage: "arrow.up.right.square")
                        .font(AppTypography.label)
                        .foregroundStyle(AppColors.textPrimaryInverse)
                        .padding(.horizontal, AppSpacing.cozy)
                        .padding(.vertical, AppSpacing.xs)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .stroke(AppColors.borderHighlight.opacity(0.5), lineWidth: 0.6)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(AppSpacing.cardSmall)
                .accessibilityLabel("在 Apple 地图中打开")
            }
        }

        if showsCollectAction {
            AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: AppSpacing.cozy) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if detail.userContext?.isSaved == true {
                        let count = detail.userContext?.usageSummary?.tripCount ?? 0
                        if count > 0 {
                            SavedPlaceUsageChip(count: count)
                                .padding(.bottom, AppSpacing.xxs)
                            Text("已收藏")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textMuted)
                        } else {
                            Text("已收藏，尚未加入旅程")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textMuted)
                        }
                        if canShowAddToTrip(for: detail) {
                            PrimaryButton(
                                title: "加入行程",
                                systemImage: "plus.circle.fill",
                                action: { addToTripPlace = detail.asSavedPlace() }
                            )
                            .accessibilityHint("把地点加入某个旅程的某一天")
                        }

                        DestructiveButton(
                            "取消收藏",
                            systemImage: "bookmark.slash",
                            isLoading: model.isSubmitting,
                            accessibilityHint: "确认后将从想去的地点中移除"
                        ) {
                            showingRemoveConfirm = true
                        }
                    } else {
                        Text("收藏后可以在创建旅程或添加行程节点时快速选择。")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textMuted)

                        saveButton(for: detail)
                            .id(saveSuccessID)
                            .disabled(model.isSubmitting)
                    }

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func canShowAddToTrip(for detail: PlaceDetail) -> Bool {
        tripProvider != nil && hasActiveTrips && detail.canAddToItinerary && detail.asSavedPlace() != nil
    }

    private func refreshActiveTripsAvailability() async {
        guard let tripProvider else {
            hasActiveTrips = false
            return
        }
        do {
            hasActiveTrips = try await tripProvider.loadActiveTrips().isEmpty == false
        } catch {
            hasActiveTrips = false
        }
    }

    @ViewBuilder
    private func heroMediaPlaceholder(for detail: PlaceDetail) -> some View {
        // 缩略图临时替代：品牌渐变底 + 居中的分类图标。
        // 后续接入实景图时，把 PlaceCategoryGlyph 替换为 AsyncImage 即可。
        ZStack {
            LinearGradient(
                colors: [
                    AppColors.brandPrimaryBackground.opacity(0.55),
                    AppColors.backgroundGrouped.opacity(0.20),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PlaceCategoryGlyph(
                scope: detail.placeScope,
                category: detail.category,
                pointSize: 48,
                containerSize: 96
            )
            .opacity(0.18)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func metaLines(_ detail: PlaceDetail) -> some View {
        let meta: [(String, String?)] = [
            ("城市", detail.cityName),
            ("国家", detail.country),
            ("地址", detail.address)
        ]
        let nonEmpty = meta.filter { !($1?.nilIfBlank ?? "").isEmpty }

        if nonEmpty.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                ForEach(Array(nonEmpty.enumerated()), id: \.offset) { _, pair in
                    let (label, value) = pair
                    if let value {
                        Text("\(label): \(value)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .shadow(color: .black.opacity(0.2), radius: 0.3, x: 0, y: 0.3)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func saveButton(for detail: PlaceDetail) -> some View {
        Button {
            guard saveSuccessID == nil else { return }
            saveSuccessID = UUID()
            Task {
                _ = await model.savePlace()
                try? await Task.sleep(for: .milliseconds(420))
                saveSuccessID = nil
            }
        } label: {
            saveButtonContent
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var saveButtonContent: some View {
        let isSaving = model.isSubmitting
        let showSuccess = saveSuccessID != nil

        Group {
            if showSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.success)
                    .transition(.scale.combined(with: .opacity))
            } else if isSaving {
                ProgressView()
                    .tint(AppColors.textPrimaryInverse)
                    .transition(.opacity)
            } else {
                Text("收藏地点")
                    .font(AppTypography.buttonTitle)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .padding(.horizontal, AppSpacing.cozy)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                .fill(showSuccess ? AppColors.success : AppColors.brandPrimary)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
        .tracciShadow(showSuccess ? AppShadow.soft : AppShadow.brand)
    }
}

/// 地点坐标小地图。`PlaceDetailView` 与探索地点半层共用（规格 §8.2 降级链的第二级）。
struct PlaceCoordinateMap: View {
    let name: String
    let latitude: Double
    let longitude: Double

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        ))) {
            Marker(name, coordinate: coordinate)
                .tint(AppColors.brandPrimary)
        }
        .accessibilityLabel("\(name)地图")
    }
}

/// 跳系统地图。详情页与探索半层共用，避免两处各拼一份 `MKMapItem`。
enum PlaceMapLauncher {
    static func open(name: String, latitude: Double, longitude: Double) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        mapItem.openInMaps()
    }
}


