/// The unit of business logic in SECA.
///
/// A `Node` is a plain Swift struct: it holds state as stored properties and
/// expresses mutations as `mutating` methods. The `@Node` macro adds the
/// protocol conformance and a default `init()` automatically.
///
/// ```swift
/// @Node
/// struct CounterNode {
///     enum Signal: SECA.Signal { case incremented(Int) }
///
///     var count = 0
///
///     mutating func increment() {
///         count += 1
///         emit(.incremented(count))
///     }
/// }
/// ```
///
/// ## Ownership model
///
/// A `Node` never holds a reference to its store. It is a pure value type
/// that knows nothing about concurrency or persistence. `NodeStore<N>` is
/// the actor that owns the node, applies mutations via `send { }`, and
/// broadcasts the results.
///
/// ## How `emit()` works
///
/// `emit()` routes signals through a task-local variable
/// (`NodeContext._emitHandler`) that `NodeStore.send(_:)` installs before
/// calling your mutation closure — the same pattern SwiftUI uses for
/// `@Environment`. The node struct holds no reference to its store.
///
/// Consequence: `emit()` is a no-op (with a debug warning) when called
/// outside a `send { }` context. This is intentional — nodes are pure
/// values with no store coupling.
///
/// ## Mutation methods must be `mutating`
///
/// Because `NodeStore` passes the node as an `inout` value to your closure,
/// any method that modifies stored properties **must** be marked `mutating`.
/// The `@Node` macro warns at compile-time if a method calls `emit()` without
/// `mutating` — non-mutating calls still compile, but state changes inside
/// that method won't be persisted by the store.
public protocol Node: Sendable {
    /// The signals this node can broadcast to other nodes or listeners.
    associatedtype Signal: Sendable

    /// Nodes must be default-initializable so `NodeStore` can create them.
    init()
}

extension Node {
    /// Broadcasts a signal to all current listeners of this node's store.
    ///
    /// Call `emit()` from inside a `mutating` method to notify other parts of
    /// the app that a meaningful event occurred. Signals are delivered
    /// synchronously to all subscribers before `send(_:)` returns.
    ///
    /// **Routing mechanism**: `emit()` reads a task-local variable
    /// (`NodeContext._emitHandler`) installed by `NodeStore.send(_:)`.
    /// It is a no-op — with a debug warning — when called outside that context.
    ///
    /// ```swift
    /// mutating func increment() {
    ///     count += 1
    ///     emit(.incremented(count))   // reaches all store.signals subscribers
    /// }
    /// ```
    public func emit(_ signal: Signal) {
        guard let handler = NodeContext._emitHandler else {
            #if DEBUG
            print(
                "[SECA] ⚠️ emit() called outside NodeStore.send(_:) on \(Self.self) "
                + "— signal '\(signal)' was dropped. "
                + "Only call emit() from a mutating method invoked via send { }."
            )
            #endif
            return
        }
        handler(signal)
    }
}
