/// Marks a struct as a SECA `Node`.
///
/// The macro synthesises:
/// - `Node` protocol conformance.
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
/// The struct is usable with `NodeStore<CounterNode>` immediately after.
///
/// > Note: In v0.1, mutation methods must still be marked `mutating` by hand.
/// > Auto-`mutating` inference and `@Observable` synthesis arrive in v0.5.
@attached(extension, conformances: Node)
@attached(member, names: named(init()))
public macro Node() = #externalMacro(module: "SECAMacros", type: "NodeMacro")
