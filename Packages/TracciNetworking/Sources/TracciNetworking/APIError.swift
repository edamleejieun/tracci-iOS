import Foundation

public enum APIError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case noData
    case unauthorized
    case business(code: Int, message: String)
    case server(statusCode: Int, message: String?)
    case decoding(String)
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请求地址无效"
        case .invalidResponse:
            return "服务器响应异常"
        case .noData:
            return "服务器未返回数据"
        case .unauthorized:
            return "登录已过期，请重新登录"
        case let .business(_, message):
            return message
        case let .server(statusCode, message):
            return message ?? "服务器错误：\(statusCode)"
        case let .decoding(message):
            return "数据解析失败：\(message)"
        case let .underlying(message):
            return message
        }
    }
}
