import Foundation

/// Lightweight local prefs for Demo Journey UX (not auth / not server state).
enum DemoJourneyPreferences {
    private static let softCoachDismissedKey = "demo.journey.softCoach.dismissed.v1"

    /// Whether the user dismissed the one-time soft coach in demo detail.
    static var hasDismissedSoftCoach: Bool {
        get { UserDefaults.standard.bool(forKey: softCoachDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: softCoachDismissedKey) }
    }

    #if DEBUG
    /// Test seam — clears coach dismissal so previews/tests can re-show it.
    static func resetSoftCoachDismissalForTesting() {
        UserDefaults.standard.removeObject(forKey: softCoachDismissedKey)
    }
    #endif
}
