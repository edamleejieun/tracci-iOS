import Foundation
import Observation

@MainActor
@Observable
final class JournalViewModel: DemoModeProviding {
    private(set) var entries: [JournalEntry] = []
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var deleteTarget: JournalEntry?

    let tripId: String
    private let journalService: JournalService
    private var tripStartDate: Date?
    private var tripEndDate: Date?
    private var tripDestination: TripDestination?
    /// Demo Journey read-only guard.
    var isDemoMode = false

    var isEmpty: Bool {
        !isLoading && entries.isEmpty
    }

    var dayGroups: [JournalDayGroup] {
        JournalGrouping.dayGroups(from: entries, tripStartDate: tripStartDate, tripEndDate: tripEndDate)
    }

    var featuredPhotos: [JournalFeaturedPhoto] {
        JournalGrouping.featuredPhotos(from: entries)
    }

    var placeSearchContext: PlaceSearchContext {
        PlaceSearchContext(
            name: tripDestination?.name,
            cityName: tripDestination?.cityName,
            country: tripDestination?.country,
            latitude: tripDestination?.latitude,
            longitude: tripDestination?.longitude
        )
    }

    init(tripId: String, tripStartDate: String? = nil, tripEndDate: String? = nil, tripDestination: TripDestination? = nil, journalService: JournalService) {
        self.tripId = tripId
        self.tripStartDate = TripDateFormatting.date(from: tripStartDate)
        self.tripEndDate = TripDateFormatting.date(from: tripEndDate)
        self.tripDestination = tripDestination
        self.journalService = journalService
    }

    func updateTripDates(startDate: String?, endDate: String?) {
        tripStartDate = TripDateFormatting.date(from: startDate)
        tripEndDate = TripDateFormatting.date(from: endDate)
    }

    func updateTripDestination(_ destination: TripDestination?) {
        tripDestination = destination
    }

    func resolvedMood(for entry: JournalEntry) -> JournalMood? {
        entry.mood
    }

    // MARK: - Load

    func loadEntries() async {
        guard !isDemoMode else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await journalService.listEntries(tripId: tripId, pageSize: 100)
            entries = response.list.sorted {
                ($0.occurredDate ?? .distantPast) > ($1.occurredDate ?? .distantPast)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isDemoMode else { return }
        await loadEntries()
    }

    /// Demo Journey: hydrate from Bundle without network.
    func applyDemoEntries(_ entries: [JournalEntry]) {
        isDemoMode = true
        self.entries = entries.sorted {
            ($0.occurredDate ?? .distantPast) > ($1.occurredDate ?? .distantPast)
        }
        isLoading = false
        errorMessage = nil
    }

    // MARK: - Create

    func createEntry(form: JournalFormState) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        errorMessage = nil

        let trimmedContent = form.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !form.allFileIds.isEmpty else {
            errorMessage = "请输入日志内容或添加图片"
            return false
        }

        guard trimmedContent.count <= 2000 else {
            errorMessage = "日志正文不能超过 2000 字"
            return false
        }

        guard form.allFileIds.count <= 9 else {
            errorMessage = "图片最多 9 张"
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            // Day anchors from the trip workspace are start-of-day (00:00). Keep that
            // calendar day, but stamp the real write time so the list does not show 00:00.
            let occurredAt = formatOccurrenceDate(resolveCreateOccurrenceDate(from: form))
            let fileIds = form.allFileIds.isEmpty ? nil : form.allFileIds

            let request = CreateJournalRequest(
                content: trimmedContent.isEmpty ? nil : trimmedContent,
                location: form.location,
                occurredAt: occurredAt,
                fileIds: fileIds,
                isHighlight: form.isHighlight,
                mood: form.mood,
                visibility: form.isPrivate ? "private" : "all"
            )

            _ = try await journalService.createEntry(tripId: tripId, request: request)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Update

    func updateEntry(_ entry: JournalEntry, form: JournalFormState) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        errorMessage = nil

        let trimmedContent = form.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !form.allFileIds.isEmpty else {
            errorMessage = "请输入日志内容或添加图片"
            return false
        }

        guard trimmedContent.count <= 2000 else {
            errorMessage = "日志正文不能超过 2000 字"
            return false
        }

        guard form.allFileIds.count <= 9 else {
            errorMessage = "图片最多 9 张"
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let occurredAt = formatOccurrenceDate(entry.occurredDate)
            let fileIds = form.allFileIds.isEmpty ? nil : form.allFileIds

            let request = UpdateJournalRequest(
                content: trimmedContent.isEmpty ? nil : trimmedContent,
                location: form.location,
                occurredAt: occurredAt,
                fileIds: fileIds,
                isHighlight: form.isHighlight,
                mood: form.mood,
                visibility: form.isPrivate ? "private" : "all"
            )

            _ = try await journalService.updateEntry(tripId: tripId, entryId: entry.id, request: request)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleHighlight(_ entry: JournalEntry) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let request = UpdateJournalRequest(
                content: entry.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                location: entry.location,
                occurredAt: formatOccurrenceDate(entry.occurredDate),
                fileIds: entry.photos.compactMap(\.fileId),
                isHighlight: !entry.isHighlight,
                mood: entry.mood,
                visibility: entry.visibility ?? "all"
            )

            _ = try await journalService.updateEntry(tripId: tripId, entryId: entry.id, request: request)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleFeaturedPhoto(_ photo: JournalPhoto) async -> Bool {
        let succeeded = await setPhotoFeatured(
            photoId: photo.id,
            isCurrentlyFeatured: photo.userFeatured
        )
        if succeeded {
            await refresh()
        }
        return succeeded
    }

    func setPhotoFeatured(photoId: String, isCurrentlyFeatured: Bool) async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            return false
        }
        guard !isSubmitting else { return false }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if isCurrentlyFeatured {
                _ = try await journalService.unfeaturePhoto(tripId: tripId, photoId: photoId)
            } else {
                _ = try await journalService.featurePhoto(tripId: tripId, photoId: photoId)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete

    func confirmDelete(_ entry: JournalEntry) {
        deleteTarget = entry
    }

    func performDelete() async -> Bool {
        guard !isDemoMode else {
            errorMessage = DemoReadOnlyCopy.toast
            deleteTarget = nil
            return false
        }
        guard let entry = deleteTarget else { return false }
        guard !isSubmitting else { return false }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await journalService.deleteEntry(tripId: tripId, entryId: entry.id)
            entries.removeAll { $0.id == entry.id }
            deleteTarget = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelDelete() {
        deleteTarget = nil
    }

    // MARK: - Image Upload

    func uploadImage(imageData: Data, fileName: String, contentType: String, width: Int?, height: Int?) async throws -> String {
        let response = try await journalService.uploadImage(
            tripId: tripId,
            imageData: imageData,
            fileName: fileName,
            contentType: contentType,
            width: width,
            height: height
        )
        return response.id
    }

    // MARK: - Helpers

    private func formatOccurrenceDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    func resolveCreateOccurrenceDate(from form: JournalFormState, now: Date = Date()) -> Date {
        JournalOccurrenceDate.resolveCreate(
            capturedAt: form.occurredAtOverride,
            dayAnchor: form.defaultOccurredDate,
            tripStartDate: tripStartDate,
            tripEndDate: tripEndDate,
            now: now
        )
    }
}
