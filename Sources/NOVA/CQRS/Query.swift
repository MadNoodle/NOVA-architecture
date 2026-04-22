/// Marker protocol for read-only requests in the CQRS pattern.
///
/// Queries read state, produce a `Result`, and must not modify anything.
/// Dispatch them through `QueryBus`, which can memoize results per query instance.
///
/// `Query` requires `Hashable` so the cache can distinguish between queries with
/// different parameters — e.g. `GetWeeklyStats(userId: "alice")` and
/// `GetWeeklyStats(userId: "bob")` are cached independently.
///
/// ```swift
/// struct GetWeeklyStats: Query {
///     typealias Result = WeeklyStatsDTO
///     let userId: String          // Hashable synthesis is automatic
/// }
///
/// let stats = try await queryBus.send(GetWeeklyStats(userId: id))
/// ```
public protocol Query: Sendable, Hashable {
    /// The type of value this query returns.
    associatedtype Result: Sendable
}

// MARK: - Cache policy

/// Controls when a `QueryBus` caches a query's result.
///
/// Use the static factory properties and methods rather than switching over
/// the type — the internal representation is intentionally opaque so new
/// policies can be added without breaking existing call sites.
///
/// ```swift
/// // Never cache:
/// bus.register(MyQuery.self, policy: .never) { ... }
///
/// // Cache forever (until invalidated):
/// bus.register(MyQuery.self, policy: .forever) { ... }
///
/// // Cache for 30 seconds:
/// bus.register(MyQuery.self, policy: .ttl(.seconds(30))) { ... }
///
/// // Auto-invalidate when a NodeStore mutates:
/// bus.register(MyQuery.self, invalidateOn: myStore) { ... }
/// ```
public struct QueryCachePolicy: Sendable {

    // Internal representation — not exposed so new cases don't break callers.
    enum Storage: Sendable {
        case never
        case forever
        case ttl(Duration)
    }
    let storage: Storage

    /// Never cache — recompute on every `send`.
    public static let never = QueryCachePolicy(storage: .never)

    /// Cache forever — compute once, reuse until `QueryBus.invalidate(_:)` is called.
    public static let forever = QueryCachePolicy(storage: .forever)

    /// Cache for `duration`, then recompute on the next `send` after expiry.
    public static func ttl(_ duration: Duration) -> QueryCachePolicy {
        QueryCachePolicy(storage: .ttl(duration))
    }
}

// MARK: - Errors

public enum QueryBusError: Error, Sendable {
    /// No handler was registered for the dispatched query type.
    case noHandlerRegistered(queryType: String)
    /// Internal type mismatch (should never happen with correct usage).
    case typeMismatch
}
