import Foundation

/// A thread-safe broadcast stream: every `subscribe()` call returns an independent
/// `AsyncStream` that receives all future signals emitted via `yield(_:)`.
///
/// Unlike `AsyncStream` (single consumer), `SignalStream` fans out every signal to
/// all active subscribers simultaneously. Subscription and emission are synchronous —
/// no `await` required — making it safe to call from actor methods.
///
/// ```swift
/// let stream = SignalStream<Int>()
///
/// let sub1 = stream.subscribe()
/// let sub2 = stream.subscribe()
///
/// stream.yield(42)   // both sub1 and sub2 receive 42
/// ```
///
/// Subscribers are cleaned up automatically when their `AsyncStream` terminates.
public final class SignalStream<S: Sendable>: @unchecked Sendable {

    private var continuations: [UUID: AsyncStream<S>.Continuation] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: Subscription

    /// Returns a new `AsyncStream` that will receive all future signals.
    ///
    /// Each call creates an independent subscription. Signals emitted before
    /// this call are **not** replayed.
    public func subscribe() -> AsyncStream<S> {
        let id = UUID()
        // Acquire lock for the entire setup to prevent a signal racing
        // between stream creation and continuation registration.
        return lock.withLock {
            var cont: AsyncStream<S>.Continuation!
            let stream = AsyncStream<S> { continuation in
                continuation.onTermination = { [weak self] _ in
                    self?.removeSubscriber(id)
                }
                cont = continuation
            }
            continuations[id] = cont
            return stream
        }
    }

    // MARK: Emission

    /// Delivers `signal` to every active subscriber.
    public func yield(_ signal: S) {
        // Snapshot under lock, then call continuations outside the lock.
        // Calling continuation.yield() while holding the lock risks deadlock:
        // on buffer policies that drop values synchronously, onTermination can
        // fire on the same thread → removeSubscriber tries lock.withLock →
        // NSLock self-deadlock. Snapshot + release first eliminates that path.
        let snapshot = lock.withLock { Array(continuations.values) }
        for cont in snapshot { cont.yield(signal) }
    }

    // MARK: Lifecycle

    /// Terminates all active subscriber streams.
    public func finish() {
        // Clear the map under lock, then finish outside the lock (same deadlock
        // rationale as yield: onTermination can fire synchronously on finish()).
        let snapshot = lock.withLock {
            let conts = Array(continuations.values)
            continuations.removeAll()
            return conts
        }
        for cont in snapshot { cont.finish() }
    }

    /// Number of active subscribers (useful for testing / diagnostics).
    public var subscriberCount: Int {
        lock.withLock { continuations.count }
    }

    // MARK: Private

    private func removeSubscriber(_ id: UUID) {
        lock.withLock { _ = continuations.removeValue(forKey: id) }
    }

    deinit { finish() }
}
