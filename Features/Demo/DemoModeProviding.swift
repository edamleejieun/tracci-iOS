import Foundation
import Observation

/// Contract for ViewModels that participate in Demo Journey read-only mode.
///
/// Mutation methods should follow guard order:
///   1. `preventDemoMutation()` — block all network writes in Demo
///   2. `!isSubmitting`            — prevent concurrent submissions
///   3. Business validation        — form / state checks
@MainActor
protocol DemoModeProviding: AnyObject {
    /// When `true`, network mutations are blocked.
    var isDemoMode: Bool { get set }
}

extension DemoModeProviding {
    /// Returns `true` when the caller should short-circuit because Demo mode
    /// disallows mutations. Individual ViewModels set their own user-facing
    /// error before returning.
    func preventDemoMutation() -> Bool {
        isDemoMode
    }
}
