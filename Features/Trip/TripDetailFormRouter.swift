import Foundation
import Observation

/// Owns Trip Detail form presentation routes independently of the rendered View tree.
@MainActor
@Observable
final class TripDetailFormRouter {
    var nodeFormMode: ItineraryNodeFormMode?
    var expenseFormMode: ExpenseFormMode?
    var journalFormMode: JournalFormMode?
    var journalInitialSection: JournalFormInitialSection = .content
}
