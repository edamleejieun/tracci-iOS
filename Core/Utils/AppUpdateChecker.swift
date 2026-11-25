import Foundation
import Observation

// MARK: - App Store links

/// Shared App Store product identifiers and URLs (App ID matches About / review links).
enum AppStoreConfig {
    static let appID = "6779085856"
    static let bundleID = "cn.tracci.ios"
    static let productURLString = "https://apps.apple.com/cn/app/id\(appID)"
    static let reviewURLString = "https://apps.apple.com/cn/app/id\(appID)?action=write-review"

    static var productURL: URL? { URL(string: productURLString) }
    static var reviewURL: URL? { URL(string: reviewURLString) }
}

// MARK: - Status

enum AppUpdateStatus: Equatable {
    /// Not checked yet this session (or result discarded).
    case idle
    case checking
    case upToDate
    case updateAvailable(latestVersion: String)
    case failed(message: String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    /// Profile list / version page secondary line (tool-first).
    var subtitle: String {
        switch self {
        case .idle:
            return "查看版本与检查更新"
        case .checking:
            return "正在检查…"
        case .upToDate:
            return "已是最新"
        case .updateAvailable(let latest):
            return "有新版本 v\(latest)"
        case .failed:
            return "暂时查不到更新"
        }
    }

    /// Creek status-dot color role (resolved in UI with AppColors).
    var creekDotKind: CreekStatusDotKind {
        switch self {
        case .idle, .checking, .upToDate, .failed:
            return .neutral
        case .updateAvailable:
            return .available
        }
    }
}

enum CreekStatusDotKind: Equatable {
    case neutral
    case available
    case warning
}

// MARK: - Checker

/// Compares the installed short version against the App Store lookup result.
/// Soft/force launch prompts can share this later; View never talks to URLSession directly.
@MainActor
@Observable
final class AppUpdateChecker {
    nonisolated private static let defaultLookupURL = URL(
        string: "https://itunes.apple.com/cn/lookup?id=\(AppStoreConfig.appID)"
    )

    private(set) var status: AppUpdateStatus = .idle
    private(set) var latestVersion: String?
    private(set) var lastCheckedAt: Date?

    let currentVersion: String
    let buildNumber: String?

    private var inFlightTask: Task<Void, Never>?
    private let session: URLSession
    private let lookupURL: URL?

    init(
        currentVersion: String? = nil,
        buildNumber: String? = nil,
        session: URLSession = .shared,
        lookupURL: URL? = AppUpdateChecker.defaultLookupURL
    ) {
        let info = Bundle.main.infoDictionary
        self.currentVersion = currentVersion
            ?? (info?["CFBundleShortVersionString"] as? String)
            ?? "1.0.0"
        self.buildNumber = buildNumber
            ?? (info?["CFBundleVersion"] as? String)
        self.session = session
        self.lookupURL = lookupURL
    }

    /// Silent / manual check. Concurrent calls coalesce on one in-flight task.
    func checkForUpdate(userInitiated: Bool = false) async {
        if let inFlightTask {
            await inFlightTask.value
            return
        }

        // Avoid hammering lookup on every Profile appear unless user taps.
        if !userInitiated,
           let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < 60 * 30 {
            switch status {
            case .upToDate, .updateAvailable:
                return
            default:
                break
            }
        }

        let task = Task { @MainActor in
            status = .checking
            defer { inFlightTask = nil }

            guard let lookupURL else {
                status = .failed(message: "无法构造更新检查地址")
                return
            }

            do {
                var request = URLRequest(url: lookupURL)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData

                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    status = .failed(message: "暂时查不到更新，可稍后重试")
                    return
                }

                let storeVersion = try Self.parseLatestVersion(from: data)
                guard let storeVersion, !storeVersion.isEmpty else {
                    status = .failed(message: "商店未返回版本信息")
                    return
                }

                latestVersion = storeVersion
                lastCheckedAt = Date()

                if Self.isStoreVersionNewer(store: storeVersion, local: currentVersion) {
                    status = .updateAvailable(latestVersion: storeVersion)
                } else {
                    status = .upToDate
                }
            } catch is CancellationError {
                if case .checking = status {
                    status = .idle
                }
            } catch {
                status = .failed(message: "暂时查不到更新，可稍后重试")
            }
        }

        inFlightTask = task
        await task.value
    }

    // MARK: - Version compare

    /// True when `store` is strictly greater than `local` (semver-ish numeric segments).
    static func isStoreVersionNewer(store: String, local: String) -> Bool {
        let s = normalizedSegments(store)
        let l = normalizedSegments(local)
        let count = max(s.count, l.count)
        for i in 0..<count {
            let sv = i < s.count ? s[i] : 0
            let lv = i < l.count ? l[i] : 0
            if sv != lv { return sv > lv }
        }
        return false
    }

    private static func normalizedSegments(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    private static func parseLatestVersion(from data: Data) throws -> String? {
        let decoded = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
        return decoded.results.first?.version
    }
}

// MARK: - Lookup DTO

private struct ITunesLookupResponse: Decodable {
    let resultCount: Int
    let results: [ITunesLookupResult]
}

private struct ITunesLookupResult: Decodable {
    let version: String?
}
