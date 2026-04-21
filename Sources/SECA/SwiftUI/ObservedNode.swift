#if canImport(SwiftUI)
import SwiftUI
import Observation

// MARK: - NodeObserver

/// A `@MainActor @Observable` mirror of a `NodeStore`'s state.
///
/// `NodeObserver` is the primary type you interact with in SwiftUI views. It keeps
/// its `state` property up-to-date by subscribing to `NodeStore.stateStream`, and
/// because it uses `@Observable`, SwiftUI automatically re-renders only the views
/// that accessed a property that actually changed.
///
/// **Mutations without state changes that don't emit a signal still update the view** —
/// `stateStream` fires after every `send`, not only when a signal is emitted.
///
/// ```swift
/// struct CounterView: View {
///     @ObservedNode var counter: NodeObserver<CounterNode>
///
///     var body: some View {
///         VStack {
///             Text("Count: \(counter.state.count)")
///             Button("Increment") {
///                 counter.send { $0.increment() }
///             }
///         }
///     }
/// }
///
/// // Parent passes the store:
/// CounterView(counter: appStore.counter)
/// ```
@MainActor
@Observable
public final class NodeObserver<N: Node> {

    // MARK: State — tracked by @Observable

    /// The latest mirrored state. Accessed in SwiftUI `body` to drive re-renders.
    public private(set) var state: N

    // MARK: Store

    /// The underlying actor store. Use for operations that don't require observation
    /// (e.g. accessing `timeline`, subscribing to `signals` for inter-node wiring).
    public let store: NodeStore<N>

    // MARK: Private

    // @ObservationIgnored prevents @Observable from wrapping this with
    // @ObservationTracked (which would reject nonisolated(unsafe)).
    // nonisolated(unsafe) lets deinit (which is nonisolated in Swift 6)
    // cancel the task without an isolation error. Task is Sendable and cancel
    // is safe to call from any context; init() is the sole writer.
    @ObservationIgnored nonisolated(unsafe) private var stateTask: Task<Void, Never>?

    // MARK: Init

    public init(store: NodeStore<N>) {
        self.store = store
        // Seed synchronously from the store's nonisolated initialState.
        // The very next send() will broadcast via stateStream, closing any gap.
        self.state = store.initialState
        let stream = store.stateStream.subscribe()
        stateTask = Task { @MainActor [weak self] in
            for await newState in stream {
                self?.state = newState
            }
        }
    }

    // MARK: Mutations

    /// Dispatches a synchronous mutation to the underlying store.
    ///
    /// The call returns immediately; the mutation runs on the store's actor and the
    /// resulting state is mirrored back to `state` via `stateStream`.
    public func send(_ mutation: @Sendable @escaping (inout N) -> Void) {
        let store = self.store
        Task { await store.send(mutation) }
    }

    deinit { stateTask?.cancel() }
}

// MARK: - @ObservedNode property wrapper

/// A SwiftUI property wrapper that creates a `NodeObserver<N>` and makes it
/// available inside a view, triggering re-renders whenever `state` changes.
///
/// Initialise with the `NodeStore` you want to observe — typically passed from a
/// parent view or resolved from a `GlobalStore`:
///
/// ```swift
/// struct CounterView: View {
///     @ObservedNode var counter: NodeObserver<CounterNode>
///
///     init(store: NodeStore<CounterNode>) {
///         _counter = ObservedNode(store)
///     }
///
///     var body: some View {
///         Text("Count: \(counter.state.count)")
///         Button("+") { counter.send { $0.increment() } }
///     }
/// }
/// ```
///
/// > Note: The initialiser takes a `NodeStore<N>` (the actor), but `wrappedValue`
/// > returns a `NodeObserver<N>` (the `@Observable` mirror). The distinction is
/// > intentional: views always work with the observer; stores handle async mutations.
@MainActor
@propertyWrapper
public struct ObservedNode<N: Node>: DynamicProperty {

    @State private var observer: NodeObserver<N>

    /// Creates the wrapper from an underlying `NodeStore`.
    ///
    /// In a view's `init`, write `_counter = ObservedNode(store)`.
    /// At the call site you can also write `@ObservedNode(store) var counter`.
    public init(_ store: NodeStore<N>) {
        _observer = State(initialValue: NodeObserver(store: store))
    }

    /// The `NodeObserver` — use `wrappedValue.state` for reading and
    /// `wrappedValue.send { }` for mutations.
    public var wrappedValue: NodeObserver<N> { observer }
}
#endif
