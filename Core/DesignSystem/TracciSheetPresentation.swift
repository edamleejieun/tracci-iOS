import SwiftUI
import UIKit

// MARK: - Sheet Kind

/// Standardized sheet presentation presets for Tracci.
///
/// Compact sheets use an explicit `.height` detent so the presentation matches content —
/// no empty space above the panel. `TracciSheetEdgeAttachment` pins the sheet to the
/// bottom edge on iPhone so it does not float with side/bottom insets (iOS 26 Liquid Glass).
enum TracciSheetKind: Equatable {
    /// Full-height form sheets: create trip, expense, journal, itinerary node.
    case formFull

    /// Compact system sheets for non-brand utility pickers.
    case formCompact(height: CGFloat)

    /// Branded dialogs: confirm, notice, action, choice.
    case dialog(height: CGFloat)

    /// Nested pickers opened from a form (date, time, gender).
    case subSheet(height: CGFloat)

    /// Tall nested sheets: place search, multi-step pickers.
    case subSheetFraction(CGFloat)

}

// MARK: - Configuration

struct TracciSheetPresentationConfiguration {
    let cornerRadius: CGFloat
    let background: Color
    let showsDragIndicator: Bool
}

extension TracciSheetKind {
    var configuration: TracciSheetPresentationConfiguration {
        switch self {
        case .formFull:
            TracciSheetPresentationConfiguration(
                cornerRadius: AppRadius.hero,
                background: AppColors.backgroundGrouped,
                // Branded form chrome (`FormSheetTopBar`, `TracciPickerSheetTopChrome`) draws its own drag bar.
                showsDragIndicator: false
            )
        case .formCompact:
            TracciSheetPresentationConfiguration(
                cornerRadius: AppRadius.hero,
                background: AppColors.backgroundGrouped,
                showsDragIndicator: false
            )
        case .dialog:
            TracciSheetPresentationConfiguration(
                cornerRadius: AppRadius.hero,
                background: AppColors.backgroundGrouped,
                showsDragIndicator: false
            )
        case .subSheet:
            TracciSheetPresentationConfiguration(
                cornerRadius: AppRadius.sheet,
                background: AppColors.backgroundGrouped,
                showsDragIndicator: false
            )
        case .subSheetFraction:
            TracciSheetPresentationConfiguration(
                cornerRadius: AppRadius.sheet,
                background: AppColors.backgroundGrouped,
                showsDragIndicator: true
            )
        }
    }

    var compactHeight: CGFloat? {
        switch self {
        case .formFull:
            return nil
        case .formCompact(let height), .dialog(let height), .subSheet(let height):
            return height
        case .subSheetFraction(let fraction):
            return TracciDialogMetrics.fractionHeight(fraction)
        }
    }
}

// MARK: - Edge Attachment (UIKit)

/// Pins partial-height sheets to the screen bottom on iPhone instead of the floating card layout.
private struct TracciSheetEdgeAttachment: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TracciSheetEdgeAttachmentController {
        TracciSheetEdgeAttachmentController()
    }

    func updateUIViewController(_ uiViewController: TracciSheetEdgeAttachmentController, context: Context) {
        uiViewController.attachIfNeeded()
    }
}

private final class TracciSheetEdgeAttachmentController: UIViewController {
    private weak var configuredSheet: UISheetPresentationController?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Defer one run-loop cycle so the parent sheet presentation controller
        // is fully configured before we try to attach edge-pinning.
        DispatchQueue.main.async { [weak self] in
            self?.attachIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        guard let sheet = resolveSheetPresentationController() else { return }
        guard configuredSheet !== sheet else { return }
        configuredSheet = sheet
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = false
    }

    private func resolveSheetPresentationController() -> UISheetPresentationController? {
        var candidate: UIViewController? = parent
        while let viewController = candidate {
            if let sheet = viewController.sheetPresentationController {
                return sheet
            }
            candidate = viewController.parent
        }
        return nil
    }
}

// MARK: - View Modifiers

struct TracciSheetPresentationModifier: ViewModifier {
    let kind: TracciSheetKind

    @ViewBuilder
    func body(content: Content) -> some View {
        if let height = kind.compactHeight {
            content.modifier(
                TracciCompactSheetModifier(height: height, configuration: kind.configuration)
            )
        } else {
            content.modifier(TracciFullSheetModifier(configuration: kind.configuration))
        }
    }
}

private struct TracciFullSheetModifier: ViewModifier {
    let configuration: TracciSheetPresentationConfiguration

    func body(content: Content) -> some View {
        content
            .presentationDetents([.large])
            .presentationCornerRadius(configuration.cornerRadius)
            .presentationBackground(configuration.background)
            .presentationDragIndicator(configuration.showsDragIndicator ? .visible : .hidden)
    }
}

private struct TracciCompactSheetModifier: ViewModifier {
    let height: CGFloat
    let configuration: TracciSheetPresentationConfiguration

    func body(content: Content) -> some View {
        content
            .presentationDetents([.height(height)])
            .presentationCornerRadius(configuration.cornerRadius)
            .presentationBackground(configuration.background)
            .presentationDragIndicator(configuration.showsDragIndicator ? .visible : .hidden)
            .background(TracciSheetEdgeAttachment())
    }
}

extension View {
    /// Applies a standardized Tracci sheet presentation preset.
    func tracciSheetPresentation(_ kind: TracciSheetKind) -> some View {
        modifier(TracciSheetPresentationModifier(kind: kind))
    }

    /// Full-height branded form sheet.
    func tracciFormSheet() -> some View {
        tracciSheetPresentation(.formFull)
    }

    /// Full-height form sheet that relies on the system navigation bar (no branded top chrome).
    func tracciNavigationFormSheet() -> some View {
        tracciFormSheet()
            .presentationDragIndicator(.visible)
    }

    /// Task sheet presentation — full-height branded sheet with hidden drag indicator.
    /// The content draws its own chrome (e.g. `FormSheetTopBar` in `.task` mode).
    func tracciTaskSheet() -> some View {
        presentationDetents([.large])
            .presentationCornerRadius(AppRadius.hero)
            .presentationBackground(AppColors.backgroundGrouped)
            .presentationDragIndicator(.hidden)
    }

    /// Editor sheet presentation — starts at `.medium`, promotes to `.large` when the
    /// keyboard appears or Dynamic Type grows. The editor auto-focuses its field, so the
    /// larger detent gives the field room above the keyboard.
    func tracciEditorSheet() -> some View {
        modifier(KeyboardPromoteDetentModifier())
            .presentationCornerRadius(AppRadius.sheet)
            .presentationBackground(AppColors.backgroundGrouped)
            .presentationDragIndicator(.hidden)
    }

    /// Blocks interactive (swipe) dismiss while `isDisabled` is true — used to guard
    /// against accidental data loss when a draft is dirty or a submit is in flight.
    ///
    /// The owner must surface its own confirmation dialog (e.g. via `TracciConfirmSheet`)
    /// from `onAttemptToDismiss`. This modifier blocks the swipe and reports the attempt;
    /// it does not own feature-specific confirmation state.
    func tracciInteractiveDismissDisabled(
        _ isDisabled: Bool,
        onAttemptToDismiss: @escaping () -> Void = {}
    ) -> some View {
        interactiveDismissDisabled(isDisabled)
            .background(
                TracciInteractiveDismissGuard(
                    isDisabled: isDisabled,
                    onAttemptToDismiss: onAttemptToDismiss
                )
                .frame(width: 0, height: 0)
            )
    }
}

// MARK: - Keyboard-Aware Detent Promotion

enum TracciEditorSheetDetentPolicy {
    static func prefersLargeDetent(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        switch dynamicTypeSize {
        case .xxLarge, .xxxLarge,
             .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}

/// Promotes a `.medium`/`.large` sheet to `.large` while the keyboard is visible,
/// then restores the user's prior detent when it dismisses. Large Dynamic Type stays at
/// `.large` so editor content remains usable above the keyboard.
private struct KeyboardPromoteDetentModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var keyboardVisible = false
    @State private var detent: PresentationDetent = .medium
    @State private var detentBeforeKeyboard: PresentationDetent = .medium

    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .large], selection: $detent)
            .onAppear {
                if TracciEditorSheetDetentPolicy.prefersLargeDetent(for: dynamicTypeSize) {
                    detent = .large
                }
            }
            .onChange(of: dynamicTypeSize) { _, newValue in
                guard TracciEditorSheetDetentPolicy.prefersLargeDetent(for: newValue) else { return }
                updateDetent(.large)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard !keyboardVisible else { return }
                detentBeforeKeyboard = detent
                keyboardVisible = true
                updateDetent(.large)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                guard keyboardVisible else { return }
                keyboardVisible = false
                let restoredDetent = TracciEditorSheetDetentPolicy.prefersLargeDetent(for: dynamicTypeSize)
                    ? PresentationDetent.large
                    : detentBeforeKeyboard
                updateDetent(restoredDetent)
            }
    }

    private func updateDetent(_ newValue: PresentationDetent) {
        withAnimation(AppMotion.animation(AppMotion.softSpring, reduceMotion: reduceMotion)) {
            detent = newValue
        }
    }
}

// MARK: - Interactive Dismiss Guard

enum TracciInteractiveDismissPolicy {
    static func shouldAllowDismiss(isDisabled: Bool) -> Bool {
        !isDisabled
    }
}

/// Defers presentation-adjacent UI mutations until SwiftUI has completed its current
/// sheet update. Keyboard responder changes must not run synchronously from dismissal
/// callbacks because their layout notifications can re-enter `SheetBridge`.
enum TracciSheetUIUpdateScheduler {
    @MainActor
    static func afterCurrentUpdate(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}

private struct TracciInteractiveDismissGuard: UIViewControllerRepresentable {
    let isDisabled: Bool
    let onAttemptToDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> TracciInteractiveDismissGuardController {
        TracciInteractiveDismissGuardController(coordinator: context.coordinator)
    }

    func updateUIViewController(
        _ uiViewController: TracciInteractiveDismissGuardController,
        context: Context
    ) {
        context.coordinator.update(
            isDisabled: isDisabled,
            onAttemptToDismiss: onAttemptToDismiss
        )
        uiViewController.attachIfNeeded()
    }

    static func dismantleUIViewController(
        _ uiViewController: TracciInteractiveDismissGuardController,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        private weak var presentationController: UIPresentationController?
        private weak var previousDelegate: UIAdaptivePresentationControllerDelegate?
        private var isDisabled = false
        private var onAttemptToDismiss: () -> Void = {}

        func update(isDisabled: Bool, onAttemptToDismiss: @escaping () -> Void) {
            self.isDisabled = isDisabled
            self.onAttemptToDismiss = onAttemptToDismiss
            presentationController?.presentedViewController.isModalInPresentation = isDisabled
        }

        func attach(to controller: UIPresentationController) {
            if presentationController !== controller {
                detach()
                presentationController = controller
            }
            // SwiftUI may replace the presentation delegate when its native
            // `interactiveDismissDisabled` preference changes. Re-assert the
            // observer on layout so blocked attempts still reach the feature's
            // discard-confirmation callback.
            if controller.delegate !== self {
                previousDelegate = controller.delegate
                controller.delegate = self
            }
            controller.presentedViewController.isModalInPresentation = isDisabled
        }

        func detach() {
            guard let presentationController else { return }
            presentationController.presentedViewController.isModalInPresentation = false
            if presentationController.delegate === self {
                presentationController.delegate = previousDelegate
            }
            self.presentationController = nil
            previousDelegate = nil
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            guard TracciInteractiveDismissPolicy.shouldAllowDismiss(isDisabled: isDisabled) else {
                return false
            }
            return previousDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if isDisabled {
                onAttemptToDismiss()
            } else {
                previousDelegate?.presentationControllerDidAttemptToDismiss?(presentationController)
            }
        }
    }
}

@MainActor
private final class TracciInteractiveDismissGuardController: UIViewController {
    private weak var coordinator: TracciInteractiveDismissGuard.Coordinator?

    init(coordinator: TracciInteractiveDismissGuard.Coordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        var candidate: UIViewController? = parent
        while let controller = candidate {
            if let presentationController = controller.presentationController,
               presentationController.presentedViewController === controller {
                coordinator?.attach(to: presentationController)
                return
            }
            candidate = controller.parent
        }
    }
}
