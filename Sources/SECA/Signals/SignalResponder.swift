/// A `Node` that handles signals emitted by another `Node`.
///
/// Declare this conformance on a node to move signal-handling logic out of
/// `GlobalStore` and into the node that actually cares about the signals.
///
/// ```swift
/// extension LogNode: SignalResponder {
///     typealias Source = CounterNode
///
///     mutating func receive(_ signal: CounterNode.Signal) {
///         switch signal {
///         case .incremented(let v): append(message: "↑ \(v)", kind: .increment)
///         // …
///         }
///     }
/// }
///
/// // In GlobalStore.init() — one line replaces the manual Task + SignalBus:
/// _routingTask = log.autoWire(to: counter)
/// ```
public protocol SignalResponder: Node {
    /// The node whose signals this node wants to receive.
    associatedtype Source: Node
    /// Called for every signal emitted by `Source`.
    mutating func receive(_ signal: Source.Signal)
}

// MARK: - NodeStore auto-wiring

extension NodeStore where N: SignalResponder {

    /// Subscribes to `source`'s signal stream and routes every signal to
    /// `N.receive(_:)` inside an isolated `send` call.
    ///
    /// Hold the returned `Task` for the lifetime of the store to keep the
    /// subscription active. Cancel it (or let it deinit) to stop routing.
    ///
    /// - Parameter source: The store whose signals will be forwarded.
    /// - Returns: A running `Task` that drives the subscription.
    public nonisolated func autoWire(to source: NodeStore<N.Source>) -> Task<Void, Never> {
        Task { [source] in
            for await signal in source.signals.subscribe() {
                await self.send { $0.receive(signal) }
            }
        }
    }
}
