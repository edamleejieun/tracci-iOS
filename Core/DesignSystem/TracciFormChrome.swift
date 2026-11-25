import SwiftUI
import UIKit

// MARK: - Section Stagger

extension View {
    /// Staggered entry for form sections — Tier 1 milestone forms.
    func tracciFormSectionAppear(index: Int) -> some View {
        fadeSlideIn(index: index, offset: AppMotion.fadeSlideOffset, animation: AppMotion.enter)
    }

    /// Dismisses the current keyboard when a form tap lands outside its active input.
    ///
    /// The recognizer checks the tap against the actual first-responder frame and only
    /// resigns that same responder on the next main-loop turn. This preserves first
    /// focus and field-to-field focus changes while still handling blank areas and
    /// non-text controls.
    func tracciDismissKeyboardOnBlankTap() -> some View {
        background {
            KeyboardDismissBlankTapInstaller()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Blank-area keyboard dismiss

private struct KeyboardDismissBlankTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        uiView.coordinator = context.coordinator
    }

    static func dismantleUIView(_ uiView: InstallerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var window: UIWindow?
        private weak var recognizer: KeyboardDismissBlankTapRecognizer?

        func attach(to window: UIWindow?) {
            guard let window else {
                detach()
                return
            }
            guard self.window !== window else { return }

            detach()

            let recognizer: KeyboardDismissBlankTapRecognizer
            if let installedRecognizer = window.gestureRecognizers?
                .compactMap({ $0 as? KeyboardDismissBlankTapRecognizer })
                .first {
                recognizer = installedRecognizer
            } else {
                recognizer = KeyboardDismissBlankTapRecognizer(window: window)
                window.addGestureRecognizer(recognizer)
            }

            recognizer.registrationCount += 1
            self.window = window
            self.recognizer = recognizer
        }

        func detach() {
            guard let recognizer else {
                window = nil
                return
            }

            recognizer.registrationCount = max(0, recognizer.registrationCount - 1)
            if recognizer.registrationCount == 0 {
                window?.removeGestureRecognizer(recognizer)
            }
            self.recognizer = nil
            window = nil
        }
    }
}

@MainActor
private final class KeyboardDismissBlankTapRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    weak var installedWindow: UIWindow?
    var registrationCount = 0

    init(window: UIWindow) {
        installedWindow = window
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handleTap))
        cancelsTouchesInView = false
        delegate = self
    }

    @objc private func handleTap() {
        guard state == .ended,
              let window = installedWindow,
              let responder = window.tracciFirstResponderView else {
            return
        }

        let tapLocation = location(in: window)
        let responderLocation = responder.convert(tapLocation, from: window)
        let protectedBounds = responder.bounds.insetBy(dx: -8, dy: -8)
        guard !protectedBounds.contains(responderLocation) else { return }

        DispatchQueue.main.async { [weak responder] in
            guard responder?.isFirstResponder == true else { return }
            responder?.resignFirstResponder()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        installedWindow?.tracciFirstResponderView != nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private extension UIView {
    var tracciFirstResponderView: UIView? {
        if isFirstResponder {
            return self
        }

        for subview in subviews {
            if let responder = subview.tracciFirstResponderView {
                return responder
            }
        }
        return nil
    }
}

// MARK: - Save Success Feedback

enum TracciFormSaveFeedback {
    static let successDisplayNanoseconds: UInt64 = 500_000_000

    @MainActor
    static func celebrateBeforeDismiss(
        showSaveSuccess: Binding<Bool>,
        dismiss: @escaping () -> Void
    ) async {
        showSaveSuccess.wrappedValue = true
        AppHaptics.success()
        try? await Task.sleep(nanoseconds: successDisplayNanoseconds)
        dismiss()
    }
}
