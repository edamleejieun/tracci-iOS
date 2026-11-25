import SwiftUI
import UIKit

enum JournalMood: String, Codable, CaseIterable, Identifiable, Equatable {
    case happy
    case relaxed
    case excited
    case peaceful
    case thoughtful

    var id: String { rawValue }

    /// SF Symbol name for list badges and mood picker. Presentation only —
    /// API still uses `rawValue` (`happy` / `relaxed` / …).
    var systemImage: String {
        switch self {
        case .happy: "face.smiling"
        case .relaxed: "leaf.fill"
        case .excited: "sparkles"
        case .peaceful: "water.waves"
        case .thoughtful: "brain.head.profile"
        }
    }

    var label: String {
        switch self {
        case .happy: "开心"
        case .relaxed: "放松"
        case .excited: "兴奋"
        case .peaceful: "平静"
        case .thoughtful: "沉思"
        }
    }

    var colorHex: UInt {
        switch self {
        case .happy: 0xFFD93D
        case .relaxed: 0x6BCB77
        case .excited: 0xFF6B6B
        case .peaceful: 0x4D96FF
        case .thoughtful: 0x9B59B6
        }
    }

    var tintColor: Color {
        Color(hex: colorHex)
    }
}

struct JournalMoodBadge: View {
    let mood: JournalMood

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: mood.systemImage)
                .font(AppTypography.microRegular)
                .symbolRenderingMode(.hierarchical)
            Text(mood.label)
                .font(AppTypography.micro)
        }
        .foregroundStyle(mood.tintColor)
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, AppSpacing.xxs)
        .background(mood.tintColor.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("心情：\(mood.label)")
    }
}

struct JournalMoodPicker: View {
    @Binding var selection: JournalMood?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Text("此刻心情")
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(JournalMood.allCases) { mood in
                        moodChip(mood)
                    }
                }
            }
        }
    }

    private func moodChip(_ mood: JournalMood) -> some View {
        let isSelected = selection == mood

        return Button {
            AppHaptics.selection()
            withAnimation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion)) {
                selection = isSelected ? nil : mood
            }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: mood.systemImage)
                    .font(AppTypography.bodyMedium)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : mood.tintColor)
                Text(mood.label)
                    .font(AppFont.system(13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textMuted)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? AppColors.brandPrimaryBackground : AppColors.cardAltBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? AppColors.brandPrimary : AppColors.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(PressableCardStyle(scale: AppMotion.pressScale, opacity: AppMotion.pressOpacity))
        .accessibilityLabel(mood.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
        JournalMoodPicker(selection: .constant(.peaceful))
        HStack {
            ForEach(JournalMood.allCases) { mood in
                JournalMoodBadge(mood: mood)
            }
        }
    }
    .padding()
    .background(AppColors.pageBackground)
}
