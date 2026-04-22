import Foundation

/// Thread-safe actor that owns a `Node`'s value, broadcasts its signals to
/// multiple subscribers, and records every mutation in a `Timeline`.
///
/// ```swift
/// let store = NodeStore<CounterNode>()
///
/// // Subscribe to signals (inter-node events)
/// Task { for await signal in store.signals.subscribe() { print(signal) } }
///
/// // Subscribe to state (for @Observable observers and debugging)
/// Task { for await state in store.stateStream.subscribe() { print(state.count) } }
///
/// // Mutate
/// await store.send { $0.increment() }
///
/// // Time-travel
/// await store.undo()
/// await store.redo()
/// await store.replay(to: Date().addingTimeInterval(-60))
///
/// // Export history
/// let snap = store.timeline.snapshot()
/// ```
public actor NodeStore<N: Node> {

    // MARK: State

    /// The current value of the node.
    public private(set) var state: N

    /// The node's default-initialised state — available synchronously (`nonisolated`).
    ///
    /// `NodeObserver` uses this to seed its `@Observable` mirror without an `await`.
    /// If the store has already been mutated before the observer connects, the observer
    /// will receive the correct state on the very next `send` via `stateStream`.
    public nonisolated let initialState: N

    // MARK: Streams

    /// Broadcast stream for **signals** emitted during mutations.
    ///
    /// Signals carry semantic events (`.incremented(5)`, `.reset`) and are the
    /// backbone of inter-node communication via `SignalBus`.
    ///
    /// Multiple components can each call `.subscribe()` to get an independent stream.
    public nonisolated let signals: SignalStream<N.Signal>

    /// Broadcast stream for **full state snapshots** after every mutation.
    ///
    /// Subscribe here when you need to react to every state change regardless of
    /// whether the node chose to emit a signal. `NodeObserver` uses this stream to
    /// keep its `@Observable` `state` mirror up-to-date.
    public nonisolated let stateStream: SignalStream<N>

    // MARK: Timeline

    /// Full mutation history. Use for time-travel, snapshots, and export.
    public nonisolated let timeline: Timeline<N>

    // MARK: Init

    /// Creates a new store.
    /// - Parameter maxTimelineCapacity: Maximum number of mutation snapshots to retain.
    ///   Oldest events are evicted when the limit is reached. Pass `0` for unlimited.
    ///   Defaults to `500`.
    public init(maxTimelineCapacity: Int = 500) {
        let initial  = N()
        state        = initial
        initialState = initial
        signals      = SignalStream()
        stateStream  = SignalStream()
        timeline     = Timeline(genesis: initial, maxCapacity: maxTimelineCapacity)
    }

    // MARK: Mutations

    /// Applies a synchronous mutation to the node.
    ///
    /// - The closure receives an `inout` reference to the current state.
    /// - Any `emit()` calls are broadcast via `signals` (synchronous, no await).
    /// - The resulting state is broadcast via `stateStream` and recorded in `timeline`.
    public func send(_ mutation: @Sendable (inout N) -> Void) {
        let signalStream = signals
        let stateStr     = stateStream
        NodeContext.withEmitHandler({ anySignal in
            guard let signal = anySignal as? N.Signal else {
                #if DEBUG
                assertionFailure(
                    "[SECA] Internal type mismatch in emit(): received \(type(of: anySignal)), "
                    + "expected \(N.Signal.self). This is a SECA bug — please file an issue."
                )
                #endif
                return
            }
            signalStream.yield(signal)
        }) {
            mutation(&state)
        }
        stateStr.yield(state)
        timeline.record(state)
    }

    // MARK: Time-travel

    /// Reverts to the state before the last mutation.
    /// Returns the restored state, or `nil` if already at genesis.
    @discardableResult
    public func undo() -> N? {
        guard let previous = timeline.undoState() else { return nil }
        state = previous
        stateStream.yield(state)
        return previous
    }

    /// Re-applies the last undone mutation.
    /// Returns the restored state, or `nil` if already at the latest event.
    @discardableResult
    public func redo() -> N? {
        guard let next = timeline.redoState() else { return nil }
        state = next
        stateStream.yield(state)
        return next
    }

    /// Restores the state recorded at or before `date` and positions the undo/redo
    /// cursor at that event so subsequent `undo()`/`redo()` calls remain consistent.
    ///
    /// If no event precedes `date` the call is a no-op.
    public func replay(to date: Date) {
        if let past = timeline.seekCursor(to: date) {
            state = past
            stateStream.yield(state)
        }
    }

    // MARK: Subscription helpers

    /// Opens a state subscription and atomically captures the current state
    /// under the same actor isolation — no gap between the two operations.
    ///
    /// `NodeObserver` uses this to seed its `@Observable` mirror with the true
    /// current state while guaranteeing it won't miss any mutation that fires
    /// between subscription and first observation.
    public func subscribeWithCurrentState() -> (state: N, stream: AsyncStream<N>) {
        let stream = stateStream.subscribe()
        return (state, stream)
    }

    // MARK: Effects

    /// Schedules an async side-effect against this store.
    ///
    /// Use for ad-hoc effects (network, timers, persistence) triggered from a
    /// signal handler or a view. For app-level flows, prefer `CommandBus` whose
    /// handlers are already async.
    ///
    /// - Returns: The underlying `Task` — discard or `await` its value as needed.
    @discardableResult
    public nonisolated func task(
        _ body: @Sendable @escaping () async -> Void
    ) -> Task<Void, Never> {
        Task { await body() }
    }

    // MARK: Lifecycle

    deinit {
        signals.finish()
        stateStream.finish()
    }
}
