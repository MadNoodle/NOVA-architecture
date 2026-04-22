import Foundation

/// A bag that holds routing `Task`s and cancels them all on `deinit`.
///
/// Use in a `GlobalStore` to ensure signal-routing tasks are cancelled when
/// the store is deallocated — critical in tests where stores are created and
/// destroyed frequently.
///
/// ```swift
/// final class AppStore: GlobalStore {
///     let counter = NodeStore<CounterNode>()
///     let log     = NodeStore<LogNode>()
///     private let _wires = WireTasks()
///
///     init() {
///         _wires += log.autoWire(to: counter)
///         StoreRegistry.shared.register(self)
///     }
/// }
/// ```
public final class WireTasks: @unchecked Sendable {

    private var tasks: [Task<Void, Never>] = []
    private let lock = NSLock()

    public init() {}

    /// Adds a task to the bag.
    public func add(_ task: Task<Void, Never>) {
        lock.withLock { tasks.append(task) }
    }

    deinit {
        // Copy under lock, then cancel outside to avoid holding lock during cancellation.
        let snapshot = lock.withLock { tasks }
        snapshot.forEach { $0.cancel() }
    }
}

/// Appends a routing task to `lhs`.
public func += (lhs: WireTasks, rhs: Task<Void, Never>) {
    lhs.add(rhs)
}
