import SwiftUI

struct YearlyReportsList: View {
    let reports: [YearlyMemoryReport]

    var body: some View {
        VStack(spacing: AppSpacing.cardSmall) {
            YearlyReportsHintCard()
                .padding(.bottom, AppSpacing.xxs)

            ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                YearlyMemoryReportCard(report: report)
                    .fadeSlideIn(index: index, offset: 20)
            }
        }
    }
}

struct YearlyReportUnavailableCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.cozy) {
            Image(systemName: "lock.fill")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 40, height: 40)
                .background(AppColors.brandPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("还在准备中")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
                Text("这一年的旅行小结还在准备。好了之后，会第一时间告诉你。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .lineSpacing(2)
            }
        }
        .padding(AppSpacing.cardSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppColors.brandPrimary.opacity(0.08), AppColors.brandPrimaryLight.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

struct YearlyReportsHintCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.cozy) {
            Image(systemName: "star")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.warning)
                .frame(width: 40, height: 40)
                .background(AppColors.warning.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("年度旅行报告")
                    .font(AppTypography.label)
                    .foregroundStyle(AppColors.textPrimary)
                Text("每年最后一天，可以把这一年走过的旅程再看一遍。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .lineSpacing(2)
            }
        }
        .padding(AppSpacing.cardSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppColors.warning.opacity(0.10), MemoryColors.accentAmber.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

struct YearlyMemoryReportCard: View {
    let report: YearlyMemoryReport

    var body: some View {
        Button {} label: {
            HStack(alignment: .top, spacing: AppSpacing.cardSmall) {
                coverStack
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                        Text("\(report.year)")
                            .font(AppTypography.yearMarkSerif)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("年度报告")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }

                    Text("\(report.trips) 次旅行 · \(report.days) 天在路上 · \(report.places) 个地点")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(2)

                    HStack(spacing: AppSpacing.tight) {
                        Image(systemName: "play.fill")
                            .font(AppTypography.captionSemibold)
                            .padding(.leading, 2)
                            .foregroundStyle(AppColors.brandPrimary)
                            .frame(width: 32, height: 32)
                            .background(AppColors.brandPrimary.opacity(0.10))
                            .clipShape(Circle())
                        Text("查看年度报告")
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.brandPrimary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.cardSmall)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .tracciElevation(.l1)
        }
        .pressableCardStyle(scale: 0.98, opacity: 0.96)
    }

    private var coverStack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(report.coverURLs.prefix(3).enumerated()), id: \.offset) { index, url in
                TripCoverView(url: url, height: 56, cornerRadius: 8)
                    .frame(width: 56, height: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white, lineWidth: 2)
                    }
                    .rotationEffect(.degrees(Double(index - 1) * 3))
                    .offset(x: CGFloat(index * 6), y: CGFloat(index * 6))
                    .zIndex(Double(3 - index))
            }
        }
    }
}
