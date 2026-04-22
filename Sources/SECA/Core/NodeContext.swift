/// Execution context for a `Node` mutation — implementation detail.
///
/// `NodeContext` is the invisible bridge between `Node.emit(_:)` and
/// `NodeStore.send(_:)`. It uses Swift's `@TaskLocal` storage to install
/// a signal handler for the duration of a mutation, then restore the
/// previous value automatically on exit.
///
/// ## Why task-local storage?
///
/// A `Node` is a pure value type (struct) with no reference to its owning
/// store. Passing the emit handler as a parameter to every mutation method
/// would pollute the user-facing API. Instead, `NodeStore.send(_:)` installs
/// the handler as a task-local before calling the mutation closure — the same
/// technique SwiftUI uses for `@Environment` and that Swift's structured
/// concurrency uses for `Task.currentPriority`.
///
/// ## Call sequence for a single `send`
///
/// ```
/// NodeStore.send { $0.increment() }
///   └─ NodeContext.withEmitHandler(signalHandler) {
///         mutation(&state)          // calls $0.increment()
///           └─ emit(.incremented)   // reads _emitHandler → signalHandler
///      }
///   └─ stateStream.yield(state)
///   └─ timeline.record(state)
/// ```
///
/// ## Thread safety
///
/// Task-locals are scoped to the current task and are never shared across
/// tasks. `NodeStore` is an actor, so all `send` calls are serialised —
/// there is no concurrent access to `_emitHandler`.
///
/// > This type is an internal implementation detail. User-facing API is
/// > `Node.emit(_:)` and `NodeStore.send(_:)`.
public enum NodeContext {

    /// Task-local emit handler installed by `NodeStore` before each mutation.
    ///
    /// `Any` erases the concrete `Signal` type so this storage can be shared
    /// across all `Node` specialisations without generics. `NodeStore.send`
    /// re-casts to `N.Signal` on arrival and `assertionFailure`s in DEBUG if
    /// the cast fails (which would indicate a framework bug, not user error).
    @TaskLocal static var _emitHandler: (@Sendable (Any) -> Void)?

    /// Runs `body` with `handler` installed as the active emit sink.
    ///
    /// `@TaskLocal.withValue` guarantees the previous value is restored when
    /// `body` returns or throws — even across `await` suspension points
    /// (though `body` here is synchronous by design).
    static func withEmitHandler(
        _ handler: @Sendable @escaping (Any) -> Void,
        perform body: () -> Void
    ) {
        NodeContext.$_emitHandler.withValue(handler, operation: body)
    }
}
