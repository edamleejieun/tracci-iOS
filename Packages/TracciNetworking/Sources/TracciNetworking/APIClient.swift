import Foundation

public protocol AccessTokenProviding: AnyObject {
    var accessToken: String? { get }
}

/// Result of a conditional GET that may return HTTP 304.
public enum ConditionalAPIResult<T: Decodable> {
    /// Server confirmed the cached representation is still current. Body is empty.
    case notModified(etag: String?)
    /// Fresh payload. `rawResponseBody` is the full `ApiResponse` JSON for private caching.
    case value(T, etag: String?, rawResponseBody: Data)
}

public final class APIClient {
    private let config: NetworkConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private weak var tokenProvider: AccessTokenProviding?

    public var unauthorizedRetryHandler: (() async -> Bool)?
    public var accountDeletedHandler: (() async -> Void)?

    /// Dedicated session for SSE — disables timeouts and response caching that would buffer events.
    private lazy var streamingSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = .infinity
        configuration.timeoutIntervalForResource = .infinity
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpAdditionalHeaders = [
            "Accept-Encoding": "identity"
        ]
        return URLSession(configuration: configuration)
    }()

    public func makeAuthorizedRequest(for endpoint: APIEndpoint, accept: String = "application/json") throws -> URLRequest {
        var request = try makeRequest(endpoint)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    /// SSE requests must not use the default 30 s timeout or cache policy.
    public func makeStreamingAuthorizedRequest(for endpoint: APIEndpoint) throws -> URLRequest {
        var request = try makeRequest(endpoint)
        request.timeoutInterval = .infinity
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        return request
    }

    /// Create a derived client with a different request timeout, sharing the same token provider.
    public func withTimeout(_ timeout: TimeInterval) -> APIClient {
        let newConfig = NetworkConfig(baseURL: config.baseURL, timeout: timeout)
        let newSession = URLSession(configuration: {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = timeout
            cfg.timeoutIntervalForResource = timeout * 2
            return cfg
        }())
        let client = APIClient(config: newConfig, session: newSession, tokenProvider: tokenProvider)
        client.unauthorizedRetryHandler = unauthorizedRetryHandler
        client.accountDeletedHandler = accountDeletedHandler
        return client
    }

    public init(
        config: NetworkConfig = .development,
        session: URLSession = .shared,
        tokenProvider: AccessTokenProviding? = nil
    ) {
        self.config = config
        self.session = session
        self.tokenProvider = tokenProvider

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func request<T: Decodable>(_ endpoint: APIEndpoint, as type: T.Type = T.self) async throws -> T {
        try await perform(endpoint, as: type, allowsUnauthorizedRetry: true)
    }

    /// Conditional request supporting HTTP 304 (`If-None-Match` via `endpoint.headers`).
    /// Use for Demo Journey and other private revalidation flows. Does not treat 304 as an error.
    public func requestConditional<T: Decodable>(
        _ endpoint: APIEndpoint,
        as type: T.Type = T.self
    ) async throws -> ConditionalAPIResult<T> {
        try await performConditional(endpoint, as: type, allowsUnauthorizedRetry: true)
    }

    public func eventStream(_ endpoint: APIEndpoint) async throws -> URLSession.AsyncBytes {
        try await openEventStream(endpoint, allowsUnauthorizedRetry: true)
    }

    private func openEventStream(
        _ endpoint: APIEndpoint,
        allowsUnauthorizedRetry: Bool
    ) async throws -> URLSession.AsyncBytes {
        let request = try makeStreamingAuthorizedRequest(for: endpoint)

        do {
            let (bytes, response) = try await streamingSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 401, endpoint.requiresAuth, allowsUnauthorizedRetry {
                if let handler = unauthorizedRetryHandler, await handler() {
                    return try await openEventStream(endpoint, allowsUnauthorizedRetry: false)
                }
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                }
                let error = parseHTTPError(statusCode: httpResponse.statusCode, data: data)
                if error.isAccountDeleted {
                    await accountDeletedHandler?()
                }
                throw error
            }

            return bytes
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.underlying(error.localizedDescription)
        }
    }

    private func perform<T: Decodable>(
        _ endpoint: APIEndpoint,
        as type: T.Type,
        allowsUnauthorizedRetry: Bool
    ) async throws -> T {
        let (data, httpResponse) = try await fetchAndValidateResponse(
            endpoint,
            allowsUnauthorizedRetry: allowsUnauthorizedRetry
        )

        do {
            return try await decodeAPIResponse(data, as: type)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.underlying(error.localizedDescription)
        }
    }

    private func performConditional<T: Decodable>(
        _ endpoint: APIEndpoint,
        as type: T.Type,
        allowsUnauthorizedRetry: Bool
    ) async throws -> ConditionalAPIResult<T> {
        let (data, httpResponse) = try await fetchAndValidateResponse(
            endpoint,
            allowsUnauthorizedRetry: allowsUnauthorizedRetry
        )

        let etag = Self.etag(from: httpResponse)

        if httpResponse.statusCode == 304 {
            return .notModified(etag: etag)
        }

        do {
            let value = try await decodeAPIResponse(data, as: type)
            return .value(value, etag: etag, rawResponseBody: data)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.underlying(error.localizedDescription)
        }
    }

    /// Shared HTTP fetch: request → 401 retry → status validation.
    ///
    /// Returns raw `(data, httpResponse)`. On 304, returns empty `Data` — callers
    /// must check `httpResponse.statusCode == 304` before decoding. Throws on
    /// non-2xx/non-304 responses.
    private func fetchAndValidateResponse(
        _ endpoint: APIEndpoint,
        allowsUnauthorizedRetry: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try makeRequest(endpoint)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // MARK: 401 retry
            //
            // When the access token has expired, the server returns 401. We attempt a
            // single token-refresh via `unauthorizedRetryHandler`, then rebuild the
            // request from the original `endpoint` and retry once.
            //
            // ETag note: the retry does NOT carry the original `If-None-Match` header
            // from the failed request. The rebuilt request's headers come entirely from
            // `endpoint.headers` — callers that need conditional revalidation on retry
            // must include the ETag in `endpoint.headers` before calling
            // `requestConditional`. `DemoJourneyService` already does this: on 401 retry
            // it re-fetches the ETag from its local cache and passes it via the
            // conditional request headers. If the cache is stale the retry degrades
            // gracefully to a full response.
            if httpResponse.statusCode == 401, endpoint.requiresAuth, allowsUnauthorizedRetry {
                if let handler = unauthorizedRetryHandler, await handler() {
                    return try await fetchAndValidateResponse(
                        endpoint,
                        allowsUnauthorizedRetry: false
                    )
                }
            }

            // 304 is a valid conditional response — let the caller decide how to handle it.
            if httpResponse.statusCode == 304 {
                return (Data(), httpResponse)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let error = parseHTTPError(statusCode: httpResponse.statusCode, data: data)
                if error.isAccountDeleted {
                    await accountDeletedHandler?()
                }
                throw error
            }

            return (data, httpResponse)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.underlying(error.localizedDescription)
        }
    }

    private func decodeAPIResponse<T: Decodable>(_ data: Data, as type: T.Type) async throws -> T {
        do {
            let wrapped = try decoder.decode(APIResponse<T>.self, from: data)
            guard wrapped.code == 0 else {
                if wrapped.code == 40302 {
                    await accountDeletedHandler?()
                }
                throw APIError.business(code: wrapped.code, message: wrapped.message)
            }

            if let payload = wrapped.data {
                return payload
            }

            if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T {
                return empty
            }

            throw APIError.noData
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decoding(Self.describe(decodingError: error))
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private static func etag(from response: HTTPURLResponse) -> String? {
        let value = response.value(forHTTPHeaderField: "ETag")
            ?? response.value(forHTTPHeaderField: "Etag")
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func makeRequest(_ endpoint: APIEndpoint) throws -> URLRequest {
        guard var components = URLComponents(url: config.baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems.filter { item in
                guard let value = item.value else { return false }
                return !value.isEmpty
            }
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = endpoint.body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        if endpoint.requiresAuth, let accessToken = tokenProvider?.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return request
    }

    private func parseHTTPError(statusCode: Int, data: Data) -> APIError {
        guard !data.isEmpty else {
            return statusCode == 401 ? .unauthorized : .server(statusCode: statusCode, message: nil)
        }

        if let errorBody = try? decoder.decode(APIResponse<EmptyResponse>.self, from: data) {
            if errorBody.code != 0 {
                return .business(code: errorBody.code, message: errorBody.message)
            }
            return .server(statusCode: statusCode, message: errorBody.message)
        }

        return statusCode == 401 ? .unauthorized : .server(statusCode: statusCode, message: nil)
    }

    private static func describe(decodingError error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let value = codingPath.map(\.stringValue).joined(separator: ".")
            return value.isEmpty ? "<root>" : value
        }

        switch error {
        case let .typeMismatch(type, context):
            return "字段 \(path(context.codingPath)) 类型不匹配，期望 \(type)：\(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "字段 \(path(context.codingPath)) 缺少值，期望 \(type)：\(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "字段 \(path(context.codingPath + [key])) 缺失：\(context.debugDescription)"
        case let .dataCorrupted(context):
            return "字段 \(path(context.codingPath)) 数据格式错误：\(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

extension APIError {
    var isAccountDeleted: Bool {
        if case let .business(code, _) = self {
            return code == 40302
        }
        return false
    }
}
