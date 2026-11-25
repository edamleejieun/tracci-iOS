import Foundation
import os
import TracciNetworking

/// Fetches the versioned read-only Demo Journey Bundle.
/// Path: `GET /api/v1/demo/journey` (relative: `demo/journey`).
struct DemoJourneyService {
    private let apiClient: APIClient
    private let cacheStore: DemoJourneyCacheStore
    private let decoder: JSONDecoder
    private let logger: Logger

    init(
        apiClient: APIClient,
        cacheStore: DemoJourneyCacheStore = DemoJourneyCacheStore(),
        logger: Logger = Logger(subsystem: "com.tracci.app", category: "DemoJourney")
    ) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.logger = logger
    }

    // MARK: - LoadResult

    /// Outcome of attempting to load a displayable Demo Journey Bundle.
    enum LoadResult {
        /// Bundle loaded, validated, and ready to present.
        case displayable(DemoJourneyBundle)
        /// Server explicitly disabled the demo feature (`enabled == false`).
        case featureOff
        /// Bundle was fetched but failed validation (unsupported schema, missing scenes,
        /// capabilities insufficient, etc.). `reason` is for diagnostics.
        case undisplayable(reason: String)
        /// Network, decoding, or other unexpected error. `message` is the localized
        /// description for diagnostics.
        case failure(message: String)

        var bundle: DemoJourneyBundle? {
            if case let .displayable(bundle) = self { return bundle }
            return nil
        }

        var isDisplayable: Bool {
            if case .displayable = self { return true }
            return false
        }
    }

    // MARK: - Public API

    /// Loads a displayable bundle, distinguishing between feature-off, invalid, and error states.
    ///
    /// - Returns: A `LoadResult` that the caller can pattern-match to decide UI behavior.
    ///   Returns `nil` only when the service itself cannot be initialized (should not happen).
    func loadDisplayableBundle() async -> LoadResult {
        do {
            return try await fetchAndResolve()
        } catch {
            logger.warning("Demo bundle load failed: \(error.localizedDescription)")
            return .failure(message: error.localizedDescription)
        }
    }

    /// Network + cache resolution with explicit errors (for tests / debugging).
    ///
    /// On a 401 response, `APIClient` will attempt a single token refresh and retry.
    /// The retried request will use the ETag from this service's local cache (if any)
    /// via `conditionalHeaders(ifNoneMatch:)`. If the cache is stale, the server
    /// returns a fresh payload and we update the cache with the new ETag. If the cache
    /// is current, the server returns 304 and we reuse the cached body.
    func fetchAndResolve() async throws -> LoadResult {
        let cached = cacheStore.load()
        let ifNoneMatch = cached?.etag

        let result = try await apiClient.requestConditional(
            APIEndpoint(
                path: "demo/journey",
                headers: conditionalHeaders(ifNoneMatch: ifNoneMatch)
            ),
            as: DemoJourneyBundle.self
        )

        switch result {
        case let .notModified(etag):
            guard let cached else {
                logger.warning("Demo bundle 304 but no cached body available")
                return .failure(message: "No cached body for 304 response")
            }
            let bundle = try decodeBundle(from: cached.responseBody)
            // Keep ETag if the server returned one.
            if let etag, etag != cached.etag {
                try? cacheStore.save(responseBody: cached.responseBody, etag: etag, bundle: bundle)
            }
            return validateOrNil(bundle)

        case let .value(bundle, etag, rawResponseBody):
            try cacheStore.save(responseBody: rawResponseBody, etag: etag, bundle: bundle)
            return validateOrNil(bundle)
        }
    }

    /// Decodes a raw `ApiResponse` body (for fixtures / cache).
    func decodeBundle(from responseBody: Data) throws -> DemoJourneyBundle {
        let wrapped = try decoder.decode(APIResponse<DemoJourneyBundle>.self, from: responseBody)
        guard wrapped.code == 0 else {
            throw APIError.business(code: wrapped.code, message: wrapped.message)
        }
        guard let data = wrapped.data else {
            throw APIError.noData
        }
        return data
    }

    /// Decodes the unwrapped Bundle JSON (Golden Snapshot shape).
    func decodeUnwrappedBundle(from data: Data) throws -> DemoJourneyBundle {
        try decoder.decode(DemoJourneyBundle.self, from: data)
    }

    func clearCache() {
        cacheStore.clear()
    }

    // MARK: - Private

    private func conditionalHeaders(ifNoneMatch: String?) -> [String: String] {
        guard let ifNoneMatch, !ifNoneMatch.isEmpty else { return [:] }
        return ["If-None-Match": ifNoneMatch]
    }

    /// Validates the bundle and returns the appropriate `LoadResult`.
    private func validateOrNil(_ bundle: DemoJourneyBundle) -> LoadResult {
        guard bundle.enabled else {
            return .featureOff
        }

        guard DemoJourneySchema.isSupported(bundle.schemaVersion) else {
            logger.warning("Demo bundle schemaVersion \(bundle.schemaVersion) is not supported")
            return .undisplayable(reason: "Unsupported schema version: \(bundle.schemaVersion)")
        }

        guard let scenes = bundle.scenes else {
            logger.warning("Demo bundle missing scenes payload")
            return .undisplayable(reason: "Missing scenes")
        }

        guard bundle.isDisplayable else {
            logger.warning("Demo bundle is not displayable (capabilities or scenes)")
            return .undisplayable(reason: "Bundle not displayable")
        }

        return .displayable(bundle)
    }

    // MARK: - Test Accessors

    /// Exposes validation logic for unit tests without performing network requests.
    static func validateResult(for bundle: DemoJourneyBundle) -> LoadResult {
        // Use a no-op service instance to access private validation logic.
        let service = DemoJourneyService(apiClient: APIClient(config: .development, session: .shared))
        return service.validateOrNil(bundle)
    }
}
