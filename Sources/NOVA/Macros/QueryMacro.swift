/// Marks a computed property as a CQRS Query result.
///
/// Indicates that the property is read-only and safe to cache.
/// Use `cache: .forever` to opt into memoization via a `_query_`-prefixed
/// backing stored property synthesised by the macro.
///
/// ```swift
/// // No cache — recomputes every access (default)
/// @Query
/// var entryCount: Int { entries.count }
///
/// // Cached — reuses the last computed value; invalidate manually
/// @Query(cache: .forever)
/// var weeklyStats: WeeklyStatsDTO {
///     WeeklyStatsDTO(entries: entries)
/// }
/// // Invalidate:  _query_weeklyStats = nil
/// ```
///
/// > Note: `cache: .invalidateOn(keyPath)` observation-based invalidation
/// > arrives in v0.5 with full `@Observable` integration.
/// >
/// > `cache: .forever` requires the containing type to be a reference type
/// > (class or actor) since the getter mutates the backing cache store.
@attached(accessor, names: named(get))
@attached(peer, names: prefixed(_query_))
public macro Query(cache: QueryCachePolicy = .never) = #externalMacro(module: "NOVAMacros", type: "QueryMacro")
