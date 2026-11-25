import SwiftUI

// Shared Apple Weather header used by `TripUnifiedCreekFeed`.
// The old `ItineraryTabView` host was unmounted and has been removed.

enum ItineraryDayWeatherHeaderStyle {
    case standard
    case compact
    case inline
}

struct ItineraryDayWeatherHeader: View {
    let day: ItineraryDayGroup
    let state: TripWeatherCardState
    var style: ItineraryDayWeatherHeaderStyle = .standard
    let onRefresh: () -> Void

    var body: some View {
        Group {
            switch style {
            case .inline:
                inlineBody
            case .standard, .compact:
                cardBody
            }
        }
    }

    private var cardBody: some View {
        Group {
            if style == .compact {
                // Single-row meta: icon · place/weather · temp · Apple mark. No tip copy, no footer row.
                compactSingleRow
            } else {
                standardCardBody
            }
        }
    }

    /// One horizontal strip for trip-detail day feed — avoids multi-line layout noise.
    private var compactSingleRow: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            icon

            Text(primaryText)
                .font(AppTypography.captionMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let tempText {
                Text(tempText)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.xs)

            if case .failed = state {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.brandPrimary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新加载天气")
            } else if let appleAttribution {
                AppleWeatherAttributionView(
                    attribution: appleAttribution,
                    style: .inline
                )
            }
        }
        .padding(.horizontal, AppSpacing.cozy)
        .padding(.vertical, AppSpacing.sm)
        .frame(minHeight: 36)
        .background(AppColors.subtleBackground.opacity(0.32))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(compactAccessibilityLabel)
    }

    private var compactAccessibilityLabel: String {
        var parts = [primaryText]
        if let tempText { parts.append(tempText) }
        if appleAttribution != nil { parts.append("数据来自 Apple Weather") }
        return parts.joined(separator: "，")
    }

    private var standardCardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText)
                        .font(AppFont.system(12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text(secondaryText)
                        .font(AppFont.system(11))
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                trailingAccessory
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.top, 10)
            .padding(.bottom, appleAttribution == nil ? 10 : AppSpacing.tight)

            if let appleAttribution {
                AppleWeatherAttributionView(
                    attribution: appleAttribution,
                    style: .footer
                )
                .padding(.horizontal, AppSpacing.sm)
                .padding(.bottom, 10)
            }
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 0.8)
        }
    }

    private var inlineBody: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.medium, padding: 0) {
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                Image(systemName: symbolName)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText)
                        .font(AppTypography.labelSemibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if let inlineDetailText {
                        Text(inlineDetailText)
                            .font(AppTypography.chipRegular)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: AppSpacing.xs)

                trailingColumn
            }
            .padding(.horizontal, AppSpacing.cozy)
            .padding(.vertical, AppSpacing.sm)
        }
        .padding(.horizontal, AppSpacing.xxs)
    }

    @ViewBuilder
    private var trailingColumn: some View {
        if case .failed = state {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(AppTypography.chipSemibold)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 30, height: 30)
                    .background(AppColors.cardBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重新加载天气")
        } else if let appleAttribution {
            AppleWeatherAttributionView(
                attribution: appleAttribution,
                style: .inline
            )
        }
    }

    private var inlineDetailText: String? {
        switch state {
        case .available:
            tempText
        case .unavailable, .failed:
            secondaryText
        case .idle, .loading:
            nil
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if case .failed = state {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.brandPrimary)
                    .frame(width: 28, height: 28)
                    .background(AppColors.cardBackground)
                    .clipShape(Circle())
            }
            .pressableCardStyle(scale: 0.94, opacity: 0.9)
        } else if let tempText {
            Text(tempText)
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .standard:
            LinearGradient(
                colors: [AppColors.cardBackground, AppColors.subtleBackground.opacity(0.54)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .compact:
            AppColors.subtleBackground.opacity(0.35)
        case .inline:
            Color.clear
        }
    }

    private var icon: some View {
        Image(systemName: symbolName)
            .font(AppTypography.bodySemibold)
            .foregroundStyle(iconColor)
            .frame(width: style == .compact ? 26 : 30, height: style == .compact ? 26 : 30)
            .background(iconColor.opacity(style == .compact ? 0.08 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: style == .compact ? 8 : 11, style: .continuous))
    }

    private var matchingItem: TripWeatherDisplayItem? {
        guard case let .available(display) = state else { return nil }
        return display.items.first { $0.date == day.date } ?? display.items.first
    }

    private var appleAttribution: AppleWeatherAttribution? {
        guard case let .available(display) = state else { return nil }
        return display.appleAttribution
    }

    private var primaryText: String {
        switch state {
        case .idle, .loading:
            return "天气加载中"
        case let .available(display):
            let location = display.locationName
            let weather = matchingItem?.weather ?? display.summary
            return "\(location) · \(weather)"
        case let .unavailable(title, _, _):
            return title
        case .failed:
            return "暂时无法获取天气"
        }
    }

    private var secondaryText: String {
        switch state {
        case .idle, .loading:
            return "正在更新 \(ItineraryTimeFormatting.displayDate(day.date)) 的出行参考"
        case let .available(display):
            if let tip = matchingItem?.tip, !tip.isEmpty {
                return tip
            }
            return display.tip ?? "可按当天情况灵活安排。"
        case let .unavailable(_, message, _):
            return message
        case let .failed(message):
            return message
        }
    }

    private var tempText: String? {
        guard let item = matchingItem else { return nil }
        switch (item.tempMin, item.tempMax) {
        case let (min?, max?):
            return "\(Int(round(min)))° / \(Int(round(max)))°"
        case let (_, max?):
            return "\(Int(round(max)))°"
        case let (min?, _):
            return "\(Int(round(min)))°"
        default:
            return nil
        }
    }

    private var symbolName: String {
        switch matchingItem?.icon {
        case "sunny": "sun.max.fill"
        case "cloudy": "cloud.fill"
        case "overcast": "smoke.fill"
        case "thunderstorm": "cloud.bolt.rain.fill"
        case "light_rain": "cloud.drizzle.fill"
        case "moderate_rain", "heavy_rain": "cloud.rain.fill"
        case "snow": "cloud.snow.fill"
        case "fog": "cloud.fog.fill"
        default:
            switch state {
            case .failed: "cloud.slash"
            case .unavailable(_, _, let systemImage): systemImage
            default: "cloud.sun.fill"
            }
        }
    }

    private var iconColor: Color {
        switch matchingItem?.icon {
        case "sunny": AppColors.warning
        case "thunderstorm": AppColors.warning
        case "light_rain", "moderate_rain", "heavy_rain": AppColors.brandPrimary
        case "snow", "cloudy", "overcast", "fog": AppColors.textPlaceholder
        default: AppColors.warning
        }
    }
}

/// WeatherKit 合规归属：以 Apple 官方 combined mark + legalPageURL 为主。
/// 视觉上做成安静脚注，避免与天气主信息抢层级。
private enum AppleWeatherAttributionStyle {
    /// 行内：mark + 外链提示，作为天气卡右侧唯一信息
    case inline
    /// 卡片脚注：细分割线 + mark
    case footer
}

private struct AppleWeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme

    let attribution: AppleWeatherAttribution
    let style: AppleWeatherAttributionStyle

    var body: some View {
        Link(destination: attribution.legalPageURL) {
            switch style {
            case .inline:
                // Mark only — no extra chevron row that forces a second visual unit.
                weatherMark
                    .frame(minHeight: 22, alignment: .center)
                    .contentShape(Rectangle())
            case .footer:
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    Rectangle()
                        .fill(AppColors.borderSubtle.opacity(0.9))
                        .frame(height: 0.5)

                    // 官方 mark 即归属主体；整行可点，避免胶囊/副文案抢层级
                    HStack {
                        weatherMark
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(style == .inline ? 0.72 : 0.8)
        .accessibilityLabel("Apple Weather 天气数据来源与法律声明")
        .accessibilityHint("打开 Apple Weather 法律归属页面")
    }

    private var weatherMark: some View {
        AsyncImage(url: markURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
            case .empty:
                fallbackMark
                    .opacity(0.7)
            case .failure:
                fallbackMark
            @unknown default:
                fallbackMark
            }
        }
        // 行内 mark 与左侧第二行文字同高；footer 略大作卡片脚注。
        .frame(width: markSize.width, height: markSize.height, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var markSize: CGSize {
        switch style {
        case .inline:
            // Compact day strip: keep mark small so it sits on the same baseline as temp text.
            CGSize(width: 52, height: 10)
        case .footer:
            CGSize(width: 64, height: 11)
        }
    }

    private var markURL: URL {
        colorScheme == .dark
            ? attribution.combinedMarkDarkURL
            : attribution.combinedMarkLightURL
    }

    private var fallbackMark: some View {
        Text(" Weather")
            .font(AppFont.system(style == .footer ? 10 : 9, weight: .medium))
            .foregroundStyle(AppColors.textPlaceholder)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}
