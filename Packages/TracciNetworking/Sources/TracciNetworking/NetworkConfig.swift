import Foundation

public struct NetworkConfig: Sendable {
    public let baseURL: URL
    public let timeout: TimeInterval

    public init(baseURL: URL, timeout: TimeInterval) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    public static var development: NetworkConfig {
        if let configuredURL = configuredBaseURL {
            return NetworkConfig(baseURL: configuredURL, timeout: 30)
        }

        return .simulator
    }

    public static let simulator = NetworkConfig(
        baseURL: URL(string: "http://localhost:8080/api/v1")!,
        timeout: 30
    )

    public static let production = NetworkConfig(
        baseURL: URL(string: "https://api.tracci.cn/api/v1")!,
        timeout: 30
    )

    public static func realDevice(host: String) -> NetworkConfig {
        localNetwork(host: host)
    }

    public static func localNetwork(host: String) -> NetworkConfig {
        NetworkConfig(
            baseURL: URL(string: "http://\(host):8080/api/v1")!,
            timeout: 30
        )
    }

    private static var configuredBaseURL: URL? {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "TRACCI_API_BASE_URL") as? String
        let environmentValue = ProcessInfo.processInfo.environment["TRACCI_API_BASE_URL"]

        return [bundleValue, environmentValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.contains("$(") }
            .flatMap(URL.init(string:))
    }
}
