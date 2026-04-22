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
        // This may be stale if the store was mutated before this observer
        // connected, but it will be corrected on the very next await below.
        self.state = store.initialState
        stateTask = Task { @MainActor [weak self, store] in
            // subscribeWithCurrentState() is an actor method: it opens the
            // subscription AND captures the current state under the same actor
            // isolation — no gap between the two operations. Any mutation that
            // fires while this Task is starting will be caught by the stream.
            let (current, stream) = await store.subscribeWithCurrentState()
            self?.state = current
            for await newState in stream {
                self?.state = newState
            }
        }
    }

    // MARK: Mutations

    /// Dispatches a synchronous mutation to the underlying store.
    ///
    /// Returns the underlying `Task` so callers can optionally `await` its
    /// completion (e.g. `await observer.send { $0.load() }.value`).
    /// The `@discardableResult` keeps existing fire-and-forget call sites unchanged.
    @discardableResult
    public func send(_ mutation: @Sendable @escaping (inout N) -> Void) -> Task<Void, Never> {
        let store = self.store
        return Task { await store.send(mutation) }
    }

    /// Async overload — use inside `.task { }` blocks or other `async` contexts.
    ///
    /// Swift disambiguates between the two `send` overloads via the presence of
    /// `await` at the call site: no `await` → sync (returns Task),
    /// `await` → this async overload (returns Void).
    public func send(_ mutation: @Sendable @escaping (inout N) -> Void) async {
        await store.send(mutation)
    }

    // MARK: Effects

    /// Schedules an async side-effect linked to this observer's store.
    ///
    /// Convenience wrapper around `NodeStore.task(_:)` — use for ad-hoc effects
    /// (network, timers) triggered from a view. Prefer `CommandBus` for
    /// app-level flows.
    @discardableResult
    public func task(_ body: @Sendable @escaping () async -> Void) -> Task<Void, Never> {
        store.task(body)
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
