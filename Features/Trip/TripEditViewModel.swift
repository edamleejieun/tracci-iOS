import Foundation
import Observation
import TracciNetworking

/// Identifies which single-field mutation is currently in flight, so the Settings
/// UI can show localised loading state and guard against concurrent edits.
enum TripEditMutation: Equatable {
    case title
    case destination
    case date
    case cover
}

private enum TripDestinationOverride {
    case unchanged
    case structured(TripDestination)
    case manual(String)
}

/// Unified presentation + business VM for the V2 Edit Trip Settings page.
///
/// Owns the authoritative `Trip` snapshot, applies each focused mutation against the latest
/// snapshot, and adopts each successful PUT response so the next mutation never
/// builds on pre-mutation data.
///
/// Presentation layers (`TripEditView` inline title/direct cover picker,
/// `TripDestinationSelectionSheet`, `TripDateEditorView`) hold only their own draft and call
/// the corresponding `update*` method here; they never touch `TripService`.
@MainActor
@Observable
final class TripEditViewModel {

    typealias CoverUploader = (
        _ tripId: String,
        _ imageData: Data,
        _ fileName: String,
        _ contentType: String,
        _ width: Int?,
        _ height: Int?
    ) async throws -> FileConfirmResponse

    // MARK: - Authoritative snapshot

    private(set) var trip: Trip
    private(set) var resolvedAccess: TripAccessContext?

    // MARK: - Mutation state

    private(set) var activeMutation: TripEditMutation?
    private(set) var mutationError: String?
    private(set) var isDeleting = false
    var deleteError: String?

    /// Date-change confirmation hook. Must be wired by the presenting View so the
    /// policy confirmation sheet can be shown. The cancel closure MUST be called on
    /// dismissal, otherwise the mutation continuation hangs forever.
    var onDateChangeNeedsConfirmation: ((String, @escaping () -> Void, @escaping () -> Void) -> Void)?

    // MARK: - Dependencies

    private let tripService: TripService
    private let coverUploader: CoverUploader

    // MARK: - Constants

    let titleMaxLength = 50
    let destinationMaxLength = 100

    // MARK: - Init

    init(
        trip: Trip,
        tripService: TripService,
        initialAccess: TripAccessContext? = nil,
        coverUploader: CoverUploader? = nil
    ) {
        self.trip = trip
        self.tripService = tripService
        self.resolvedAccess = initialAccess ?? trip.access
        self.coverUploader = coverUploader ?? { tripId, imageData, fileName, contentType, width, height in
            try await tripService.uploadCoverImage(
                tripId: tripId,
                imageData: imageData,
                fileName: fileName,
                contentType: contentType,
                width: width,
                height: height
            )
        }
    }

    // MARK: - Derived display values

    var effectiveAccess: TripAccessContext? {
        resolvedAccess ?? trip.access
    }

    var canUpdateTrip: Bool {
        TripEditPolicy.canUpdateTrip(effectiveAccess)
    }

    var canDeleteTrip: Bool {
        TripEditPolicy.canDeleteTrip(effectiveAccess)
    }

    var destinationDisplayValue: String {
        trip.destinationName ?? ""
    }

    var dateRangeDisplayValue: String? {
        guard let start = TripDateFormatting.date(from: trip.startDate),
              let end = TripDateFormatting.date(from: trip.endDate) else { return nil }
        let days = TracciDateContext.inclusiveDayCount(start: start, end: end) ?? 1
        return "\(TripDateFormatting.displayString(from: start)) — \(TripDateFormatting.displayString(from: end)) · \(days) 天"
    }

    var coverPreviewURL: URL? {
        trip.coverPreviewURL
    }

    var isMutating: Bool {
        activeMutation != nil
    }

    // MARK: - Access

    /// Lists may not carry access. Detail is the server-authoritative capability source.
    func refreshAccess() async {
        do {
            if let access = try await tripService.tripDetail(id: trip.id).access {
                resolvedAccess = access
            }
        } catch {
            // Preserve the last known access; mutations remain server-authoritative.
        }
    }

    func applyAccess(_ access: TripAccessContext) {
        resolvedAccess = access
    }

    func clearMutationError() {
        mutationError = nil
    }

    func reportMutationError(_ message: String) {
        mutationError = message
    }

    // MARK: - Title mutation

    @discardableResult
    func updateTitle(_ rawTitle: String) async -> Bool {
        guard beginMutation(.title) else { return false }
        defer { endMutation(.title) }

        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= titleMaxLength else {
            mutationError = title.isEmpty ? "请输入旅程名称" : "旅程名称不能超过 50 字"
            return false
        }

        do {
            let request = makeRequest(title: title)
            try await updateCanonicalSnapshot(using: request)
            return true
        } catch let error as APIError {
            mutationError = error.localizedDescription
            return false
        } catch {
            mutationError = error.localizedDescription
            return false
        }
    }

    // MARK: - Destination mutation

    @discardableResult
    func updateDestination(_ destination: TripDestination?, manualName: String?) async -> Bool {
        guard beginMutation(.destination) else { return false }
        defer { endMutation(.destination) }

        let destinationOverride: TripDestinationOverride
        if let destination {
            guard let name = destination.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  name.count <= destinationMaxLength else {
                mutationError = "请选择有效的目的地"
                return false
            }
            destinationOverride = .structured(destination)
        } else {
            let name = (manualName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= destinationMaxLength else {
                mutationError = name.isEmpty ? "请输入目的地" : "目的地不能超过 100 字"
                return false
            }
            destinationOverride = .manual(name)
        }

        do {
            let request = makeRequest(destinationOverride: destinationOverride)
            try await updateCanonicalSnapshot(using: request)
            return true
        } catch let error as APIError {
            mutationError = error.localizedDescription
            return false
        } catch {
            mutationError = error.localizedDescription
            return false
        }
    }

    // MARK: - Date mutation

    /// Updates dates. Confirmation, when required, is completed inside this one
    /// mutation token so accepting the prompt cannot race a recursive mutation.
    @discardableResult
    func updateDates(start: Date, end: Date, confirmed: Bool = false) async -> Bool {
        guard beginMutation(.date) else { return false }
        defer { endMutation(.date) }

        let newStart = Calendar.current.startOfDay(for: start)
        let newEnd = Calendar.current.startOfDay(for: end)
        guard newStart <= newEnd else {
            mutationError = "结束日期不能早于开始日期"
            return false
        }

        var hasStatusChangeConfirmation = confirmed

        // Status-change guard (client pre-check layer).
        if !hasStatusChangeConfirmation, trip.effectiveStatus == .completed {
            let originalStart = TripDateFormatting.date(from: trip.startDate)
            let originalEnd = TripDateFormatting.date(from: trip.endDate)
            if newStart != originalStart || newEnd != originalEnd,
               let outcome = TripEditPolicy.dateChangeOutcome(trip: trip, newStart: newStart, newEnd: newEnd).userMessage {
                guard await requestDateConfirmation(message: outcome) else { return false }
                hasStatusChangeConfirmation = true
            }
        }

        do {
            let request = makeRequest(
                start: newStart,
                end: newEnd,
                statusChangeConfirmed: hasStatusChangeConfirmation
            )
            try await updateCanonicalSnapshot(using: request)
            return true
        } catch let error as APIError {
            // Server-side status-change guard fallback.
            if case .business(let code, let message) = error,
               code == TripAPIBusinessCode.statusChangeRequiresConfirm,
               !hasStatusChangeConfirmation {
                guard await requestDateConfirmation(message: message) else { return false }
                do {
                    let confirmedRequest = makeRequest(
                        start: newStart,
                        end: newEnd,
                        statusChangeConfirmed: true
                    )
                    try await updateCanonicalSnapshot(using: confirmedRequest)
                    return true
                } catch {
                    mutationError = error.localizedDescription
                    return false
                }
            }
            mutationError = error.localizedDescription
            return false
        } catch {
            mutationError = error.localizedDescription
            return false
        }
    }

    private func requestDateConfirmation(message: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var hasResumed = false
            let resumeOnce: (Bool) -> Void = { value in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: value)
            }
            guard let present = onDateChangeNeedsConfirmation else {
                mutationError = message
                resumeOnce(false)
                return
            }
            present(message, { resumeOnce(true) }, { resumeOnce(false) })
        }
    }

    // MARK: - Cover mutation

    func uploadCover(
        imageData: Data,
        fileName: String,
        contentType: String,
        width: Int?,
        height: Int?
    ) async -> Bool {
        guard beginMutation(.cover) else { return false }
        defer { endMutation(.cover) }

        do {
            let response = try await coverUploader(trip.id, imageData, fileName, contentType, width, height)
            let request = makeRequest(coverFileId: response.id)
            try await updateCanonicalSnapshot(using: request)
            return true
        } catch let error as APIError {
            mutationError = error.localizedDescription
            return false
        } catch {
            mutationError = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete

    @discardableResult
    func deleteTrip() async -> Bool {
        guard !isDeleting else { return false }
        guard TripEditPolicy.canDeleteTrip(effectiveAccess) else {
            deleteError = "没有权限删除此旅程"
            return false
        }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }
        do {
            try await tripService.deleteTrip(id: trip.id)
            return true
        } catch {
            deleteError = error.localizedDescription
            return false
        }
    }

    // MARK: - Snapshot refresh

    /// The PUT response is the snapshot committed by this mutation. Using it
    /// directly avoids both transient detail failures and eventually-consistent GET
    /// responses rolling the next full-snapshot PUT back to pre-mutation values.
    private func updateCanonicalSnapshot(using request: UpdateTripRequest) async throws {
        let updated = try await tripService.updateTrip(id: trip.id, request)
        trip = updated
        if let access = updated.access {
            resolvedAccess = access
        }
    }

    // MARK: - Request builders

    /// Builds an `UpdateTripRequest` from the current snapshot, overriding only
    /// the fields the focused editor has changed. This preserves the existing
    /// full-snapshot contract without requiring partial-update support.
    private func makeRequest(
        title: String? = nil,
        destinationOverride: TripDestinationOverride = .unchanged,
        start: Date? = nil,
        end: Date? = nil,
        coverFileId: String? = nil,
        statusChangeConfirmed: Bool = false
    ) -> UpdateTripRequest {
        let destinationName: String
        let selectedDestination: TripDestination?
        switch destinationOverride {
        case .unchanged:
            destinationName = trip.destinationName ?? ""
            selectedDestination = trip.destination
        case .structured(let destination):
            destinationName = destination.name ?? ""
            selectedDestination = destination
        case .manual(let name):
            destinationName = name
            selectedDestination = nil
        }

        let state = TripFormState(
            title: title ?? trip.title,
            destinationName: destinationName,
            selectedDestination: selectedDestination,
            startDate: start ?? TripDateFormatting.date(from: trip.startDate),
            endDate: end ?? TripDateFormatting.date(from: trip.endDate),
            coverFileId: coverFileId ?? trip.coverPhoto?.fileId,
            coverPreviewURL: trip.coverPreviewURL,
            destinationSavedPlaceId: nil
        )
        return UpdateTripRequest(
            from: state,
            baseCurrency: trip.baseCurrency,
            statusChangeConfirmed: statusChangeConfirmed
        )
    }

    // MARK: - Mutation token

    private func beginMutation(_ mutation: TripEditMutation) -> Bool {
        guard activeMutation == nil else { return false }
        activeMutation = mutation
        mutationError = nil
        return true
    }

    private func endMutation(_ mutation: TripEditMutation) {
        if activeMutation == mutation {
            activeMutation = nil
        }
    }
}
