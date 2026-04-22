import Foundation

/// A property wrapper that defers `NodeStore` creation until first access.
///
/// Use inside a `GlobalStore` for nodes that are expensive to initialise or
/// only needed by a subset of the app's screens:
///
/// ```swift
/// final class AppStore: GlobalStore {
///     let core     = NodeStore<CoreNode>()   // always created
///     @LazyNode var premium: NodeStore<PremiumNode>  // created on first access
/// }
/// ```
///
/// The `NodeStore` is created **at most once**; all subsequent accesses return
/// the same instance. Thread-safe via `NSLock`.
@propertyWrapper
public final class LazyNode<N: Node>: @unchecked Sendable {

    private var _store: NodeStore<N>?
    private let lock = NSLock()

    public init() {}

    public var wrappedValue: NodeStore<N> {
        lock.withLock {
            if _store == nil { _store = NodeStore<N>() }
            return _store!
        }
    }

    /// True if the `NodeStore` has been created; false if it is still pending.
    public var isLoaded: Bool {
        lock.withLock { _store != nil }
    }

    /// Provides access to the wrapper itself (e.g. `store.$premium.isLoaded`).
    public var projectedValue: LazyNode<N> { self }
}
