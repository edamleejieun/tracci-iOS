import SwiftUI

// MARK: - CTA texture (G2.2)

/// Primary CTA fill texture: same-hue vertical luminance ramp (±2–3%) + a top
/// hairline inner highlight over a flat brand base. Keeps the flat-color brand
/// look while removing the "default solid fill" cheapness — no strong gradients,
/// no glass. The hairline `strokeShape` must match the caller's clip shape:
/// pass the same radius via `init(base:strokeRadius:)`, or the exact shape via
/// `init(base:strokeShape:)` when clipping with e.g. `Capsule` (a fixed corner
/// radius drifts from a capsule's dynamic radius under large Dynamic Type).
struct TracciCTABackground<S: InsettableShape>: View {
    var base: Color
    var strokeShape: S

    init(base: Color, strokeShape: S) {
        self.base = base
        self.strokeShape = strokeShape
    }

    init(base: Color, strokeRadius: CGFloat) where S == RoundedRectangle {
        self.init(
            base: base,
            strokeShape: RoundedRectangle(cornerRadius: strokeRadius, style: .continuous)
        )
    }

    var body: some View {
        ZStack {
            base

            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.10), location: 0),
                    .init(color: .white.opacity(0.0), location: 0.42),
                    .init(color: .black.opacity(0.0), location: 0.62),
                    .init(color: .black.opacity(0.035), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            strokeShape
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared press style

/// One tactile press language across all brand buttons — primary, secondary, ghost
/// and text links. Text-only buttons pass `scales: false` so labels don't shimmer
/// under compression. Honors Reduce Motion (feedback collapses to opacity-free).
struct TracciPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var scales = true

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        return configuration.label
            .opacity(isPressed ? AppMotion.pressOpacity : 1)
            .scaleEffect(isPressed && scales && !reduceMotion ? AppMotion.pressScale : 1)
            .animation(
                AppMotion.animation(AppMotion.press, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - PrimaryButton

enum TracciPrimaryButtonState: Equatable {
    case enabled
    case disabled
    case loading

    init(isEnabled: Bool, isLoading: Bool) {
        if isLoading {
            self = .loading
        } else {
            self = isEnabled ? .enabled : .disabled
        }
    }
}

/// Primary action button — full-width brand button for main CTAs.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var isEnabled = true
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: TracciPrimaryButtonState {
        TracciPrimaryButtonState(isEnabled: isEnabled, isLoading: isLoading)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.tight) {
                if isLoading {
                    AppProgressIndicator(tint: foregroundColor, diameter: 20)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.buttonIcon)
                }
                Text(title)
                    .font(AppTypography.buttonTitle)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, AppSpacing.cozy)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(ctaBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .tracciShadow(state == .disabled ? AppShadow.level0 : AppShadow.brand)
        }
        .disabled(state != .enabled)
        .buttonStyle(TracciPressableButtonStyle())
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: state)
    }

    /// G2.2 texture applies to enabled + loading states; disabled stays flat.
    @ViewBuilder
    private var ctaBackground: some View {
        if state == .disabled {
            AppColors.subtleBackground
        } else {
            // 白字 CTA 用深一档品牌蓝（#2563EB，白字 5.17:1）；brandPrimary 白字仅 3.68:1。
            TracciCTABackground(base: AppColors.brandPrimaryStrong, strokeRadius: AppRadius.button)
        }
    }

    private var foregroundColor: Color {
        state == .disabled ? AppColors.textMuted : AppColors.textPrimaryInverse
    }
}

// MARK: - SecondaryButton

/// Secondary button — outlined style for secondary actions.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.tight) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.buttonIcon)
                }
                Text(title)
                    .font(AppTypography.buttonTitleMedium)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(AppColors.textMuted)
            .padding(.horizontal, AppSpacing.cozy)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .stroke(AppColors.borderDefault, lineWidth: 1)
            }
        }
        .buttonStyle(TracciPressableButtonStyle())
    }
}

// MARK: - SecondaryTextButton

/// Text-only button for tertiary actions (links, "skip", etc.).
struct SecondaryTextButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.buttonTitleSecondary)
                .foregroundStyle(AppColors.interactiveText)
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
    }
}

// MARK: - Empty-trip CTA copy

/// Shared labels for “no trip yet” empty states (洞察 / 回忆).
/// Keep visual weight via full-size `OutlinedButton` — not compact — so peer tabs match.
enum TracciEmptyTripCTA {
    static let title = "开始第一段旅程"
    static let systemImage = "map"
}

// MARK: - OutlinedButton

/// Outlined button — brand-colored border capsule for primary actions in empty / onboarding states.
///
/// Use when you want a prominent CTA without the visual weight of a filled `PrimaryButton`.
/// Typical use: empty-state `TracciEmptyTripCTA` where a GhostButton is too subtle
/// and a PrimaryButton would feel too heavy.
struct OutlinedButton: View {
    let title: String
    var systemImage: String?
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 6 : 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(compact ? AppTypography.buttonIconCompact : AppTypography.buttonIcon)
                }
                Text(title)
                    .font(compact ? AppTypography.label : AppTypography.buttonTitle)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(AppColors.interactiveText)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 10 : 14)
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 42 : 52)
            .background(
                RoundedRectangle(cornerRadius: compact ? AppRadius.pill : AppRadius.button, style: .continuous)
                    .stroke(AppColors.brandPrimary.opacity(0.45), lineWidth: 1.2)
            )
            .background(
                RoundedRectangle(cornerRadius: compact ? AppRadius.pill : AppRadius.button, style: .continuous)
                    .fill(AppColors.brandPrimary.opacity(0.06))
            )
        }
        .buttonStyle(OutlinedButtonStyle())
    }
}

private struct OutlinedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        return configuration.label
            .opacity(pressed ? 0.72 : 1)
            .scaleEffect(pressed ? AppMotion.pressScale : 1)
            .animation(pressed ? AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion) : nil, value: configuration.isPressed)
    }
}

// MARK: - GhostButton

/// Ghost button — transparent background, for low-emphasis actions within cards or sheets.
struct GhostButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.buttonIconCompact)
                }
                Text(title)
                    .font(AppTypography.label)
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
    }
}

// MARK: - Success check

/// Compact success glyph: circle fill + stroke-drawn check.
/// Reduce Motion shows the completed mark immediately.
struct TracciSuccessCheck: View {
    var size: CGFloat = 22
    var fillsCircle = true
    var circleColor: Color = AppColors.success
    var checkColor: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var lineWidth: CGFloat {
        max(1.8, size * 0.09)
    }

    var body: some View {
        ZStack {
            if fillsCircle {
                Circle().fill(circleColor)
            }

            TracciSuccessCheckPath()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(
                    checkColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .scaleEffect(drawn || reduceMotion ? 1 : AppMotion.successCheckStartScale)
        .offset(y: drawn || reduceMotion ? 0 : AppMotion.successCheckAppearDistance)
        .opacity(drawn || reduceMotion ? 1 : 0)
        .onAppear(perform: play)
        .accessibilityHidden(true)
    }

    private func play() {
        if reduceMotion {
            drawn = true
            return
        }
        withAnimation(AppMotion.animation(AppMotion.successCheck, reduceMotion: reduceMotion)) {
            drawn = true
        }
    }
}

struct TracciSuccessCheckPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.18))
        return path
    }
}

/// Consent / boolean disc: fill first, then stroke-draw the check. Uncheck is a quick fade.
struct TracciStrokeCheckbox: View {
    var isOn: Bool
    var size: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var lineWidth: CGFloat {
        max(1.6, size * 0.09)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isOn ? AppColors.brandPrimary : AppColors.textDisabled,
                    lineWidth: 1.6
                )
            Circle()
                .fill(AppColors.brandPrimary)
                .opacity(isOn ? 1 : 0)
                .scaleEffect(isOn ? 1 : AppMotion.modalOpenScale)

            TracciSuccessCheckPath()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .animation(AppMotion.animation(AppMotion.checkFill, reduceMotion: reduceMotion), value: isOn)
        .onAppear {
            drawn = isOn
        }
        .onChange(of: isOn) { _, on in
            if reduceMotion {
                drawn = on
                return
            }
            if on {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    drawn = false
                }
                withAnimation(AppMotion.animation(AppMotion.checkDraw.delay(AppMotion.checkFillDuration), reduceMotion: reduceMotion)) {
                    drawn = true
                }
            } else {
                withAnimation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion)) {
                    drawn = false
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - FormSheetTopBar

/// Top bar for sheet-style and pushed forms (journal, expense, itinerary, trip edit, join trip).
///
/// In `.sheet` presentation this draws the branded drag bar. When hosting inside
/// `tracciBottomSheet`, pass `showDragBar: false` on the container so only one bar appears.
///
/// - `.form`: cancel + save button (default) — for traditional save/cancel forms.
/// - `.editor`: cancel + "完成" done button — keyboard-first focused editors.
/// - `.task`: cancel only, no trailing action — the primary CTA lives fixed at the bottom.
struct FormSheetTopBar: View {
    let title: String
    var cancelTitle = "取消"
    var saveTitle = "保存"
    var isCancelEnabled = true
    var isSubmitting = false
    var isSaveEnabled = true
    var showSaveSuccess = false
    var showsSaveButton = true
    var presentation: FormChromePresentation = .sheet
    var bottomPadding: CGFloat = 12
    let onCancel: () -> Void
    var onSave: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topInset = SafeAreaMetrics.top

    var body: some View {
        VStack(spacing: 0) {
            if presentation == .sheet {
                TracciPickerChrome.dragBar
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.sm)
            }

            ZStack {
                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .padding(.horizontal, 64)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    topBarActionButton(
                        title: cancelTitle,
                        foreground: isCancelEnabled ? AppColors.interactiveText : AppColors.textDisabled,
                        alignment: .leading,
                        action: onCancel
                    )
                    .disabled(!isCancelEnabled)

                    Spacer(minLength: AppSpacing.sm)

                    if showsSaveButton {
                        Button(action: { onSave?() }) {
                            saveButtonLabel
                        }
                        .buttonStyle(TracciPressableButtonStyle(scales: false))
                        .disabled(isSubmitting || showSaveSuccess || !isSaveEnabled)
                    } else {
                        Color.clear
                            .frame(minWidth: 48)
                            .frame(height: 44)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageX)

            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 0.5)
                .padding(.top, AppSpacing.cozy)
        }
        .padding(.top, presentation == .sheet ? 0 : topPadding)
        .padding(.bottom, bottomPadding)
        .animation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion), value: showSaveSuccess)
        .animation(AppMotion.animation(AppMotion.quick, reduceMotion: reduceMotion), value: isSubmitting)
        .onAppear(perform: refreshTopInset)
        .tracciReadsSafeAreaTop($topInset)
    }

    private func topBarActionButton(
        title: String,
        foreground: Color,
        alignment: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.buttonTitleMedium)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .frame(minWidth: 48)
                .frame(height: 44, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(TracciPressableButtonStyle(scales: false))
    }

    private var topPadding: CGFloat {
        switch presentation {
        case .sheet:
            return SafeAreaMetrics.sheetChromeTopPadding
        case .pushed:
            return SafeAreaMetrics.chromeTopPadding(using: topInset)
        }
    }

    private func refreshTopInset() {
        guard presentation == .pushed else { return }
        topInset = SafeAreaMetrics.top
    }

    private var saveButtonLabel: some View {
        ZStack(alignment: .trailing) {
            if showSaveSuccess {
                TracciSuccessCheck(size: 22)
                    .transition(.scale(scale: AppMotion.successCheckStartScale).combined(with: .opacity))
            } else if isSubmitting {
                AppProgressIndicator(diameter: 18)
                    .transition(.opacity)
            } else {
                Text(saveTitle)
                    .font(AppTypography.buttonTitle)
                    .lineLimit(1)
                    .foregroundStyle(saveButtonForeground)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 48)
        .frame(height: 44, alignment: .trailing)
        .contentShape(Rectangle())
    }

    private var saveButtonForeground: Color {
        if showSaveSuccess { return AppColors.success }
        return isSaveEnabled ? AppColors.interactiveText : AppColors.textDisabled
    }
}

// MARK: - Fixed Bottom CTA Container

/// A safe-area-aware container that pins a primary CTA to the bottom of a sheet/task page.
///
/// Place this in `.safeAreaInset(edge: .bottom)` on the owning scaffold (not a
/// raw `VStack` footer). It draws a subtle top separator and extends its
/// background through the home-indicator region.
///
/// The button itself sits above the safe area; the container's background extends into
/// the home-indicator region so there is no gap.
struct TracciFixedBottomCTA<CTA: View>: View {
    var backgroundColor: Color = AppColors.backgroundPrimary
    @ViewBuilder var content: () -> CTA

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 0.5)

            content()
                .padding(.horizontal, AppSpacing.pageX)
                .padding(.top, AppSpacing.fixedCTATopPadding)
                .padding(.bottom, AppSpacing.fixedCTABottomPadding)
        }
        .frame(maxWidth: .infinity)
        .background(backgroundColor.ignoresSafeArea(edges: .bottom))
    }
}

#if DEBUG
#Preview("Primary Button States") {
    VStack(spacing: AppSpacing.md) {
        PrimaryButton(title: "创建旅程", systemImage: "plus", action: {})
        PrimaryButton(title: "创建旅程", isLoading: true, action: {})
        PrimaryButton(title: "创建旅程", isEnabled: false, action: {})
    }
    .padding(AppSpacing.pageX)
    .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
