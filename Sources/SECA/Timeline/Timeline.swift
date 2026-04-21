import Foundation

/// Records every mutation applied to a `NodeStore` and enables time-travel.
///
/// Each `NodeStore` owns one `Timeline`. Access it via `store.timeline`:
///
/// ```swift
/// // Inspect history
/// store.timeline.events         // all recorded events
/// store.timeline.canUndo        // true if undo is available
///
/// // Time-travel (call on NodeStore, not Timeline directly)
/// await store.undo()            // revert last mutation
/// await store.redo()            // re-apply last undone mutation
/// await store.replay(to: date)  // jump to a specific point in time
///
/// // Export
/// let snap = store.timeline.snapshot()
/// ```
///
/// `Timeline` is thread-safe: all state is protected by an `NSLock`.
///
/// ## Memory management
/// Pass `maxCapacity` to cap how many events are retained. Once the limit is
/// reached the oldest events are evicted (ring-buffer semantics). A value of
/// `0` means unlimited — use with care in long-running apps.
public final class Timeline<N: Node>: @unchecked Sendable {

    // MARK: State

    /// The node's state before any mutation was recorded. Used by `undo()` to
    /// revert past the first event back to "blank slate".
    private let genesis: N
    private var _events: [TimelineEvent<N>] = []
    /// Index of the currently visible event.
    /// -1  → at genesis (before any event)
    ///  0  → first event
    ///  n  → nth event
    private var cursor: Int = -1
    private let lock = NSLock()

    /// Maximum number of events to keep. `0` means unlimited.
    public let maxCapacity: Int

    // MARK: Init

    init(genesis: N, maxCapacity: Int = 500) {
        self.genesis = genesis
        self.maxCapacity = maxCapacity
    }

    // MARK: Recording (called by NodeStore)

    /// Appends a new event for `state`. Discards any redo branch that existed.
    /// If `maxCapacity > 0` and the limit is exceeded, the oldest events are evicted.
    func record(_ state: N) {
        lock.withLock {
            // Truncate everything after cursor (redo branch)
            if cursor < _events.count - 1 {
                _events = Array(_events.prefix(cursor + 1))
            }
            _events.append(TimelineEvent(id: UUID(), timestamp: Date(), state: state))
            cursor = _events.count - 1

            // Evict oldest events when over capacity
            if maxCapacity > 0 && _events.count > maxCapacity {
                let excess = _events.count - maxCapacity
                _events.removeFirst(excess)
                // Shift cursor; clamp to -1 when all events before cursor were evicted
                cursor = max(-1, cursor - excess)
            }
        }
    }

    // MARK: Time-travel helpers (called by NodeStore)

    /// Moves cursor one step back and returns the restored state, or `nil` if already at genesis.
    ///
    /// When `cursor == 0` (first event), returns `genesis` (the state before any mutation).
    func undoState() -> N? {
        lock.withLock {
            guard cursor >= 0 else { return nil }
            if cursor == 0 {
                cursor = -1
                return genesis
            }
            cursor -= 1
            return _events[cursor].state
        }
    }

    /// Moves cursor one step forward and returns the restored state, or `nil` if at the end.
    func redoState() -> N? {
        lock.withLock {
            guard cursor < _events.count - 1 else { return nil }
            cursor += 1
            return _events[cursor].state
        }
    }

    /// Returns the state of the most recent event recorded at or before `date`, without
    /// moving the cursor (non-destructive lookup). Use for snapshots and read-only inspection.
    func stateAt(_ date: Date) -> N? {
        lock.withLock {
            _events.last(where: { $0.timestamp <= date })?.state
        }
    }

    /// Moves the cursor to the most recent event recorded at or before `date` and returns
    /// its state. Unlike `stateAt(_:)`, this **does** update the undo/redo position so that
    /// subsequent `undo()`/`redo()` calls are consistent with the replayed state.
    ///
    /// Returns `nil` when no event precedes `date` (cursor is unchanged in that case).
    func seekCursor(to date: Date) -> N? {
        lock.withLock {
            guard let idx = _events.lastIndex(where: { $0.timestamp <= date }) else {
                return nil
            }
            cursor = idx
            return _events[idx].state
        }
    }

    // MARK: Public read-only interface

    /// All recorded events in chronological order.
    public var events: [TimelineEvent<N>] {
        lock.withLock { _events }
    }

    /// `true` when there is at least one earlier state to revert to (including genesis).
    public var canUndo: Bool {
        lock.withLock { cursor >= 0 }
    }

    /// `true` when there is at least one later state to re-apply.
    public var canRedo: Bool {
        lock.withLock { cursor < _events.count - 1 }
    }

    /// The number of recorded events.
    public var count: Int {
        lock.withLock { _events.count }
    }

    /// Exports the current history as an immutable `Snapshot`.
    public func snapshot() -> Snapshot<N> {
        lock.withLock { Snapshot(events: _events) }
    }
}
