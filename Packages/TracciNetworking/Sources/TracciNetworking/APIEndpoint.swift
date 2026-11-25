import Foundation

public struct APIEndpoint: @unchecked Sendable {
    public var path: String
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]
    public var body: Encodable?
    public var requiresAuth: Bool
    public var headers: [String: String]

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        body: Encodable? = nil,
        requiresAuth: Bool = true,
        headers: [String: String] = [:]
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
        self.requiresAuth = requiresAuth
        self.headers = headers
    }
}

public struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    public init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }

    public func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
