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
public enum QueryCachePolicy: Sendable {
    /// Never cache — recompute on every `send`.
    case never
    /// Cache forever — compute once, reuse until `QueryBus.invalidate(_:)` is called.
    case forever
    // `.invalidateOn(keyPath)` — observation-based invalidation, arrives in v0.5
}

// MARK: - Errors

public enum QueryBusError: Error, Sendable {
    /// No handler was registered for the dispatched query type.
    case noHandlerRegistered(queryType: String)
    /// Internal type mismatch (should never happen with correct usage).
    case typeMismatch
}
