import Foundation

/// Credentials for a single COS upload session.
/// Moved from Journal models so Networking owns the full upload surface.
public struct FileUploadCredentials: Decodable, Sendable {
    public let fileId: String
    public let objectKey: String?
    public let uploadUrl: String
    public let method: String?
    public let headers: [String: String]?
    public let formData: [String: String]?
    public let fileFieldName: String?
    public let expiresAt: String?

    public init(
        fileId: String,
        objectKey: String? = nil,
        uploadUrl: String,
        method: String? = nil,
        headers: [String: String]? = nil,
        formData: [String: String]? = nil,
        fileFieldName: String? = nil,
        expiresAt: String? = nil
    ) {
        self.fileId = fileId
        self.objectKey = objectKey
        self.uploadUrl = uploadUrl
        self.method = method
        self.headers = headers
        self.formData = formData
        self.fileFieldName = fileFieldName
        self.expiresAt = expiresAt
    }
}

/// Confirmed file metadata after COS upload.
public struct FileConfirmResponse: Decodable, Sendable {
    public let id: String
    public let url: String?
    public let thumbnailUrl: String?
    public let previewUrl: String?
    public let exportUrl: String?
    public let storyPortraitUrl: String?
    public let storyCardUrl: String?
    public let squareUrl: String?
    public let watermarkedUrl: String?
    public let contentType: String?
    public let size: Int?
    public let width: Int?
    public let height: Int?
    public let status: String?
    public let createdAt: String?

    public init(
        id: String,
        url: String? = nil,
        thumbnailUrl: String? = nil,
        previewUrl: String? = nil,
        exportUrl: String? = nil,
        storyPortraitUrl: String? = nil,
        storyCardUrl: String? = nil,
        squareUrl: String? = nil,
        watermarkedUrl: String? = nil,
        contentType: String? = nil,
        size: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        status: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.previewUrl = previewUrl
        self.exportUrl = exportUrl
        self.storyPortraitUrl = storyPortraitUrl
        self.storyCardUrl = storyCardUrl
        self.squareUrl = squareUrl
        self.watermarkedUrl = watermarkedUrl
        self.contentType = contentType
        self.size = size
        self.width = width
        self.height = height
        self.status = status
        self.createdAt = createdAt
    }
}
