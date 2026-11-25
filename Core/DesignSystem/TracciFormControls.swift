import SwiftUI

// MARK: - Sliding selection pill

/// Shared sliding highlight for mutually exclusive options.
/// Reduce Motion skips geometry morph and just shows the selected fill.
struct TracciSlidingSelectionPill<S: Shape>: View {
    var isSelected: Bool
    var namespace: Namespace.ID
    var id: String = "tracci-selection-pill"
    var fill: Color
    var shape: S
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isSelected {
                if reduceMotion {
                    shape.fill(fill)
                } else {
                    shape.fill(fill)
                        .matchedGeometryEffect(id: id, in: namespace)
                }
            }
        }
        .shadow(color: isSelected ? shadowColor : .clear, radius: shadowRadius, x: 0, y: shadowRadius > 0 ? 2 : 0)
    }
}

// MARK: - Segmented Control

struct TracciSegmentedControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    guard selection != option else { return }
                    AppHaptics.selection()
                    withAnimation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(AppTypography.label)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            TracciSlidingSelectionPill(
                                isSelected: isSelected,
                                namespace: selectionNamespace,
                                fill: AppColors.cardBackground,
                                shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                shadowColor: .black.opacity(0.06),
                                shadowRadius: 6
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.xxs)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 1)
        }
        .animation(AppMotion.animation(AppMotion.selectionPill, reduceMotion: reduceMotion), value: selection)
    }
}

// MARK: - Disclosure Section

struct TracciDisclosureSection<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                AppHaptics.selection()
                withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    label()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textPlaceholder)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Stepper

struct TracciStepperControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unitSuffix: String = ""

    var body: some View {
        HStack(spacing: AppSpacing.cozy) {
            stepButton(systemImage: "minus", enabled: value > range.lowerBound) {
                value -= 1
            }

            Text("\(value)\(unitSuffix)")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .frame(minWidth: 52)

            stepButton(systemImage: "plus", enabled: value < range.upperBound) {
                value += 1
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.tight)
        .background(AppColors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(AppTypography.labelSemibold)
                .foregroundStyle(enabled ? AppColors.brandPrimary : AppColors.textDisabled)
                .frame(width: 32, height: 32)
                .background(enabled ? AppColors.brandPrimaryBackground : AppColors.cardBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Switch Row

struct TracciSwitchRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            AppHaptics.selection()
            isOn.toggle()
        } label: {
            HStack(spacing: AppSpacing.cozy) {
                label()
                Spacer(minLength: 0)
                TracciSwitchThumb(isOn: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

private struct TracciSwitchThumb: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AppColors.brandPrimary : AppColors.borderDefault)
                .frame(width: 46, height: 28)
                .animation(AppMotion.animation(AppMotion.checkFill, reduceMotion: reduceMotion), value: isOn)

            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                .padding(3)
        }
        .animation(
            AppMotion.animation(isOn ? AppMotion.switchOn : AppMotion.switchOff, reduceMotion: reduceMotion),
            value: isOn
        )
    }
}

#if DEBUG
#Preview("Tracci Form Controls") {
    struct Host: View {
        @State private var mode = 0
        @State private var expanded = true
        @State private var count = 2
        @State private var enabled = true

        var body: some View {
            VStack(spacing: AppSpacing.lg) {
                TracciSegmentedControl(selection: $mode, options: [0, 1, 2]) { option in
                    ["问答", "调整", "补充"][option]
                }

                TracciDisclosureSection(isExpanded: $expanded) {
                    Text("更多偏好")
                        .font(AppTypography.label)
                } content: {
                    Text("展开内容")
                        .padding(.top, AppSpacing.tight)
                }

                TracciStepperControl(value: $count, range: 1...12, unitSuffix: " 人")
                TracciSwitchRow(isOn: $enabled) {
                    Text("留作故事片段")
                }
            }
            .padding()
        }
    }

    return Host()
}
#endif