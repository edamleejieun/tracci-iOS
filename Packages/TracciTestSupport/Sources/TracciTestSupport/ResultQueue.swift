import Foundation

/// Thread-safe queue that accumulates async results in arrival order.
///
/// Useful for characterizing concurrent reload / generation-discard behaviour
/// without binding tests to a specific View hierarchy.
///
/// ```swift
/// let queue = ResultQueue<String, Error>()
/// Task { queue.append(.success("a")) }
/// let results = try await queue.awaitAll(count: 1, timeout: 1.0)
/// ```
public final class ResultQueue<Success, Failure: Error>: @unchecked Sendable {
    public init() {}

    private let lock = NSLock()
    private var results: [Result<Success, Failure>] = []

    public func append(_ result: Result<Success, Failure>) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }

    public func appendSuccess(_ value: Success) {
        append(.success(value))
    }

    public func appendFailure(_ error: Failure) {
        append(.failure(error))
    }

    /// Wait until at least `count` results arrive, then return a snapshot.
    @discardableResult
    public func awaitAll(count: Int, timeout: TimeInterval = 2.0) async throws -> [Result<Success, Failure>] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            let snapshot = results
            lock.unlock()

            if snapshot.count >= count {
                return snapshot
            }
            if Date() >= deadline {
                throw TimeoutError(expected: count, received: snapshot.count)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Wait until at least `count` successes arrive (failures still recorded).
    public func awaitSuccesses(count: Int, timeout: TimeInterval = 2.0) async throws -> [Success] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            lock.lock()
            let snapshot = results
            lock.unlock()

            let successes = snapshot.compactMap { try? $0.get() }
            if successes.count >= count {
                return successes
            }
            if Date() >= deadline {
                let failureCount = snapshot.count - successes.count
                throw TimeoutError(expected: count, received: successes.count, failures: failureCount)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    public func reset() {
        lock.lock()
        results.removeAll()
        lock.unlock()
    }

    public var currentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return results.count
    }
}

public struct TimeoutError: Error, Equatable {
    let expected: Int
    let received: Int
    let failures: Int?

    public init(expected: Int, received: Int, failures: Int? = nil) {
        self.expected = expected
        self.received = received
        self.failures = failures
    }

    public var localizedDescription: String {
        if let failures {
            return "Timeout: expected \(expected) successes, received \(received) with \(failures) failures"
        }
        return "Timeout: expected \(expected) results, received \(received)"
    }
}
