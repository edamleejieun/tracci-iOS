import SwiftUI

/// 城市页的地点卡（规格 §7.4）。
///
/// 缩略图 + 名称 + 类别 + 气质标签三行，右侧 ♡ 快捷收藏（§7.5）。
/// 整卡与 ♡ 是**兄弟**而不是嵌套按钮：嵌套时内层会吃掉外层手势，
/// 兄弟结构才能保证两个命中区各自独立、互不误触。
struct ExplorePlaceRow: View {
    let place: PublishedPlace
    let isSaved: Bool
    /// 打开地点半层（规格 §8）。为 `nil` 时整卡不响应点按，也不宣称可打开。
    var onOpen: (() -> Void)?
    var onSave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            openTarget
            saveTarget
        }
        .padding(.leading, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.cozy)
        .frame(minHeight: 92)
        .background(AppColors.cardBackground)
        .clipShape(cardShape)
        .overlay { cardShape.stroke(AppColors.borderSubtle, lineWidth: 1) }
        .tracciElevation(.l1)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
    }

    // MARK: - Open target

    @ViewBuilder
    private var openTarget: some View {
        if let onOpen {
            Button(action: onOpen) {
                rowContent
            }
            .buttonStyle(TracciPressableButtonStyle(scales: false))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityHint("打开地点详情")
        } else {
            rowContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: AppSpacing.cozy) {
            thumbnail

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                // 规格 §10：地点名一律墨色，禁止蓝色地名。
                Text(place.name)
                    .font(AppTypography.listTitleMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(place.category.displayName)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let highlight {
                    Text(highlight)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 72)
        .contentShape(Rectangle())
    }

    /// 无 `cover` → 品类占位（规格 §7.4），列表里不允许出现空白方块。
    private var thumbnail: some View {
        ZStack {
            ExploreCoverFallback(
                scope: place.placeScope,
                category: place.category,
                glyphPointSize: 20
            )

            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .accessibilityHidden(true)
    }

    private var coverURL: URL? {
        guard let raw = place.cover?.displayURL, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    // MARK: - Quick save

    private var saveTarget: some View {
        Button(action: onSave) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(AppTypography.buttonIcon)
                .foregroundStyle(isSaved ? AppColors.brandPrimary : AppColors.textMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                // 规格 §10.1：收藏反馈 = 图标 scale + opacity 一次，不额外加装饰动画。
                .id(isSaved)
                .transition(.scale(scale: 1.14).combined(with: .opacity))
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: isSaved)
        .accessibilityLabel(isSaved ? "已收藏" : "收藏地点")
        .accessibilityHint(isSaved ? "已收藏，可在想去的地点中管理" : "加入我的想去的地点")
    }

    // MARK: - Accessibility

    private var highlight: String? {
        guard let highlight = place.highlight?.trimmingCharacters(in: .whitespacesAndNewlines),
              !highlight.isEmpty else { return nil }
        return highlight
    }

    /// 规格 §10.2：「{name}，{category.displayName}」，有 `highlight` 时追加。
    private var spokenLabel: String {
        var label = "\(place.name)，\(place.category.displayName)"
        if let highlight { label += "，\(highlight)" }
        return label
    }
}

// MARK: - Previews

#Preview("Explore place rows") {
    ScrollView {
        VStack(spacing: AppSpacing.sm) {
            ExplorePlaceRow(
                place: explorePreviewPlace(highlight: "夜色下的湖面与塔影", isSaved: false),
                isSaved: false,
                onOpen: {},
                onSave: {}
            )
            ExplorePlaceRow(
                place: explorePreviewPlace(highlight: nil, isSaved: true),
                isSaved: true,
                onOpen: {},
                onSave: {}
            )
            ExplorePlaceRow(
                place: explorePreviewPlace(highlight: "没有封面时用品类占位，不留空白方块", isSaved: false),
                isSaved: false,
                onSave: {}
            )
        }
        .padding(AppSpacing.pageX)
    }
    .tracciAtmosphere(.creek)
}

private func explorePreviewPlace(highlight: String?, isSaved: Bool) -> PublishedPlace {
    PublishedPlace(
        id: "place-leifeng",
        name: "雷峰塔",
        placeScope: .poi,
        category: .attraction,
        cityName: "杭州",
        country: "中国",
        latitude: 30.2318,
        longitude: 120.1486,
        supportedUsages: [.itineraryNode],
        highlight: highlight,
        publishedAt: "2026-08-18 09:30:00",
        isSaved: isSaved,
        cover: isSaved
            ? nil
            : PublishedPlaceCover(
                id: "cover-leifeng",
                thumbnailUrl: "https://picsum.photos/seed/leifeng/144/144",
                previewUrl: nil,
                url: nil,
                altText: nil,
                attribution: nil
            )
    )
}
