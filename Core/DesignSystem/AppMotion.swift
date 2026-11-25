import SwiftUI
import UIKit

/// Shared motion tokens for Tracci. Apply by tier so key moments stay memorable without
/// over-animating browse flows.
///
/// - **Tier 1 — Milestone:** create trip, add itinerary node, AI draft applied.
///   Use `AppHaptics.success()` plus a single prominent entry (e.g. `fadeSlideIn(index: 0)`).
/// - **Tier 2 — Context expansion:** home/all-trips lists, filter changes, day switches.
///   Use `fadeSlideIn` stagger + `motionTransition` with `quick` / `normal`.
/// - **Tier 3 — Micro interaction:** card press, filter pills, toggles.
///   Use `pressableCardStyle` + `quick` / `softSpring` + selection haptics.
enum AppMotion {
    static let quickDuration: TimeInterval = 0.18
    static let normalDuration: TimeInterval = 0.28
    static let slowDuration: TimeInterval = 0.42
    static let atmosphereDuration: TimeInterval = 8
    /// Crossfade between journey-stage scene temperatures after trip status refresh.
    /// Kept under one second so the page responds promptly while avoiding a hard color jump.
    static let atmosphereTransitionDuration: TimeInterval = 0.85

    /// Media fade-in after decode (covers, journal grid). Keep short to avoid laggy lists.
    static let imageFadeDuration: TimeInterval = 0.20
    /// Soft entrance when pushing into trip detail (opacity only under Reduce Motion).
    static let detailEnterDuration: TimeInterval = 0.26
    static let detailEnterScale: CGFloat = 0.985

    static let pressScale: CGFloat = 0.975
    static let selectedScale: CGFloat = 1.025
    static let pressOpacity: Double = 0.92
    /// Finger-down press. 160ms ease-out — high-frequency, must stay snappy.
    static let pressDuration: TimeInterval = 0.16
    static let fadeSlideOffset: CGFloat = 10
    static let largeFadeSlideOffset: CGFloat = 14
    static let milestoneOffset: CGFloat = 18
    /// Starting scale for a newly created card's milestone entrance (grows to 1.0).
    static let milestoneEntranceScale: CGFloat = 0.96
    /// How long a card keeps its "newly created" mark after creation. Must
    /// comfortably cover `milestoneSpring`'s entrance + settle — tune together
    /// with the spring. Drives `HomeViewModel.markNewlyCreated`.
    static let milestoneEntranceWindow: TimeInterval = 1.6
    /// Day-switch creek motion. Pagination must remain directional, so this uses a
    /// non-overshooting curve: later days always travel left, earlier days right.
    static let daySwitchDistance: CGFloat = 44
    static let daySwitchDuration: TimeInterval = 0.30
    static let daySwitchFadedOpacity: Double = 0.58
    static let daySwitchReducedMotionOpacity: Double = 0.72
    /// Secondary “depth” layer: opacity/scale settle with the slide (no delay).
    /// A delayed parallax left residual on rapid Day taps.
    static let daySwitchDepthScale: CGFloat = 0.982
    /// The route spine never grows from zero so timeline context remains visually stable.
    static let daySpineInitialScale: CGFloat = 0.30
    /// Map ↔ timeline focus feedback.
    static let mapMarkerSelectedScale: CGFloat = 1.15
    static let mapMarkerBounceDuration: TimeInterval = 0.35
    static let mapMarkerBounceDamping: CGFloat = 0.75
    static let mapMarkerSettleDuration: TimeInterval = 0.28
    static let timelineLinkPulseInDuration: TimeInterval = 0.10
    static let timelineLinkPulseOutDuration: TimeInterval = 0.30
    static let listStaggerDelay: TimeInterval = 0.035
    static let maxStaggerDelay: TimeInterval = 0.18

    /// Sliding selection pill (segmented controls, filter chips, mode toggles).
    static let selectionPillDuration: TimeInterval = 0.25
    /// Skeleton / cover content reveal: long enough to read the handoff, short enough for lists.
    static let skeletonRevealDuration: TimeInterval = 0.40
    static let skeletonRevealBlur: CGFloat = 2
    /// Form error shake: five segments, large then small.
    static let errorShakeSegmentDuration: TimeInterval = 0.08
    static let errorShakeSmallDistance: CGFloat = 6
    static let errorShakeLargeDistance: CGFloat = 8
    /// Success check: path draw + settle. Matches `TracciFormSaveFeedback` display window.
    static let successCheckDuration: TimeInterval = 0.50
    static let successCheckStartScale: CGFloat = 0.86
    static let successCheckAppearDistance: CGFloat = 6
    /// Modal / launcher pre-scale. Bigger surfaces start further from rest (never below ~0.96).
    static let modalOpenScale: CGFloat = 0.96
    static let modalCloseScale: CGFloat = 0.97

    /// Plus → menu morph. Open invites; close gets out of the way.
    static let morphOpenDuration: TimeInterval = 0.32
    static let morphCloseDuration: TimeInterval = 0.20
    /// Number pop-in: last two glyphs stagger so the update reads as a count, not a flash.
    static let numberPopDuration: TimeInterval = 0.40
    static let numberPopDistance: CGFloat = 8
    static let numberPopBlur: CGFloat = 2
    static let numberPopStagger: TimeInterval = 0.04
    /// Toast rise + stack. Close is snappier than open.
    static let toastOpenDuration: TimeInterval = 0.35
    static let toastCloseDuration: TimeInterval = 0.22
    static let toastDistance: CGFloat = 16
    static let toastBlur: CGFloat = 2
    static let toastScale: CGFloat = 0.97
    static let toastStackPeek: CGFloat = 12
    static let toastStackDepthScale: CGFloat = 0.06
    static let toastMaxStack = 3
    /// Empty-state / companion copy: stacked lines rise with a short blur.
    static let textsRevealOffset: CGFloat = 12
    static let textsRevealBlur: CGFloat = 3
    static let textsRevealStagger: TimeInterval = 0.06
    /// Switch thumb: overshoot only when turning on.
    static let switchOnResponse: TimeInterval = 0.32
    static let switchOffDuration: TimeInterval = 0.15
    /// Consent checkbox: fill the disc, then draw the check.
    static let checkFillDuration: TimeInterval = 0.15
    static let checkDrawDuration: TimeInterval = 0.35
    /// Join-success overlay hold after the check draws, then the host dismisses.
    static let joinSuccessHoldDuration: TimeInterval = 0.72
    /// Search / filter clear: text flies up-right, blurs, and fades.
    static let inputClearDuration: TimeInterval = 0.40
    static let inputClearDistanceX: CGFloat = 8
    static let inputClearDistanceY: CGFloat = -12
    static let inputClearBlur: CGFloat = 2
    /// NEW / count badge first appearance.
    static let badgePopDuration: TimeInterval = 0.50
    /// Caret / 溪线进度的呼吸周期。比 `atmosphereDuration` 快得多——这是「还在处理中」的
    /// 信号，不是氛围背景；Reduce Motion 下调用方应改用常亮而不是这个动画。
    static let pulseDuration: TimeInterval = 0.7
    /// 呼吸时压到的最低不透明度（常亮为 1）。
    static let pulseDimmedOpacity: CGFloat = 0.15

    static var pulse: Animation {
        .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
    }

    static var quick: Animation {
        .easeOut(duration: quickDuration)
    }

    /// Card / chip / button press. Ease-out so the down-state is immediate.
    static var press: Animation {
        .easeOut(duration: pressDuration)
    }

    /// Content entrance (lists, tab swap, delete). Starts fast; not for on-screen morphs.
    static var enter: Animation {
        .easeOut(duration: normalDuration)
    }

    /// On-screen morphs (dock show/hide, layout springs). Not a default entrance.
    static var normal: Animation {
        .easeInOut(duration: normalDuration)
    }

    static var slow: Animation {
        .easeInOut(duration: slowDuration)
    }

    static var softSpring: Animation {
        .spring(response: 0.30, dampingFraction: 0.86)
    }

    /// Creation and growth moments. Use at most once for the primary event on a screen.
    static var milestoneSpring: Animation {
        .spring(response: 0.42, dampingFraction: 0.80)
    }

    /// Day switches, filters, and compact context changes.
    static var contextSpring: Animation {
        .spring(response: 0.30, dampingFraction: 0.88)
    }

    /// Root tab chrome compact ↔ expanded. Springs real geometry (height/padding);
    /// glyphs stay stable via ZStack layout (not by scaling the glass host).
    static var chromeMode: Animation {
        .spring(response: 0.40, dampingFraction: 0.84)
    }

    /// Sliding selection lens + newly selected glyph emphasis. Slightly snappier than
    /// chromeMode so the destination change reads as intentional, not laggy.
    static var tabSelection: Animation {
        .spring(response: 0.32, dampingFraction: 0.78)
    }

    /// Previous tab settles out quickly so it does not spring-shrink with the lens.
    static let tabDeselectDuration: TimeInterval = 0.12

    static var daySwitch: Animation {
        .easeOut(duration: daySwitchDuration)
    }

    // MARK: Map explore surface (browse ↔ 全屏地图)

    /// 进入大地图：ease-out，略长以读清展开。
    static let mapExploreEnterDuration: TimeInterval = 0.30
    /// 退出大地图：更快（约 70% 进入时长）。
    static let mapExploreExitDuration: TimeInterval = 0.22
    /// 底部 dock / 浮层相对地图本体的错峰。
    static let mapExploreChromeDelay: TimeInterval = 0.05
    /// Reduce Motion：仅短 fade。
    static let mapExploreReducedDuration: TimeInterval = 0.15

    static var mapExploreEnter: Animation {
        .easeOut(duration: mapExploreEnterDuration)
    }

    static var mapExploreExit: Animation {
        .easeIn(duration: mapExploreExitDuration)
    }

    static var mapExploreChromeEnter: Animation {
        .easeOut(duration: mapExploreEnterDuration * 0.9).delay(mapExploreChromeDelay)
    }

    static var mapExploreChromeExit: Animation {
        .easeIn(duration: mapExploreExitDuration * 0.85)
    }

    static var mapExploreReduced: Animation {
        .easeOut(duration: mapExploreReducedDuration)
    }

    /// 大地图内切换 Day / 卡片联动镜头：短 ease-out，与 Tab 下划线同节奏。
    static let mapExploreDayCameraDuration: TimeInterval = 0.24

    static var mapExploreDayCamera: Animation {
        .easeOut(duration: mapExploreDayCameraDuration)
    }

    /// Optional ambient breathing for emotional surfaces. Never use for content cards.
    static var atmosphereBreathing: Animation {
        .easeInOut(duration: atmosphereDuration).repeatForever(autoreverses: true)
    }

    static var atmosphereTransition: Animation {
        .easeInOut(duration: atmosphereTransitionDuration)
    }

    static var imageFade: Animation {
        .easeOut(duration: imageFadeDuration)
    }

    static var detailEnter: Animation {
        .easeOut(duration: detailEnterDuration)
    }

    /// Symmetric pill travel between mutually exclusive options.
    static var selectionPill: Animation {
        .easeInOut(duration: selectionPillDuration)
    }

    static var skeletonReveal: Animation {
        .easeInOut(duration: skeletonRevealDuration)
    }

    static var successCheck: Animation {
        .easeOut(duration: successCheckDuration)
    }

    static var morphOpen: Animation {
        .spring(response: morphOpenDuration, dampingFraction: 0.82)
    }

    static var morphClose: Animation {
        .easeInOut(duration: morphCloseDuration)
    }

    static var numberPop: Animation {
        .spring(response: numberPopDuration, dampingFraction: 0.72)
    }

    static var toastOpen: Animation {
        .easeOut(duration: toastOpenDuration)
    }

    static var toastClose: Animation {
        .easeIn(duration: toastCloseDuration)
    }

    static var textsReveal: Animation {
        .easeOut(duration: slowDuration)
    }

    static var switchOn: Animation {
        .spring(response: switchOnResponse, dampingFraction: 0.62)
    }

    static var switchOff: Animation {
        .easeOut(duration: switchOffDuration)
    }

    static var checkFill: Animation {
        .easeOut(duration: checkFillDuration)
    }

    static var checkDraw: Animation {
        .easeOut(duration: checkDrawDuration)
    }

    static var inputClear: Animation {
        .easeOut(duration: inputClearDuration)
    }

    static var badgePop: Animation {
        .spring(response: badgePopDuration, dampingFraction: 0.62)
    }

    static func revealTransition(reduceMotion: Bool, blur: CGFloat = skeletonRevealBlur) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .modifier(
                active: TracciRevealBlurModifier(progress: 1, blur: blur),
                identity: TracciRevealBlurModifier(progress: 0, blur: blur)
            ),
            removal: .modifier(
                active: TracciRevealBlurModifier(progress: 1, blur: blur),
                identity: TracciRevealBlurModifier(progress: 0, blur: blur)
            )
        )
    }

    // MARK: - Memory Story Tokens

    static let storyPageTransition: Animation = .interactiveSpring(response: 0.36, dampingFraction: 0.86, blendDuration: 0.08)
    static let launcherPresent: Animation = .spring(response: 0.38, dampingFraction: 0.82)
    static let launcherDismiss: Animation = .easeInOut(duration: 0.24)
    static let storyCoverFade: Animation = .easeOut(duration: 0.9)
    static let storyElementFade: Animation = .easeOut(duration: 0.5)
    static let storyEntry: Animation = .easeOut(duration: 0.35)
    static let storyStaggerBase: TimeInterval = 0.1
    static let storyStaggerStep: TimeInterval = 0.1

    static func staggerDelay(for index: Int) -> TimeInterval {
        min(Double(index) * listStaggerDelay, maxStaggerDelay)
    }

    /// Reduce Motion: short ease-out so opacity/color can still fade.
    /// Callers must zero offset/scale themselves — this helper does not drop movement.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: quickDuration) : animation
    }

    static func transition(reduceMotion: Bool, yOffset: CGFloat = fadeSlideOffset) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: yOffset))
    }
}

enum AppHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var scale: CGFloat = AppMotion.pressScale
    var opacity: Double = AppMotion.pressOpacity
    /// Extra vertical lift on press for hero cards. Default 0 keeps the
    /// existing behavior; set to a small positive value (e.g. 2) to add a
    /// "cover pushes toward viewer" hint without a separate gesture.
    var heroLift: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .offset(y: configuration.isPressed && !reduceMotion ? -heroLift : 0)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(AppMotion.animation(AppMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct FadeSlideInModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var delay: TimeInterval = 0
    var offset: CGFloat = AppMotion.fadeSlideOffset
    var animation: Animation = AppMotion.enter
    /// When false, content renders visible/static so another entrance can drive it (P2).
    var active: Bool = true

    func body(content: Content) -> some View {
        content
            .opacity(!active || hasAppeared ? 1 : 0)
            .offset(y: (!active || reduceMotion || hasAppeared) ? 0 : offset)
            .onAppear {
                guard active, !hasAppeared else { return }
                withAnimation(AppMotion.animation(animation.delay(reduceMotion ? 0 : delay), reduceMotion: reduceMotion)) {
                    hasAppeared = true
                }
            }
            .onChange(of: active) { _, nowActive in
                // Already on screen — settle without replaying the stagger.
                if nowActive { hasAppeared = true }
            }
    }
}

/// Milestone entrance for a freshly created card (P2): starts at scale 0.9 + opacity 0
/// and grows into place with `milestoneSpring`. Inactive content renders untouched.
///
/// Important: creation often marks a card as “new” *after* it has already appeared
/// (refresh first, then set `newlyCreatedNodeId`). Handle `active` flipping true
/// post-appear, otherwise the card stays at opacity 0 forever.
struct MilestoneEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var active: Bool

    private var isResting: Bool { !active || settled || reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(isResting ? 1 : 0)
            .scaleEffect(isResting ? 1 : AppMotion.milestoneEntranceScale, anchor: .top)
            .onAppear {
                playEntranceIfNeeded()
            }
            .onChange(of: active) { _, nowActive in
                if nowActive {
                    // Card was already on-screen when creation id was assigned.
                    playEntranceIfNeeded()
                } else {
                    // Reset so a later create on this row can animate again.
                    settled = false
                }
            }
    }

    private func playEntranceIfNeeded() {
        guard active, !settled else { return }
        if reduceMotion {
            settled = true
            return
        }
        withAnimation(AppMotion.animation(AppMotion.milestoneSpring, reduceMotion: reduceMotion)) {
            settled = true
        }
    }
}

private struct TracciRevealBlurModifier: ViewModifier {
    var progress: Double
    var blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .blur(radius: blur * progress)
    }
}

/// Horizontal form-error shake. Replays when `trigger` becomes active.
///
/// Pass the error string (or a bool) so a new failure of the same copy still
/// replays if the ViewModel clears then sets the message.
struct TracciErrorShakeModifier<Value: Equatable>: ViewModifier {
    let trigger: Value
    var isActive: (Value) -> Bool
    var playsHaptic: Bool
    var shakesOnAppear: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakeToken = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeToken) { view, offset in
                view.offset(x: reduceMotion ? 0 : offset)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    LinearKeyframe(-AppMotion.errorShakeLargeDistance, duration: AppMotion.errorShakeSegmentDuration)
                    LinearKeyframe(AppMotion.errorShakeLargeDistance, duration: AppMotion.errorShakeSegmentDuration)
                    LinearKeyframe(-AppMotion.errorShakeSmallDistance, duration: AppMotion.errorShakeSegmentDuration)
                    LinearKeyframe(AppMotion.errorShakeSmallDistance, duration: AppMotion.errorShakeSegmentDuration)
                    LinearKeyframe(0, duration: AppMotion.errorShakeSegmentDuration)
                }
            }
            .onAppear {
                guard shakesOnAppear, isActive(trigger) else { return }
                fire()
            }
            .onChange(of: trigger) { _, newValue in
                guard isActive(newValue) else { return }
                fire()
            }
    }

    private func fire() {
        if playsHaptic {
            AppHaptics.error()
        }
        guard !reduceMotion else { return }
        shakeToken += 1
    }
}

struct TracciTextsRevealModifier: ViewModifier {
    var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : AppMotion.textsRevealOffset)
            .blur(radius: reduceMotion || appeared ? 0 : AppMotion.textsRevealBlur)
            .onAppear {
                if reduceMotion {
                    appeared = true
                    return
                }
                let delay = min(Double(index) * AppMotion.textsRevealStagger, AppMotion.maxStaggerDelay)
                withAnimation(AppMotion.animation(AppMotion.textsReveal.delay(delay), reduceMotion: reduceMotion)) {
                    appeared = true
                }
            }
    }
}

/// Per-glyph pop-in when a numeric string changes. Last two glyphs stagger.
struct TracciNumberPopIn: View {
    let text: String
    var font: Font = AppTypography.captionMedium
    var color: Color = AppColors.textPrimary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(font)
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .modifier(
                        TracciDigitPopModifier(
                            token: text,
                            index: index,
                            total: text.count,
                            reduceMotion: reduceMotion
                        )
                    )
            }
        }
    }
}

private struct TracciDigitPopModifier: ViewModifier {
    let token: String
    let index: Int
    let total: Int
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : AppMotion.numberPopDistance)
            .blur(radius: shown || reduceMotion ? 0 : AppMotion.numberPopBlur)
            .onAppear(perform: play)
            .onChange(of: token) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    shown = false
                }
                play()
            }
    }

    private func play() {
        if reduceMotion {
            shown = true
            return
        }
        let fromEnd = total - 1 - index
        let staggerSteps = min(max(fromEnd, 0), 2)
        let delay = AppMotion.numberPopStagger * Double(staggerSteps)
        withAnimation(AppMotion.animation(AppMotion.numberPop.delay(delay), reduceMotion: reduceMotion)) {
            shown = true
        }
    }
}

/// Flying snapshot of a field's text while the binding is cleared.
struct TracciClearDissolveLayer: View {
    let text: String?
    let progress: CGFloat
    var font: Font = AppTypography.listBody
    var color: Color = AppColors.textPrimary
    var leadingInset: CGFloat = 40

    var body: some View {
        if let text, progress < 1 {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.leading, leadingInset)
                .offset(
                    x: progress * AppMotion.inputClearDistanceX,
                    y: progress * AppMotion.inputClearDistanceY
                )
                .opacity(Double(1 - progress))
                .blur(radius: progress * AppMotion.inputClearBlur)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

enum TracciClearDissolve {
    @MainActor
    static func play(
        text: Binding<String>,
        snapshot: Binding<String?>,
        progress: Binding<CGFloat>,
        reduceMotion: Bool
    ) {
        let current = text.wrappedValue
        guard !current.isEmpty else { return }
        if reduceMotion {
            text.wrappedValue = ""
            return
        }
        snapshot.wrappedValue = current
        progress.wrappedValue = 0
        text.wrappedValue = ""
        withAnimation(AppMotion.inputClear) {
            progress.wrappedValue = 1
        }
        Task {
            try? await Task.sleep(for: .seconds(AppMotion.inputClearDuration))
            snapshot.wrappedValue = nil
            progress.wrappedValue = 0
        }
    }
}

extension View {
    func pressableCardStyle(scale: CGFloat = AppMotion.pressScale, opacity: Double = AppMotion.pressOpacity, heroLift: CGFloat = 0) -> some View {
        buttonStyle(PressableCardStyle(scale: scale, opacity: opacity, heroLift: heroLift))
    }

    func fadeSlideIn(index: Int = 0, offset: CGFloat = AppMotion.fadeSlideOffset, animation: Animation = AppMotion.enter, active: Bool = true) -> some View {
        modifier(
            FadeSlideInModifier(
                delay: AppMotion.staggerDelay(for: index),
                offset: offset,
                animation: animation,
                active: active
            )
        )
    }

    /// Milestone creation entrance (P2) — applied to a freshly created card.
    func milestoneEntrance(active: Bool) -> some View {
        modifier(MilestoneEntranceModifier(active: active))
    }

    func motionTransition(reduceMotion: Bool, yOffset: CGFloat = AppMotion.fadeSlideOffset) -> some View {
        transition(AppMotion.transition(reduceMotion: reduceMotion, yOffset: yOffset))
    }

    /// Skeleton / cover handoff. Pair with `AppMotion.skeletonReveal` or `imageFade`.
    func tracciRevealTransition(reduceMotion: Bool) -> some View {
        transition(AppMotion.revealTransition(reduceMotion: reduceMotion))
    }

    /// Shake this control when `errorMessage` becomes non-nil.
    func tracciErrorShake(_ errorMessage: String?, haptic: Bool = true, onAppear: Bool = false) -> some View {
        modifier(
            TracciErrorShakeModifier(
                trigger: errorMessage,
                isActive: { $0 != nil },
                playsHaptic: haptic,
                shakesOnAppear: onAppear
            )
        )
    }

    /// Shake this control when `isError` flips to true.
    func tracciErrorShake(_ isError: Bool, haptic: Bool = true, onAppear: Bool = false) -> some View {
        modifier(
            TracciErrorShakeModifier(
                trigger: isError,
                isActive: { $0 },
                playsHaptic: haptic,
                shakesOnAppear: onAppear
            )
        )
    }

    /// Shake this control when `trigger` is active.
    func tracciErrorShake<Value: Equatable>(
        _ trigger: Value,
        active: @escaping (Value) -> Bool,
        haptic: Bool = true,
        onAppear: Bool = false
    ) -> some View {
        modifier(
            TracciErrorShakeModifier(
                trigger: trigger,
                isActive: active,
                playsHaptic: haptic,
                shakesOnAppear: onAppear
            )
        )
    }

    /// Staggered blurred rise for stacked copy (empty states, companion cards).
    func tracciTextsReveal(index: Int) -> some View {
        modifier(TracciTextsRevealModifier(index: index))
    }

    // MARK: - Hero zoom transition (G3.1)

    /// Marks a home card as the zoom-transition source for its detail hero.
    /// No-op below iOS 18 — the deployment target stays iOS 17.
    @ViewBuilder
    func tracciHeroZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Applies the shared-element zoom transition on the pushed trip detail page.
    /// Skipped below iOS 18 and under Reduce Motion (falls back to the existing
    /// `detailEnter` settle). If no matching source is visible (e.g. the push came
    /// from All Trips), the system uses the default push transition.
    @ViewBuilder
    func tracciHeroZoomDestination(id: some Hashable, in namespace: Namespace.ID, reduceMotion: Bool) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
