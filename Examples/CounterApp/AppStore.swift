import SECA

// MARK: - AppStore

/// Single source of truth for the Counter demo.
///
/// Owns the node stores and wires inter-node signal routing.
/// Mutations live on the nodes; views call them via `store.send { }`.
final class AppStore: GlobalStore, @unchecked Sendable {

    // MARK: Stores

    let counter = NodeStore<CounterNode>()
    let log     = NodeStore<LogNode>()

    // MARK: Init

    init() {
        // LogNode declares SignalResponder<CounterNode> — one line wires the whole routing.
        _routingTask = log.autoWire(to: counter)
        StoreRegistry.shared.register(self)
    }

    private let _routingTask: Task<Void, Never>

    // MARK: Cross-node operations
    //
    // Undo/redo coordinate two nodes (counter + log) so they belong here.

    func undoCounter() async {
        if let restored = await counter.undo() {
            await log.send { $0.append(message: "↩  undo → \(restored.count)", kind: .undo) }
        }
    }

    func redoCounter() async {
        if let restored = await counter.redo() {
            await log.send { $0.append(message: "↪  redo → \(restored.count)", kind: .redo) }
        }
    }

    // MARK: Derived data

    var timelineStats: TimelineStats {
        let tl     = counter.timeline
        let events = tl.events
        let values = events.map(\.state.count)
        return TimelineStats(
            operationCount: events.count,
            highestValue:   values.max() ?? 0,
            lowestValue:    values.min() ?? 0,
            canUndo:        tl.canUndo,
            canRedo:        tl.canRedo
        )
    }
}
