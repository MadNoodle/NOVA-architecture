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
/// // Read — from anywhere; results for different userIds are cached separately
/// let alice = try await bus.send(GetWeeklyStats(userId: "alice"))
/// let bob   = try await bus.send(GetWeeklyStats(userId: "bob"))
///
/// // Invalidate by type (drops every cached instance of that query)
/// await bus.invalidate(GetWeeklyStats.self)
/// ```
public actor QueryBus {

    // MARK: Internal types

    private struct Registration: @unchecked Sendable {
        let handle: @Sendable (Any) async throws -> Any
        let policy: QueryCachePolicy
    }

    // MARK: State

    private var registrations: [ObjectIdentifier: Registration] = [:]
    /// Cache keyed first by query TYPE, then by query VALUE (as AnyHashable).
    /// This ensures `GetStats(userId: "alice")` and `GetStats(userId: "bob")` never
    /// collide, while `invalidate(GetStats.self)` can still wipe all entries at once.
    private var cache: [ObjectIdentifier: [AnyHashable: Any]] = [:]

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
        cache.removeValue(forKey: key)  // reset cache on re-registration
    }

    /// Removes the handler (and all cached results) for query type `Q`.
    public func unregister<Q: Query>(_ type: Q.Type) {
        let key = ObjectIdentifier(type)
        registrations.removeValue(forKey: key)
        cache.removeValue(forKey: key)
    }

    // MARK: Dispatch

    /// Dispatches `query` and returns the result, using the per-instance cache if applicable.
    ///
    /// - Throws: `QueryBusError.noHandlerRegistered` if no handler exists.
    ///           Re-throws any error from the handler itself.
    public func send<Q: Query>(_ query: Q) async throws -> Q.Result {
        let typeKey  = ObjectIdentifier(Q.self)
        let valueKey = AnyHashable(query)

        // Return cached value if policy allows and a matching entry exists
        if let reg = registrations[typeKey], case .forever = reg.policy,
           let cached = cache[typeKey]?[valueKey] as? Q.Result {
            return cached
        }

        guard let reg = registrations[typeKey] else {
            throw QueryBusError.noHandlerRegistered(queryType: "\(Q.self)")
        }

        let raw = try await reg.handle(query)
        guard let result = raw as? Q.Result else {
            throw QueryBusError.typeMismatch
        }

        if case .forever = reg.policy {
            cache[typeKey, default: [:]][valueKey] = result
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
}
