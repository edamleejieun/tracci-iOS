import SwiftUI

// MARK: - Shimmer

/// Soft shimmer for skeleton / image-loading surfaces. Honors Reduce Motion.
struct AppShimmerOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.0), location: 0),
                    .init(color: .white.opacity(0.34), location: 0.45),
                    .init(color: .white.opacity(0.48), location: 0.5),
                    .init(color: .white.opacity(0.34), location: 0.55),
                    .init(color: .white.opacity(0.0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.55)
            .offset(x: phase * width)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            phase = -0.6
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                phase = 1.15
            }
        }
    }
}

// MARK: - Skeleton bone

/// Single placeholder block for list/card skeletons.
struct AppSkeletonBone: View {
    var width: CGFloat?
    var height: CGFloat = 10
    var cornerRadius: CGFloat = 4
    var showsShimmer = true

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [AppColors.backgroundGrouped, AppColors.cardBackground],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .overlay {
                if showsShimmer {
                    AppShimmerOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Cover chrome

enum TripCoverChromePhase: Equatable {
    /// No cover URL configured.
    case empty
    /// Cover URL is loading.
    case loading
    /// Cover URL failed to load.
    case failure
}

/// Shared surface for trip covers — list thumbs, featured cards, detail hero.
struct TripCoverChrome: View {
    var phase: TripCoverChromePhase = .empty
    var iconPointSize: CGFloat = 20
    /// When false, only the base gradient shows.
    var showsGlyph = true

    var body: some View {
        ZStack {
            baseGradient

            if phase == .loading {
                AppShimmerOverlay()
            }

            if showsGlyph {
                glyph
            }
        }
        .accessibilityHidden(true)
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var gradientColors: [Color] {
        switch phase {
        case .empty, .loading:
            [
                AppColors.subtleBackground,
                AppColors.backgroundGrouped.opacity(0.92),
                AppColors.brandPrimaryBackground.opacity(0.55),
            ]
        case .failure:
            [
                AppColors.subtleBackground,
                AppColors.subtleBackground.opacity(0.88),
                AppColors.borderSubtle.opacity(0.55),
            ]
        }
    }

    @ViewBuilder
    private var glyph: some View {
        let diameter = max(32, iconPointSize * 2.05)

        ZStack {
            Circle()
                .fill(AppColors.cardBackground.opacity(phase == .failure ? 0.72 : 0.78))
                .frame(width: diameter, height: diameter)

            Image(systemName: glyphName)
                .font(AppFont.system(iconPointSize, weight: .medium))
                .foregroundStyle(glyphColor)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var glyphName: String {
        switch phase {
        case .empty: "map"
        case .loading: "photo"
        case .failure: "photo.badge.exclamationmark"
        }
    }

    private var glyphColor: Color {
        switch phase {
        case .empty, .loading:
            AppColors.textDisabled
        case .failure:
            AppColors.textMuted.opacity(0.72)
        }
    }
}

/// Loads a remote cover and fills the parent bounds. Parent should set frame / clipShape.
struct TripCoverFillView: View {
    let url: URL?
    var iconPointSize: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        coverStack(phase: phase, size: geo.size)
                    }
                } else {
                    TripCoverChrome(phase: .empty, iconPointSize: iconPointSize)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private func coverStack(phase: AsyncImagePhase, size: CGSize) -> some View {
        ZStack {
            TripCoverChrome(phase: chromePhase(for: phase), iconPointSize: iconPointSize)
                .frame(width: size.width, height: size.height)

            if case let .success(image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .transition(AppMotion.revealTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(
            AppMotion.animation(AppMotion.imageFade, reduceMotion: reduceMotion),
            value: Self.isImageLoaded(phase)
        )
    }

    private func chromePhase(for phase: AsyncImagePhase) -> TripCoverChromePhase {
        switch phase {
        case .success:
            .empty
        case .failure:
            .failure
        case .empty:
            .loading
        @unknown default:
            .empty
        }
    }

    private static func isImageLoaded(_ phase: AsyncImagePhase) -> Bool {
        if case .success = phase { return true }
        return false
    }
}

// MARK: - Trip list skeleton

/// Matches home / all-trips list rhythm: one featured cover + regular cards.
struct TripListSkeletonView: View {
    var featuredCount: Int = 1
    var regularCount: Int = 3
    var verticalPadding: CGFloat = AppSpacing.md

    var body: some View {
        LazyVStack(spacing: AppSpacing.lg) {
            ForEach(0..<featuredCount, id: \.self) { _ in
                featuredCard
            }
            ForEach(0..<regularCount, id: \.self) { _ in
                regularCard
            }
        }
        .padding(.vertical, verticalPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载旅程")
    }

    private var featuredCard: some View {
        TripCoverChrome(phase: .loading, iconPointSize: 26)
            .frame(height: 218)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    AppSkeletonBone(width: 92, height: 10, cornerRadius: 3)
                    AppSkeletonBone(width: 168, height: 16, cornerRadius: 4)
                    AppSkeletonBone(width: 128, height: 10, cornerRadius: 3)
                    HStack(spacing: 8) {
                        AppSkeletonBone(width: 64, height: 22, cornerRadius: 11)
                        AppSkeletonBone(width: 64, height: 22, cornerRadius: 11)
                    }
                }
                .padding(18)
            }
            .tracciShadow(AppShadow.soft)
    }

    private var regularCard: some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.card, padding: AppSpacing.cardSmall) {
            HStack(spacing: 12) {
                TripCoverChrome(phase: .loading, iconPointSize: 18)
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        AppSkeletonBone(width: 120, height: 12, cornerRadius: 3)
                        Spacer(minLength: 8)
                        AppSkeletonBone(width: 40, height: 18, cornerRadius: 9)
                    }
                    AppSkeletonBone(width: 96, height: 9, cornerRadius: 3)
                    AppSkeletonBone(width: 110, height: 9, cornerRadius: 3)
                    AppSkeletonBone(width: 140, height: 8, cornerRadius: 3)
                }
            }
        }
    }
}

// MARK: - Memory / Stats / Export skeletons

/// Memory tab initial load: companion block + featured story card + list rows.
struct MemoryListSkeletonView: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            companionBlock

            TripCoverChrome(phase: .loading, iconPointSize: 26)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSkeletonBone(width: 72, height: 18, cornerRadius: 9)
                        AppSkeletonBone(width: 150, height: 16, cornerRadius: 4)
                        AppSkeletonBone(width: 110, height: 10, cornerRadius: 3)
                    }
                    .padding(18)
                }

            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    tripRowSkeleton(coverSize: 72)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载回忆")
    }

    private var companionBlock: some View {
        AppElevationCard(level: .l1, role: .hero, radius: AppRadius.hero, padding: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: 12) {
                AppSkeletonBone(width: 28, height: 28, cornerRadius: 8)
                AppSkeletonBone(width: 72, height: 10, cornerRadius: 3)
                AppSkeletonBone(height: 12, cornerRadius: 3)
                AppSkeletonBone(width: 200, height: 12, cornerRadius: 3)
            }
        }
    }
}

/// Stats tab initial load: narrative card + metric tiles.
struct StatsDashboardSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            AppElevationCard(level: .l1, role: .hero, radius: AppRadius.hero, padding: AppSpacing.xl) {
                VStack(alignment: .leading, spacing: 12) {
                    AppSkeletonBone(width: 28, height: 28, cornerRadius: 8)
                    AppSkeletonBone(width: 80, height: 10, cornerRadius: 3)
                    AppSkeletonBone(height: 13, cornerRadius: 3)
                    AppSkeletonBone(width: 180, height: 13, cornerRadius: 3)
                    AppSkeletonBone(width: 140, height: 13, cornerRadius: 3)
                }
            }

            HStack(spacing: 12) {
                metricTile
                metricTile
            }

            AppElevationCard(level: .l0, role: .utility, radius: AppRadius.card, padding: AppSpacing.card) {
                VStack(alignment: .leading, spacing: 12) {
                    AppSkeletonBone(width: 96, height: 12, cornerRadius: 3)
                    AppSkeletonBone(height: 10, cornerRadius: 3)
                    AppSkeletonBone(width: 220, height: 10, cornerRadius: 3)
                    AppSkeletonBone(height: 72, cornerRadius: AppRadius.medium)
                }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载洞察")
    }

    private var metricTile: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.card, padding: AppSpacing.cardSmall) {
            VStack(alignment: .leading, spacing: 10) {
                AppSkeletonBone(width: 48, height: 10, cornerRadius: 3)
                AppSkeletonBone(width: 64, height: 22, cornerRadius: 4)
                AppSkeletonBone(width: 80, height: 9, cornerRadius: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Compact material / export loading block.
struct ContentBlockSkeletonView: View {
    var rowCount: Int = 3
    var accessibilityLabelText = "正在加载"

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { _ in
                tripRowSkeleton(coverSize: 56)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }
}

/// Horizontal photo strip skeleton (memory material flow).
struct PhotoStripSkeletonView: View {
    var count: Int = 4

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { _ in
                    TripCoverChrome(phase: .loading, iconPointSize: 16)
                        .frame(width: 112, height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载照片")
    }
}

private func tripRowSkeleton(coverSize: CGFloat) -> some View {
    AppElevationCard(level: .l0, role: .utility, radius: AppRadius.card, padding: AppSpacing.cardSmall) {
        HStack(spacing: 12) {
            TripCoverChrome(phase: .loading, iconPointSize: max(14, coverSize * 0.24))
                .frame(width: coverSize, height: coverSize)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                AppSkeletonBone(width: 128, height: 12, cornerRadius: 3)
                AppSkeletonBone(width: 96, height: 9, cornerRadius: 3)
                AppSkeletonBone(width: 72, height: 9, cornerRadius: 3)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Previews

#Preview("Trip list skeleton") {
    ScrollView {
        TripListSkeletonView()
            .padding(.horizontal, AppSpacing.pageX)
    }
    .tracciPageBackground()
}

#Preview("Memory / Stats skeletons") {
    ScrollView {
        VStack(spacing: 32) {
            MemoryListSkeletonView()
            StatsDashboardSkeletonView()
        }
        .padding(.horizontal, AppSpacing.pageX)
    }
    .tracciPageBackground()
}

#Preview("Cover chrome phases") {
    HStack(spacing: 12) {
        TripCoverChrome(phase: .empty)
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        TripCoverChrome(phase: .loading)
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        TripCoverChrome(phase: .failure)
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .padding()
    .tracciPageBackground()
}
