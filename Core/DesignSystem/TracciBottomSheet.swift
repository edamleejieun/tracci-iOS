import SwiftUI
import UIKit

// MARK: - Dialog Metrics

enum TracciDialogMetrics {
    static var topChromeHeight: CGFloat {
        AppSpacing.pickerChromeTop + 5 + AppSpacing.pickerDragToTitle
    }

    static var bottomInset: CGFloat {
        max(SafeAreaMetrics.bottom, 16) + AppSpacing.sm
    }

    /// Active window height — used to convert fractional sheet presets to edge-attached heights.
    static var screenHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        if let window = windowScene?.windows.first(where: \.isKeyWindow) {
            return window.bounds.height
        }
        return UIScreen.main.bounds.height
    }

    static func fractionHeight(_ fraction: CGFloat) -> CGFloat {
        screenHeight * fraction
    }

    static func confirmHeight(message: String, buttonRowCount: Int = 1) -> CGFloat {
        let chrome = topChromeHeight
        let icon: CGFloat = 56
        let sectionGap = AppSpacing.lg
        let titleBlock: CGFloat = 26
        let titleToMessage = AppSpacing.sm
        let estimatedMessageLines = max(2, min(5, Int(ceil(Double(message.count) / 20.0))))
        let messageBlock = CGFloat(estimatedMessageLines) * 22
        let buttonBlock = CGFloat(buttonRowCount) * 48 + (buttonRowCount > 1 ? 12 : 0)
        return chrome + icon + sectionGap + titleBlock + titleToMessage + messageBlock + sectionGap + buttonBlock + bottomInset
    }

    static func actionSheetHeight(actionCount: Int, hasHeader: Bool) -> CGFloat {
        let chrome = topChromeHeight
        let header: CGFloat = hasHeader ? 64 : 0
        let rowBlock = CGFloat(actionCount) * 56
        let cancelBlock: CGFloat = 12 + 54
        return chrome + header + rowBlock + cancelBlock + bottomInset
    }

    static func tripShareSheetHeight(activeMemberCount: Int) -> CGFloat {
        let chrome = topChromeHeight
        let header: CGFloat = activeMemberCount > 0 ? 98 : 62
        let inviteCard: CGFloat = 18 + 90
        let quickActions: CGFloat = 14 + 100
        return chrome + header + inviteCard + quickActions + bottomInset
    }

    static func choiceSheetHeight(itemCount: Int) -> CGFloat {
        let chrome = topChromeHeight
        let header: CGFloat = 58
        let rowBlock = CGFloat(itemCount) * 56
        return chrome + header + rowBlock + bottomInset
    }

    // MARK: - Compact Form Sheets

    /// Action row only (cancel / title / save). Does not include drag bar.
    static let formSheetTopBarHeight: CGFloat = 56

    enum InvitationSheetState {
        case create
        case result
        case error
    }

    /// Invite-friends sheet heights aligned with `CreateInvitationView`.
    static func invitationSheetHeight(
        state: InvitationSheetState,
        errorMessage: String? = nil,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> CGFloat {
        let topChrome = formSheetTopBarHeight
        let header: CGFloat = 56
        let bottomPadding = max(20, SafeAreaMetrics.bottom + 10)
        let roleSection: CGFloat = 36 + 88 + 88 + 16
        let generateButton: CGFloat = 50
        let formSpacing: CGFloat = 32

        let content: CGFloat
        switch state {
        case .create:
            content = roleSection + formSpacing + generateButton
        case .result:
            content = 100 + 14 + (50 + 12 + 50)
        case .error:
            let errorBanner = estimatedErrorBannerHeight(
                lineCount: estimatedMessageLines(for: errorMessage ?? "错误", charactersPerLine: 28)
            )
            content = roleSection + formSpacing + errorBanner + 16 + generateButton
        }

        let base = topChrome + header + content + bottomPadding
        return scaledCompactSheetHeight(base, dynamicTypeSize: dynamicTypeSize)
    }

    static func compactSheetScale(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall: 0.94
        case .small: 0.96
        case .medium: 0.98
        case .large: 1.0
        case .xLarge: 1.05
        case .xxLarge: 1.10
        case .xxxLarge: 1.15
        case .accessibility1: 1.22
        case .accessibility2: 1.30
        case .accessibility3: 1.38
        case .accessibility4: 1.46
        case .accessibility5: 1.54
        @unknown default: 1.0
        }
    }

    static func scaledCompactSheetHeight(_ base: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        min(base * compactSheetScale(for: dynamicTypeSize), screenHeight * 0.92)
    }

    static func estimatedMessageLines(for text: String, charactersPerLine: Int) -> Int {
        max(1, min(4, Int(ceil(Double(max(text.count, 1)) / Double(charactersPerLine)))))
    }

    static func estimatedErrorBannerHeight(lineCount: Int) -> CGFloat {
        24 + CGFloat(lineCount) * 18
    }

    /// Stats trip picker when the list is short enough for a compact sheet.
    static func statsTripPickerSheetHeight(tripCount: Int) -> CGFloat {
        let chrome = topChromeHeight
        let header: CGFloat = 72
        let rowBlock = CGFloat(max(tripCount, 1)) * 56 + CGFloat(max(0, tripCount - 1)) * 8
        return min(chrome + header + rowBlock + bottomInset, 520)
    }

    /// Export content options sheet.
    static let exportContentOptionsSheetHeight: CGFloat = 470

    /// Export itinerary day picker sheet.
    static let exportDayPickerSheetHeight: CGFloat = 520
}

// MARK: - Bottom Sheet Chrome

enum TracciSheetChrome {
    static var dragBar: some View {
        TracciPickerChrome.dragBar
    }
}

/// 弹窗呈现生命周期阶段，用于驱动出场/退场动画。
enum TracciSheetPresentationPhase {
    /// 初始状态：弹窗在屏幕下方不可见。
    case idle
    /// 出场中：正在播放滑入动画。
    case presenting
    /// 已呈现：弹窗完全可见，可交互。
    case presented
    /// 退场中：正在播放滑出动画。
    case dismissing
}

/// 弹层出入场动效 token，语汇与 `AppMotion` 弹簧族一致。
/// 退场时长同时暴露给 window 层，用于安排 hosting view 的移除时机。
private enum TracciSheetMotion {
    static let entrance = Animation.spring(response: 0.40, dampingFraction: 0.85)
    static let exitDuration: TimeInterval = 0.28
    /// Reduce Motion：不做位移，仅短淡入淡出。
    static let reducedDuration: TimeInterval = 0.18

    static func exit(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: reducedDuration) : .easeIn(duration: exitDuration)
    }

    /// 退场动画播完后移除 hosting view 的等待时长（动画时长 + 缓冲）。
    static var removalDelay: TimeInterval {
        let base = UIAccessibility.isReduceMotionEnabled ? reducedDuration : exitDuration
        return base + 0.06
    }
}

/// Full-screen overlay bottom sheet used for branded compact flows.
struct TracciBottomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    var sheetHeight: CGFloat?
    var showDragBar: Bool = true
    var tapOutsideToDismiss: Bool = true
    var dragToDismiss: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        TracciBottomSheetWindowPresenter(
            isPresented: $isPresented,
            sheetHeight: sheetHeight,
            showDragBar: showDragBar,
            tapOutsideToDismiss: tapOutsideToDismiss,
            dragToDismiss: dragToDismiss,
            content: content
        )
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}

private struct TracciBottomSheetWindowPresenter<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var sheetHeight: CGFloat?
    var showDragBar: Bool
    var tapOutsideToDismiss: Bool
    var dragToDismiss: Bool
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    /// 视图被移出树时（如外层 `if` 条件翻转、页面被 pop）清理挂在 window 上的弹窗 view。
    /// 没有它，dismantle 不会触发 `updateUIViewController(isPresented: false)`，
    /// window 层会残留一个按钮已失效的「幽灵」遮罩，挡住整个 App。
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let rootView = AnyView(
            TracciBottomSheetOverlay(
                isPresented: $isPresented,
                sheetHeight: sheetHeight,
                showDragBar: showDragBar,
                tapOutsideToDismiss: tapOutsideToDismiss,
                dragToDismiss: dragToDismiss,
                content: content
            )
            .ignoresSafeArea(.all)
        )

        if isPresented {
            context.coordinator.present(from: uiViewController, rootView: rootView)
        } else {
            // 退场：把携带 false binding 的最新 rootView 刷给 overlay 触发退出动画，
            // hosting view 由 coordinator 在动画结束后移除，避免“瞬间消失”。
            context.coordinator.playExit(rootView: rootView)
        }
    }

    final class Coordinator {
        private var hostingController: UIHostingController<AnyView>?
        private var teardownTask: Task<Void, Never>?

        @MainActor
        func present(from sourceViewController: UIViewController, rootView: AnyView) {
            guard let window = sourceViewController.view.window ?? TracciBottomSheetWindowPresenter.activeKeyWindow else {
                return
            }

            // 重新呈现时撤销还未执行的退场移除。
            teardownTask?.cancel()
            teardownTask = nil

            if let hostingController {
                hostingController.rootView = rootView
                hostingController.view.frame = window.bounds
                return
            }

            let controller = UIHostingController(rootView: rootView)
            controller.view.backgroundColor = .clear
            controller.view.frame = window.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(controller.view)
            hostingController = controller
        }

        /// `isPresented` 翻转为 false：overlay 收到新值后播放退场动画，
        /// 这里在动画时长之后移除 hosting view。
        @MainActor
        func playExit(rootView: AnyView) {
            guard let controller = hostingController else { return }
            controller.rootView = rootView
            guard teardownTask == nil else { return }
            teardownTask = Task { @MainActor [weak self, weak controller] in
                try? await Task.sleep(nanoseconds: UInt64(TracciSheetMotion.removalDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                controller?.view.removeFromSuperview()
                self?.hostingController = nil
                self?.teardownTask = nil
            }
        }

        /// 立即移除（页面 pop / dismantle 清理路径，不播动画）。
        @MainActor
        func dismiss() {
            teardownTask?.cancel()
            teardownTask = nil
            hostingController?.view.removeFromSuperview()
            hostingController = nil
        }
    }

    private static var activeKeyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        return windowScene?.windows.first(where: \.isKeyWindow)
    }
}

private struct TracciBottomSheetOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    var sheetHeight: CGFloat?
    var showDragBar: Bool
    var tapOutsideToDismiss: Bool
    var dragToDismiss: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var isDismissing = false
    /// 拖拽过程中是否已触发过阈值 haptic（避免重复触发）。
    @State private var didFireThresholdHaptic = false
    /// 弹窗生命周期阶段：控制出场/退场动画。
    @State private var phase: TracciSheetPresentationPhase = .presenting

    /// 动画进度 0→1：出场涨到 1、退场落回 0，驱动位移/透明度/遮罩。
    @State private var animationProgress: CGFloat = 0

    // MARK: - Constants

    /// 触发关闭的拖拽距离阈值。
    private let dismissThreshold: CGFloat = 100
    /// 松手瞬时向下速度（pt/s）超过此值视为甩动关闭。
    /// 必须用释放瞬间速度：全程平均速度会把「快拖—停顿—松手」误判成甩动。
    private let flickDismissVelocity: CGFloat = 500
    /// 拖拽惯性预测终点越过该位移（pt）即关闭，覆盖「甩动后减速松手」。
    private let flickDismissPredictedTravel: CGFloat = 140
    /// 拖拽阻力系数：超过阈值后施加橡胶带效果。
    private let rubberBandResistance: CGFloat = 0.55
    /// 遮罩基础不透明度。
    private let scrimBaseOpacity: Double = 0.30
    /// 遮罩最小不透明度（拖拽到阈值时）。
    private let scrimMinOpacity: Double = 0.12

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                scrimLayer
                sheetPanel(proxy: proxy)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea()
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                if tapOutsideToDismiss {
                    dismiss()
                }
            }
            // 退场中不再接收触摸：动画播放期间不遮挡下层内容。
            .allowsHitTesting(phase == .presented || phase == .presenting)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardHeight(from: notification, containerHeight: proxy.size.height)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                updateKeyboardHeight(0)
            }
            .onAppear {
                playEntrance()
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    playEntrance()
                } else {
                    playExit()
                }
            }
        }
    }

    // MARK: - Scrim

    private var scrimLayer: some View {
        Color.black.opacity(scrimOpacity)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                guard tapOutsideToDismiss else { return }
                dismiss()
            }
            .accessibilityHidden(true)
    }

    /// 遮罩透明度：随动画进度淡入（出场）/ 渐隐（退场），拖拽时进一步衰减。
    private var scrimOpacity: Double {
        let progress = dragProgress
        return max(0, scrimBaseOpacity * Double(animationProgress) - (scrimBaseOpacity - scrimMinOpacity) * progress)
    }

    /// 当前拖拽进度（0 = 静止，1 = 到达阈值）。
    private var dragProgress: Double {
        guard dragToDismiss, dragOffset > 0 else { return 0 }
        return min(1.0, Double(dragOffset / dismissThreshold))
    }

    // MARK: - Sheet Panel

    private func sheetPanel(proxy: GeometryProxy) -> some View {
        let keyboardLift = max(0, keyboardHeight - proxy.safeAreaInsets.bottom)
        let maxHeight = max(240, proxy.size.height * 0.92 - keyboardLift)
        let resolvedHeight = min(sheetHeight ?? maxHeight, maxHeight)
        // 出/入场滑行距离盖过整个面板，保证高面板也能完全离屏。
        // Reduce Motion 下不做位移，仅靠透明度做纯淡入淡出。
        let travel = reduceMotion ? 0 : resolvedHeight + 60
        let phaseOffset: CGFloat
        switch phase {
        case .idle, .presenting, .dismissing:
            phaseOffset = travel * (1 - animationProgress)
        case .presented:
            phaseOffset = 0
        }
        let surfaceYOffset = phaseOffset + (keyboardLift > 0 ? -keyboardLift : 0) + dragOffset

        return VStack(spacing: 0) {
            if showDragBar {
                TracciSheetChrome.dragBar
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xs)
                    .gesture(dismissDragGesture)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: resolvedHeight, alignment: .top)
        .background(AppColors.backgroundGrouped)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: AppRadius.hero,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: AppRadius.hero,
                style: .continuous
            )
        )
        // 使用 drawingGroup 将阴影栅格化，避免动画过程中每帧重绘阴影
        .drawingGroup()
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: -6)
        .offset(y: surfaceYOffset)
        // 出场渐进显现、退场渐隐，避免高面板在屏幕边缘“跳一下”
        .opacity(panelOpacity)
        .tracciSheetLayoutDebug(
            name: "fullscreen-sheet",
            hostFrame: proxy.frame(in: .global),
            surfaceYOffset: surfaceYOffset,
            configuredDetent: resolvedHeight,
            safeAreaInsets: proxy.safeAreaInsets
        )
    }

    /// 面板透明度：出场时随进度渐进显现，退场时随之渐隐。
    private var panelOpacity: Double {
        if phase == .presented { return 1 }
        return Double(min(1, animationProgress * 2))
    }

    // MARK: - Drag Gesture

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard dragToDismiss else { return }
                let raw = max(0, value.translation.height)
                // 超过阈值后施加阻力，制造橡胶带手感
                if raw > dismissThreshold {
                    let excess = raw - dismissThreshold
                    dragOffset = dismissThreshold + excess * rubberBandResistance
                } else {
                    dragOffset = raw
                }
                // 越过阈值时触发一次 haptic
                if dragOffset >= dismissThreshold && !didFireThresholdHaptic {
                    didFireThresholdHaptic = true
                    AppHaptics.selection()
                }
            }
            .onEnded { value in
                guard dragToDismiss else { return }
                let flickedDown = value.velocity.height > flickDismissVelocity
                let shouldDismiss = dragOffset >= dismissThreshold
                    || flickedDown
                    || value.predictedEndTranslation.height > flickDismissPredictedTravel
                didFireThresholdHaptic = false
                if shouldDismiss {
                    dismiss()
                } else {
                    withAnimation(resetAnimation) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Animations

    /// 拖拽回弹动画：软弹簧，松手后自然归位。
    private var resetAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.35, dampingFraction: 0.90)
    }

    // MARK: - Entrance / Exit / Dismiss

    /// 出场：spring 滑入 + 遮罩淡入。Reduce Motion 下不位移，纯淡入。
    /// 首次挂载由 `onAppear` 触发；退场中途重新呈现由 `onChange` 触发。
    private func playEntrance() {
        isDismissing = false
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: TracciSheetMotion.reducedDuration)) {
                animationProgress = 1
                phase = .presented
            }
            return
        }
        withAnimation(TracciSheetMotion.entrance) {
            animationProgress = 1
            phase = .presented
            dragOffset = 0
        }
    }

    /// 退场：面板下滑渐隐、遮罩渐隐；hosting view 由 window 层在动画结束后移除。
    private func playExit() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(TracciSheetMotion.exit(reduceMotion: reduceMotion)) {
            animationProgress = 0
            phase = .dismissing
        }
    }

    /// 所有关闭入口（点遮罩 / 拖拽 / escape / 外部 binding 翻转）统一走这里：
    /// 只翻转 `isPresented`，动画与移除时机由 `onChange` 与 window 层接管。
    private func dismiss() {
        isPresented = false
    }

    private func updateKeyboardHeight(_ height: CGFloat) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            keyboardHeight = height
        }
    }

    private func updateKeyboardHeight(from notification: Notification, containerHeight: CGFloat) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        if let window = Self.activeKeyWindow {
            let frameInWindow = window.convert(frame, from: nil)
            updateKeyboardHeight(max(0, window.bounds.height - frameInWindow.minY))
        } else {
            updateKeyboardHeight(max(0, containerHeight - frame.minY))
        }
    }

    private static var activeKeyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        return windowScene?.windows.first(where: \.isKeyWindow)
    }
}

#if DEBUG
private struct TracciSheetLayoutDebugModifier: ViewModifier {
    let name: String
    let hostFrame: CGRect
    let surfaceYOffset: CGFloat
    let configuredDetent: CGFloat
    let safeAreaInsets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { surfaceProxy in
                    Color.clear
                        .task(id: debugID(surfaceProxy: surfaceProxy)) {
                            log(surfaceProxy: surfaceProxy)
                        }
                }
            }
    }

    private func debugID(surfaceProxy: GeometryProxy) -> String {
        let surfaceFrame = surfaceProxy.frame(in: .global)
        let visibleSurfaceFrame = surfaceFrame.offsetBy(dx: 0, dy: surfaceYOffset)
        return [
            rounded(hostFrame.minY),
            rounded(hostFrame.maxY),
            rounded(visibleSurfaceFrame.minY),
            rounded(visibleSurfaceFrame.maxY),
            rounded(configuredDetent),
            rounded(safeAreaInsets.bottom)
        ].joined(separator: ":")
    }

    private func log(surfaceProxy: GeometryProxy) {
        let surfaceFrame = surfaceProxy.frame(in: .global)
        let visibleSurfaceFrame = surfaceFrame.offsetBy(dx: 0, dy: surfaceYOffset)
        let contentFrame = visibleSurfaceFrame
        let delta = hostFrame.maxY - visibleSurfaceFrame.maxY
        print(
            """
            [SheetLayout] \(name) host=\(format(hostFrame)) surface=\(format(visibleSurfaceFrame)) content=\(format(contentFrame)) safeAreaBottom=\(rounded(safeAreaInsets.bottom)) detent=\(rounded(configuredDetent)) measuredContentHeight=\(rounded(contentFrame.height)) host.maxY-surface.maxY=\(rounded(delta))
            """
        )
    }

    private func format(_ rect: CGRect) -> String {
        "(x:\(rounded(rect.minX)), y:\(rounded(rect.minY)), w:\(rounded(rect.width)), h:\(rounded(rect.height)), maxY:\(rounded(rect.maxY)))"
    }

    private func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
#endif

private extension View {
    @ViewBuilder
    func tracciSheetLayoutDebug(
        name: String,
        hostFrame: CGRect,
        surfaceYOffset: CGFloat,
        configuredDetent: CGFloat,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        #if DEBUG
        modifier(
            TracciSheetLayoutDebugModifier(
                name: name,
                hostFrame: hostFrame,
                surfaceYOffset: surfaceYOffset,
                configuredDetent: configuredDetent,
                safeAreaInsets: safeAreaInsets
            )
        )
        #else
        self
        #endif
    }
}

extension View {
    /// Full-screen overlay bottom sheet.
    ///
    /// **Drag-bar ownership (avoid double chrome):**
    /// - Content already draws a drag bar (`FormSheetTopBar` sheet mode,
    ///   `TracciPickerSheetTopChrome`, `TracciDialogSheetScaffold`, etc.)
    ///   → pass `showDragBar: false`.
    /// - Content has no chrome of its own (e.g. `TripShareSheet` when
    ///   `embeddedInBottomSheet == true`) → leave `showDragBar: true` (default).
    func tracciBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        height: CGFloat? = nil,
        showDragBar: Bool = true,
        tapOutsideToDismiss: Bool = true,
        dragToDismiss: Bool = true,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        overlay {
            TracciBottomSheet(
                isPresented: isPresented,
                sheetHeight: height,
                showDragBar: showDragBar,
                tapOutsideToDismiss: tapOutsideToDismiss,
                dragToDismiss: dragToDismiss,
                content: content
            )
        }
    }
}

// MARK: - Dialog Button Style

/// 弹窗按钮的按下态反馈：轻缩放 + 透明度，与品牌 spring 一致。
struct TracciDialogButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressScale: CGFloat = 0.97
    var pressOpacity: Double = 0.90

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressScale : 1)
            .opacity(configuration.isPressed ? pressOpacity : 1)
            .animation(
                AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

extension View {
    /// 弹窗按钮标准按下态。
    func tracciDialogButtonStyle(scale: CGFloat = 0.97, opacity: Double = 0.90) -> some View {
        buttonStyle(TracciDialogButtonStyle(pressScale: scale, pressOpacity: opacity))
    }
}

// MARK: - Confirm Tone

enum TracciConfirmTone {
    case destructive
    case caution
    case neutral

    var icon: String {
        switch self {
        case .destructive: "trash"
        case .caution: "exclamationmark.triangle"
        case .neutral: "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .destructive: AppColors.danger
        case .caution: AppColors.warning
        case .neutral: AppColors.brandPrimary
        }
    }

    var iconBackground: Color {
        switch self {
        case .destructive: AppColors.dangerBackground
        case .caution: Color(hex: 0xFFFBEB)
        case .neutral: AppColors.brandPrimaryBackground
        }
    }

    var confirmColor: Color {
        switch self {
        case .destructive: AppColors.danger
        case .caution: AppColors.warning
        case .neutral: AppColors.brandPrimary
        }
    }
}

// MARK: - Dialog Scaffold

private struct TracciDialogSheetScaffold<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            TracciPickerSheetTopChrome()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AppColors.backgroundGrouped)
    }
}

// MARK: - Confirm Sheet

/// Branded confirmation sheet — icon, title, message, cancel + confirm actions.
/// Replaces system `.confirmationDialog` and destructive `.alert`.
///
/// **Async confirm:** pass `onConfirmAsync` returning `true` to dismiss after success.
/// While the async work runs, the confirm button shows loading and both actions are disabled.
/// Failures should return `false` and optionally set `errorMessage` so the sheet stays open.
struct TracciConfirmSheet: View {
    @Binding var isPresented: Bool
    var tone: TracciConfirmTone = .destructive
    var icon: String?
    var iconColor: Color?
    var iconBackground: Color?
    let title: String
    let message: String
    var cancelTitle: String = "取消"
    let confirmTitle: String
    var confirmColor: Color?
    var sheetHeight: CGFloat?
    /// Shown under the message when async confirm fails (or for external validation).
    var errorMessage: Binding<String?> = .constant(nil)
    /// Sync path: runs then dismisses immediately. Ignored when `onConfirmAsync` is set.
    var onConfirm: () -> Void = {}
    /// Async path: return `true` to dismiss, `false` to keep the sheet open (e.g. failure).
    var onConfirmAsync: (() async -> Bool)?
    var onCancel: (() -> Void)?

    @State private var isConfirming = false

    private var resolvedHeight: CGFloat {
        let base = sheetHeight ?? TracciDialogMetrics.confirmHeight(message: message, buttonRowCount: 1)
        if let error = errorMessage.wrappedValue, !error.isEmpty {
            return base + 28
        }
        return base
    }

    private var usesAsyncConfirm: Bool {
        onConfirmAsync != nil
    }

    var body: some View {
        TracciBottomSheet(
            isPresented: $isPresented,
            sheetHeight: resolvedHeight,
            showDragBar: false,
            tapOutsideToDismiss: false,
            dragToDismiss: false
        ) {
            confirmBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isPresented) { _, presented in
            if presented {
                isConfirming = false
                errorMessage.wrappedValue = nil
                AppHaptics.lightImpact()
            }
        }
    }

    private var confirmBody: some View {
        TracciDialogSheetScaffold {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: icon ?? tone.icon)
                    .font(AppFont.system(24, weight: .medium))
                    .foregroundStyle(iconColor ?? tone.iconColor)
                    .frame(width: 56, height: 56)
                    .background(iconBackground ?? tone.iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.sm) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    if let error = errorMessage.wrappedValue, !error.isEmpty {
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.danger)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }

                HStack(spacing: AppSpacing.cozy) {
                    Button {
                        guard !isConfirming else { return }
                        AppHaptics.selection()
                        isPresented = false
                        onCancel?()
                    } label: {
                        Text(cancelTitle)
                            .font(AppTypography.buttonTitleMedium)
                            .foregroundStyle(AppColors.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.tight)
                            .padding(.vertical, AppSpacing.cozy)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background(AppColors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                    .tracciDialogButtonStyle()
                    .disabled(isConfirming)
                    .opacity(isConfirming ? 0.55 : 1)

                    Button {
                        handleConfirm()
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            if isConfirming {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(confirmTitle)
                                .font(AppTypography.buttonTitle)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, AppSpacing.tight)
                        .padding(.vertical, AppSpacing.cozy)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(confirmColor ?? tone.confirmColor)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                    .tracciDialogButtonStyle()
                    .disabled(isConfirming)
                    .accessibilityLabel(isConfirming ? "\(confirmTitle)，处理中" : confirmTitle)
                }
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.bottom, TracciDialogMetrics.bottomInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func handleConfirm() {
        guard !isConfirming else { return }
        errorMessage.wrappedValue = nil

        if tone == .destructive || tone == .caution {
            AppHaptics.warning()
        } else {
            AppHaptics.mediumImpact()
        }

        if let onConfirmAsync {
            isConfirming = true
            Task {
                let shouldDismiss = await onConfirmAsync()
                isConfirming = false
                if shouldDismiss {
                    isPresented = false
                }
            }
        } else {
            onConfirm()
            isPresented = false
        }
    }
}

// MARK: - Notice Sheet

/// Single-action acknowledgment sheet for success or informational outcomes.
/// Replaces system `.alert` that only needs one confirmation button.
struct TracciNoticeSheet: View {
    @Binding var isPresented: Bool
    var icon: String = "checkmark.circle.fill"
    var iconColor: Color = AppColors.success
    var iconBackground: Color = AppColors.successBackground
    let title: String
    let message: String
    var buttonTitle: String = "好的"
    var sheetHeight: CGFloat?
    let onAcknowledge: () -> Void

    private var resolvedHeight: CGFloat {
        sheetHeight ?? TracciDialogMetrics.confirmHeight(message: message, buttonRowCount: 1)
    }

    var body: some View {
        TracciBottomSheet(
            isPresented: $isPresented,
            sheetHeight: resolvedHeight,
            showDragBar: false,
            tapOutsideToDismiss: false,
            dragToDismiss: false
        ) {
            noticeBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isPresented) { _, presented in
            if presented {
                AppHaptics.success()
            }
        }
    }

    private var noticeBody: some View {
        TracciDialogSheetScaffold {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: icon)
                    .font(AppFont.system(24, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 56, height: 56)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.sm) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    AppHaptics.lightImpact()
                    onAcknowledge()
                    isPresented = false
                } label: {
                    Text(buttonTitle)
                        .font(AppTypography.buttonTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.tight)
                        .padding(.vertical, AppSpacing.cozy)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(AppColors.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                }
                .tracciDialogButtonStyle()
            }
            .padding(.horizontal, AppSpacing.pageX)
            .padding(.bottom, TracciDialogMetrics.bottomInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

#if DEBUG
#Preview("Tracci Confirm Sheet") {
    struct PreviewHost: View {
        @State private var showConfirm = true

        var body: some View {
            Color.clear
                .tracciPageBackground()
                .overlay {
                    TracciConfirmSheet(
                        isPresented: $showConfirm,
                        tone: .caution,
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "退出登录？",
                        message: "退出后，你需要重新登录才能继续使用趣溪。",
                        confirmTitle: "退出登录",
                        confirmColor: AppColors.danger,
                        onConfirm: {}
                    )
                }
        }
    }

    return PreviewHost()
}
#endif
