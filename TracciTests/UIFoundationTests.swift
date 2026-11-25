import SwiftUI
import UIKit
import XCTest
@testable import Tracci

@MainActor
final class UIFoundationTests: XCTestCase {
    /// 侧滑组件的回归护栏：识别器一度挂在覆盖整页的浮层上，并把左边缘 32pt 的触摸全吞掉
    /// ——左上返回键的左半边、以及从左侧起手的滚动都点不动。现在它挂在导航控制器的视图上。
    func testInteractivePopGestureDoesNotSwallowLeftEdgeTouches() throws {
        let content = ScrollView {
            Text("城市内容")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 240)
        }
        .overlay(alignment: .topLeading) {
            Button("返回") {}
                .frame(width: 46, height: 46)
                .padding(.top, 60)
                .padding(.leading, 20)
        }
        .tracciInteractivePopGesture(
            shouldHandlePop: { true },
            onPopFinished: {}
        )

        let hosting = UIHostingController(rootView: content)
        let navigationController = UINavigationController(rootViewController: hosting)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        navigationController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let ownedRecognizers = navigationController.view.gestureRecognizers?.filter {
            $0.name == "tracci.interactivePop"
        }
        XCTAssertEqual(
            ownedRecognizers?.count ?? 0,
            1,
            "组件应把一个边缘手势挂到导航控制器的视图上"
        )
        XCTAssertEqual(ownedRecognizers?.first?.isEnabled, true)

        // 旧实现把识别器挂在覆盖整页的浮层上，于是浮层自己成了左 32pt 的命中目标。
        XCTAssertNil(
            Self.findViewHostingEdgePanRecognizer(in: hosting.view),
            "页面浮层不应再持有任何边缘手势"
        )

        // (30, 80) 落在左上返回按钮那一带，也正是曾经的死区。
        //
        // 想直接断言「命中了 UIButton」行不通：按钮在 ScrollView 的 `.overlay` 里，
        // SwiftUI 的命中树走 HostingScrollView，UIKit 侧 hitTest 落不到按钮包装视图上——
        // 那是命中几何的限制，不是缺陷。改成断言旧 bug 的签名：命中必须落进页面内容，
        // 且命中链上不能再有边缘手势宿主（旧实现的 EdgePanView 本身就是命中目标）。
        let hit = window.hitTest(CGPoint(x: 30, y: 80), with: nil)
        XCTAssertNotNil(hit)

        let hitChain = Self.ancestorChain(of: hit)
        XCTAssertTrue(
            hitChain.contains { $0 === hosting.view },
            "左边缘的触摸要落进页面内容里。命中链：\(hitChain.map { String(describing: type(of: $0)) })"
        )
        // 只看页面内部的命中路径：导航控制器自己的视图上也挂着系统 `interactivePop`，
        // 那是合法的祖先，不能算进来。
        let pageChain = Self.ancestorChain(of: hit).prefix { $0 !== hosting.view }
        XCTAssertFalse(
            pageChain.contains { view in
                (view.gestureRecognizers ?? []).contains { $0 is UIScreenEdgePanGestureRecognizer }
            },
            "命中链上不能再有边缘手势宿主——旧实现的 EdgePanView 就是命中目标本身"
        )
    }

    /// `view` 及其全部祖先（含自己）。
    private static func ancestorChain(of view: UIView?) -> [UIView] {
        var chain: [UIView] = []
        var current = view
        while let node = current {
            chain.append(node)
            current = node.superview
        }
        return chain
    }

    private static func superviewChain(of view: UIView) -> String {
        var chain: [String] = []
        var current: UIView? = view
        while let node = current {
            chain.append(String(describing: type(of: node)))
            current = node.superview
        }
        return chain.reversed().joined(separator: " > ")
    }

    private static func findViewHostingEdgePanRecognizer(in view: UIView) -> UIView? {
        if view.gestureRecognizers?.contains(where: { $0 is UIScreenEdgePanGestureRecognizer }) == true {
            return view
        }
        for subview in view.subviews {
            if let found = findViewHostingEdgePanRecognizer(in: subview) {
                return found
            }
        }
        return nil
    }

    func testPrimaryButtonStatePrecedenceAndAvailability() {
        XCTAssertEqual(TracciPrimaryButtonState(isEnabled: true, isLoading: false), .enabled)
        XCTAssertEqual(TracciPrimaryButtonState(isEnabled: false, isLoading: false), .disabled)
        XCTAssertEqual(TracciPrimaryButtonState(isEnabled: true, isLoading: true), .loading)
        XCTAssertEqual(TracciPrimaryButtonState(isEnabled: false, isLoading: true), .loading)
    }

    func testSelectionRowStatesExposeStableAccessibilityStatus() {
        XCTAssertEqual(TracciSelectionRowState.idle.accessibilityStatus, "")
        XCTAssertEqual(TracciSelectionRowState.selected.accessibilityStatus, "已选择")
        XCTAssertEqual(TracciSelectionRowState.loading.accessibilityStatus, "正在保存")
        XCTAssertEqual(TracciSelectionRowState.error.accessibilityStatus, "保存失败，请重试")
        XCTAssertFalse(TracciSelectionRowState.loading.allowsSelection)
        XCTAssertTrue(TracciSelectionRowState.error.allowsSelection)
    }

    func testSettingsRowAccessibilityKeepsLabelAndValueSeparate() {
        let interactive = TracciSettingsRowAccessibility(
            label: "目的地",
            value: "日本 · 京都",
            isInteractive: true
        )
        XCTAssertEqual(interactive.label, "目的地")
        XCTAssertEqual(interactive.value, "日本 · 京都")
        XCTAssertEqual(interactive.hint, "打开目的地")

        let displayOnly = TracciSettingsRowAccessibility(
            label: "创建者",
            value: "张三",
            isInteractive: false
        )
        XCTAssertEqual(displayOnly.hint, "")
    }

    func testEditorDetentPolicyPromotesLargeText() {
        XCTAssertFalse(TracciEditorSheetDetentPolicy.prefersLargeDetent(for: .large))
        XCTAssertTrue(TracciEditorSheetDetentPolicy.prefersLargeDetent(for: .xxLarge))
        XCTAssertTrue(TracciEditorSheetDetentPolicy.prefersLargeDetent(for: .accessibility5))
    }

    func testInteractiveDismissPolicyBlocksOnlyGuardedDrafts() {
        XCTAssertTrue(TracciInteractiveDismissPolicy.shouldAllowDismiss(isDisabled: false))
        XCTAssertFalse(TracciInteractiveDismissPolicy.shouldAllowDismiss(isDisabled: true))
    }

    func testSheetUIUpdateSchedulerDoesNotMutateSynchronously() async {
        let scheduled = expectation(description: "deferred sheet UI update")
        var didRun = false

        TracciSheetUIUpdateScheduler.afterCurrentUpdate {
            didRun = true
            scheduled.fulfill()
        }

        XCTAssertFalse(didRun)
        await fulfillment(of: [scheduled], timeout: 1)
        XCTAssertTrue(didRun)
    }

    func testTaskSheetDismissGestureRequiresDominantDownwardDrag() {
        XCTAssertTrue(
            TracciTaskSheetDismissGesturePolicy.isDownwardDismissAttempt(
                CGSize(width: 8, height: 72)
            )
        )
        XCTAssertFalse(
            TracciTaskSheetDismissGesturePolicy.isDownwardDismissAttempt(
                CGSize(width: 8, height: 40)
            )
        )
        XCTAssertFalse(
            TracciTaskSheetDismissGesturePolicy.isDownwardDismissAttempt(
                CGSize(width: 90, height: 72)
            )
        )
    }

    func testPickerConfirmDocksToBottomOnPushedTimePage() {
        XCTAssertFalse(TracciPickerConfirmPlacement.usesDockedBottomCTA(.sheet))
        XCTAssertTrue(TracciPickerConfirmPlacement.usesDockedBottomCTA(.pushed))
    }

    func testDateRangePickerKeepsPushedEditorOnScreenAfterConfirm() {
        XCTAssertTrue(TracciDateRangePickerDismissPolicy.shouldDismissAfterConfirm(.sheet))
        XCTAssertFalse(TracciDateRangePickerDismissPolicy.shouldDismissAfterConfirm(.pushed))
    }

    func testCalendarGridCellsHaveUniqueIdentities() {
        let calendar = TracciDateContext.calendar
        let month = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let cells = TracciCalendarFormatting.gridCells(for: month)
        let ids = cells.map(\.id)

        XCTAssertFalse(cells.isEmpty)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertGreaterThan(cells.filter { $0.date == nil }.count, 1)
    }

    func testFoundationPrimaryAndSecondaryStatesRender() {
        assertRenders(
            VStack(spacing: 8) {
                PrimaryButton(title: "默认", action: {})
                PrimaryButton(title: "载入中", isLoading: true, action: {})
                PrimaryButton(title: "不可用", isEnabled: false, action: {})
                TracciSelectionRow(title: "已选择", state: .selected, action: {})
                TracciSelectionRow(title: "失败", state: .error, action: {})
                TracciSettingsRow(label: "目的地", value: "日本 · 京都", action: {})
            }
            .padding()
            .environment(\.dynamicTypeSize, .accessibility2)
        )
    }

    private func assertRenders<V: View>(
        _ view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let renderer = ImageRenderer(
            content: view
                .frame(width: 390)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        XCTAssertNotNil(renderer.uiImage, file: file, line: line)
    }
}
