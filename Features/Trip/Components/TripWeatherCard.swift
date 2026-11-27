import SwiftUI

struct TripWeatherCard: View {
    let state: TripWeatherCardState
    let onRefresh: () -> Void

    var body: some View {
        AppElevationCard(level: .l1, role: .content, radius: AppRadius.extraLarge, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header

                switch state {
                case .idle, .loading:
                    loadingContent
                case let .available(display):
                    availableContent(display)
                case let .unavailable(title, message, systemImage):
                    quietState(title: title, message: message, systemImage: systemImage, tint: AppColors.warning)
                case let .failed(message):
                    quietState(title: "暂时无法获取天气", message: message, systemImage: "cloud", tint: AppColors.textDisabled)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("出行天气")
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Forecast for your trip")
                    .font(AppTypography.chipRegular)
                    .foregroundStyle(AppColors.textPlaceholder)
            }

            Spacer()

            if case .available = state {
                Button(action: onRefresh) {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "arrow.clockwise")
                            .font(AppTypography.chipSemibold)
                        Text("刷新")
                            .font(AppTypography.chipSemibold)
                    }
                    .foregroundStyle(AppColors.interactiveText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, AppSpacing.cozy)
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous)
                .fill(AppColors.subtleBackground)
                .frame(height: 112)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        capsule(width: 86, height: 12)
                        capsule(width: 132, height: 16)
                        capsule(width: 104, height: 26)
                    }
                    .padding(AppSpacing.cardSmall)
                }

            HStack(spacing: AppSpacing.tight) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppColors.subtleBackground)
                        .frame(width: 82, height: 98)
                        .overlay {
                            VStack(spacing: AppSpacing.tight) {
                                capsule(width: 42, height: 8)
                                Circle()
                                    .fill(AppColors.borderDefault)
                                    .frame(width: 24, height: 24)
                                capsule(width: 48, height: 12)
                            }
                        }
                }
            }
            .redacted(reason: .placeholder)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func availableContent(_ display: TripWeatherDisplay) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textMuted)
                        Text(display.locationName)
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                    }

                    if let dateRange = display.dateRange {
                        Text(dateRange)
                            .font(AppTypography.chipRegular)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }

                    Text(display.summary)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.top, AppSpacing.xxs)

                    if let tempRange = display.tempRange {
                        Text(tempRange)
                            .font(AppTypography.pageTitle)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }

                Spacer()

                Image(systemName: symbolName(for: display.items.first?.icon))
                    .font(AppFont.system(30, weight: .medium))
                    .foregroundStyle(iconColor(for: display.items.first?.icon))
                    .frame(width: 58, height: 58)
                    .background(iconColor(for: display.items.first?.icon).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous))
            }
            .padding(AppSpacing.cardSmall)
            .background(
                LinearGradient(
                    colors: [AppColors.cardAltBackground, AppColors.subtleBackground.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))

            if let tip = display.tip, !tip.isEmpty {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: "umbrella")
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.brandPrimary)
                    Text(tip)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, AppSpacing.cozy)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.cardAltBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous))
            }

            Text("逐日预报")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textPlaceholder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(display.items.prefix(5)) { item in
                        WeatherDayPill(item: item)
                    }
                }
                .padding(.trailing, 18)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func quietState(title: String, message: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: AppSpacing.cozy) {
            Image(systemName: systemImage)
                .font(AppTypography.pageTitle)
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.modal, style: .continuous))

            VStack(spacing: 5) {
                Text(title)
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(message)
                    .font(AppTypography.labelRegular)
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.card)
        .padding(.bottom, 22)
        .padding(.top, AppSpacing.xxs)
    }

    private func capsule(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(AppColors.borderDefault)
            .frame(width: width, height: height)
    }

    private func symbolName(for icon: String?) -> String {
        switch icon {
        case "sunny": "sun.max.fill"
        case "cloudy": "cloud.fill"
        case "overcast": "smoke.fill"
        case "thunderstorm": "cloud.bolt.rain.fill"
        case "light_rain": "cloud.drizzle.fill"
        case "moderate_rain", "heavy_rain": "cloud.rain.fill"
        case "snow": "cloud.snow.fill"
        case "fog": "cloud.fog.fill"
        default: "cloud.sun.fill"
        }
    }

    private func iconColor(for icon: String?) -> Color {
        switch icon {
        case "sunny": AppColors.warning
        case "thunderstorm": AppColors.warning
        case "light_rain", "moderate_rain", "heavy_rain": AppColors.brandPrimary
        case "snow", "cloudy", "overcast", "fog": AppColors.textPlaceholder
        default: AppColors.warning
        }
    }
}

struct WeatherDayPill: View {
    let item: TripWeatherDisplayItem

    var body: some View {
        VStack(spacing: 7) {
            Text(ItineraryTimeFormatting.displayDate(item.date))
                .font(AppTypography.chipRegular)
                .foregroundStyle(AppColors.textPlaceholder)
            Text(item.weekday ?? ItineraryTimeFormatting.weekday(item.date))
                .font(AppTypography.microRegular)
                .foregroundStyle(AppColors.textDisabled)

            Image(systemName: symbolName)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(iconColor)
                .frame(height: 24)

            Text(tempText)
                .font(AppTypography.labelSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            if let pop = item.pop, pop > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(AppFont.system(8, weight: .semibold))
                    Text("\(Int(round(pop * 100)))%")
                        .font(AppTypography.micro)
                }
                .foregroundStyle(AppColors.brandPrimary.opacity(0.82))
            }
        }
        .frame(width: 86, height: 108)
        .background(AppColors.subtleBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var tempText: String {
        switch (item.tempMin, item.tempMax) {
        case let (min?, max?):
            "\(Int(round(max)))° / \(Int(round(min)))°"
        case let (_, max?):
            "\(Int(round(max)))°"
        case let (min?, _):
            "\(Int(round(min)))°"
        default:
            "--"
        }
    }

    private var symbolName: String {
        switch item.icon {
        case "sunny": "sun.max.fill"
        case "cloudy": "cloud.fill"
        case "overcast": "smoke.fill"
        case "thunderstorm": "cloud.bolt.rain.fill"
        case "light_rain": "cloud.drizzle.fill"
        case "moderate_rain", "heavy_rain": "cloud.rain.fill"
        case "snow": "cloud.snow.fill"
        case "fog": "cloud.fog.fill"
        default: "cloud.sun.fill"
        }
    }

    private var iconColor: Color {
        switch item.icon {
        case "sunny": AppColors.warning
        case "thunderstorm": AppColors.warning
        case "light_rain", "moderate_rain", "heavy_rain": AppColors.brandPrimary
        case "snow", "cloudy", "overcast", "fog": AppColors.textPlaceholder
        default: AppColors.warning
        }
    }
}

