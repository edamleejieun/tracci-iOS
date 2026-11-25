import SwiftUI

/// Custom gender picker sheet — replaces system confirmationDialog
/// with a branded Tracci selection UI consistent with other picker sheets.
struct TracciGenderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let currentGender: EditProfileViewModel.Gender
    let onConfirm: (EditProfileViewModel.Gender) -> Void

    @State private var draftGender: EditProfileViewModel.Gender

    init(
        currentGender: EditProfileViewModel.Gender = .undisclosed,
        onConfirm: @escaping (EditProfileViewModel.Gender) -> Void
    ) {
        self.currentGender = currentGender
        self.onConfirm = onConfirm
        _draftGender = State(initialValue: currentGender)
    }

    var body: some View {
        TracciPickerSheetScaffold(
            title: "选择性别",
            subtitle: "选择你的性别，用于个性化展示",
            sheetHeight: 460,
            onConfirm: confirmSelection
        ) {
            VStack(spacing: AppSpacing.sm) {
                ForEach(EditProfileViewModel.Gender.allCases, id: \.self) { gender in
                    GenderOptionCard(
                        gender: gender,
                        isSelected: draftGender == gender
                    ) {
                        select(gender)
                    }
                }
            }
            .tracciPickerHorizontalPadding()
            .tracciPickerContentTopSpacing()
        }
        .animation(
            AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion),
            value: draftGender
        )
    }

    private func select(_ gender: EditProfileViewModel.Gender) {
        AppHaptics.selection()
        withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
            draftGender = gender
        }
    }

    private func confirmSelection() {
        AppHaptics.success()
        onConfirm(draftGender)
        dismiss()
    }
}

// MARK: - Gender Option Card

private struct GenderOptionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let gender: EditProfileViewModel.Gender
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.10))
                        .frame(width: 40, height: 40)

                    Image(systemName: genderIcon)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(iconTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(gender.displayName)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(genderDescription)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPlaceholder)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.brandPrimary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .padding(.horizontal, AppSpacing.card)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(AppColors.borderSubtle, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle(scale: 0.985, opacity: 0.96))
        .accessibilityLabel("\(gender.displayName)，\(genderDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("选中\(gender.displayName)")
    }

    private var genderIcon: String {
        switch gender {
        case .male: return "figure.stand"
        case .female: return "figure.stand.dress"
        case .undisclosed: return "eye.slash"
        }
    }

    private var iconTint: Color {
        switch gender {
        case .male: return AppColors.brandPrimary
        case .female: return Color(hex: 0xEC4899)
        case .undisclosed: return AppColors.textMuted
        }
    }

    private var genderDescription: String {
        switch gender {
        case .male: return "先生 / 他"
        case .female: return "女士 / 她"
        case .undisclosed: return "不公开性别信息"
        }
    }
}

// MARK: - Preview

#Preview("Gender Picker") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TracciGenderPickerSheet(currentGender: .undisclosed) { _ in }
        }
}
