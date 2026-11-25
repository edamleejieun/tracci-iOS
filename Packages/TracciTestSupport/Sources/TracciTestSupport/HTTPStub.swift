import Foundation
import TracciNetworking

/// Thread-safe HTTP stub that intercepts `URLSession` requests via `URLProtocol`.
///
/// ## Usage
///
/// ```swift
/// let stub = HTTPStub()
/// stub.install()
/// defer { stub.uninstall() }
///
/// stub.stubAPISuccess(
///     path: "/api/v1/trips/trip-1",
///     method: "GET",
///     dataJSON: #"{"id":"trip-1","title":"A"}"#
/// )
///
/// let client = stub.makeAPIClient()
/// ```
///
/// Always call `install()` before firing requests and `uninstall()` in `tearDown`.
/// Only one stub may be installed at a time.
public final class HTTPStub {
    public init() {}

    private static let registryLock = NSLock()
    private static weak var installed: HTTPStub?

    private let lock = NSLock()
    private var responses: [URLStubKey: StubResponse] = [:]
    private var requestLog: [URLRequest] = []

    // MARK: - Lifecycle

    /// Install this instance as the active interceptor for `StubURLProtocol`.
    public func install() {
        Self.registryLock.lock()
        defer { Self.registryLock.unlock() }
        Self.installed = self
    }

    /// Remove this instance if it is currently installed.
    public func uninstall() {
        Self.registryLock.lock()
        defer { Self.registryLock.unlock() }
        if Self.installed === self {
            Self.installed = nil
        }
    }

    fileprivate static var current: HTTPStub? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return installed
    }

    // MARK: - URLProtocol

    public final class StubURLProtocol: Foundation.URLProtocol {
        public override class func canInit(with request: URLRequest) -> Bool {
            guard let scheme = request.url?.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }

        public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        public override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: HTTPStubError.missingURL)
                return
            }

            guard let stub = HTTPStub.current else {
                client?.urlProtocol(self, didFailWithError: HTTPStubError.notInstalled)
                return
            }

            stub.recordRequest(request)

            let key = URLStubKey(path: url.pathAndQuery, method: request.httpMethod ?? "GET")
            let matched = stub.response(for: key) ?? stub.responseMatchingPathOnly(url: url, method: request.httpMethod ?? "GET")

            if let matched {
                let httpResponse = HTTPURLResponse(
                    url: url,
                    statusCode: matched.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: matched.headers
                )!
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                if let body = matched.body {
                    client?.urlProtocol(self, didLoad: body)
                }
                client?.urlProtocolDidFinishLoading(self)
            } else {
                let message = "No stub for \(request.httpMethod ?? "?") \(url.pathAndQuery)"
                let httpResponse = HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/plain"]
                )!
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(message.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        public override func stopLoading() {}
    }

    // MARK: - Types

    public struct URLStubKey: Hashable, CustomStringConvertible {
        public let path: String
        public let method: String

        public init(path: String, method: String = "GET") {
            self.path = path
            self.method = method.uppercased()
        }

        public var description: String { "\(method) \(path)" }
    }

    public struct StubResponse {
        public let statusCode: Int
        public let body: Data?
        public let headers: [String: String]
        /// When true, match by path without query string if exact key is missing.
        public let allowPathOnlyMatch: Bool

        public init(
            statusCode: Int = 200,
            body: Data? = nil,
            headers: [String: String] = ["Content-Type": "application/json"],
            allowPathOnlyMatch: Bool = false
        ) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
            self.allowPathOnlyMatch = allowPathOnlyMatch
        }
    }

    // MARK: - Configuration

    /// Register a raw HTTP response for an exact path (+ optional query) and method.
    public func addResponse(
        for path: String,
        method: String = "GET",
        statusCode: Int = 200,
        body: Data? = nil,
        headers: [String: String] = ["Content-Type": "application/json"],
        allowPathOnlyMatch: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }
        let key = URLStubKey(path: path, method: method)
        responses[key] = StubResponse(
            statusCode: statusCode,
            body: body,
            headers: headers,
            allowPathOnlyMatch: allowPathOnlyMatch
        )
    }

    /// Register a success envelope: `{ "code": 0, "message": "OK", "data": <payload> }`.
    ///
    /// - Parameters:
    ///   - path: Full URL path including `/api/v1` prefix and query string when needed.
    ///   - dataJSON: JSON object/array/null string for the `data` field (not re-encoded).
    public func stubAPISuccess(
        path: String,
        method: String = "GET",
        dataJSON: String,
        allowPathOnlyMatch: Bool = false
    ) {
        let envelope = """
        {"code":0,"message":"OK","data":\(dataJSON)}
        """
        addResponse(
            for: path,
            method: method,
            statusCode: 200,
            body: Data(envelope.utf8),
            allowPathOnlyMatch: allowPathOnlyMatch
        )
    }

    /// Register a business-error envelope with HTTP 200 (API convention: code != 0).
    public func stubAPIBusinessError(
        path: String,
        method: String = "GET",
        code: Int,
        message: String,
        allowPathOnlyMatch: Bool = false
    ) {
        let envelope = """
        {"code":\(code),"message":\(jsonString(message)),"data":null}
        """
        addResponse(
            for: path,
            method: method,
            statusCode: 200,
            body: Data(envelope.utf8),
            allowPathOnlyMatch: allowPathOnlyMatch
        )
    }

    /// Register an HTTP-level error that still carries an API envelope body.
    public func stubHTTPError(
        path: String,
        method: String = "GET",
        statusCode: Int,
        code: Int,
        message: String,
        allowPathOnlyMatch: Bool = false
    ) {
        let envelope = """
        {"code":\(code),"message":\(jsonString(message)),"data":null}
        """
        addResponse(
            for: path,
            method: method,
            statusCode: statusCode,
            body: Data(envelope.utf8),
            allowPathOnlyMatch: allowPathOnlyMatch
        )
    }

    public func removeResponse(for path: String, method: String = "GET") {
        lock.lock()
        defer { lock.unlock() }
        responses.removeValue(forKey: URLStubKey(path: path, method: method))
    }

    public func removeAllResponses() {
        lock.lock()
        defer { lock.unlock() }
        responses.removeAll()
    }

    public func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requestLog
    }

    public func resetRequestLog() {
        lock.lock()
        defer { lock.unlock() }
        requestLog.removeAll()
    }

    public func requestCount(forPathContains substring: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestLog.filter { $0.url?.pathAndQuery.contains(substring) == true }.count
    }

    /// First recorded request body as UTF-8 string, if any.
    public func firstRequestBodyUTF8() -> String? {
        guard let body = recordedRequests().first.flatMap({ $0.httpBodyData }) else { return nil }
        return String(data: body, encoding: .utf8)
    }

    /// Build an ephemeral `APIClient` whose session routes through this stub.
    public func makeAPIClient(
        baseURL: URL = URL(string: "http://localhost:8080/api/v1")!,
        timeout: TimeInterval = 5,
        tokenProvider: AccessTokenProviding? = nil
    ) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        let session = URLSession(configuration: configuration)
        return APIClient(
            config: NetworkConfig(baseURL: baseURL, timeout: timeout),
            session: session,
            tokenProvider: tokenProvider
        )
    }

    // MARK: - Internals

    private func response(for key: URLStubKey) -> StubResponse? {
        lock.lock()
        defer { lock.unlock() }
        return responses[key]
    }

    private func responseMatchingPathOnly(url: URL, method: String) -> StubResponse? {
        lock.lock()
        defer { lock.unlock() }
        let pathOnly = url.path
        let methodKey = method.uppercased()
        for (key, response) in responses where response.allowPathOnlyMatch {
            let registeredPathOnly = key.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? key.path
            if key.method == methodKey, registeredPathOnly == pathOnly {
                return response
            }
        }
        return nil
    }

    private func recordRequest(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requestLog.append(request)
    }

    /// Encode a Swift string as a JSON string literal. `JSONSerialization` rejects
    /// top-level strings, so use `JSONEncoder` (or manual escaping) instead.
    private func jsonString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

// MARK: - Helpers

public extension URL {
    var pathAndQuery: String {
        if let query = query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }
}

public extension URLRequest {
    /// `httpBody` is often nil when the body was set via a stream; materialize when needed.
    var httpBodyData: Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 { return nil }
            if read == 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

public enum HTTPStubError: Error, Equatable {
    case missingURL
    case notInstalled
}
