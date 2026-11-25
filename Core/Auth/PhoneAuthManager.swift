import Foundation
import UIKit

#if canImport(ATAuthSDK)
import ATAuthSDK

// MARK: - Phone Auth Manager

/// Manages Alibaba Cloud PNVS (号码认证服务) SDK for one-tap phone login.
///
/// Architecture mirrors `WeChatLoginManager`: singleton, `#if canImport` conditional compilation,
/// ObjC callback → async/await bridging via `withCheckedThrowingContinuation`.
final class PhoneAuthManager: @unchecked Sendable {
    static let shared = PhoneAuthManager()

    /// Thread-safe box for a `CheckedContinuation`, preventing double-resume crashes
    /// when ObjC SDK callbacks fire more than once.
    /// Captured by closures directly instead of stored as a `self` property,
    /// avoiding the visibility bug where `self.continuation` is nil in SDK callbacks.
    private final class ContinuationBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?

        init(_ continuation: CheckedContinuation<T, Error>) {
            self.continuation = continuation
        }

        @discardableResult
        func resume(returning value: T) -> Bool {
            let c: CheckedContinuation<T, Error>?
            lock.lock()
            c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
            return c != nil
        }

        @discardableResult
        func resume(throwing error: Error) -> Bool {
            let c: CheckedContinuation<T, Error>?
            lock.lock()
            c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(throwing: error)
            return c != nil
        }

        var hasContinuation: Bool {
            lock.lock()
            defer { lock.unlock() }
            return continuation != nil
        }
    }

    private(set) var isConfigured = false

    /// Last successful `checkEnvAvailable` — avoids a carrier round-trip on every tap.
    /// Written from SDK callbacks (main) and read from async callers; timestamps only.
    nonisolated(unsafe) private var envCheckCache: (ok: Bool, at: Date)?
    private let envCheckCacheTTL: TimeInterval = 90

    /// Last successful `accelerateLoginPage` — carrier pre-fetch expires; refresh proactively.
    nonisolated(unsafe) private var accelerateSucceededAt: Date?
    private let accelerateRefreshInterval: TimeInterval = 8 * 60

    private init() {}

    // MARK: - Configure (call once in AppDelegate)

    func configure() {
        // Read from Environment Variable (Scheme → Environment Variables) first,
        // then fall back to Info.plist (Build Setting).
        let envValue = ProcessInfo.processInfo.environment["ALIYUN_PNVS_AUTH_INFO"]
        let plistValue = Bundle.main.object(forInfoDictionaryKey: "ALIYUN_PNVS_AUTH_INFO") as? String

        guard let authInfo = [envValue, plistValue].compactMap({ $0 }).first(where: { !$0.isEmpty && !$0.contains("$(") }) else {
            return
        }

        TXCommonHandler.sharedInstance().setAuthSDKInfo(authInfo) { [weak self] result in
            let code = result["resultCode"] as? String
            self?.isConfigured = (code == PNSCodeSuccess)
            #if DEBUG
            if !(self?.isConfigured ?? false) {
                print("[PhoneAuthManager] SDK auth failed: \(result)")
            }
            #endif
        }
    }

    // MARK: - Prewarm (images + brand host + carrier prefetch)

    /// Call when the auth landing appears. Keeps self-drawn art and glow, but moves
    /// their first-cost off the present frame so the page can animate more richly.
    func prepareForOneTapPresentation() async {
        guard isConfigured else { return }

        await MainActor.run {
            Self.warmImageCaches()
            BrandPrimaryLockupHostView.prewarm(subtitle: "旅行规划与记录")
        }

        async let env: Void = {
            _ = try? await self.checkEnvAvailable(force: false)
        }()
        async let accel: Void = {
            try? await self.accelerateLoginPageIfNeeded()
        }()
        _ = await (env, accel)
    }

    // MARK: - Check Environment

    /// - Parameter force: When true, always hits the SDK (e.g. after a hard failure).
    func checkEnvAvailable(force: Bool = false) async throws -> Bool {
        if !force {
            if let cached = envCheckCache,
               Date().timeIntervalSince(cached.at) < envCheckCacheTTL,
               cached.ok {
                return true
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            // Use deprecated API — functionally equivalent for one-tap login check.
            // The newer checkEnvAvailableWithAuthType:complete: doesn't bridge to Swift
            // cleanly in this SDK version.
            TXCommonHandler.sharedInstance().checkEnvAvailable { [weak self] result in
                let code = result?["resultCode"] as? String
                if code == PNSCodeSuccess {
                    self?.envCheckCache = (true, Date())
                    box.resume(returning: true)
                } else {
                    self?.envCheckCache = (false, Date())
                    box.resume(throwing: PhoneAuthError.from(resultCode: code ?? ""))
                }
            }
        }
    }

    // MARK: - Pre-accelerate Login Page

    func accelerateLoginPage(timeout: TimeInterval = 3.0) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = ContinuationBox(continuation)
            TXCommonHandler.sharedInstance().accelerateLoginPage(withTimeout: timeout) { [weak self] result in
                let code = result["resultCode"] as? String
                if code == PNSCodeSuccess {
                    self?.accelerateSucceededAt = Date()
                    box.resume(returning: ())
                } else {
                    // Pre-acceleration failure is non-fatal; don't throw
                    box.resume(returning: ())
                }
            }
        }
    }

    /// Refreshes carrier pre-fetch when missing or stale so `getLoginToken` does not
    /// block on an internal accelerate during present.
    func accelerateLoginPageIfNeeded(timeout: TimeInterval = 3.0) async throws {
        if let last = accelerateSucceededAt,
           Date().timeIntervalSince(last) < accelerateRefreshInterval {
            return
        }
        try await accelerateLoginPage(timeout: timeout)
    }

    // MARK: - Request One-Tap Login

    func requestOneTapLogin(from controller: UIViewController, timeout: TimeInterval = 5.0) async throws -> String {
        guard isConfigured else {
            throw PhoneAuthError.notConfigured
        }

        // Ensure assets are warm even if landing skipped / cold-tapped quickly.
        await MainActor.run {
            Self.warmImageCaches()
            BrandPrimaryLockupHostView.prewarm(subtitle: "旅行规划与记录")
        }
        // Best-effort refresh if pre-fetch is stale (non-blocking failure).
        try? await accelerateLoginPageIfNeeded()

        let model = buildCustomModel()

        #if DEBUG
        print("[PhoneAuthManager] requestOneTapLogin: entering withCheckedThrowingContinuation...")
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            #if DEBUG
            print("[PhoneAuthManager] Inside continuation closure, creating box...")
            #endif
            let box = ContinuationBox(continuation)
            #if DEBUG
            print("[PhoneAuthManager] Box created, calling getLoginToken...")
            #endif

            // Safety timeout is only for a missing SDK terminal callback. The user may
            // spend time reading the carrier page, so do not tie this to token timeout.
            let safetyTimeout = max(timeout + 8.0, 120.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + safetyTimeout) {
                guard box.hasContinuation else { return }
                #if DEBUG
                print("[PhoneAuthManager] Safety timeout triggered after \(safetyTimeout)s")
                #endif
                Self.setLoginButtonLoading(false)
                TXCommonHandler.sharedInstance().cancelLoginVC(animated: true) {
                    BrandPrimaryLockupHostView.parkOffscreenIfNeeded()
                }
                box.resume(throwing: PhoneAuthError.timeout)
            }

            TXCommonHandler.sharedInstance().getLoginToken(withTimeout: timeout, controller: controller, model: model) { result in
                let code = result["resultCode"] as? String ?? ""
                #if DEBUG
                print("[PhoneAuthManager] SDK callback: resultCode=\(code)")
                #endif

                switch code {
                case PNSCodeSuccess:
                    guard let token = result["token"] as? String, !token.isEmpty else {
                        #if DEBUG
                        print("[PhoneAuthManager] PNSCodeSuccess but token is empty/nil, throwing tokenFetchFailed")
                        #endif
                        Self.setLoginButtonLoading(false)
                        box.resume(throwing: PhoneAuthError.tokenFetchFailed)
                        return
                    }
                    #if DEBUG
                    print("[PhoneAuthManager] PNSCodeSuccess with token (len=\(token.count)), calling box.resume(returning:)")
                    #endif
                    let didResume = box.resume(returning: token)
                    #if DEBUG
                    print("[PhoneAuthManager] box.resume(returning:) returned, didResume=\(didResume)")
                    #endif

                case PNSCodeLoginControllerPresentSuccess:
                    // Page is up — light haptic marks the memory moment without blocking.
                    DispatchQueue.main.async {
                        AppHaptics.lightImpact()
                    }

                case PNSCodeLoginControllerClickCheckBoxBtn,
                    PNSCodeLoginControllerClickProtocol,
                    PNSCodeLoginPrivacyAlertViewClose,
                    PNSCodeLoginPrivacyAlertViewPrivacyContentClick:
                    break

                case PNSCodeLoginClickPrivacyAlertView:
                    // Privacy sheet is showing — wait for「同意并继续」before loading.
                    Self.setLoginButtonLoading(false)

                case PNSCodeLoginPrivacyAlertViewClickContinue:
                    Self.setLoginButtonLoading(true)

                case PNSCodeLoginControllerClickCancel:
                    Self.setLoginButtonLoading(false)
                    box.resume(throwing: PhoneAuthError.userCancelled)

                case PNSCodeLoginControllerClickChangeBtn:
                    Self.setLoginButtonLoading(false)
                    box.resume(throwing: PhoneAuthError.userSwitchedMethod)

                case PNSCodeLoginControllerClickLoginBtn:
                    // Always show in-button loading on tap; SDK may not report isChecked reliably.
                    Self.setLoginButtonLoading(true)
                    DispatchQueue.main.async {
                        AppHaptics.selection()
                    }

                case PNSCodeLoginControllerPresentFailed,
                    PNSCodeGetTokenFailed,
                    PNSCodeInterfaceTimeout,
                    PNSCodeInterfaceDemoted,
                    PNSCodeInterfaceLimited,
                    PNSCodeLoginControllerDeallocVC,
                    PNSCodeLoginControllerSuspendDisMissVC:
                    Self.setLoginButtonLoading(false)
                    box.resume(throwing: PhoneAuthError.from(resultCode: code))

                default:
                    // Unknown or unhandled terminal codes — resume with error to avoid
                    // hanging the continuation until the 120-second safety timeout.
                    #if DEBUG
                    print("[PhoneAuthManager] Unhandled terminal resultCode=\(code), resuming with error")
                    #endif
                    Self.setLoginButtonLoading(false)
                    box.resume(throwing: PhoneAuthError.from(resultCode: code))
                }
            }
            #if DEBUG
            print("[PhoneAuthManager] getLoginToken called, waiting for callback...")
            #endif
        }
    }

    // MARK: - Cancel Login Page

    func cancelLogin(animated: Bool = true) {
        Self.setLoginButtonLoading(false)
        Self.AuthPageContentEntrance.reset()
        TXCommonHandler.sharedInstance().cancelLoginVC(animated: animated) {
            BrandPrimaryLockupHostView.parkOffscreenIfNeeded()
        }
    }

    /// Hides the in-button loading spinner (and any legacy SDK overlay).
    func hideLoginLoading() {
        Self.setLoginButtonLoading(false)
        TXCommonHandler.sharedInstance().hideLoginLoading()
    }

    // MARK: - Custom Model (Tracci Brand)

    private func buildCustomModel() -> TXCustomModel {
        let model = TXCustomModel()

        // ── Tracci Brand Tokens ───────────────────────────────────────────
        let brandBlue       = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1.0) // #3B82F6
        let textPrimary     = UIColor(red: 0.184, green: 0.165, blue: 0.145, alpha: 1.0) // #2F2A25
        let textMuted       = UIColor(red: 0.478, green: 0.439, blue: 0.420, alpha: 1.0) // #7A746B
        let horizontalPadding: CGFloat = 28

        // ── Full-Screen Mode (no contentViewFrameBlock) ───────────────────
        model.navIsHidden = true
        model.hideNavBackItem = true
        // Match AppColors.backgroundPrimary (.systemBackground) on the landing page.
        model.backgroundColor = .systemBackground
        // Default presentDirection is bottom-up; explicit raw value for Swift bridging.
        model.presentDirection = PNSPresentationDirection(rawValue: 0)!
        // Custom CAAnimation drives the page; duration still informs SDK fallbacks.
        model.animationDuration = Self.authPageAnimationDuration
        model.entryAnimation = Self.makeAuthPageEntryAnimation()
        model.exitAnimation = Self.makeAuthPageExitAnimation()
        model.preferredStatusBarStyle = .default

        // ── Element Layout ───────────────────────────────────────────────
        // Brand cluster aligns with AuthLandingView; action cluster breathes in the middle band.

        model.logoFrameBlock = { _, superViewSize, _ in
            let layout = Self.authPageLayout(for: superViewSize.height)
            return CGRect(
                x: 0,
                y: layout.brandTop,
                width: superViewSize.width,
                height: Self.brandLockupHeight
            )
        }

        model.numberFrameBlock = { _, superViewSize, frame in
            let layout = Self.authPageLayout(for: superViewSize.height)
            var f = frame
            f.origin.y = layout.numberY
            f.origin.x = (superViewSize.width - f.width) / 2
            return f
        }

        model.loginBtnFrameBlock = { _, superViewSize, _ in
            let layout = Self.authPageLayout(for: superViewSize.height)
            return CGRect(
                x: horizontalPadding,
                y: layout.loginY,
                width: superViewSize.width - horizontalPadding * 2,
                height: 54
            )
        }

        model.changeBtnFrameBlock = { _, superViewSize, _ in
            let layout = Self.authPageLayout(for: superViewSize.height)
            return CGRect(
                x: horizontalPadding,
                y: layout.changeY,
                width: superViewSize.width - horizontalPadding * 2,
                height: 44
            )
        }

        model.privacyFrameBlock = { _, superViewSize, frame in
            let layout = Self.authPageLayout(for: superViewSize.height)
            var f = frame
            f.origin.x = horizontalPadding
            f.size.width = superViewSize.width - horizontalPadding * 2
            f.origin.y = superViewSize.height - f.size.height - layout.privacyBottomInset
            return f
        }

        // ── Brand lockup (custom view — SDK clips logoImage to a circle) ──
        model.logoIsHidden = true
        model.sloganIsHidden = true
        model.customViewBlock = Self.installAuthPageCustomViews
        model.customViewLayoutBlock = Self.layoutAuthPageCustomViews

        // ── Phone Number ──────────────────────────────────────────────────
        model.numberColor = textPrimary
        model.numberFont  = UIFont.systemFont(ofSize: 28, weight: .semibold)

        // ── Login Button ──────────────────────────────────────────────────
        model.loginBtnText = NSAttributedString(
            string: "本机号码一键登录",
            attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
        )
        model.loginBtnBgImgs = Self.cachedLoginButtonImages

        // Custom in-button spinner; SDK default is a centered page overlay.
        model.showLoginLoading = false

        // ── "Switch to other methods" Button ──────────────────────────────
        model.changeBtnIsHidden = false
        model.changeBtnTitle = NSAttributedString(
            string: "使用邮箱登录",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: brandBlue
            ]
        )

        // ── Privacy / Agreement ───────────────────────────────────────────
        model.checkBoxIsHidden           = false
        model.checkBoxIsChecked          = false
        model.checkBoxWH                 = 18
        model.checkBoxImages             = Self.cachedCheckBoxImages
        model.checkBoxVerticalCenter     = false
        model.expandAuthPageCheckedScope = true
        model.privacyPreText             = "我已阅读并同意"
        model.privacyOne   = ["《用户协议》", "https://tracci.cn/terms"]
        model.privacyTwo   = ["《隐私政策》", "https://tracci.cn/privacy"]
        model.privacyColors = [textMuted, brandBlue]
        model.privacyFont   = UIFont.systemFont(ofSize: 13)
        model.privacyLineSpaceDp = 5
        model.privacyAlignment   = .natural

        // ── Secondary Privacy Bottom Sheet ────────────────────────────────
        let alertHorizontalPadding: CGFloat = 24
        let alertBottomInset: CGFloat = 28

        model.privacyAlertIsNeedShow = true
        model.privacyAlertIsNeedAutoLogin = true
        model.privacyAlertTitleContent = "登录前请先阅读并同意"
        model.privacyAlertTitleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        model.privacyAlertTitleColor = textPrimary
        model.privacyAlertTitleAlignment = .center
        model.privacyAlertBackgroundColor = .white
        model.privacyAlertCornerRadiusArray = [
            NSNumber(value: 24), NSNumber(value: 0),
            NSNumber(value: 0), NSNumber(value: 24)
        ]
        model.privacyAlertBtnContent = "同意并继续"
        model.privacyAlertBtnCornerRadius = 16
        model.privacyAlertBtnBackgroundImages = Self.cachedPrivacyAlertButtonImages
        model.privacyAlertButtonTextColors = [UIColor.white, UIColor.white]
        model.privacyAlertButtonFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
        model.privacyAlertContentFont = UIFont.systemFont(ofSize: 14)
        model.privacyAlertContentColors = [textMuted, brandBlue]
        model.privacyAlertContentAlignment = .natural
        model.privacyAlertLineSpaceDp = 5
        model.privacyAlertMaskColor = UIColor.black
        model.privacyAlertMaskAlpha = 0.45
        model.privacyAlertCloseButtonIsNeedShow = false
        model.tapPrivacyAlertMaskCloseAlert = true
        // Secondary consent sheet motion (sheet + dimming mask).
        model.privacyAlertAnimationDuration = 0.38
        model.privacyAlertEntryAnimation = Self.makePrivacyAlertEntryAnimation()
        model.privacyAlertExitAnimation = Self.makePrivacyAlertExitAnimation()
        model.privacyAlertMaskEntryAnimation = Self.makePrivacyAlertMaskEntryAnimation()
        model.privacyAlertMaskExitAnimation = Self.makePrivacyAlertMaskExitAnimation()

        // Unchecked-consent nudge when user taps login too early.
        model.privacyAnimation = Self.makePrivacyNudgeAnimation()
        model.checkboxAnimation = Self.makeCheckboxNudgeAnimation()

        model.privacyAlertFrameBlock = { _, superViewSize, _ in
            let width = superViewSize.width
            let height: CGFloat = 272
            return CGRect(x: 0, y: superViewSize.height - height, width: width, height: height)
        }

        model.privacyAlertTitleFrameBlock = { _, superViewSize, _ in
            CGRect(
                x: alertHorizontalPadding,
                y: 24,
                width: superViewSize.width - alertHorizontalPadding * 2,
                height: 28
            )
        }

        model.privacyAlertPrivacyContentFrameBlock = { _, superViewSize, _ in
            CGRect(
                x: alertHorizontalPadding,
                y: 60,
                width: superViewSize.width - alertHorizontalPadding * 2,
                height: 96
            )
        }

        model.privacyAlertButtonFrameBlock = { _, superViewSize, _ in
            CGRect(
                x: alertHorizontalPadding,
                y: superViewSize.height - alertBottomInset - 54,
                width: superViewSize.width - alertHorizontalPadding * 2,
                height: 54
            )
        }

        return model
    }

    private static let brandLockupHeight: CGFloat = BrandTokens.primaryLockupHeight(showsSlogan: true)

    /// Vertical metrics for the SDK auth page, aligned with `AuthLandingView` brand spacing.
    private struct AuthPageLayout {
        let brandTop: CGFloat
        let numberY: CGFloat
        let loginY: CGFloat
        let changeY: CGFloat
        let privacyBottomInset: CGFloat
    }

    private static func authPageLayout(for screenHeight: CGFloat) -> AuthPageLayout {
        // AuthLandingView: safe area + 72pt top padding before the logo card.
        let safeTop: CGFloat = screenHeight >= 844 ? 59 : (screenHeight >= 812 ? 47 : 20)
        let brandTop = safeTop + 72

        let privacyBottomInset: CGFloat = 40
        let privacyReservedHeight: CGFloat = 72
        let contentTop = brandTop + brandLockupHeight + 28
        let contentBottom = screenHeight - privacyBottomInset - privacyReservedHeight
        let availableHeight = max(contentBottom - contentTop, 200)

        let numberY = contentTop + availableHeight * 0.24
        let loginY = numberY + 36 + 36
        let changeY = loginY + 54 + 20

        return AuthPageLayout(
            brandTop: brandTop,
            numberY: numberY,
            loginY: loginY,
            changeY: changeY,
            privacyBottomInset: privacyBottomInset
        )
    }

    private static let loginSpinnerSize: CGFloat = 22
    private static let loginSpinnerTrailingInset: CGFloat = 22

    private enum AuthPageCustomViewTag {
        static let loginLoadingBackground = 9_003
        static let loginLoadingTitle = 9_004
        static let loginSpinner = 9_005
    }

    /// Lighter brand blue shown while login is in progress (#93C5FD).
    private static let loginButtonLoadingColor = UIColor(red: 0.576, green: 0.773, blue: 0.992, alpha: 1.0)

    private enum AuthPageCustomViews {
        /// Sits above the SDK login button so the spinner is actually visible.
        static weak var loginButtonOverlay: UIView?
        static var lastLoginFrame: CGRect = .zero
    }

    /// Staggered editorial entrance for SDK-owned content (number / CTA / switch / privacy).
    /// Brand lockup has its own host choreography; this only targets carrier views.
    private enum AuthPageContentEntrance {
        static weak var superView: UIView?
        static var didPrepare = false
        static var didPlay = false
        static var numberFrame: CGRect = .zero
        static var loginFrame: CGRect = .zero
        static var changeFrame: CGRect = .zero
        static var privacyFrame: CGRect = .zero

        static func reset() {
            didPrepare = false
            didPlay = false
            superView = nil
            numberFrame = .zero
            loginFrame = .zero
            changeFrame = .zero
            privacyFrame = .zero
        }

        static func noteLayout(
            superView: UIView?,
            numberFrame: CGRect,
            loginFrame: CGRect,
            changeFrame: CGRect,
            privacyFrame: CGRect
        ) {
            self.superView = superView
            self.numberFrame = numberFrame
            self.loginFrame = loginFrame
            self.changeFrame = changeFrame
            self.privacyFrame = privacyFrame

            guard let superView, !didPlay else { return }

            // Hide content as soon as SDK frames resolve so the page entry doesn't
            // flash a fully-settled form before the stagger runs.
            let views = resolvedViews(in: superView)
            guard !views.isEmpty else { return }

            if !didPrepare {
                for view in views {
                    view.layer.removeAllAnimations()
                    view.alpha = 0
                    view.transform = CGAffineTransform(translationX: 0, y: 12)
                        .scaledBy(x: 0.98, y: 0.98)
                }
                didPrepare = true
            }

            schedulePlayIfNeeded()
        }

        private static func schedulePlayIfNeeded() {
            guard didPrepare, !didPlay else { return }

            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            // After page present (~0.42) and brand settle start (~0.06), content follows.
            let baseDelay: TimeInterval = reduceMotion ? 0 : 0.18
            let step: TimeInterval = reduceMotion ? 0 : 0.06

            // Mark played only once we have targets, so empty first layouts can retry.
            DispatchQueue.main.async {
                guard !AuthPageContentEntrance.didPlay,
                      let superView = AuthPageContentEntrance.superView else { return }
                let ordered = resolvedViews(in: superView)
                guard !ordered.isEmpty else { return }

                AuthPageContentEntrance.didPlay = true

                if reduceMotion {
                    for view in ordered {
                        view.alpha = 1
                        view.transform = .identity
                    }
                    return
                }

                for (index, view) in ordered.enumerated() {
                    // Re-assert start state in case SDK re-laid out between passes.
                    if view.alpha > 0.95 {
                        view.alpha = 0
                        view.transform = CGAffineTransform(translationX: 0, y: 12)
                            .scaledBy(x: 0.98, y: 0.98)
                    }
                    UIView.animate(
                        withDuration: 0.46,
                        delay: baseDelay + step * Double(index),
                        usingSpringWithDamping: 0.86,
                        initialSpringVelocity: 0.28,
                        options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
                    ) {
                        view.alpha = 1
                        view.transform = .identity
                    }
                }
            }
        }

        private static func resolvedViews(in superView: UIView) -> [UIView] {
            var result: [UIView] = []
            let frames = [numberFrame, loginFrame, changeFrame, privacyFrame]
            for frame in frames {
                guard !frame.isEmpty,
                      let view = findSDKView(in: superView, expectedFrame: frame),
                      !result.contains(where: { $0 === view }) else { continue }
                result.append(view)
            }
            return result
        }
    }

    private static func installAuthPageCustomViews(_ superView: UIView) {
        AuthPageContentEntrance.reset()
        AuthPageContentEntrance.superView = superView
        installBrandLockupView(superView)
        installLoginButtonSpinner(superView)
    }

    private static func layoutAuthPageCustomViews(
        screenSize: CGSize,
        contentViewFrame: CGRect,
        navFrame: CGRect,
        titleBarFrame: CGRect,
        logoFrame: CGRect,
        sloganFrame: CGRect,
        numberFrame: CGRect,
        loginFrame: CGRect,
        changeBtnFrame: CGRect,
        privacyFrame: CGRect
    ) {
        layoutBrandLockupView(
            screenSize: screenSize,
            contentViewFrame: contentViewFrame,
            navFrame: navFrame,
            titleBarFrame: titleBarFrame,
            logoFrame: logoFrame,
            sloganFrame: sloganFrame,
            numberFrame: numberFrame,
            loginFrame: loginFrame,
            changeBtnFrame: changeBtnFrame,
            privacyFrame: privacyFrame
        )
        layoutLoginButtonSpinner(loginFrame: loginFrame)

        let hostSuperView = BrandUIKitHostRegistry.sharedHost?.superview
            ?? AuthPageCustomViews.loginButtonOverlay?.superview
        AuthPageContentEntrance.noteLayout(
            superView: hostSuperView,
            numberFrame: numberFrame,
            loginFrame: loginFrame,
            changeFrame: changeBtnFrame,
            privacyFrame: privacyFrame
        )
    }

    /// Frame-proximity match for SDK-owned controls (number label, login, change, privacy).
    private static func findSDKView(in superView: UIView, expectedFrame: CGRect) -> UIView? {
        guard !expectedFrame.isEmpty else { return nil }

        var best: UIView?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for candidate in superView.subviews {
            if candidate === AuthPageCustomViews.loginButtonOverlay
                || candidate === BrandUIKitHostRegistry.sharedHost {
                continue
            }
            // Skip full-bleed backgrounds.
            if candidate.bounds.width >= superView.bounds.width - 2,
               candidate.bounds.height >= superView.bounds.height - 2 {
                continue
            }

            let frame = candidate.frame
            let widthDelta = abs(frame.width - expectedFrame.width)
            let heightDelta = abs(frame.height - expectedFrame.height)
            let midYDelta = abs(frame.midY - expectedFrame.midY)
            let midXDelta = abs(frame.midX - expectedFrame.midX)

            // Loose match: vertical band + comparable size.
            guard midYDelta < 14, heightDelta < 20 else { continue }
            // Number can be narrower; privacy/login should be close in width.
            let widthLimit: CGFloat = expectedFrame.height > 40 ? 24 : max(expectedFrame.width * 0.45, 40)
            guard widthDelta < widthLimit else { continue }

            let score = midYDelta * 2 + midXDelta * 0.5 + heightDelta + widthDelta * 0.25
            if score < bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    private static func installLoginButtonSpinner(_ superView: UIView) {
        if Thread.isMainThread {
            installLoginButtonSpinnerOnMain(superView)
        } else {
            DispatchQueue.main.async { installLoginButtonSpinnerOnMain(superView) }
        }
    }

    private static func installLoginButtonSpinnerOnMain(_ superView: UIView) {
        AuthPageCustomViews.loginButtonOverlay?.removeFromSuperview()

        let overlay = UIView()
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        overlay.layer.zPosition = 1_000
        overlay.isHidden = true

        let background = UIView()
        background.tag = AuthPageCustomViewTag.loginLoadingBackground
        background.backgroundColor = loginButtonLoadingColor
        background.layer.cornerRadius = 16
        background.layer.cornerCurve = .continuous
        overlay.addSubview(background)

        let titleLabel = UILabel()
        titleLabel.tag = AuthPageCustomViewTag.loginLoadingTitle
        titleLabel.text = "本机号码一键登录"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        overlay.addSubview(titleLabel)

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.tag = AuthPageCustomViewTag.loginSpinner
        spinner.color = .white
        spinner.isUserInteractionEnabled = false
        overlay.addSubview(spinner)

        superView.addSubview(overlay)
        AuthPageCustomViews.loginButtonOverlay = overlay
    }

    private static func layoutLoginButtonSpinner(loginFrame: CGRect) {
        AuthPageCustomViews.lastLoginFrame = loginFrame

        let apply = {
            guard let overlay = AuthPageCustomViews.loginButtonOverlay,
                  let superView = overlay.superview else { return }

            overlay.frame = loginFrame
            let bounds = overlay.bounds

            overlay.viewWithTag(AuthPageCustomViewTag.loginLoadingBackground)?.frame = bounds
            overlay.viewWithTag(AuthPageCustomViewTag.loginLoadingTitle)?.frame = bounds

            guard let spinner = overlay.viewWithTag(AuthPageCustomViewTag.loginSpinner) as? UIActivityIndicatorView else {
                return
            }
            spinner.frame = CGRect(
                x: bounds.width - loginSpinnerTrailingInset - loginSpinnerSize,
                y: (bounds.height - loginSpinnerSize) / 2,
                width: loginSpinnerSize,
                height: loginSpinnerSize
            )

            if let loginButton = findSDKLoginButton(in: superView, expectedFrame: loginFrame) {
                superView.insertSubview(overlay, aboveSubview: loginButton)
            } else {
                superView.bringSubviewToFront(overlay)
            }
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async { apply() }
        }
    }

    private static func setSDKLoginButtonEnabled(_ isEnabled: Bool) {
        guard let overlay = AuthPageCustomViews.loginButtonOverlay,
              let superView = overlay.superview,
              !AuthPageCustomViews.lastLoginFrame.isEmpty,
              let loginButton = findSDKLoginButton(in: superView, expectedFrame: AuthPageCustomViews.lastLoginFrame) else {
            return
        }

        loginButton.isUserInteractionEnabled = isEnabled
        (loginButton as? UIButton)?.isEnabled = isEnabled
    }

    /// Locates the SDK-managed login button so the spinner overlay can sit directly on top.
    private static func findSDKLoginButton(in superView: UIView, expectedFrame: CGRect) -> UIView? {
        findSDKView(in: superView, expectedFrame: expectedFrame)
    }

    private static func ensureLoginButtonSpinnerLayout() {
        guard AuthPageCustomViews.lastLoginFrame.isEmpty,
              let overlay = AuthPageCustomViews.loginButtonOverlay,
              let superView = overlay.superview else { return }

        let metrics = authPageLayout(for: superView.bounds.height)
        let horizontalPadding: CGFloat = 28
        let frame = CGRect(
            x: horizontalPadding,
            y: metrics.loginY,
            width: superView.bounds.width - horizontalPadding * 2,
            height: 54
        )
        layoutLoginButtonSpinner(loginFrame: frame)
    }

    private static func setLoginButtonLoading(_ isLoading: Bool) {
        let apply = {
            ensureLoginButtonSpinnerLayout()

            if !AuthPageCustomViews.lastLoginFrame.isEmpty {
                layoutLoginButtonSpinner(loginFrame: AuthPageCustomViews.lastLoginFrame)
            }

            guard let overlay = AuthPageCustomViews.loginButtonOverlay,
                  let spinner = overlay.viewWithTag(AuthPageCustomViewTag.loginSpinner) as? UIActivityIndicatorView else {
                return
            }

            setSDKLoginButtonEnabled(!isLoading)

            if isLoading {
                overlay.isHidden = false
                overlay.isUserInteractionEnabled = true
                spinner.startAnimating()
                overlay.superview?.bringSubviewToFront(overlay)
            } else {
                spinner.stopAnimating()
                overlay.isHidden = true
                overlay.isUserInteractionEnabled = false
            }
        }

        // Defer to next run loop so we layer above the SDK login button after it updates.
        DispatchQueue.main.async {
            apply()
            guard isLoading, !AuthPageCustomViews.lastLoginFrame.isEmpty else { return }
            DispatchQueue.main.async {
                layoutLoginButtonSpinner(loginFrame: AuthPageCustomViews.lastLoginFrame)
            }
        }
    }

    /// SwiftUI brand lockup via UIHostingController — matches `AuthLandingView.brandSection` without slogan.
    private static func installBrandLockupView(_ superView: UIView) {
        _ = BrandPrimaryLockupHostView.install(in: superView, subtitle: "旅行规划与记录")
    }

    private static func layoutBrandLockupView(
        screenSize: CGSize,
        contentViewFrame: CGRect,
        navFrame: CGRect,
        titleBarFrame: CGRect,
        logoFrame: CGRect,
        sloganFrame: CGRect,
        numberFrame: CGRect,
        loginFrame: CGRect,
        changeBtnFrame: CGRect,
        privacyFrame: CGRect
    ) {
        BrandPrimaryLockupHostView.layout(in: logoFrame)
    }

    // MARK: - Auth Page Motion (CAAnimation for ATAuthSDK)

    /// Slightly longer than SDK default (0.25) so the editorial rise can read clearly
    /// without feeling sluggish. Content brand settle follows ~80ms later.
    private static let authPageAnimationDuration: CGFloat = 0.42

    /// Full-screen present: soft rise + fade + micro-scale (Creek Editorial).
    /// Uses independent key paths so scale and translation compose cleanly.
    private static func makeAuthPageEntryAnimation() -> CAAnimation {
        let duration = CFTimeInterval(authPageAnimationDuration)
        let group = CAAnimationGroup()

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        opacity.duration = duration * 0.78
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 36
        rise.toValue = 0
        rise.duration = duration
        // Ease-out curve with a gentle settle (control points ≈ cubic-bezier(0.2, 0.9, 0.2, 1)).
        rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.985
        scale.toValue = 1.0
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)

        group.animations = [opacity, rise, scale]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        return group
    }

    private static func makeAuthPageExitAnimation() -> CAAnimation {
        let duration: CFTimeInterval = 0.30
        let group = CAAnimationGroup()

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1
        opacity.toValue = 0
        opacity.duration = duration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let sink = CABasicAnimation(keyPath: "transform.translation.y")
        sink.fromValue = 0
        sink.toValue = 22
        sink.duration = duration
        sink.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.7, 0.2)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.99
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)

        group.animations = [opacity, sink, scale]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        return group
    }

    // MARK: - Consent nudge + privacy alert motion

    /// Gentle horizontal shake for the privacy row when login is tapped without consent.
    private static func makePrivacyNudgeAnimation() -> CAAnimation {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -7, 7, -5, 5, -2, 2, 0]
        shake.keyTimes = [0, 0.12, 0.28, 0.44, 0.6, 0.76, 0.9, 1]
        shake.duration = 0.42
        shake.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return shake
    }

    /// Soft pulse on the checkbox so the missing consent is easy to notice.
    private static func makeCheckboxNudgeAnimation() -> CAAnimation {
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.22, 0.94, 1.08, 1]
        pulse.keyTimes = [0, 0.22, 0.48, 0.72, 1]
        pulse.duration = 0.4
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return pulse
    }

    private static func makePrivacyAlertEntryAnimation() -> CAAnimation {
        let duration: CFTimeInterval = 0.38
        let group = CAAnimationGroup()

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        opacity.duration = duration * 0.7
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 40
        rise.toValue = 0
        rise.duration = duration
        rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.22, 1.0)

        group.animations = [opacity, rise]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        return group
    }

    private static func makePrivacyAlertExitAnimation() -> CAAnimation {
        let duration: CFTimeInterval = 0.26
        let group = CAAnimationGroup()

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1
        opacity.toValue = 0
        opacity.duration = duration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let sink = CABasicAnimation(keyPath: "transform.translation.y")
        sink.fromValue = 0
        sink.toValue = 28
        sink.duration = duration
        sink.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.7, 0.2)

        group.animations = [opacity, sink]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        return group
    }

    private static func makePrivacyAlertMaskEntryAnimation() -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.28
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        return fade
    }

    private static func makePrivacyAlertMaskExitAnimation() -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        return fade
    }

    // MARK: - Cached Self-Drawn Images

    /// Touch image caches on the main actor so first present never hits UIGraphics.
    private static func warmImageCaches() {
        _ = cachedLoginButtonImages
        _ = cachedCheckBoxImages
        _ = cachedPrivacyAlertButtonImages
    }

    private static let cachedLoginButtonImages: [UIImage] = makeLoginButtonImages()
    private static let cachedCheckBoxImages: [UIImage] = makeCheckBoxImages()
    private static let cachedPrivacyAlertButtonImages: [UIImage] = makePrivacyAlertButtonImages()

    /// Generates programmatic button background images aligned with `PrimaryButton`.
    /// Disabled state keeps full brand blue — SDK shows "disabled" when checkbox is
    /// unchecked, but we still want a confident CTA; the privacy sheet handles consent.
    private static func makeLoginButtonImages() -> [UIImage] {
        let brandBlue = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1.0)
        let highlightedBlue = UIColor(red: 0.180, green: 0.420, blue: 0.880, alpha: 1.0)
        return makeRoundedButtonImages(
            normal: brandBlue,
            disabled: loginButtonLoadingColor,
            highlighted: highlightedBlue
        )
    }

    /// Checkbox icons visible on white background (matches `AuthLegalConsentRow`).
    private static func makeCheckBoxImages() -> [UIImage] {
        let uncheckedStroke = UIColor(red: 0.77, green: 0.73, blue: 0.71, alpha: 1.0)
        let brandBlue = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1.0)
        let size = CGSize(width: 20, height: 20)

        let unchecked = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let path = UIBezierPath(ovalIn: rect)
            uncheckedStroke.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let checked = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let circle = UIBezierPath(ovalIn: rect)
            brandBlue.setFill()
            circle.fill()

            let check = UIBezierPath()
            check.move(to: CGPoint(x: 5.5, y: 10.2))
            check.addLine(to: CGPoint(x: 8.8, y: 13.5))
            check.addLine(to: CGPoint(x: 14.5, y: 7.0))
            UIColor.white.setStroke()
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        }

        return [unchecked, checked]
    }

    private static func makePrivacyAlertButtonImages() -> [UIImage] {
        let brandBlue = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1.0)
        let highlightedBlue = UIColor(red: 0.180, green: 0.420, blue: 0.880, alpha: 1.0)

        func image(with color: UIColor) -> UIImage {
            let size = CGSize(width: 44, height: 54)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { _ in
                let path = UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerRadius: 16
                )
                color.setFill()
                path.fill()
            }
            return img.resizableImage(
                withCapInsets: UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22),
                resizingMode: .stretch
            )
        }

        return [image(with: brandBlue), image(with: highlightedBlue)]
    }

    private static func makeRoundedButtonImages(
        normal: UIColor,
        disabled: UIColor,
        highlighted: UIColor
    ) -> [UIImage] {
        func image(with color: UIColor) -> UIImage {
            let size = CGSize(width: 44, height: 54)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { _ in
                let path = UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerRadius: 16
                )
                color.setFill()
                path.fill()
            }
            return img.resizableImage(
                withCapInsets: UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22),
                resizingMode: .stretch
            )
        }

        return [image(with: normal), image(with: disabled), image(with: highlighted)]
    }
}

// MARK: - Phone Auth Error

enum PhoneAuthError: LocalizedError {
    case sdkNotIntegrated
    case notConfigured
    case noSIMCard
    case noCellularNetwork
    case userCancelled
    case userSwitchedMethod
    case tokenFetchFailed
    case timeout
    case carrierMaintenance
    case sdkError(String?)

    var errorDescription: String? {
        switch self {
        case .sdkNotIntegrated:
            return "请先集成号码认证 SDK"
        case .notConfigured:
            return "号码认证服务尚未配置"
        case .noSIMCard:
            return "请插入 SIM 卡后重试"
        case .noCellularNetwork:
            return "请开启蜂窝数据网络后使用本机号码登录"
        case .userCancelled:
            return nil // Silent — no toast needed
        case .userSwitchedMethod:
            return nil // Silent — handled by switching to email form
        case .tokenFetchFailed:
            return "一键登录失败，请使用邮箱登录"
        case .timeout:
            return "登录超时，请稍后重试"
        case .carrierMaintenance:
            return "运营商服务维护中，请使用邮箱登录"
        case .sdkError:
            return "号码认证失败，请使用邮箱登录"
        }
    }

    static func from(resultCode: String) -> PhoneAuthError {
        switch resultCode {
        case PNSCodeNoSIMCard:
            return .noSIMCard
        case PNSCodeNoCellularNetwork:
            return .noCellularNetwork
        case PNSCodeInterfaceDemoted, PNSCodeInterfaceLimited:
            return .carrierMaintenance
        case PNSCodeInterfaceTimeout:
            return .timeout
        case PNSCodeGetTokenFailed, PNSCodeGetMaskPhoneFailed:
            return .tokenFetchFailed
        default:
            return .sdkError(resultCode)
        }
    }
}

#else

// MARK: - Stub (SDK not integrated)

final class PhoneAuthManager: @unchecked Sendable {
    static let shared = PhoneAuthManager()

    var isConfigured: Bool { false }

    private init() {}

    func configure() {}

    func prepareForOneTapPresentation() async {}

    func checkEnvAvailable(force: Bool = false) async throws -> Bool {
        throw PhoneAuthError.sdkNotIntegrated
    }

    func accelerateLoginPage(timeout: TimeInterval = 3.0) async throws {
        throw PhoneAuthError.sdkNotIntegrated
    }

    func accelerateLoginPageIfNeeded(timeout: TimeInterval = 3.0) async throws {
        throw PhoneAuthError.sdkNotIntegrated
    }

    func requestOneTapLogin(from controller: UIViewController, timeout: TimeInterval = 5.0) async throws -> String {
        throw PhoneAuthError.sdkNotIntegrated
    }

    func cancelLogin(animated: Bool = true) {}

    func hideLoginLoading() {}
}

enum PhoneAuthError: LocalizedError {
    case sdkNotIntegrated
    case notConfigured
    case noSIMCard
    case noCellularNetwork
    case userCancelled
    case userSwitchedMethod
    case tokenFetchFailed
    case timeout
    case carrierMaintenance
    case sdkError(String?)

    var errorDescription: String? {
        switch self {
        case .sdkNotIntegrated:
            return "号码认证 SDK 未集成"
        default:
            return "号码认证服务不可用"
        }
    }
}

#endif
