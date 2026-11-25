import Foundation

/// Private on-disk cache for Demo Journey only.
/// Must never write into live trip list/detail/stats caches.
struct DemoJourneyCacheStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    private var bundleURL: URL { directoryURL.appendingPathComponent("bundle.json") }
    private var etagURL: URL { directoryURL.appendingPathComponent("etag.txt") }
    private var metaURL: URL { directoryURL.appendingPathComponent("meta.json") }

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = base
                .appendingPathComponent("tracci.demo.journey", isDirectory: true)
        }
    }

    struct CachedBundle: Equatable {
        let responseBody: Data
        let etag: String?
        let schemaVersion: Int?
        let contentVersion: String?
    }

    func load() -> CachedBundle? {
        guard fileManager.fileExists(atPath: bundleURL.path) else { return nil }
        guard let responseBody = try? Data(contentsOf: bundleURL), !responseBody.isEmpty else {
            return nil
        }

        let etag = (try? String(contentsOf: etagURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = loadMeta()

        return CachedBundle(
            responseBody: responseBody,
            etag: etag?.isEmpty == false ? etag : nil,
            schemaVersion: meta?.schemaVersion,
            contentVersion: meta?.contentVersion
        )
    }

    /// Atomically replace the cached response body and ETag.
    func save(responseBody: Data, etag: String?, bundle: DemoJourneyBundle) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let tempBundle = directoryURL.appendingPathComponent("bundle.json.tmp")
        try responseBody.write(to: tempBundle, options: .atomic)
        _ = try? fileManager.removeItem(at: bundleURL)
        try fileManager.moveItem(at: tempBundle, to: bundleURL)

        if let etag, !etag.isEmpty {
            try etag.write(to: etagURL, atomically: true, encoding: .utf8)
        } else if fileManager.fileExists(atPath: etagURL.path) {
            try? fileManager.removeItem(at: etagURL)
        }

        let meta = Meta(
            schemaVersion: bundle.schemaVersion,
            contentVersion: bundle.contentVersion,
            referenceDate: bundle.referenceDate,
            savedAt: ISO8601DateFormatter().string(from: Date())
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: metaURL, options: .atomic)
    }

    func clear() {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try? fileManager.removeItem(at: directoryURL)
    }

    // MARK: - Private

    private struct Meta: Codable {
        let schemaVersion: Int
        let contentVersion: String
        let referenceDate: String
        let savedAt: String
    }

    private func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }
}
