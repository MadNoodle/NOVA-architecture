// MARK: - NodeCollection

/// A keyed, ordered collection of `NodeStore<N>` instances.
///
/// `NodeCollection` is the SECA composability primitive for dynamic lists —
/// the equivalent of TCA's `Scope` applied to a collection of nodes. Each
/// item has an independent `NodeStore` with its own state, signals, and timeline.
///
/// ```swift
/// // In a GlobalStore:
/// let todos = NodeCollection<TodoNode>()
///
/// // Add / remove stores by stable ID:
/// let store = todos.add(id: uuid)
/// todos.remove(id: uuid)
///
/// // Forward all child signals to a handler:
/// await todos.observeAll { signal in
///     // react to any TodoNode.Signal
/// }
/// ```
///
/// For SwiftUI, pair with `NodeCollectionObserver` which mirrors the collection's
/// `ids` as an `@Observable` property so `ForEach` re-renders automatically.
///
/// - Note: `NodeCollection` is an `actor` — all mutations are async and
///   thread-safe. Use `NodeCollectionObserver` for synchronous SwiftUI access.
public actor NodeCollection<N: Node> {

    // MARK: Snapshot type

    /// An immutable snapshot of the collection's current contents.
    ///
    /// `@unchecked Sendable` because `AnyHashable` is not formally `Sendable`
    /// in Swift 6, but all IDs in this collection are constrained to
    /// `Hashable & Sendable` at creation time, and `NodeStore` is an actor
    /// (hence `Sendable`). The struct is immutable and the actor serialises
    /// all writes, so this is safe.
    public struct Snapshot: @unchecked Sendable {
        public let ids: [AnyHashable]
        public let stores: [AnyHashable: NodeStore<N>]
    }

    // MARK: State

    private var stores: [AnyHashable: NodeStore<N>] = [:]

    /// Ordered list of IDs, maintained in insertion order.
    private var orderedIDs: [AnyHashable] = []

    // MARK: Change notifications

    /// Fires `Void` after every `add` or `remove`.
    ///
    /// `NodeCollectionObserver` subscribes here and fetches a fresh `Snapshot`
    /// on each notification. `SignalStream<Void>` is `nonisolated` because
    /// `Void` is `Sendable` and `SignalStream` is `@unchecked Sendable`.
    public nonisolated let collectionStream: SignalStream<Void> = SignalStream()

    // MARK: Init

    public init() {}

    // MARK: CRUD

    /// Returns the existing store for `id`, or creates a new one if absent.
    ///
    /// Calling `add(id:)` with the same ID more than once is idempotent —
    /// it returns the same `NodeStore` every time.
    @discardableResult
    public func add<ID: Hashable & Sendable>(id: ID) -> NodeStore<N> {
        let key = AnyHashable(id)
        if let existing = stores[key] { return existing }
        let store = NodeStore<N>()
        stores[key] = store
        orderedIDs.append(key)
        collectionStream.yield(())
        if let handler = forwardingHandler {
            startForwarding(store, id: key, handler: handler)
        }
        return store
    }

    /// Removes the store for `id`. No-op if `id` is not present.
    public func remove<ID: Hashable & Sendable>(id: ID) {
        let key = AnyHashable(id)
        guard let store = stores.removeValue(forKey: key) else { return }
        orderedIDs.removeAll { $0 == key }
        let storeKey = ObjectIdentifier(store)
        forwardingTasks[storeKey]?.cancel()
        forwardingTasks.removeValue(forKey: storeKey)
        collectionStream.yield(())
    }

    /// Returns the store for `id`, or `nil` if not present.
    public subscript<ID: Hashable & Sendable>(id: ID) -> NodeStore<N>? {
        stores[AnyHashable(id)]
    }

    /// Returns an immutable snapshot of the current IDs and stores.
    ///
    /// Used by `NodeCollectionObserver` to seed its local cache under actor
    /// isolation — both values are captured atomically in the same actor hop.
    public func currentSnapshot() -> Snapshot {
        Snapshot(ids: orderedIDs, stores: stores)
    }

    // MARK: Signal forwarding

    // Keyed by ObjectIdentifier(store) — both ObjectIdentifier and Task are Sendable,
    // making this dict Sendable and accessible from nonisolated deinit.
    private var forwardingTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var forwardingHandler: (@Sendable (N.Signal) async -> Void)?

    /// Forwards signals from every node in the collection through `handler`.
    ///
    /// Stores added via `add(id:)` **after** this call are automatically wired —
    /// the handler is stored and applied to each new store on creation.
    ///
    /// Calling `observeAll` again replaces the previous handler and re-wires
    /// all existing stores.
    ///
    /// ```swift
    /// await todos.observeAll { signal in
    ///     if case .completed(let id) = signal {
    ///         await analytics.track(.todoCompleted(id))
    ///     }
    /// }
    /// ```
    public func observeAll(handler: @Sendable @escaping (N.Signal) async -> Void) {
        for task in forwardingTasks.values { task.cancel() }
        forwardingTasks.removeAll()
        forwardingHandler = handler
        for (key, store) in stores {
            startForwarding(store, id: key, handler: handler)
        }
    }

    private func startForwarding(
        _ store: NodeStore<N>,
        id: AnyHashable,
        handler: @Sendable @escaping (N.Signal) async -> Void
    ) {
        let storeKey = ObjectIdentifier(store)
        forwardingTasks[storeKey]?.cancel()
        let sub = store.signals.subscribe()
        forwardingTasks[storeKey] = Task {
            for await signal in sub {
                guard !Task.isCancelled else { break }
                await handler(signal)
            }
        }
    }

    // MARK: Lifecycle

    deinit {
        for task in forwardingTasks.values { task.cancel() }
        collectionStream.finish()
    }
}

// MARK: - NodeCollectionObserver

#if canImport(SwiftUI)
import Observation

/// A `@MainActor @Observable` mirror of a `NodeCollection`.
///
/// Use this in SwiftUI views — `ids` is tracked by `@Observable` so `ForEach`
/// automatically re-renders when nodes are added or removed.
///
/// ```swift
/// // In GlobalStore:
/// let todos   = NodeCollection<TodoNode>()
/// let todosUI = NodeCollectionObserver(collection: todos)
///
/// // In a view:
/// ForEach(appStore.todosUI.ids, id: \.self) { id in
///     if let store = appStore.todosUI[id] {
///         TodoRow(store: store)
///     }
/// }
/// ```
///
/// `NodeCollection` (the `actor`) is the source of truth; `NodeCollectionObserver`
/// is a read-only mirror — mutate the collection through the actor methods.
@MainActor
@Observable
public final class NodeCollectionObserver<N: Node> {

    // MARK: Observable state

    /// Current IDs in insertion order. SwiftUI observes this automatically.
    public private(set) var ids: [AnyHashable] = []

    // MARK: References

    /// The underlying actor collection.
    public let collection: NodeCollection<N>

    // MARK: Private

    // nonisolated(unsafe) + @ObservationIgnored: same pattern as NodeObserver.
    // syncTask is written once in init and cancelled in deinit; both operations
    // are safe from nonisolated contexts (Task.cancel() is thread-safe).
    @ObservationIgnored nonisolated(unsafe) private var syncTask: Task<Void, Never>?

    // Local store snapshot — @unchecked Sendable justified: all values are actors or
    // were created from Sendable IDs; snapshot is immutable after assignment.
    @ObservationIgnored private var storeSnapshot: NodeCollection<N>.Snapshot?

    // MARK: Init

    public init(collection: NodeCollection<N>) {
        self.collection = collection
        let stream = collection.collectionStream.subscribe()
        syncTask = Task { @MainActor [weak self, collection] in
            // Seed with current state under actor isolation (atomic snapshot)
            let initial = await collection.currentSnapshot()
            self?.ids = initial.ids
            self?.storeSnapshot = initial
            // Receive future change notifications
            for await _ in stream {
                let snapshot = await collection.currentSnapshot()
                self?.ids = snapshot.ids
                self?.storeSnapshot = snapshot
            }
        }
    }

    // MARK: Access

    /// Returns the store for `id`, or `nil` if not present.
    ///
    /// Uses a local snapshot updated on every collection change — no `await` needed.
    public subscript<ID: Hashable & Sendable>(id: ID) -> NodeStore<N>? {
        storeSnapshot?.stores[AnyHashable(id)]
    }

    deinit { syncTask?.cancel() }
}
#endif
