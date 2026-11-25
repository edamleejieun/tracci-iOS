import SwiftUI

struct ExportTripPickerCard: View {
    let trip: Trip?
    let dateRangeText: String
    let daysText: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            AppElevationCard(level: .l0, role: .utility, radius: AppRadius.large, padding: 12) {
                HStack(spacing: AppSpacing.cozy) {
                    coverThumbnail

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(trip?.title ?? "选择旅行")
                            .font(AppTypography.buttonTitleMedium)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        if trip != nil {
                            Text("\(dateRangeText) · \(daysText)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textPlaceholder)
                                .lineLimit(1)
                        } else {
                            Text("选择要回顾的旅程")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textPlaceholder)
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 2) {
                        Text("切换")
                            .font(AppTypography.chipRegular)
                            .foregroundStyle(AppColors.textPlaceholder)
                        Image(systemName: "chevron.down")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.textPlaceholder)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var coverThumbnail: some View {
        TripCoverView(url: trip?.coverCardURL, fallbackURL: trip?.coverPreviewURL, height: 56, cornerRadius: AppRadius.small)
            .frame(width: 56)
    }
}

struct ExportTripPickerSheet: View {
    let trips: [Trip]
    let selectedTripId: String?
    let dateRangeText: (Trip) -> String
    let daysText: (Trip) -> String
    let onSelect: (Trip) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColors.borderDefault)
                .frame(width: 36, height: 5)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)

            Text("选择旅行")
                .font(AppTypography.listTitle)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.bottom, AppSpacing.xxs)

            Text("选择你想要生成回忆内容的旅行")
                .font(AppTypography.labelRegular)
                .foregroundStyle(AppColors.textPlaceholder)
                .padding(.bottom, AppSpacing.card)

            ScrollView {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(trips) { trip in
                        tripRow(trip)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.bottom, AppSpacing.card)
    }

    private func tripRow(_ trip: Trip) -> some View {
        let isSelected = trip.id == selectedTripId

        return Button {
            onSelect(trip)
            dismiss()
        } label: {
            HStack(spacing: AppSpacing.cozy) {
                TripCoverView(url: trip.coverCardURL, fallbackURL: trip.coverPreviewURL, height: 56, cornerRadius: AppRadius.small)
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("\(dateRangeText(trip)) · \(daysText(trip))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.brandPrimary)
                }
            }
            .padding(AppSpacing.cozy)
            .background(isSelected ? AppColors.cardBackground : AppColors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.26), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
