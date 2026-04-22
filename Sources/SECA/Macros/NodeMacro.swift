/// Marks a struct as a SECA `Node`.
///
/// The macro synthesises:
/// - `Node` protocol conformance via an extension.
/// - A default `public init() {}` if none is defined.
///
/// ```swift
/// @Node
/// struct CounterNode {
///     enum Signal: SECA.Signal { case incremented(Int) }
///     var count = 0
///     mutating func increment() { count += 1; emit(.incremented(count)) }
/// }
/// ```
///
/// ## What the macro expansion looks like
///
/// Expanding `@Node` in Xcode ("Expand Macro") produces exactly two
/// declarations — nothing surprising:
///
/// ```swift
/// extension CounterNode: Node {}
/// public init() {}
/// ```
///
/// All runtime behaviour (`emit()` routing, signal broadcasting, timeline
/// recording) lives in `NodeStore` and the `Node` protocol extension —
/// not in the macro expansion. See `Node` for a full explanation of the
/// ownership model and how `emit()` works.
///
/// ## Compile-time diagnostics
///
/// The macro scans your methods and warns if a method calls `emit()` without
/// being marked `mutating`. The warning comes with a fix-it to insert
/// `mutating` in the correct position. This catches a common mistake early:
/// non-`mutating` methods can call `emit()` without a compiler error, but
/// any state they write will not be persisted by `NodeStore`.
@attached(extension, conformances: Node)
@attached(member, names: named(init()))
public macro Node() = #externalMacro(module: "SECAMacros", type: "NodeMacro")
