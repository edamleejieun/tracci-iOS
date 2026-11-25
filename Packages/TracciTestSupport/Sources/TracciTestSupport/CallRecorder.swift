import Foundation

/// Records method invocations on a test double for later assertion.
///
/// ```swift
/// let recorder = CallRecorder<String, String>()
/// recorder.record(method: "list", arguments: ["page=1"])
/// XCTAssertEqual(recorder.callCount(for: "list"), 1)
/// ```
public final class CallRecorder<MethodName: Hashable, Argument: Equatable>: @unchecked Sendable {
    public init() {}

    private let lock = NSLock()
    private var calls: [MethodName: [(arguments: [Argument], date: Date)]] = [:]

    public func record(method: MethodName, arguments: [Argument] = []) {
        lock.lock()
        defer { lock.unlock() }
        calls[method, default: []].append((arguments: arguments, date: Date()))
    }

    public func callCount(for method: MethodName) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls[method]?.count ?? 0
    }

    public func arguments(for method: MethodName, at index: Int) -> [Argument]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entries = calls[method], entries.indices.contains(index) else { return nil }
        return entries[index].arguments
    }

    public func allArguments(for method: MethodName) -> [[Argument]] {
        lock.lock()
        defer { lock.unlock() }
        return calls[method]?.map(\.arguments) ?? []
    }

    public func wasCalled(_ method: MethodName) -> Bool {
        callCount(for: method) > 0
    }

    public func wasNotCalled(_ method: MethodName) -> Bool {
        callCount(for: method) == 0
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        calls.removeAll()
    }
}
