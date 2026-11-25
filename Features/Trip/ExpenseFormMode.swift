import Foundation

enum ExpenseFormMode: Identifiable {
    case create(defaultDate: Date?, itineraryLink: ExpenseItineraryLink?)
    case duplicate(Expense, defaultDate: Date?)
    case edit(Expense)

    var id: String {
        switch self {
        case .create: return "create"
        case .duplicate(let expense, _): return "duplicate-\(expense.id)"
        case .edit(let expense): return expense.id
        }
    }

    var existingExpense: Expense? {
        if case .edit(let expense) = self { return expense }
        return nil
    }

    var duplicateExpense: Expense? {
        if case .duplicate(let expense, _) = self { return expense }
        return nil
    }

    var defaultDate: Date? {
        switch self {
        case .create(let date, _): return date
        case .duplicate(_, let date): return date
        case .edit: return nil
        }
    }

    var itineraryLink: ExpenseItineraryLink? {
        if case .create(_, let link) = self { return link }
        return nil
    }
}

