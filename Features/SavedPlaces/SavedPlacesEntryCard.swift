import SwiftUI

// MARK: - Entry Card Model

/// Lightweight summary loader for the Profile entry card.
///
/// Fetches the first page only (enough for total + recent-name preview).
/// City count is shown only when the whole collection fits in one page,
/// so the meta never reports a lower-bound number as fact.
@MainActor
@Observable
final class SavedPlacesEntryCardModel {
    private static let pageSize = 20
    private static let previewLimit = 3

    private let service: any SavedPlaceServicing

    private(set) var total = 0
    private var items: [SavedPlace] = []
    private(set) var didLoad = false

    init(service: any SavedPlaceServicing) {
        self.service = service
    }

    var previewItems: [SavedPlace] {
        Array(items.prefix(Self.previewLimit))
    }

    var overflowCount: Int {
        max(0, total - previewItems.count)
    }

    /// Recent names for the Profile preview. Names, not category tints —
    /// there is no cover image in v1, so colored glyph tiles read as empty blocks.
    var previewLine: String? {
        let names = previewItems.map(\.place.name).filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        if overflowCount > 0 {
            return names.joined(separator: "、") + " 等"
        }
        return names.joined(separator: "、")
    }

    var subtitle: String {
        guard didLoad, total > 0 else {
            return "收藏想去的地方，规划时快速选用"
        }
        if items.count >= total {
            let cities = Set(items.compactMap(Self.cityKey)).count
            if cities > 0 {
                return "\(total) 个 · \(cities) 个城市"
            }
        }
        return "共 \(total) 个收藏"
    }

    func load() async {
        do {
            let response = try await service.list(
                SavedPlaceListQuery(page: 1, pageSize: Self.pageSize)
            )
            total = response.total
            items = response.list
        } catch {
            // 入口卡片加载失败静默降级为默认引导语；
            // 入口仍然可用，列表页有自己的错误态与重试。
        }
        didLoad = true
    }

    private static func cityKey(of item: SavedPlace) -> String? {
        if item.place.placeScope == .destination {
            return item.place.name
        }
        return item.place.cityName?.nilIfBlank ?? item.place.country?.nilIfBlank
    }
}

// MARK: - Entry Card

/// Profile「旅行」分区的想去的地点入口资产卡。
///
/// 与设置行（L0 utility）拉开层级：L1 内容卡 + 数量/城市 meta + 最近收藏地名。
/// 无封面图时不使用类别色块占位，避免在「我的」里读成一排小色块。
struct SavedPlacesEntryCard: View {
    @State private var model: SavedPlacesEntryCardModel
    let onOpen: () -> Void

    init(service: any SavedPlaceServicing, onOpen: @escaping () -> Void) {
        _model = State(initialValue: SavedPlacesEntryCardModel(service: service))
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            AppElevationCard(level: .l1, role: .content, radius: AppRadius.extraLarge, padding: AppSpacing.card) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.md) {
                        ZStack {
                            AppColors.brandPrimaryBackground
                            Image(systemName: "bookmark.fill")
                                .font(AppTypography.listTitleMedium)
                                .foregroundStyle(AppColors.brandPrimary)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("想去的地点")
                                .font(AppTypography.cardBody)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(model.subtitle)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(AppColors.textDisabled)
                    }

                    if let previewLine = model.previewLine {
                        Text(previewLine)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("想去的地点")
        .accessibilityValue(
            [model.subtitle, model.previewLine]
                .compactMap { $0 }
                .joined(separator: "，")
        )
        .accessibilityHint("点按查看全部收藏地点")
        .task { await model.load() }
    }
}
