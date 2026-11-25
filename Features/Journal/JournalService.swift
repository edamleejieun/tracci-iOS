import Foundation
import TracciNetworking

struct JournalService {
    private let apiClient: APIClient
    private let fileUploadService: FileUploadService

    init(apiClient: APIClient, fileUploadService: FileUploadService) {
        self.apiClient = apiClient
        self.fileUploadService = fileUploadService
    }

    // MARK: - Journal CRUD

    func listEntries(tripId: String, page: Int = 1, pageSize: Int = 20) async throws -> PageResponse<JournalEntry> {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]

        return try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/journal",
                queryItems: queryItems
            ),
            as: PageResponse<JournalEntry>.self
        )
    }

    func createEntry(tripId: String, request: CreateJournalRequest) async throws -> JournalEntry {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/journal",
                method: .post,
                body: request
            ),
            as: JournalEntry.self
        )
    }

    func updateEntry(tripId: String, entryId: String, request: UpdateJournalRequest) async throws -> JournalEntry {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/journal/\(entryId)",
                method: .put,
                body: request
            ),
            as: JournalEntry.self
        )
    }

    func deleteEntry(tripId: String, entryId: String) async throws {
        _ = try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/journal/\(entryId)",
                method: .delete
            ),
            as: EmptyResponse.self
        )
    }

    func featurePhoto(tripId: String, photoId: String) async throws -> JournalPhoto {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/journal/photos/\(photoId)/featured",
                method: .put
            ),
            as: JournalPhoto.self
        )
    }

    func unfeaturePhoto(tripId: String, photoId: String) async throws -> JournalPhoto {
        try await apiClient.request(
            APIEndpoint(
                path: "trips/\(tripId)/journal/photos/\(photoId)/featured",
                method: .delete
            ),
            as: JournalPhoto.self
        )
    }

    // MARK: - File Upload

    func uploadImage(
        tripId: String,
        imageData: Data,
        fileName: String,
        contentType: String,
        width: Int?,
        height: Int?
    ) async throws -> FileConfirmResponse {
        try await fileUploadService.uploadImage(
            businessType: "JOURNAL_PHOTO",
            businessId: tripId,
            imageData: imageData,
            fileName: fileName,
            contentType: contentType,
            width: width,
            height: height
        )
    }
}
