import Testing
@testable import SECA

// MARK: - Fixture

private struct CounterNode: Node {
    enum Signal: Sendable, Equatable {
        case incremented(Int)
        case reset
    }

    var count = 0

    mutating func increment() {
        count += 1
        emit(.incremented(count))
    }

    mutating func reset() {
        count = 0
        emit(.reset)
    }
}

// MARK: - NodeStore tests

@Suite("NodeStore")
struct NodeStoreTests {

    @Test("Initial state is default-initialized")
    func initialState() async {
        let store = NodeStore<CounterNode>()
        let count = await store.state.count
        #expect(count == 0)
    }

    @Test("send mutates state")
    func sendMutatesState() async {
        let store = NodeStore<CounterNode>()
        await store.send { $0.increment() }
        await store.send { $0.increment() }
        let count = await store.state.count
        #expect(count == 2)
    }

    @Test("send emits signals in order")
    func sendEmitsSignals() async {
        let store = NodeStore<CounterNode>()

        // Collect 3 signals inside the Task so no mutable state is shared.
        let collector = Task<[CounterNode.Signal], Never> {
            var collected: [CounterNode.Signal] = []
            for await signal in store.signals.subscribe() {
                collected.append(signal)
                if collected.count == 3 { break }
            }
            return collected
        }

        await store.send { $0.increment() }
        await store.send { $0.increment() }
        await store.send { $0.reset() }

        let received = await collector.value
        #expect(received == [.incremented(1), .incremented(2), .reset])
    }

    @Test("emit outside send is silently dropped")
    func emitOutsideSend() async {
        // Calling emit directly (outside a NodeStore mutation) must not crash.
        let node = CounterNode()
        node.emit(.incremented(99)) // no NodeContext installed — should be a no-op
        #expect(node.count == 0)
    }

    @Test("multiple sends accumulate state correctly")
    func multipleResets() async {
        let store = NodeStore<CounterNode>()
        for _ in 0..<5 { await store.send { $0.increment() } }
        await store.send { $0.reset() }
        let count = await store.state.count
        #expect(count == 0)
    }
}
