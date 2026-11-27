import SwiftUI

// MARK: - CategoryTheme

private struct CategoryTheme {
    let background: Color
    let foreground: Color
}

private let categoryThemes: [PlaceCategory: CategoryTheme] = [
    .attraction: CategoryTheme(
        background: AppColors.itineraryAttraction.opacity(0.18),
        foreground: AppColors.itineraryAttraction),
    .restaurant: CategoryTheme(
        background: AppColors.itineraryRestaurant.opacity(0.18),
        foreground: AppColors.itineraryRestaurant),
    .hotel: CategoryTheme(
        background: AppColors.itineraryHotel.opacity(0.18),
        foreground: AppColors.itineraryHotel),
    .shopping: CategoryTheme(
        background: AppColors.itineraryShopping.opacity(0.18),
        foreground: AppColors.itineraryShopping),
    .transport: CategoryTheme(
        background: AppColors.itineraryTransport.opacity(0.18),
        foreground: AppColors.itineraryTransport),
    .city: CategoryTheme(
        background: AppColors.itineraryOther.opacity(0.14),
        foreground: AppColors.itineraryOther),
    .region: CategoryTheme(
        background: AppColors.itineraryOther.opacity(0.14),
        foreground: AppColors.itineraryOther),
    .other: CategoryTheme(
        background: AppColors.itineraryOther.opacity(0.14),
        foreground: AppColors.itineraryOther)
]

// MARK: - PlaceCategoryGlyph

/// Deterministic glyph + tint for saved-place category surfaces.
/// Used by list rows, picker rows, and editor results to visually distinguish
/// DESTINATION (cities/regions) from POI categories without exposing technical labels.
struct PlaceCategoryGlyph: View {
    let scope: PlaceScope
    let category: PlaceCategory
    var pointSize: CGFloat = 18
    var containerSize: CGFloat = 36

    var body: some View {
        ZStack {
            containerBackground
            Image(systemName: symbolName)
                .font(AppFont.system(pointSize, weight: .medium))
                .foregroundStyle(foregroundColor)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: containerSize, height: containerSize)
        .accessibilityHidden(true)
    }

    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: containerSize * 0.24, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        switch scope {
        case .destination:
            AppColors.brandPrimaryBackground
        case .poi:
            categoryTheme.background
        }
    }

    private var categoryTheme: CategoryTheme {
        categoryThemes[category] ?? categoryThemes[.other]!
    }

    private var foregroundColor: Color {
        switch scope {
        case .destination:
            AppColors.textSecondary
        case .poi:
            categoryTheme.foreground
        }
    }

    private var symbolName: String {
        if scope == .destination {
            return category == .city ? "building.2" : "map"
        }
        switch category {
        case .attraction: return "star.viewfinder"
        case .restaurant: return "fork.knife"
        case .hotel: return "bed.double"
        case .shopping: return "bag"
        case .transport: return "tram"
        case .city, .region, .other: return "mappin"
        }
    }
}

// MARK: - SavedPlacePickerChip

/// Branded chip for "从想去的地点选择/添加" context entries in Trip / Itinerary forms.
struct SavedPlacePickerChip: View {
    let title: String
    var count: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark")
                    .font(AppTypography.buttonIconCompact)
                Text(title)
                    .font(AppTypography.buttonTitleMedium)
                if let count {
                    Text("· \(count)")
                        .font(AppTypography.captionSemibold)
                }
            }
            .foregroundStyle(AppColors.interactiveText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(AppColors.brandPrimaryBackground)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SavedPlacesListSkeletonConfiguration

private struct SavedPlacesListSkeletonConfiguration {
    static let rowCount = 5
    static let iconSide: CGFloat = 42
    static let titleWidth: CGFloat = 140
    static let titleHeight: CGFloat = 14
    static let subtitleWidth: CGFloat = 100
    static let subtitleHeight: CGFloat = 10
    static let metaWidth: CGFloat = 80
    static let metaHeight: CGFloat = 10
    static let rowSpacing: CGFloat = 8
}

// MARK: - SavedPlacesListSkeletonView

/// Skeleton for the saved-places list: search bar + up to 5 card rows.
struct SavedPlacesListSkeletonView: View {
    var rowCount: Int = SavedPlacesListSkeletonConfiguration.rowCount
    var accessibilityLabelText = "正在加载收藏地点"

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            searchBarSkeleton
            VStack(spacing: AppSpacing.sm) {
                ForEach(0..<rowCount, id: \.self) { _ in
                    rowSkeleton
                }
            }
        }
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var searchBarSkeleton: some View {
        AppSkeletonBone(height: 48, cornerRadius: AppRadius.medium)
            .padding(.horizontal, AppSpacing.pageX)
    }

    private var rowSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSkeletonBone(
                width: SavedPlacesListSkeletonConfiguration.titleWidth,
                height: SavedPlacesListSkeletonConfiguration.titleHeight,
                cornerRadius: 3)
            AppSkeletonBone(
                width: SavedPlacesListSkeletonConfiguration.subtitleWidth,
                height: SavedPlacesListSkeletonConfiguration.subtitleHeight,
                cornerRadius: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.settingsRowHorizontalPadding)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.settingsSurface, style: .continuous))
    }
}

// MARK: - PlaceDetailSkeletonConfiguration

private struct PlaceDetailSkeletonConfiguration {
    static let heroTitleWidth: CGFloat = 180
    static let heroTitleHeight: CGFloat = 20
    static let heroSubtitleWidth: CGFloat = 140
    static let heroSubtitleHeight: CGFloat = 12
    static let heroSpacing: CGFloat = 10
    static let mapHeight: CGFloat = 220
    static let actionTitleWidth: CGFloat = 120
    static let actionDetailWidth: CGFloat = 200
    static let actionLineHeight: CGFloat = 12
    static let actionSpacing: CGFloat = 10
}

// MARK: - PlaceDetailSkeletonView

/// Skeleton for the place-detail screen: hero + map + action card.
struct PlaceDetailSkeletonView: View {
    var accessibilityLabelText = "正在加载地点详情"

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            AppElevationCard(level: .l2, role: .hero, radius: AppRadius.hero, padding: AppSpacing.card) {
                VStack(alignment: .leading, spacing: PlaceDetailSkeletonConfiguration.heroSpacing) {
                    AppSkeletonBone(
                        width: PlaceDetailSkeletonConfiguration.heroTitleWidth,
                        height: PlaceDetailSkeletonConfiguration.heroTitleHeight,
                        cornerRadius: 4)
                    AppSkeletonBone(
                        width: PlaceDetailSkeletonConfiguration.heroSubtitleWidth,
                        height: PlaceDetailSkeletonConfiguration.heroSubtitleHeight,
                        cornerRadius: 3)
                }
            }

            AppSkeletonBone(
                height: PlaceDetailSkeletonConfiguration.mapHeight,
                cornerRadius: AppRadius.large)

            AppElevationCard(level: .l1, role: .content, radius: AppRadius.large, padding: AppSpacing.cozy) {
                VStack(alignment: .leading, spacing: PlaceDetailSkeletonConfiguration.actionSpacing) {
                    AppSkeletonBone(
                        width: PlaceDetailSkeletonConfiguration.actionTitleWidth,
                        height: PlaceDetailSkeletonConfiguration.actionLineHeight,
                        cornerRadius: 3)
                    AppSkeletonBone(
                        width: PlaceDetailSkeletonConfiguration.actionDetailWidth,
                        height: PlaceDetailSkeletonConfiguration.actionLineHeight,
                        cornerRadius: 3)
                }
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }
}

// MARK: - Previews

#Preview("Place glyphs — destination") {
    HStack(spacing: AppSpacing.md) {
        PlaceCategoryGlyph(scope: .destination, category: .city)
        PlaceCategoryGlyph(scope: .destination, category: .region)
    }
    .padding()
    .tracciPageBackground()
}

#Preview("Place glyphs — POI") {
    HStack(spacing: AppSpacing.md) {
        ForEach(PlaceCategory.allCases, id: \.self) { cat in
            PlaceCategoryGlyph(scope: .poi, category: cat)
        }
    }
    .padding()
    .tracciPageBackground()
}

#Preview("Saved places list skeleton") {
    ScrollView {
        SavedPlacesListSkeletonView()
            .padding(.horizontal, AppSpacing.pageX)
    }
    .tracciAtmosphere(.creek)
}

#Preview("Place detail skeleton") {
    ScrollView {
        PlaceDetailSkeletonView()
            .padding(.horizontal, AppSpacing.pageX)
    }
    .tracciAtmosphere(.creek)
}
