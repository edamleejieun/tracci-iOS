import Foundation

/// Schema negotiation for `GET /demo/journey`.
/// Unknown schema versions must hide the demo and fall back to the real home empty state.
enum DemoJourneySchema {
    /// Currently supported Bundle structure versions.
    static let supportedVersions: Set<Int> = [1]

    static let currentSupportedVersion = 1

    static func isSupported(_ schemaVersion: Int) -> Bool {
        supportedVersions.contains(schemaVersion)
    }
}
