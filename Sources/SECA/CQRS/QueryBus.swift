import Foundation

/// Routes `Query` values to registered async handlers with optional memoization.
///
/// Results are cached **per query instance** — two queries of the same type but
/// with different parameters (e.g. different user IDs) occupy separate cache slots.
/// This requires `Query: Hashable`, which is synthesised automatically for most structs.
///
/// ```swift
/// let bus = QueryBus()
///
/// // Register — once, at app startup
/// await bus.register(GetWeeklyStats.self, policy: .forever) { query in
///     await statsStore.state.computeWeekly(for: query.userId)
/// }
///
/// // Auto-invalidate when a store mutates:
/// bus.register(GetWeeklyStats.self, invalidateOn: statsStore) { query in
///     await statsStore.state.computeWeekly(for: query.userId)
/// }
///
/// // Read — from anywhere; results for different userIds are cached separately
/// let alice = try await bus.send(GetWeeklyStats(userId: "alice"))
/// let bob   = try await bus.send(GetWeeklyStats(userId: "bob"))
///
/// // Invalidate by type (drops every cached instance of that query)
/// await bus.invalidate(GetWeeklyStats.self)
/// ```
public actor QueryBus {

    // MARK: Internal types

    private struct Registration: Sendable {
        let handle: @Sendable (Any) async throws -> Any
        let policy: QueryCachePolicy
    }

    // @unchecked because `value` is `Any` — the actor serialises all access,
    // so there is no concurrent mutation risk.
    private struct CacheEntry: @unchecked Sendable {
        let value: Any
        /// `nil` means the entry never expires (`.forever` policy).
        let expiresAt: ContinuousClock.Instant?
    }

    // MARK: State

    private var registrations: [ObjectIdentifier: Registration] = [:]

    /// Cache keyed first by query TYPE, then by query VALUE (as AnyHashable).
    /// This ensures `GetStats(userId: "alice")` and `GetStats(userId: "bob")` never
    /// collide, while `invalidate(GetStats.self)` can still wipe all entries at once.
    private var cache: [ObjectIdentifier: [AnyHashable: CacheEntry]] = [:]

    /// Tasks that watch a NodeStore's stateStream and invalidate on every mutation.
    private var invalidationTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    public init() {}

    // MARK: Registration

    /// Registers `handler` for query type `Q` with the given cache `policy`.
    /// Replaces any previous registration for that type and clears its cache.
    public func register<Q: Query>(
        _ type: Q.Type = Q.self,
        policy: QueryCachePolicy = .never,
        handler: @Sendable @escaping (Q) async throws -> Q.Result
    ) {
        let key = ObjectIdentifier(type)
        registrations[key] = Registration(
            handle: { any in
                guard let query = any as? Q else { throw QueryBusError.typeMismatch }
                return try await handler(query)
            },
            policy: policy
        )
        cache.removeValue(forKey: key)
    }

    /// Registers `handler` for query type `Q` and automatically invalidates all
    /// cached results whenever `store` is mutated.
    ///
    /// Equivalent to calling `register(_:policy:.forever:handler:)` and then
    /// watching the store's `stateStream` to call `invalidate(Q.self)` on every change.
    ///
    /// ```swift
    /// bus.register(GetStats.self, invalidateOn: counterStore) { _ in
    ///     await counterStore.state.computeStats()
    /// }
    /// ```
    public func register<Q: Query, N: Node>(
        _ type: Q.Type = Q.self,
        policy: QueryCachePolicy = .forever,
        invalidateOn store: NodeStore<N>,
        handler: @Sendable @escaping (Q) async throws -> Q.Result
    ) {
        register(type, policy: policy, handler: handler)
        let key = ObjectIdentifier(Q.self)
        invalidationTasks[key]?.cancel()
        let sub = store.stateStream.subscribe()
        invalidationTasks[key] = Task { [weak self] in
            for await _ in sub {
                await self?.invalidate(Q.self)
            }
        }
    }

    /// Removes the handler (and all cached results) for query type `Q`.
    public func unregister<Q: Query>(_ type: Q.Type) {
        let key = ObjectIdentifier(type)
        registrations.removeValue(forKey: key)
        cache.removeValue(forKey: key)
        invalidationTasks[key]?.cancel()
        invalidationTasks.removeValue(forKey: key)
    }

    // MARK: Dispatch

    /// Dispatches `query` and returns the result, using the per-instance cache if applicable.
    ///
    /// - Throws: `QueryBusError.noHandlerRegistered` if no handler exists.
    ///           Re-throws any error from the handler itself.
    public func send<Q: Query>(_ query: Q) async throws -> Q.Result {
        let typeKey  = ObjectIdentifier(Q.self)
        let valueKey = AnyHashable(query)

        // Check cache based on policy
        if let reg = registrations[typeKey], let entry = cache[typeKey]?[valueKey] {
            switch reg.policy.storage {
            case .forever:
                if let result = entry.value as? Q.Result { return result }
            case .ttl:
                if let exp = entry.expiresAt, ContinuousClock.now < exp,
                   let result = entry.value as? Q.Result { return result }
            case .never:
                break
            }
        }

        guard let reg = registrations[typeKey] else {
            throw QueryBusError.noHandlerRegistered(queryType: "\(Q.self)")
        }

        let raw = try await reg.handle(query)
        guard let result = raw as? Q.Result else {
            throw QueryBusError.typeMismatch
        }

        // Store in cache according to policy
        switch reg.policy.storage {
        case .forever:
            cache[typeKey, default: [:]][valueKey] = CacheEntry(value: result, expiresAt: nil)
        case .ttl(let duration):
            let expiry = ContinuousClock.now.advanced(by: duration)
            cache[typeKey, default: [:]][valueKey] = CacheEntry(value: result, expiresAt: expiry)
        case .never:
            break
        }

        return result
    }

    // MARK: Cache management

    /// Clears all cached results for every instance of query type `Q`.
    /// The next `send` for any instance of `Q` will recompute and re-cache.
    public func invalidate<Q: Query>(_ type: Q.Type = Q.self) {
        cache.removeValue(forKey: ObjectIdentifier(type))
    }

    /// Clears all cached results for all query types.
    public func invalidateAll() {
        cache.removeAll()
    }

    // MARK: Lifecycle

    deinit {
        for task in invalidationTasks.values { task.cancel() }
    }
}
