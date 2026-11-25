import Foundation
import TracciNetworking

struct ExpenseService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func listExpenses(
        tripId: String,
        page: Int = 1,
        pageSize: Int = 50,
        category: ExpenseCategory? = nil
    ) async throws -> PageResponse<Expense> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]

        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category.id))
        }

        return try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/expenses",
                queryItems: queryItems
            ),
            as: PageResponse<Expense>.self
        )
    }

    func listAllExpenses(tripId: String, category: ExpenseCategory? = nil) async throws -> [Expense] {
        let pageSize = 100
        var page = 1
        var allExpenses: [Expense] = []

        while true {
            let response = try await listExpenses(
                tripId: tripId,
                page: page,
                pageSize: pageSize,
                category: category
            )
            allExpenses.append(contentsOf: response.list)

            if allExpenses.count >= response.total || response.list.isEmpty {
                return allExpenses
            }

            page += 1
        }
    }

    func createExpense(tripId: String, request: CreateExpenseRequest) async throws -> Expense {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/expenses",
                method: .post,
                body: request
            ),
            as: Expense.self
        )
    }

    func updateExpense(tripId: String, expenseId: String, request: UpdateExpenseRequest) async throws -> Expense {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/expenses/\(expenseId)",
                method: .put,
                body: request
            ),
            as: Expense.self
        )
    }

    func deleteExpense(tripId: String, expenseId: String) async throws {
        _ = try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/expenses/\(expenseId)",
                method: .delete
            ),
            as: EmptyResponse.self
        )
    }

    func fetchSummary(tripId: String) async throws -> ExpenseSummary {
        try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/expenses/summary"),
            as: ExpenseSummary.self
        )
    }

    // MARK: - Settlement

    func fetchSettlement(tripId: String) async throws -> ExpenseSettlement {
        try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/expenses/settlement"),
            as: ExpenseSettlement.self
        )
    }

    // MARK: - Custom Categories

    func listCustomCategories(tripId: String) async throws -> [CustomExpenseCategory] {
        try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/expense-categories"),
            as: [CustomExpenseCategory].self
        )
    }

    func createCustomCategory(tripId: String, name: String) async throws -> CustomExpenseCategory {
        struct Body: Encodable { let name: String }
        return try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/expense-categories", method: .post, body: Body(name: name)),
            as: CustomExpenseCategory.self
        )
    }

    func deleteCustomCategory(tripId: String, categoryId: String) async throws {
        _ = try await apiClient.request(
            APIEndpoint(path: "trips/\(tripId)/expense-categories/\(categoryId)", method: .delete),
            as: EmptyResponse.self
        )
    }
}
