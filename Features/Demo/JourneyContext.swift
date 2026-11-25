import Foundation

/// Distinguishes a real trip workspace from a read-only Demo Journey Bundle.
/// Never encode Demo as `tripDetail(tripId: "demo-...")` or pass Demo IDs to live business APIs.
enum JourneyContext {
    case live(tripID: String)
    case demo(bundle: DemoJourneyBundle, scene: DemoJourneySceneKind)

    var isDemo: Bool {
        if case .demo = self { return true }
        return false
    }

    var isLive: Bool { !isDemo }

    var liveTripID: String? {
        if case let .live(tripID) = self { return tripID }
        return nil
    }

    var demoBundle: DemoJourneyBundle? {
        if case let .demo(bundle, _) = self { return bundle }
        return nil
    }

    var demoSceneKind: DemoJourneySceneKind? {
        if case let .demo(_, scene) = self { return scene }
        return nil
    }

    /// Active Demo scene payload when this context is Demo; otherwise `nil`.
    var demoScene: DemoJourneyScene? {
        guard case let .demo(bundle, scene) = self else { return nil }
        return bundle.scene(scene)
    }

    var capabilities: DemoJourneyCapabilities? {
        demoBundle?.capabilities
    }

    /// Returns a Demo context pointed at another scene of the same Bundle.
    func switchingDemoScene(to scene: DemoJourneySceneKind) -> JourneyContext {
        guard case let .demo(bundle, _) = self else { return self }
        return .demo(bundle: bundle, scene: scene)
    }
}

extension JourneyContext: Equatable {
    static func == (lhs: JourneyContext, rhs: JourneyContext) -> Bool {
        switch (lhs, rhs) {
        case let (.live(l), .live(r)):
            return l == r
        case let (.demo(lb, ls), .demo(rb, rs)):
            // Identity by schema/content/scene — full scene payloads are large and not Equatable.
            return lb.schemaVersion == rb.schemaVersion
                && lb.contentVersion == rb.contentVersion
                && lb.referenceDate == rb.referenceDate
                && ls == rs
        default:
            return false
        }
    }
}
