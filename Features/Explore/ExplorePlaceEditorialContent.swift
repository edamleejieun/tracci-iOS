import SwiftUI

/// 规格 §8.2 第 3 块：`recommendedDurationMinutes` 的本地化。
///
/// 只有满 1 小时才四舍五入到最近的 30 分钟——45 分钟原样读「约 45 分钟」，
/// 抹成 30 或 60 都会把编辑给的时长读错。
enum ExploreDurationText {
    static func localized(_ minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "约 \(minutes) 分钟" }

        let rounded = Int((Double(minutes) / 30).rounded()) * 30
        let hours = rounded / 60
        return rounded % 60 == 0 ? "约 \(hours) 小时" : "约 \(hours).5 小时"
    }
}

/// 正文块。固定顺序在 `ExplorePlaceEditorialContent.blocks(from:)` 里定，
/// 空块直接不进数组——「隐藏」由数据决定，视图不再逐块判空。
struct ExploreEditorialBlock: Equatable {
    enum Body: Equatable {
        case paragraph(String)
        case bullets([String])
        case duration(String)
    }

    let title: String
    let body: Body
}

/// 地点半层的正文（规格 §8.2）：介绍 / 亮点 / 建议时长 / 宜访时段 / 游览提示 / 预约提示 / 须知。
///
/// 顺序是契约语义而不是排版偏好，所以写死；全空时老实说「暂无更多介绍」，不留空白区。
struct ExplorePlaceEditorialContent: View {
    let content: PlaceEditorialContent?

    private enum Layout {
        /// 设计稿 `.block`：块之间 0.5px 分隔线，上下各 22pt。
        static let blockGap: CGFloat = 22
        static let headingGap: CGFloat = 10
        static let bulletGap: CGFloat = 9
        static let bulletDotSize: CGFloat = 5
        static let bulletDotCornerRadius: CGFloat = 3
        /// `.bullet i { margin-top: 9px }`——圆点对齐首行文字的视觉中线。
        static let bulletDotTopInset: CGFloat = 9
        /// `.block h4 { letter-spacing: 0.1em }`，12pt 字号下即 1.2pt。
        static let headingKerning: CGFloat = 1.2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let blocks = Self.blocks(from: content)

            if blocks.isEmpty {
                Text("暂无更多介绍")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Layout.blockGap)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.element.title) { index, block in
                    if index > 0 {
                        Divider()
                            .padding(.top, Layout.blockGap)
                    }
                    blockView(block)
                        .padding(.top, Layout.blockGap)
                }
            }
        }
    }

    static func blocks(from content: PlaceEditorialContent?) -> [ExploreEditorialBlock] {
        guard let content else { return [] }

        var blocks: [ExploreEditorialBlock] = []
        if let introduction = trimmed(content.introduction) {
            blocks.append(.init(title: "介绍", body: .paragraph(introduction)))
        }
        if let highlights = nonEmpty(content.highlights) {
            blocks.append(.init(title: "亮点", body: .bullets(highlights)))
        }
        if let minutes = content.recommendedDurationMinutes,
           let duration = ExploreDurationText.localized(minutes) {
            blocks.append(.init(title: "建议时长", body: .duration(duration)))
        }
        if let bestVisitTime = trimmed(content.bestVisitTime) {
            blocks.append(.init(title: "宜访时段", body: .paragraph(bestVisitTime)))
        }
        if let visitTips = nonEmpty(content.visitTips) {
            blocks.append(.init(title: "游览提示", body: .bullets(visitTips)))
        }
        if let reservationTips = trimmed(content.reservationTips) {
            blocks.append(.init(title: "预约提示", body: .paragraph(reservationTips)))
        }
        if let notice = trimmed(content.notice) {
            blocks.append(.init(title: "须知", body: .paragraph(notice)))
        }
        return blocks
    }

    @ViewBuilder
    private func blockView(_ block: ExploreEditorialBlock) -> some View {
        VStack(alignment: .leading, spacing: Layout.headingGap) {
            Text(block.title)
                .font(AppTypography.captionSemibold)
                .kerning(Layout.headingKerning)
                .foregroundStyle(AppColors.textMuted)
                // 规格 §10.2：段落标题进 h2，VoiceOver 转子轮可以逐块跳。
                .accessibilityHeading(.h2)

            switch block.body {
            case let .paragraph(text):
                paragraph(text)
            case let .bullets(items):
                bullets(items)
            case let .duration(text):
                Text(text)
                    .font(AppTypography.metricValue)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .lineSpacing(7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Layout.bulletGap) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: Layout.bulletGap) {
                    RoundedRectangle(cornerRadius: Layout.bulletDotCornerRadius)
                        .fill(AppColors.textPlaceholder)
                        .frame(width: Layout.bulletDotSize, height: Layout.bulletDotSize)
                        .padding(.top, Layout.bulletDotTopInset)
                        .accessibilityHidden(true)

                    Text(item)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func nonEmpty(_ values: [String]?) -> [String]? {
        let items = values?.compactMap { trimmed($0) } ?? []
        return items.isEmpty ? nil : items
    }
}

#if DEBUG
private func previewEditorialContent() -> PlaceEditorialContent {
    PlaceEditorialContent(
        version: 3,
        introduction: "从午门进、神武门出，是唯一不受折返困扰的走法。中轴线上三大殿最挤，两侧的东六宫、珍宝馆反而常常走得从容。",
        highlights: [
            "太和殿广场：中轴线上最开阔的一段，站在丹陛前回头看，能读出整座城的尺度。",
            "珍宝馆：旺季常被忽略，人流比中轴线少一半。",
        ],
        recommendedDurationMinutes: 180,
        visitTips: [
            "从午门进、神武门出，单向通行不回头。",
            "租一台讲解器，比跟着人流走省力。",
        ],
        bestVisitTime: "上午 8:30–10:30，或闭馆前两小时",
        reservationTips: "需提前 7 天在官方渠道实名预约，周一闭馆（法定节假日除外）。",
        notice: "院内禁止使用无人机；部分宫殿室内不开放拍照。"
    )
}

#Preview("地点正文 · 全量") {
    ExplorePlaceEditorialContent(content: previewEditorialContent())
        .padding(AppSpacing.cardSmall)
        .background(AppColors.cardBackground)
}

#Preview("地点正文 · 只有介绍") {
    ExplorePlaceEditorialContent(
        content: PlaceEditorialContent(
            version: 1,
            introduction: "一段只有介绍的内容。",
            highlights: nil,
            recommendedDurationMinutes: nil,
            visitTips: nil,
            bestVisitTime: nil,
            reservationTips: nil,
            notice: nil
        )
    )
    .padding(AppSpacing.cardSmall)
    .background(AppColors.cardBackground)
}

#Preview("地点正文 · 全空") {
    ExplorePlaceEditorialContent(content: nil)
        .padding(AppSpacing.cardSmall)
        .background(AppColors.cardBackground)
}
#endif
