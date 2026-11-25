import SwiftUI
import UIKit

extension View {
    func tracciInteractivePopGesture(
        shouldHandlePop: @escaping () -> Bool,
        onPopFinished: @escaping () -> Void
    ) -> some View {
        overlay(
            TracciInteractivePopGestureReporter(
                shouldHandlePop: shouldHandlePop,
                onPopFinished: onPopFinished
            )
            // 这层不参与命中测试：手势识别器挂在导航控制器的视图上，浮层一旦吃下触摸
            // 就会把左边缘整条内容的触摸吞掉（含左上返回键与从左侧起手的滚动）。
            .allowsHitTesting(false)
        )
    }
}

private struct TracciInteractivePopGestureReporter: UIViewControllerRepresentable {
    let shouldHandlePop: () -> Bool
    let onPopFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            shouldHandlePop: shouldHandlePop,
            onPopFinished: onPopFinished
        )
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onResolveNavigationController = { navigationController in
            context.coordinator.attach(to: navigationController)
        }
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.shouldHandlePop = shouldHandlePop
        context.coordinator.onPopFinished = onPopFinished

        DispatchQueue.main.async {
            guard let navigationController = controller.navigationController else { return }
            context.coordinator.attach(to: navigationController)
        }
        // 路径深度变化会走到这里（闭包每次渲染都重建）：按方案 A 重排接管权。
        context.coordinator.syncGestureRouting()
    }

    final class Controller: UIViewController {
        var onResolveNavigationController: ((UINavigationController) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            resolveNavigationController()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            resolveNavigationController()
        }

        private func resolveNavigationController() {
            guard let navigationController else { return }
            onResolveNavigationController?(navigationController)
        }
    }

    final class Coordinator: NSObject {
        var shouldHandlePop: () -> Bool
        var onPopFinished: () -> Void
        private weak var navigationController: UINavigationController?
        private weak var gestureHostView: UIView?
        private weak var edgePanGestureRecognizer: UIScreenEdgePanGestureRecognizer?
        private var isHandlingPop = false
        private var didReportPop = false
        private var disabledNavigationControllerID: ObjectIdentifier?

        private static var disabledNavigationControllerCounts: [ObjectIdentifier: Int] = [:]

        init(
            shouldHandlePop: @escaping () -> Bool,
            onPopFinished: @escaping () -> Void
        ) {
            self.shouldHandlePop = shouldHandlePop
            self.onPopFinished = onPopFinished
        }

        deinit {
            restoreNativeInteractivePopIfNeeded()
            detachEdgePanGesture()
        }

        func attach(to navigationController: UINavigationController) {
            if self.navigationController !== navigationController {
                restoreNativeInteractivePopIfNeeded()
                detachEdgePanGesture()
            }

            self.navigationController = navigationController
            installEdgePanGestureIfNeeded(on: navigationController.view)
            // 方案 A（2026-09-15 拍板）：接管权跟随 shouldHandlePop 走，不再无条件禁原生手势。
            syncGestureRouting()
        }

        /// 挂在导航控制器的视图上——识别器在祖先视图上依然能收到下发给内容的触摸，
        /// 系统的 `interactivePop` 自己也是这么挂的；挂在页面浮层上则会吃掉浮层下的触摸。
        private func installEdgePanGestureIfNeeded(on view: UIView) {
            guard edgePanGestureRecognizer == nil else { return }

            let recognizer = UIScreenEdgePanGestureRecognizer(
                target: self,
                action: #selector(handleInteractivePopGesture(_:))
            )
            recognizer.edges = .left
            // 导航视图上系统自己也会挂边缘手势，命名后才能把自己认领出来。
            recognizer.name = "tracci.interactivePop"
            view.addGestureRecognizer(recognizer)

            gestureHostView = view
            edgePanGestureRecognizer = recognizer
        }

        /// 识别器的 target 是自己，绝不能留在导航视图上比本对象活得久。
        private func detachEdgePanGesture() {
            guard let recognizer = edgePanGestureRecognizer else { return }
            gestureHostView?.removeGestureRecognizer(recognizer)
            edgePanGestureRecognizer = nil
            gestureHostView = nil
        }

        /// 「仅根页接管」：根页用自己的边缘手势（禁原生，防两套手势打架）；
        /// 非根页停掉自己的手势、归还原生 `interactivePop`——二级页保住系统跟手转场。
        /// 历史上这里无条件禁用整个 NavigationStack 的原生手势且不分层级，
        /// 曾让「我的」二级页失去系统侧滑返回。
        func syncGestureRouting() {
            let isRoot = shouldHandlePop()
            edgePanGestureRecognizer?.isEnabled = isRoot
            if isRoot {
                navigationController.map { disableNativeInteractivePopIfNeeded($0) }
            } else {
                restoreNativeInteractivePopIfNeeded()
            }
        }

        private func disableNativeInteractivePopIfNeeded(_ navigationController: UINavigationController) {
            let id = ObjectIdentifier(navigationController)
            guard disabledNavigationControllerID != id else { return }

            Self.disabledNavigationControllerCounts[id, default: 0] += 1
            disabledNavigationControllerID = id
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        }

        private func restoreNativeInteractivePopIfNeeded() {
            guard let id = disabledNavigationControllerID else { return }
            let remainingCount = max((Self.disabledNavigationControllerCounts[id] ?? 1) - 1, 0)

            if remainingCount == 0 {
                Self.disabledNavigationControllerCounts[id] = nil
                navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            } else {
                Self.disabledNavigationControllerCounts[id] = remainingCount
            }

            disabledNavigationControllerID = nil
        }

        @objc private func handleInteractivePopGesture(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                isHandlingPop = shouldHandlePop()
                didReportPop = false
            case .ended:
                finishIfThresholdPassed(recognizer)
            case .cancelled, .failed:
                isHandlingPop = false
                didReportPop = false
            default:
                break
            }
        }

        private func finishIfThresholdPassed(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard isHandlingPop else { return }

            let translation = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            let passedDistance = translation.x > 72 && abs(translation.x) > abs(translation.y) * 1.35
            let passedVelocity = velocity.x > 520 && abs(velocity.x) > abs(velocity.y) * 1.2

            guard passedDistance || passedVelocity else {
                isHandlingPop = false
                didReportPop = false
                return
            }

            reportPopFinished()
        }

        private func reportPopFinished() {
            guard !didReportPop else { return }
            didReportPop = true
            isHandlingPop = false
            onPopFinished()
            #if DEBUG
            print("[TabBarPath:InteractivePop] completed")
            #endif
        }
    }
}
