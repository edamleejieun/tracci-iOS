import Foundation
import Observation
import TracciNetworking

enum TripFormFieldKey: Hashable {
    case title
    case destination
    case startDate
    case endDate
    case dateRange
}

/// Whether the current title was auto-generated from destination + dates, or
/// hand-edited by the user.
///
/// `generated`  → destination/date changes silently refresh the title.
/// `userEdited` → destination/date changes must NOT overwrite the user's title;
///                clearing the field reverts to `generated` so the suggestion returns.
enum TripTitleOrigin: Equatable {
    case generated
    case userEdited
}

enum TripCreateDismissDecision: Equatable {
    case dismissImmediately
    case confirmDiscard
    case blockedWhileSubmitting
}

/// Create-only presentation VM for the V2 Create Task Sheet.
///
/// Owns the draft (destination, dates, title), derives the default title from
/// "目的地 display name + 本地化 inclusive day count + 日游", validates, and
/// submits via `TripService.createTrip`. Deliberately free of cover / member /
/// permission concerns — those live in `TripEditViewModel`.
///
/// Title-origin tracking guarantees that hand-edited names are never silently
/// clobbered by destination/date edits (see `TripTitleOrigin`).
@MainActor
@Observable
final class TripCreateViewModel {
    // MARK: - Draft

    private(set) var destination: TripDestination?
    private(set) var destinationDisplayName: String = ""
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private(set) var title: String = ""
    private(set) var titleOrigin: TripTitleOrigin = .generated

    // MARK: - UI state

    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var validationErrors: [TripFormFieldKey: String] = [:]

    // MARK: - Dependencies

    private let tripService: TripService
    private let baseCurrency: String?
    /// 探索带来的目的地种子（规格 §7.3）；`nil` 就是普通创建入口。
    private let seed: TripCreateSeed?

    init(
        tripService: TripService,
        baseCurrency: String? = nil,
        seed: TripCreateSeed? = nil
    ) {
        self.tripService = tripService
        self.baseCurrency = baseCurrency
        self.seed = seed
        // `destination` 故意留空：契约这条路径只发 `destinationSavedPlaceId`，
        // 展示名仅用于表单回显与标题建议。
        destinationDisplayName = seed?.destinationName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Constants

    let titleMaxLength = 50
    let destinationMaxLength = 100

    // MARK: - Derived state

    /// 种子目的地只读预填，表单不给改的入口（规格 §7.3）。
    var isDestinationLocked: Bool { seed != nil }

    var hasDestination: Bool {
        !destinationDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasCompleteDateRange: Bool {
        guard let startDate, let endDate else { return false }
        return endDate >= startDate
    }

    /// Progressive disclosure keeps the create path destination → dates → title.
    /// A meaningful default title requires both a destination and a valid date range.
    var showsTitleEditor: Bool {
        hasDestination && hasCompleteDateRange
    }

    var isDirty: Bool {
        // 种子目的地是预填不是用户输入：还没碰表单就退出时不该弹「放弃创建」。
        (hasDestination && !isDestinationLocked) || startDate != nil || endDate != nil || !title.isEmpty
    }

    var dismissDecision: TripCreateDismissDecision {
        Self.dismissDecision(isDirty: isDirty, isSubmitting: isSubmitting)
    }

    static func dismissDecision(
        isDirty: Bool,
        isSubmitting: Bool
    ) -> TripCreateDismissDecision {
        if isSubmitting { return .blockedWhileSubmitting }
        return isDirty ? .confirmDiscard : .dismissImmediately
    }

    var isFormValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDestination = destinationDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasDestination,
              trimmedDestination.count <= destinationMaxLength,
              !trimmedTitle.isEmpty, trimmedTitle.count <= titleMaxLength,
              let start = startDate, let end = endDate,
              end >= start else {
            return false
        }
        return true
    }

    // MARK: - Title suggestion

    /// Pure title rule: "目的地 display name + 本地化 inclusive day count + 日游".
    ///
    /// Returns `nil` until both the destination and a valid date range exist.
    static func suggestedTitle(
        destinationName: String,
        startDate: Date?,
        endDate: Date?
    ) -> String? {
        let name = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let start = startDate,
              let end = endDate,
              end >= start,
              let days = TracciDateContext.inclusiveDayCount(start: start, end: end) else {
            return nil
        }
        return "\(name) \(days) 日游"
    }

    private func regenerateTitleIfNeeded() {
        guard titleOrigin == .generated else { return }
        title = Self.suggestedTitle(
            destinationName: destinationDisplayName,
            startDate: startDate,
            endDate: endDate
        ) ?? ""
    }

    // MARK: - Destination mutations

    func selectDestination(_ destination: TripDestination) {
        self.destination = destination
        self.destinationDisplayName = destination.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clearValidation(for: .destination)
        regenerateTitleIfNeeded()
    }

    func useManualDestination(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        destination = nil
        destinationDisplayName = trimmed
        clearValidation(for: .destination)
        regenerateTitleIfNeeded()
    }

    // MARK: - Date mutations

    func updateDates(start: Date, end: Date) {
        startDate = start
        endDate = end
        clearDateValidation()
        regenerateTitleIfNeeded()
    }

    // MARK: - Title mutation (user edit)

    /// Reflects a user edit of the title field. An empty title reverts to the
    /// generated origin and re-adopts the suggestion; any non-empty value marks
    /// the title as user-edited so destination/date changes stop overwriting it.
    func userDidEditTitle(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleOrigin = .generated
            title = ""
            regenerateTitleIfNeeded()
        } else {
            title = raw
            titleOrigin = .userEdited
        }
        clearValidation(for: .title)
    }

    // MARK: - Validation

    func validationMessage(for field: TripFormFieldKey) -> String? {
        validationErrors[field]
    }

    @discardableResult
    func validate() -> Bool {
        var errors: [TripFormFieldKey: String] = [:]

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errors[.title] = "请输入旅程名称"
        } else if trimmedTitle.count > titleMaxLength {
            errors[.title] = "旅程名称不能超过 50 字"
        }

        let trimmedDestination = destinationDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDestination.isEmpty {
            errors[.destination] = "请输入旅行目的地"
        } else if trimmedDestination.count > destinationMaxLength {
            errors[.destination] = "目的地不能超过 100 字"
        }

        if startDate == nil {
            errors[.startDate] = "请选择开始日期"
        }

        if endDate == nil {
            errors[.endDate] = "请选择结束日期"
        }

        if let start = startDate, let end = endDate, end < start {
            errors[.dateRange] = "结束日期不能早于开始日期"
        }

        validationErrors = errors
        return errors.isEmpty
    }

    // MARK: - Submit

    func submit() async -> Trip? {
        guard !isSubmitting else { return nil }

        errorMessage = nil
        guard validate() else { return nil }

        isSubmitting = true
        defer { isSubmitting = false }

        let request = makeRequest()
        do {
            return try await tripService.createTrip(request)
        } catch is CancellationError {
            return nil
        } catch let error as APIError {
            errorMessage = error.localizedDescription
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func makeRequest() -> CreateTripRequest {
        let state = TripFormState(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationName: destinationDisplayName,
            selectedDestination: destination,
            startDate: startDate,
            endDate: endDate,
            coverFileId: nil,
            coverPreviewURL: nil,
            destinationSavedPlaceId: seed?.destinationSavedPlaceId
        )
        return CreateTripRequest(from: state, baseCurrency: baseCurrency)
    }

    // MARK: - Validation cleanup

    private func clearValidation(for field: TripFormFieldKey) {
        validationErrors[field] = nil
        if field == .title || field == .destination {
            errorMessage = nil
        }
    }

    private func clearDateValidation() {
        validationErrors[.startDate] = nil
        validationErrors[.endDate] = nil
        validationErrors[.dateRange] = nil
        errorMessage = nil
    }
}
