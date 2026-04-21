/// Execution context for a Node mutation.
///
/// Uses Swift's task-local storage to route `emit()` calls from inside
/// a mutation closure back to the owning `NodeStore` — without requiring
/// nodes to hold any reference to the store.
///
/// This type is an implementation detail. User-facing API is `Node.emit(_:)`
/// and `NodeStore.send(_:)`.
public enum NodeContext {

    /// Task-local emit handler installed by `NodeStore` before each mutation.
    /// `Any` erases the concrete `Signal` type; `NodeStore` re-casts on arrival.
    @TaskLocal static var _emitHandler: (@Sendable (Any) -> Void)?

    /// Runs `body` with `handler` active as the current emit sink.
    /// Restores the previous handler (if any) on exit.
    static func withEmitHandler(
        _ handler: @Sendable @escaping (Any) -> Void,
        perform body: () -> Void
    ) {
        NodeContext.$_emitHandler.withValue(handler, operation: body)
    }
}
