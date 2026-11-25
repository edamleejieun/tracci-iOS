import SwiftUI

private enum ExportPreviewPalette {
    static let coverLight = Color(hex: 0xE8E4DE)
    static let coverShade = Color(hex: 0xD9D5CF)
    static let coverSun = Color(hex: 0xD4C8B8)
    static let filmPaper = Color(hex: 0xF5F2ED)
    static let filmMark = Color(hex: 0xD8D1C8)
    static let filmPhoto = Color(hex: 0xDDD7CE)
    static let summaryPaper = Color(hex: 0xFAFAF8)
    static let summaryMeta = Color(hex: 0xD8D1C8)
    static let summaryRule = Color(hex: 0xE5E0DA)
    static let summaryValue = Color(hex: 0xC9C1B8)
}

struct ExportModeSegment: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var mode: ExportMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ExportMode.allCases) { item in
                Button {
                    guard mode != item else { return }
                    AppHaptics.selection()
                    withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
                        mode = item
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: item.systemImage)
                            .font(AppTypography.bodyMedium)
                        Text(item.title)
                            .font(AppTypography.label)
                    }
                    .foregroundStyle(mode == item ? AppColors.textPrimary : AppColors.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.cozy)
                    .background(mode == item ? AppColors.cardBackground : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                    .tracciElevation(mode == item ? .l1 : .l0)
                }
                .pressableCardStyle(scale: 0.98, opacity: 0.92)
            }
        }
        .padding(AppSpacing.xxs)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

struct ExportTripSummaryCard: View {
    let title: String
    let dateRangeText: String
    let subtitle: String

    var body: some View {
        AppElevationCard(level: .l0, role: .utility, radius: AppRadius.large, padding: 14) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.buttonTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(dateRangeText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPlaceholder)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textMuted)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ExportTemplatePicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selected: ExportTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            Text("模板")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: AppSpacing.tight) {
                ForEach(ExportTemplate.allCases) { template in
                    Button {
                        AppHaptics.selection()
                        withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
                            selected = template
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            templatePreview(template)
                                .frame(height: 64)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(template.shortHint)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textPlaceholder)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.sm)
                        .background(selected == template ? AppColors.cardBackground : AppColors.subtleBackground)
                        .scaleEffect(selected == template && !reduceMotion ? AppMotion.selectedScale : 1)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        .overlay {
                            if selected == template {
                                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                    .stroke(AppColors.brandPrimary.opacity(0.35), lineWidth: 1)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if selected == template {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(AppFont.system(17))
                                    .foregroundStyle(AppColors.brandPrimary)
                                    .background(Circle().fill(.white))
                                    .offset(x: 3, y: -3)
                            }
                        }
                    }
                    .pressableCardStyle(scale: 0.98, opacity: 0.92)
                }
            }
        }
    }

    @ViewBuilder
    private func templatePreview(_ template: ExportTemplate) -> some View {
        switch template {
        case .travelCover:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ExportPreviewPalette.coverLight, ExportPreviewPalette.coverShade],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(.white.opacity(0.8)).frame(width: 42, height: 5)
                        Capsule().fill(.white.opacity(0.58)).frame(width: 28, height: 4)
                    }
                    .padding(AppSpacing.tight)
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(ExportPreviewPalette.coverSun)
                        .frame(width: 22, height: 22)
                        .padding(AppSpacing.tight)
                }
        case .filmCollage:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ExportPreviewPalette.filmPaper)
                .overlay {
                    ZStack {
                        ForEach(0..<5, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(ExportPreviewPalette.filmMark)
                                .frame(width: 4, height: 3)
                                .offset(x: CGFloat(index - 2) * 13, y: -24)
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 32, height: 42)
                            .rotationEffect(.degrees(-5))
                            .offset(x: -12, y: 4)
                            .tracciElevation(.l0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ExportPreviewPalette.filmPhoto)
                            .frame(width: 30, height: 38)
                            .rotationEffect(.degrees(4))
                            .offset(x: 14, y: -2)
                            .tracciElevation(.l0)
                    }
                }
        case .minimalSummary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ExportPreviewPalette.summaryPaper)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(AppColors.textPrimary.opacity(0.72)).frame(width: 44, height: 6)
                        Capsule().fill(ExportPreviewPalette.summaryMeta).frame(width: 32, height: 4)
                        Spacer(minLength: 6)
                        ForEach(0..<3, id: \.self) { _ in
                            HStack {
                                Capsule().fill(ExportPreviewPalette.summaryRule).frame(width: 28, height: 4)
                                Spacer()
                                Capsule().fill(ExportPreviewPalette.summaryValue).frame(width: 18, height: 4)
                            }
                        }
                    }
                    .padding(AppSpacing.tight)
                }
        }
    }
}

private extension ExportTemplate {
    var shortHint: String {
        switch self {
        case .travelCover: "首图感"
        case .filmCollage: "多照片"
        case .minimalSummary: "数据感"
        }
    }
}

struct ExportFormatPicker: View {
    @Binding var selected: ExportFormat

    var body: some View {
        TracciChoiceMenuButton(
            title: "导出比例",
            triggerTitle: "比例",
            triggerValue: selected.displayLabel,
            triggerIcon: selected == .square ? "square" : "rectangle.portrait",
            items: ExportFormat.allCases.map {
                TracciChoiceItem(
                    id: $0.rawValue,
                    title: $0.displayLabel,
                    systemImage: $0 == .square ? "square" : "rectangle.portrait"
                )
            },
            selectedID: selected.rawValue,
            onSelect: { item in
                if let match = ExportFormat.allCases.first(where: { $0.rawValue == item.id }) {
                    selected = match
                }
            }
        )
    }
}
