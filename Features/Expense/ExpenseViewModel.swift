import Foundation
import Observation

@MainActor
@Observable
final class ExpenseViewModel: DemoModeProviding {
    let tripId: String
    let tripStartDate: String
    let tripEndDate: String
    let baseCurrency: String

    private(set) var expenses: [Expense] = []
    private(set) var summary: ExpenseSummary?
    private(set) var settlement: ExpenseSettlement?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    private(set) var members: [TripMemberResp] = []
    private(set) var customCategories: [CustomExpenseCategory] = []
    private(set) var isCategoriesLoading = false
    private(set) var categoryErrorMessage: String?

    var showAddForm = false
    var editingExpense: Expense?

    private let expenseService: ExpenseService
    private let collaborationService: CollaborationService?
    private var hasLoaded = false
    private var loadGeneration = 0
    private var memberLoadGeneration = 0
    /// Demo Journey read-only guard.
    var isDemoMode = false

    init(
        tripId: String,
        tripStartDate: String,
        tripEndDate: String,
        baseCurrency: String,
        expenseService: ExpenseService,
        collaborationService: CollaborationService? = nil
    ) {
        self.tripId = tripId
        self.tripStartDate = tripStartDate
        self.tripEndDate = tripEndDate
        self.baseCurrency = baseCurrency
        self.expenseService = expenseService
        self.collaborationService = collaborationService
    }

    // MARK: - Load

    func refresh() async {
        await load(force: true)
    }

    func load() async {
        await load(force: false)
    }

    func loadMembers() async {
        guard !isDemoMode, let collaborationService else { return }
        memberLoadGeneration += 1
        let generation = memberLoadGeneration
        do {
            let members = try await collaborationService.listMembers(tripId: tripId)
            guard generation == memberLoadGeneration else { return }
            self.members = members
        } catch {
            guard generation == memberLoadGeneration else { return }
            self.members = []
        }
    }

    // MARK: - Custom Categories

    func loadCustomCategories() async {
        guard !isDemoMode else { return }
        isCategoriesLoading = true
        categoryErrorMessage = nil
        defer { isCategoriesLoading = false }
        do {
            customCategories = try await expenseService.listCustomCategories(tripId: tripId)
        } catch {
            categoryErrorMessage = error.localizedDescription
        }
    }

    /// 创建成功返回新建分类（供表单自动选中）；失败返回 nil 并记录 `categoryErrorMessage`。
    func addCustomCategory(name: String) async -> CustomExpenseCategory? {
        guard !isDemoMode else {
            categoryErrorMessage = DemoReadOnlyCopy.toast
            return nil
        }
        categoryErrorMessage = nil
        do {
            let category = try await expenseService.createCustomCategory(tripId: tripId, name: name)
            customCategories.append(category)
            return category
        } catch {
            categoryErrorMessage = error.localizedDescription
            return nil
        }
    }

    func removeCustomCategory(categoryId: String) async -> Bool {
        guard !isDemoMode else {
            categoryErrorMessage = DemoReadOnlyCopy.toast
            return false
        }
        categoryErrorMessage = nil
        do {
            try await expenseService.deleteCustomCategory(tripId: tripId, categoryId: categoryId)
            customCategories.removeAll { $0.id == categoryId }
            return true
        } catch {
            categoryErrorMessage = error.localizedDescription
            return false
        }
    }

    private func load(force: Bool) async {
        guard !isDemoMode else { return }
        guard force || !hasLoaded else { return }

        loadGeneration += 1
        let generation = loadGeneration

        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            async let expensesTask = expenseService.listAllExpenses(tripId: tripId)
            async let summaryTask = expenseService.fetchSummary(tripId: tripId)

            let (fetchedExpenses, summaryResponse) = try await (expensesTask, summaryTask)

            guard generation == loadGeneration else { return }

            expenses = Self.sortedExpenses(fetchedExpenses)
            summary = summaryResponse
            errorMessage = nil
            hasLoaded = true
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }

        do {
            let fetchedSettlement = try await expenseService.fetchSettlement(tripId: tripId)
            guard generation == loadGeneration else { return }
            settlement = fetchedSettlement
        } catch {
            guard generation == loadGeneration else { return }
            settlement = nil
        }
    }

    /// Demo Journey: hydrate from Bundle without network.
    func applyDemo(expenses: [Expense], summary: ExpenseSummary, settlement: ExpenseSettlement? = nil) {
        isDemoMode = true
        loadGeneration += 1
        self.expenses = Self.sortedExpenses(expenses)
        self.summary = summary
        self.settlement = settlement
        errorMessage = nil
        isLoading = false
        hasLoaded = true
    }

    func applyDemoMembers(_ members: [TripMemberResp]) {
        self.members = members
    }

    // MARK: - Create

    func createExpense(_ request: CreateExpenseRequest) async -> Bool {
        guard !isDemoMode else {
            submitError = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        invalidatePendingLoads()
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            _ = try await expenseService.createExpense(tripId: tripId, request: request)
            showAddForm = false
            await refreshAfterMutation()
            return true
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    // MARK: - Update

    func updateExpense(expenseId: String, request: UpdateExpenseRequest) async -> Bool {
        guard !isDemoMode else {
            submitError = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        invalidatePendingLoads()
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            _ = try await expenseService.updateExpense(
                tripId: tripId, expenseId: expenseId, request: request
            )
            editingExpense = nil
            await refreshAfterMutation()
            return true
        } catch {
            submitError = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete

    func deleteExpense(_ expense: Expense) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        invalidatePendingLoads()
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await expenseService.deleteExpense(tripId: tripId, expenseId: expense.id)
            await refreshAfterMutation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Mutation refresh

    private func refreshAfterMutation() async {
        hasLoaded = false
        await load(force: true)
    }

    private func invalidatePendingLoads() {
        loadGeneration += 1
        isLoading = false
    }

    // MARK: - Computed

    var todayTotal: Decimal {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return expenses
            .filter { expense in
                guard let date = expense.spentAtDate else { return false }
                return calendar.isDate(date, inSameDayAs: today)
            }
            .reduce(Decimal(0)) { $0 + $1.amountCnyDecimal }
    }

    var hasExpenses: Bool {
        !expenses.isEmpty
    }

    private static func sortedExpenses(_ expenses: [Expense]) -> [Expense] {
        expenses.sorted { lhs, rhs in
            switch (lhs.spentAtDate, rhs.spentAtDate) {
            case let (lhsDate?, rhsDate?):
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.createdAt ?? "" > rhs.createdAt ?? ""
            }
        }
    }
}
