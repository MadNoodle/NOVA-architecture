/// Marker protocol for all SECA signal types.
///
/// Signals flow across concurrency boundaries so they must be `Sendable`.
/// Implement this on a nested enum inside your `Node`:
///
/// ```swift
/// struct CounterNode: Node {
///     enum Signal: SECA.Signal {
///         case incremented(Int)
///         case reset
///     }
/// }
/// ```
public protocol Signal: Sendable {}
