/// The unit of business logic in SECA.
///
/// Define your state as a plain Swift struct conforming to `Node`.
/// Use the `@Node` macro (v0.5) to remove boilerplate; until then,
/// mark mutation methods as `mutating` and call `emit()` freely.
///
/// ```swift
/// struct CounterNode: Node {
///     enum Signal: Sendable { case incremented(Int) }
///
///     var count = 0
///
///     mutating func increment() {
///         count += 1
///         emit(.incremented(count))
///     }
/// }
/// ```
public protocol Node: Sendable {
    /// The signals this node can broadcast to other nodes or listeners.
    associatedtype Signal: Sendable

    /// Nodes must be default-initializable so `NodeStore` can create them.
    init()
}

extension Node {
    /// Broadcasts a signal to all current listeners.
    ///
    /// Only has effect when called from within a `NodeStore.send(_:)` mutation.
    /// In debug builds, calling `emit` outside that context triggers a runtime
    /// warning so the mistake is surfaced immediately during development.
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
