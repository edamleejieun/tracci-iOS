import SwiftUI

/// Hero 区右下角的封面/地图模式切换控件。
struct TripHeroModeToggle: View {
    @Binding var currentMode: TripHeroMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            toggleButton(mode: .cover)
            toggleButton(mode: .map)
        }
        .padding(3)
        .tracciMediaChromeGlass(in: Capsule(), wash: .black.opacity(0.22))
        .animation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion), value: currentMode)
    }

    private func toggleButton(mode: TripHeroMode) -> some View {
        let isSelected = currentMode == mode
        return Button {
            guard currentMode != mode else { return }
            withAnimation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion)) {
                currentMode = mode
            }
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AppColors.brandPrimary : .white.opacity(0.7))
                .frame(width: 30, height: 26)
                .background {
                    TracciSlidingSelectionPill(
                        isSelected: isSelected,
                        namespace: selectionNamespace,
                        fill: AppColors.brandPrimary.opacity(0.14),
                        shape: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                }
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
        .accessibilityLabel(mode.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
