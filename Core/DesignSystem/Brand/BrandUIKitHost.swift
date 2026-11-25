import SwiftUI
import UIKit

/// Embeds SwiftUI brand lockup in UIKit surfaces (e.g. carrier one-tap auth SDK page).
///
/// Performance notes:
/// - Prefer **reusing** a single host via `prewarm` so `UIHostingController` + glow
///   are not created during the modal present frame.
/// - Entrance choreography runs after the host is reparented into the SDK page so the
///   page transition stays smooth while brand motion still feels intentional.
final class BrandPrimaryLockupHostView: UIView {
    private var hostingController: UIHostingController<AnyView>?
    private let showsSlogan: Bool
    private let subtitle: String?
    private var hasPlayedEntrance = false

    init(showsSlogan: Bool = true, subtitle: String? = nil) {
        self.showsSlogan = showsSlogan
        self.subtitle = subtitle
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = false
        installHostingContent()
    }

    override init(frame: CGRect) {
        self.showsSlogan = true
        self.subtitle = nil
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        installHostingContent()
    }

    required init?(coder: NSCoder) {
        self.showsSlogan = true
        self.subtitle = nil
        super.init(coder: coder)
        backgroundColor = .clear
        clipsToBounds = false
        installHostingContent()
    }

    private func installHostingContent() {
        hostingController?.view.removeFromSuperview()

        let root = AnyView(
            BrandLockupView(style: .primary, showsGlow: true, showsSlogan: showsSlogan, subtitle: subtitle)
                // Rasterize blur+glow layers so breathing does not re-blur every frame
                // during the auth-page transition.
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        hostingController = host
    }

    /// Forces SwiftUI layout so the first visible paint is cheap.
    func forceLayoutWarmup(width: CGFloat) {
        let height = BrandTokens.primaryLockupHeight(showsSlogan: showsSlogan)
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        setNeedsLayout()
        layoutIfNeeded()
        hostingController?.view.setNeedsLayout()
        hostingController?.view.layoutIfNeeded()
    }

    /// Restores identity without animation — used when reusing a settled host.
    func resetVisualState() {
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        hasPlayedEntrance = false
    }

    /// Soft editorial settle-in for the brand cluster after the SDK page is up.
    func prepareEntrance() {
        layer.removeAllAnimations()
        hasPlayedEntrance = false
        alpha = 0
        // Slight rise + soft scale — matches AppMotion milestone feel without fighting
        // the full-screen present animation.
        transform = CGAffineTransform(translationX: 0, y: 18)
            .scaledBy(x: 0.96, y: 0.96)
    }

    func playEntranceIfNeeded(reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        guard !hasPlayedEntrance else { return }
        hasPlayedEntrance = true

        if reduceMotion {
            alpha = 1
            transform = .identity
            return
        }

        // Leads the content stagger (number/CTA ~0.18+): page CA → brand → form.
        UIView.animate(
            withDuration: 0.50,
            delay: 0.06,
            usingSpringWithDamping: 0.80,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    // MARK: - Install / Prewarm

    /// Builds (or reuses) an off-screen host so present-time cost is mostly reparenting.
    static func prewarm(showsSlogan: Bool = true, subtitle: String? = nil) {
        let apply = {
            let width = UIScreen.main.bounds.width
            if let existing = BrandUIKitHostRegistry.sharedHost {
                existing.forceLayoutWarmup(width: width)
                return
            }

            guard let window = keyWindow() else { return }
            let host = BrandPrimaryLockupHostView(showsSlogan: showsSlogan, subtitle: subtitle)
            host.isUserInteractionEnabled = false
            host.accessibilityElementsHidden = true
            // Park far off-screen; still in the active window so SwiftUI can layout.
            host.frame = CGRect(
                x: -UIScreen.main.bounds.width * 2,
                y: 0,
                width: width,
                height: BrandTokens.primaryLockupHeight(showsSlogan: showsSlogan)
            )
            window.addSubview(host)
            host.forceLayoutWarmup(width: width)
            BrandUIKitHostRegistry.sharedHost = host
            BrandUIKitHostRegistry.isOffscreenPrewarm = true
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    @discardableResult
    static func install(in superView: UIView, showsSlogan: Bool = true, subtitle: String? = nil) -> BrandPrimaryLockupHostView {
        if Thread.isMainThread {
            return installOnMain(in: superView, showsSlogan: showsSlogan, subtitle: subtitle)
        }
        var created: BrandPrimaryLockupHostView!
        DispatchQueue.main.sync {
            created = installOnMain(in: superView, showsSlogan: showsSlogan, subtitle: subtitle)
        }
        return created
    }

    private static func installOnMain(in superView: UIView, showsSlogan: Bool, subtitle: String?) -> BrandPrimaryLockupHostView {
        let host: BrandPrimaryLockupHostView
        if let existing = BrandUIKitHostRegistry.sharedHost {
            existing.removeFromSuperview()
            host = existing
        } else {
            host = BrandPrimaryLockupHostView(showsSlogan: showsSlogan, subtitle: subtitle)
            BrandUIKitHostRegistry.sharedHost = host
        }

        host.isUserInteractionEnabled = false
        host.prepareEntrance()
        superView.addSubview(host)
        BrandUIKitHostRegistry.isOffscreenPrewarm = false
        BrandUIKitHostRegistry.pendingEntrance = true
        return host
    }

    static func layout(in frame: CGRect) {
        let apply = {
            guard let host = BrandUIKitHostRegistry.sharedHost else { return }
            host.frame = frame
            if BrandUIKitHostRegistry.pendingEntrance {
                BrandUIKitHostRegistry.pendingEntrance = false
                host.playEntranceIfNeeded()
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// Parks the host off-screen again so the next present reuses it without rebuild.
    static func parkOffscreenIfNeeded() {
        let apply = {
            guard let host = BrandUIKitHostRegistry.sharedHost else { return }
            guard let window = keyWindow() else {
                host.removeFromSuperview()
                return
            }
            host.resetVisualState()
            host.isUserInteractionEnabled = false
            let width = UIScreen.main.bounds.width
            host.frame = CGRect(
                x: -width * 2,
                y: 0,
                width: width,
                height: BrandTokens.primaryLockupHeight(showsSlogan: host.showsSlogan)
            )
            if host.superview !== window {
                window.addSubview(host)
            }
            BrandUIKitHostRegistry.isOffscreenPrewarm = true
            BrandUIKitHostRegistry.pendingEntrance = false
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

enum BrandUIKitHostRegistry {
    static weak var sharedHost: BrandPrimaryLockupHostView?
    static var isOffscreenPrewarm = false
    static var pendingEntrance = false
}
