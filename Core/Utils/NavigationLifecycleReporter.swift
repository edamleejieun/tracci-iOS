import SwiftUI
import UIKit

/// Reusable UIViewControllerRepresentable that reports view controller lifecycle events
/// with correct handling of interactive swipe-back gestures.
///
/// Two callbacks:
/// - `onReappear`: Fires on every `viewDidAppear` (not just first). Use on pushed views
///   to hide the tab bar whenever this view becomes visible again (e.g., after a pop-back,
///   after a cancelled swipe-back).
/// - `onPopCompleted`: Fires early when an interactive pop transition starts.
/// - `onPopCancelled`: Fires when an interactive pop transition is cancelled.
/// - `onPopFinished`: Fires only after a pop transition completes without cancellation.
///
/// Key behaviors:
/// - `viewDidAppear` always fires `onReappear` — ensures pushed views re-hide the tab bar
///   when they re-appear after a pop from a deeper view
/// - `viewWillDisappear` + coordinator: early trigger `onPopCompleted`; if cancelled → `onReappear`
/// - `viewWillAppear` + coordinator: if an interactive child pop is cancelled, report cancellation
///
/// Tab bar visibility is derived from each tab's `NavigationPath` in `MainTabView`.
/// Use this reporter only for non–tab-bar lifecycle side effects.
struct NavigationLifecycleReporter: UIViewControllerRepresentable {
    let onReappear: () -> Void
    let onPopCompleted: () -> Void
    let onPopCancelled: () -> Void
    let onPopFinished: () -> Void

    init(
        onReappear: @escaping () -> Void,
        onPopCompleted: @escaping () -> Void = {},
        onPopCancelled: @escaping () -> Void = {},
        onPopFinished: @escaping () -> Void = {}
    ) {
        self.onReappear = onReappear
        self.onPopCompleted = onPopCompleted
        self.onPopCancelled = onPopCancelled
        self.onPopFinished = onPopFinished
    }

    func makeUIViewController(context: Context) -> LifecycleViewController {
        let vc = LifecycleViewController()
        vc.onReappear = onReappear
        vc.onPopCompleted = onPopCompleted
        vc.onPopCancelled = onPopCancelled
        vc.onPopFinished = onPopFinished
        return vc
    }

    func updateUIViewController(_ uiViewController: LifecycleViewController, context: Context) {
        uiViewController.onReappear = onReappear
        uiViewController.onPopCompleted = onPopCompleted
        uiViewController.onPopCancelled = onPopCancelled
        uiViewController.onPopFinished = onPopFinished
    }

    final class LifecycleViewController: UIViewController {
        var onReappear: (() -> Void)?
        var onPopCompleted: (() -> Void)?
        var onPopCancelled: (() -> Void)?
        var onPopFinished: (() -> Void)?

        // MARK: - Appearing

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            guard let coordinator = transitionCoordinator, coordinator.isInteractive else { return }

            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                if context.isCancelled {
                    self.onPopCancelled?()
                }
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Always fire on appear — ensures pushed views re-hide the tab bar
            // after a pop-back (e.g., draft list reappearing after popping preview).
            onReappear?()
        }

        // MARK: - Disappearing

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)

            let isBeingPopped = isMovingFromParent
            guard let coordinator = transitionCoordinator else {
                if isBeingPopped {
                    onPopFinished?()
                }
                return
            }

            let isInteractivePop = isBeingPopped && coordinator.isInteractive
            if isInteractivePop {
                onPopCompleted?()
            }

            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                if context.isCancelled {
                    if isInteractivePop {
                        self.onPopCancelled?()
                    }
                    self.onReappear?()
                    return
                }
                if isBeingPopped {
                    self.onPopFinished?()
                }
            }
        }
    }
}
