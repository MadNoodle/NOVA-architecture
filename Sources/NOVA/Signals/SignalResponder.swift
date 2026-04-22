/// A `Node` that handles signals emitted by another `Node`.
///
/// Conform a node to `SignalResponder` to declare a typed dependency on
/// another node's signal stream. Use `NodeStore.autoWire(to:)` to activate
/// the connection inside your `GlobalStore`.
///
/// For nodes that need to receive signals from **multiple** sources, use
/// the closure-based `autoWire(to:_:)` overload instead — a node cannot
/// conform to `SignalResponder` more than once.
///
/// ```swift
/// // Single-source: declare on the node
/// extension LogNode: SignalResponder {
///     typealias Source = CounterNode
///     mutating func receive(_ signal: CounterNode.Signal) { ... }
/// }
/// _wires += log.autoWire(to: counter)
///
/// // Multi-source: closure in GlobalStore
/// _wires += dashboard.autoWire(to: user)   { $0.onUser($1) }
/// _wires += dashboard.autoWire(to: cart)   { $0.onCart($1) }
/// ```
public protocol SignalResponder: Node {
    /// The node whose signals this node wants to receive.
    associatedtype Source: Node
    /// Called for every signal emitted by `Source`.
    mutating func receive(_ signal: Source.Signal)
}

// MARK: - Protocol-based wiring (single source, declarative)

extension NodeStore where N: SignalResponder {

    /// Subscribes to `source`'s signals and routes each one to `N.receive(_:)`.
    ///
    /// Add the returned `Task` to a ``WireTasks`` bag so it is cancelled when
    /// the store is deallocated.
    public nonisolated func autoWire(to source: NodeStore<N.Source>) -> Task<Void, Never> {
        // Subscribe synchronously so signals emitted immediately after autoWire()
        // returns are not lost while the Task is still starting up.
        let sub = source.signals.subscribe()
        return Task {
            for await signal in sub {
                await self.send { $0.receive(signal) }
            }
        }
    }
}

// MARK: - Closure-based wiring (multi-source)

extension NodeStore {

    /// Subscribes to `source`'s signals and forwards each one to `handler`.
    ///
    /// Use this overload when a node needs to receive signals from more than one
    /// source, or when you prefer not to use the ``SignalResponder`` protocol:
    ///
    /// ```swift
    /// _wires += dashboard.autoWire(to: user)    { $0.onUserSignal($1) }
    /// _wires += dashboard.autoWire(to: cart)    { $0.onCartSignal($1) }
    /// _wires += dashboard.autoWire(to: orders)  { $0.onOrderSignal($1) }
    /// ```
    ///
    /// Add the returned `Task` to a ``WireTasks`` bag so it is cancelled when
    /// the store is deallocated.
    public nonisolated func autoWire<Source: Node>(
        to source: NodeStore<Source>,
        _ handler: @Sendable @escaping (inout N, Source.Signal) -> Void
    ) -> Task<Void, Never> {
        let sub = source.signals.subscribe()
        return Task {
            for await signal in sub {
                await self.send { handler(&$0, signal) }
            }
        }
    }
}
