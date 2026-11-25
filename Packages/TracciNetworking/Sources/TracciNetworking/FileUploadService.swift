import Foundation

public struct FileUploadService {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func uploadImage(
        businessType: String,
        businessId: String?,
        imageData: Data,
        fileName: String,
        contentType: String,
        width: Int?,
        height: Int?
    ) async throws -> FileConfirmResponse {
        let credentials = try await getUploadCredentials(
            businessType: businessType,
            businessId: businessId,
            fileName: fileName,
            contentType: contentType,
            size: imageData.count
        )

        let etag = try await uploadToCOS(
            uploadUrl: credentials.uploadUrl,
            headers: credentials.headers,
            imageData: imageData,
            contentType: contentType
        )

        return try await confirmUpload(
            fileId: credentials.fileId,
            etag: etag,
            width: width,
            height: height
        )
    }

    // MARK: - Private

    private func getUploadCredentials(
        businessType: String,
        businessId: String?,
        fileName: String,
        contentType: String,
        size: Int
    ) async throws -> FileUploadCredentials {
        struct UploadCredentialsRequest: Encodable {
            let businessType: String
            let businessId: String?
            let fileName: String
            let contentType: String
            let size: Int
            let uploadMethod: String
        }

        let request = UploadCredentialsRequest(
            businessType: businessType,
            businessId: businessId,
            fileName: fileName,
            contentType: contentType,
            size: size,
            uploadMethod: "PUT"
        )

        return try await apiClient.request(
            APIEndpoint(
                path: "files/upload-credentials",
                method: .post,
                body: request
            ),
            as: FileUploadCredentials.self
        )
    }

    private func confirmUpload(
        fileId: String,
        etag: String?,
        width: Int?,
        height: Int?
    ) async throws -> FileConfirmResponse {
        struct ConfirmRequest: Encodable {
            let etag: String?
            let width: Int?
            let height: Int?
        }

        return try await apiClient.request(
            APIEndpoint(
                path: "files/\(fileId)/confirm",
                method: .post,
                body: ConfirmRequest(etag: etag, width: width, height: height)
            ),
            as: FileConfirmResponse.self
        )
    }

    private func uploadToCOS(
        uploadUrl: String,
        headers: [String: String]?,
        imageData: Data,
        contentType: String
    ) async throws -> String? {
        guard let url = URL(string: uploadUrl) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 60

        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (_, response) = try await URLSession.shared.upload(for: request, from: imageData)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.underlying("图片上传失败，请稍后重试")
        }

        return httpResponse.value(forHTTPHeaderField: "ETag")
    }
}
