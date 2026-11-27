import SwiftUI

/// Home empty-state demo entry. Visual weight stays below a real featured surface,
/// but still shows the Bundle cover so the sample feels concrete on device.
struct HomeDemoJourneyCard: View {
    let trip: Trip
    let dateRangeText: String
    let totalDaysText: String

    private enum Metrics {
        static let coverHeight: CGFloat = 120
    }

    private var coverURL: URL? {
        trip.coverCardURL ?? trip.coverThumbnailURL ?? trip.coverPreviewURL
    }

    private var coverFallbackURL: URL? {
        let primary = coverURL
        return [trip.coverPreviewURL, trip.coverThumbnailURL, trip.coverHeroURL]
            .compactMap { $0 }
            .first { $0 != primary }
    }

    /// Prefer structured destination; skip when title already names the place.
    private var destinationLine: String? {
        guard let raw = trip.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        let title = trip.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title == raw || title.contains(raw) || raw.contains(title) {
            return nil
        }
        let stripped = raw
            .replacingOccurrences(of: "市", with: "")
            .replacingOccurrences(of: "省", with: "")
            .replacingOccurrences(of: "自治区", with: "")
        if !stripped.isEmpty, title.contains(stripped) {
            return nil
        }
        return raw
    }

    /// Non-zero content pills only — keeps archive density quiet but concrete.
    private var contentPills: [(systemImage: String, text: String)] {
        var pills: [(String, String)] = []
        if let nodeCount = trip.nodeCount, nodeCount > 0 {
            pills.append(("point.topleft.down.curvedto.point.bottomright.up", "\(nodeCount) 行程"))
        }
        if let journalCount = trip.journalCount, journalCount > 0 {
            pills.append(("book.closed", "\(journalCount) 日志"))
        }
        if let expenseCount = trip.expenseCount, expenseCount > 0 {
            pills.append(("yensign.circle", "\(expenseCount) 开支"))
        } else if let total = trip.totalCny,
                  let value = Double(total),
                  value > 0 {
            pills.append(("yensign.circle", "有开支"))
        }
        return pills
    }

    private var accessibilitySummary: String {
        var parts = [
            DemoReadOnlyCopy.homeAccessibilityLabelPrefix,
            trip.title,
        ]
        if let destinationLine {
            parts.append(destinationLine)
        }
        parts.append(totalDaysText)
        for pill in contentPills {
            parts.append(pill.text)
        }
        return parts.joined(separator: "，")
    }

    var body: some View {
        AppElevationCard(level: .l1, role: .archive, radius: AppRadius.card, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                coverBand

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(trip.title)
                        .font(AppTypography.listTitleMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: AppSpacing.sm) {
                        if let destinationLine {
                            Label(destinationLine, systemImage: "mappin.and.ellipse")
                        }
                        Label(totalDaysText, systemImage: "calendar")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textMuted)
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)

                    Text(dateRangeText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)

                    if !contentPills.isEmpty {
                        HStack(spacing: AppSpacing.xs) {
                            ForEach(Array(contentPills.enumerated()), id: \.offset) { _, pill in
                                Label(pill.text, systemImage: pill.systemImage)
                                    .font(AppTypography.chipRegular)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(AppColors.cardBackground.opacity(0.88))
                                    )
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(contentPills.map(\.text).joined(separator: "，"))
                    }

                    Text(DemoReadOnlyCopy.homeValueLine)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppSpacing.card)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(DemoReadOnlyCopy.homeAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private var coverBand: some View {
        ZStack(alignment: .topLeading) {
            TripCoverView(
                url: coverURL,
                fallbackURL: coverFallbackURL,
                height: Metrics.coverHeight,
                cornerRadius: 0
            )
            .frame(maxWidth: .infinity)
            .clipped()

            // Soft bottom scrim so the card body meets the photo cleanly.
            VStack {
                Spacer()
                LinearGradient(
                    colors: [
                        Color.clear,
                        AppColors.cardBackground.opacity(0.55),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
            }
            .allowsHitTesting(false)

            Text(DemoReadOnlyCopy.identityPill)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.interactiveText)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColors.cardBackground.opacity(0.94))
                )
                .padding(AppSpacing.cardSmall)
                .accessibilityHidden(true)
        }
        .frame(height: Metrics.coverHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        // Top corners follow the outer elevation card continuous radius.
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: AppRadius.card,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: AppRadius.card,
                style: .continuous
            )
        )
    }
}

/// Quiet placeholder while Demo Bundle revalidates after a real empty list.
struct HomeDemoJourneyLoadingCard: View {
    var body: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.card, padding: AppSpacing.card) {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("正在准备示例旅程…")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在准备示例旅程")
    }
}

#if DEBUG
#Preview("Demo journey card") {
    let trip = Trip(
        id: "demo-preview",
        title: "魔都五日 · 浦西浦东",
        startDate: "2026-07-29",
        endDate: "2026-08-02",
        status: .ongoing,
        totalDays: 5,
        destination: TripDestination(
            name: "上海",
            provider: "DEMO",
            providerPlaceId: "demo-shanghai",
            country: "中国",
            latitude: 31.23,
            longitude: 121.47,
            adcode: "310000",
            cityCode: "021",
            provinceName: "上海市",
            cityName: "上海市",
            districtName: "黄浦区"
        ),
        coverPhoto: nil,
        baseCurrency: "CNY",
        totalCny: "8750.00",
        nodeCount: 22,
        journalCount: 9,
        expenseCount: 14,
        access: nil,
        createdAt: nil,
        updatedAt: nil
    )

    ScrollView {
        HomeDemoJourneyCard(
            trip: trip,
            dateRangeText: "7月29日 – 8月2日",
            totalDaysText: "5 天"
        )
        .padding(AppSpacing.lg)
    }
    .tracciAtmosphere(.creek)
}
#endif
