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
        lock.withLock {
            for cont in continuations.values { cont.yield(signal) }
        }
    }

    // MARK: Lifecycle

    /// Terminates all active subscriber streams.
    public func finish() {
        lock.withLock {
            for cont in continuations.values { cont.finish() }
            continuations.removeAll()
        }
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
