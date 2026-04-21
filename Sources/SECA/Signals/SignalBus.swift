/// Routes signals from source `NodeStore`s to async handlers.
///
/// `SignalBus` is the backbone of inter-node communication. Register handlers
/// on source stores; the bus drains each store's signal stream and dispatches
/// to all registered handlers concurrently.
///
/// ```swift
/// let bus = SignalBus()
///
/// await bus.observe(anxietyStore) { signal in
///     if case .entryAdded(let entry) = signal {
///         await healthStore.send { $0.syncWith(entry) }
///     }
/// }
///
/// // Later:
/// await bus.cancel(anxietyStore)
/// ```
///
/// `SignalBus` owns the observation tasks. It cancels all of them on `deinit`.
///
/// > **Retain cycles**: if your handler captures the `SignalBus` itself (e.g. to
/// > register further observations), use `[weak bus]` to avoid a cycle:
/// > `bus.tasks → Task → handler → bus`. Capturing stores or other actors is safe.
public actor SignalBus {

    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    public init() {}

    /// Starts observing signals from `store` and forwarding them to `handler`.
    ///
    /// If `store` was already observed, the previous observation is cancelled first.
    /// `handler` is called serially in the order signals are emitted.
    public func observe<N: Node>(
        _ store: NodeStore<N>,
        handler: @Sendable @escaping (N.Signal) async -> Void
    ) {
        let key = ObjectIdentifier(store)
        tasks[key]?.cancel()
        let sub = store.signals.subscribe()
        tasks[key] = Task { [weak self] in
            for await signal in sub {
                guard !Task.isCancelled else { break }
                await handler(signal)
            }
            // Remove the task from the registry once the stream ends
            // so the dictionary doesn't accumulate dead entries.
            await self?.removeTask(for: key)
        }
    }

    /// Stops observing signals from `store`.
    public func cancel<N: Node>(_ store: NodeStore<N>) {
        let key = ObjectIdentifier(store)
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
    }

    /// Stops all observations.
    public func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    deinit {
        for task in tasks.values { task.cancel() }
    }

    // MARK: Private

    private func removeTask(for key: ObjectIdentifier) {
        tasks.removeValue(forKey: key)
    }
}
