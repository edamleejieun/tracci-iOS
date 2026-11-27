import SwiftUI

// MARK: - Cover fallback

/// 规格 §6.3：城市没有封面时用品牌渐变 + 分类字形兜底，网格里不允许出现空白格子。
/// 色值取自 `designs/explore-v2` 的 `.grad-cover`；探索三层（首页卡 / 城市页 Hero / 半层 Hero）共用。
struct ExploreCoverFallback: View {
    let scope: PlaceScope
    let category: PlaceCategory
    var glyphPointSize: CGFloat = 30

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x4E86D6), location: 0),
                    .init(color: AppColors.brandPrimary, location: 0.42),
                    .init(color: Color(hex: 0x2E6BC9), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 设计稿 `.grad-cover::after`：右上偏置的白色径向高光，让渐变不死板。
            gradientHighlight

            PlaceCategoryGlyph(
                scope: scope,
                category: category,
                pointSize: glyphPointSize,
                containerSize: glyphPointSize * 2.1
            )
        }
        .accessibilityHidden(true)
    }

    /// CSS `radial-gradient(circle at 78% 16%, white 0.26 → transparent 58%)`：
    /// 终止半径 = 着色点到最远角的距离 × 58%。
    private var gradientHighlight: some View {
        GeometryReader { proxy in
            let center = UnitPoint(x: 0.78, y: 0.16)
            let dx = max(center.x, 1 - center.x) * proxy.size.width
            let dy = max(center.y, 1 - center.y) * proxy.size.height
            RadialGradient(
                colors: [.white.opacity(0.26), .clear],
                center: center,
                startRadius: 0,
                endRadius: (dx * dx + dy * dy).squareRoot() * 0.58
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - City card

/// 探索首页的城市卡（规格 §6.3）。
///
/// 封面铺满 + 底部 scrim 承载文字；城市名靠左、气质标签靠右同一行。
/// 整卡可点，不显示计数，标签缺失时只留城市名——客户端不替服务端编内容。
struct ExploreCityCard: View {
    let place: PublishedPlace
    /// 规格 §6.3：只剩一座城市时改单列 16:9，避免半宽的孤零零方块。
    var aspectRatio: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                cover(size: proxy.size)
                readabilityScrim
                metaRow
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(cardShape)
        .tracciElevation(.l1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("打开城市")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
    }

    private var coverURL: URL? {
        guard let raw = place.cover?.displayURL, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// 兜底常驻底层、照片加载成功后盖上去：加载中和加载失败都不会露白。
    private func cover(size: CGSize) -> some View {
        ZStack {
            ExploreCoverFallback(scope: place.placeScope, category: place.category)
                .frame(width: size.width, height: size.height)

            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 设计稿 `.scrim`：底部 0.72 暖墨（`AppColors.mediaScrimInk`）渐隐，
    /// 56% 处 0.16、30% 以上全透——与城市页 Hero 的墨色 scrim 同一色源。
    private var readabilityScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.30),
                .init(color: AppColors.mediaScrimInk.opacity(0.16), location: 0.56),
                .init(color: AppColors.mediaScrimInk.opacity(0.72), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .accessibilityHidden(true)
    }

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
            Text(place.name)
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimaryInverse)
                .lineLimit(1)
                .truncationMode(.tail)
                // 城市名是这张卡的主信息：先拿满宽度，标签拿剩下的再截断。
                .layoutPriority(1)

            if let highlight = trimmedHighlight {
                Text(highlight)
                    .font(AppTypography.chip)
                    .foregroundStyle(AppColors.textPrimaryInverse.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, alignment: .trailing)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.cozy)
    }

    private var trimmedHighlight: String? {
        guard let highlight = place.highlight?.trimmingCharacters(in: .whitespacesAndNewlines),
              !highlight.isEmpty else { return nil }
        return highlight
    }

    private var spokenLabel: String {
        guard let highlight = trimmedHighlight else { return place.name }
        return "\(place.name)，\(highlight)"
    }
}

// MARK: - Grid skeleton

/// 规格 §6.6：首屏骨架铺 4 块城市卡，形状与真实卡片一致，加载完成后不发生跳位。
struct ExploreCityGridSkeleton: View {
    var tileCount = 4

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: AppSpacing.md) {
            ForEach(0..<tileCount, id: \.self) { _ in
                skeletonTile
            }
        }
        .padding(.horizontal, AppSpacing.pageX)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载探索内容")
    }

    static let columns = [GridItem(.flexible(), spacing: AppSpacing.md), GridItem(.flexible(), spacing: AppSpacing.md)]

    /// `AppSkeletonBone` 的高度是定值，撑不满方形格子，这里直接用可伸缩的形状 + 共用微光。
    private var skeletonTile: some View {
        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
            .fill(AppColors.subtleBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AppShimmerOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Pagination footer

/// 规格 §6.6 / §7.7 同一套分页状态：首页网格与城市页地点流共用，避免两层各写一份「加载更多」。
struct ExploreLoadMoreFooter: View {
    let hasMore: Bool
    let isLoadingMore: Bool
    var errorMessage: String?
    /// 两层加载的对象不同（城市 / 地点），无障碍提示各自说明。
    var loadMoreHint: String
    var retryHint: String
    var onLoadMore: () -> Void
    var onRetryLoadMore: () -> Void

    var body: some View {
        Group {
            if let message = errorMessage {
                failure(message)
            } else if hasMore {
                loadMoreButton
            }
        }
    }

    /// 设计稿 `.ghost-btn`：次要操作用透明底的文字按钮，不与白卡片抢层级。
    private var loadMoreButton: some View {
        Button(action: onLoadMore) {
            HStack(spacing: AppSpacing.xs) {
                if isLoadingMore {
                    AppProgressIndicator(diameter: 16)
                }
                Text("加载更多")
                    .font(AppTypography.bodyMedium)
            }
            .foregroundStyle(AppColors.interactiveText)
            .padding(.horizontal, AppSpacing.lg)
            .frame(minWidth: 132, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
        .disabled(isLoadingMore)
        .padding(.top, AppSpacing.xs)
        .accessibilityHint(loadMoreHint)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textMuted)
                .multilineTextAlignment(.center)

            Button("重试", action: onRetryLoadMore)
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.interactiveText)
                .buttonStyle(TracciPressableButtonStyle(scales: false))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHint(retryHint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xs)
    }
}

// MARK: - Previews

#Preview("Explore city cards") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            ExploreCityCard(place: explorePreviewCity(coverURL: nil, highlight: "西湖十景"))
            ExploreCityCard(place: explorePreviewCity(coverURL: "https://example.com/hangzhou.jpg", highlight: nil))
            ExploreCityCard(place: explorePreviewCity(coverURL: nil, highlight: nil), aspectRatio: 16 / 9)
            ExploreCityGridSkeleton()
        }
        .padding(.vertical, AppSpacing.md)
    }
    .tracciAtmosphere(.creek)
}

private func explorePreviewCity(coverURL: String?, highlight: String?) -> PublishedPlace {
    PublishedPlace(
        id: "place-hangzhou",
        name: "杭州",
        placeScope: .destination,
        category: .city,
        cityName: "杭州",
        country: "中国",
        latitude: 30.2741,
        longitude: 120.1551,
        supportedUsages: [.tripDestination],
        highlight: highlight,
        publishedAt: "2026-08-20 09:30:00",
        isSaved: false,
        cover: coverURL.map {
            PublishedPlaceCover(id: "cover-1", thumbnailUrl: $0, previewUrl: nil, url: nil, altText: nil, attribution: nil)
        }
    )
}
