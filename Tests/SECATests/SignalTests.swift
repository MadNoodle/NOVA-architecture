import Testing
@testable import SECA

// MARK: - Fixtures

private struct PingNode: Node {
    enum Signal: Sendable, Equatable { case pinged(Int) }
    var count = 0
    mutating func ping() { count += 1; emit(.pinged(count)) }
}

private struct PongNode: Node {
    enum Signal: Sendable, Equatable { case ponged(Int) }
    var received = 0
    mutating func pong(_ value: Int) { received = value; emit(.ponged(value)) }
}

// MARK: - SignalStream tests

@Suite("SignalStream")
struct SignalStreamTests {

    @Test("Single subscriber receives all signals")
    func singleSubscriber() async {
        let stream = SignalStream<Int>()
        let sub = stream.subscribe()   // synchronous

        let collector = Task<[Int], Never> {
            var results: [Int] = []
            for await v in sub {
                results.append(v)
                if results.count == 3 { break }
            }
            return results
        }

        stream.yield(1)
        stream.yield(2)
        stream.yield(3)

        #expect(await collector.value == [1, 2, 3])
    }

    @Test("Multiple subscribers each receive all signals")
    func multipleSubscribers() async {
        let stream = SignalStream<String>()
        let sub1 = stream.subscribe()
        let sub2 = stream.subscribe()

        let c1 = Task<[String], Never> {
            var r: [String] = []
            for await v in sub1 { r.append(v); if r.count == 2 { break } }
            return r
        }
        let c2 = Task<[String], Never> {
            var r: [String] = []
            for await v in sub2 { r.append(v); if r.count == 2 { break } }
            return r
        }

        stream.yield("a")
        stream.yield("b")

        #expect(await c1.value == ["a", "b"])
        #expect(await c2.value == ["a", "b"])
    }

    @Test("finish() terminates all subscriber streams")
    func finishTerminates() async {
        let stream = SignalStream<Int>()
        let sub = stream.subscribe()

        let done = Task<Bool, Never> {
            for await _ in sub {}
            return true
        }

        stream.yield(1)
        stream.finish()

        #expect(await done.value == true)
    }

    @Test("subscriberCount tracks active subscriptions")
    func subscriberCount() async {
        let stream = SignalStream<Int>()
        #expect(stream.subscriberCount == 0)
        let sub1 = stream.subscribe()
        let sub2 = stream.subscribe()
        #expect(stream.subscriberCount == 2)
        // Terminate one by breaking out of the loop
        let t = Task { for await _ in sub1 { break } }
        stream.yield(1)
        await t.value
        await Task.yield()
        #expect(stream.subscriberCount == 1)
        // Cleanup
        _ = sub2
        stream.finish()
    }
}

// MARK: - SignalBus tests

@Suite("SignalBus")
struct SignalBusTests {

    @Test("observe routes signals to handler")
    func observeRoutesSignals() async {
        let pingStore = NodeStore<PingNode>()
        let bus = SignalBus()

        // Independent subscription — unaffected by bus consuming its own sub
        let received = Task<[PingNode.Signal], Never> {
            var results: [PingNode.Signal] = []
            for await signal in pingStore.signals.subscribe() {
                results.append(signal)
                if results.count == 2 { break }
            }
            return results
        }

        await Task.yield()

        await pingStore.send { $0.ping() }
        await pingStore.send { $0.ping() }

        #expect(await received.value == [.pinged(1), .pinged(2)])
        await bus.cancelAll()
    }

    @Test("cancel stops routing for a specific store")
    func cancelStopsRouting() async {
        let store = NodeStore<PingNode>()
        let bus = SignalBus()
        let counter = CallCounter()

        await bus.observe(store) { _ in await counter.increment() }

        await store.send { $0.ping() }
        await Task.yield()
        await Task.yield()

        await bus.cancel(store)
        let before = await counter.value

        await store.send { $0.ping() }
        await Task.yield()
        await Task.yield()

        #expect(await counter.value == before)
    }

    @Test("inter-node signal routing via bus")
    func interNodeRouting() async {
        let pingStore = NodeStore<PingNode>()
        let pongStore = NodeStore<PongNode>()
        let bus = SignalBus()

        await bus.observe(pingStore) { signal in
            if case .pinged(let value) = signal {
                await pongStore.send { $0.pong(value) }
            }
        }

        let pongSignals = Task<[PongNode.Signal], Never> {
            var results: [PongNode.Signal] = []
            for await signal in pongStore.signals.subscribe() {
                results.append(signal)
                if results.count == 2 { break }
            }
            return results
        }

        await Task.yield()

        await pingStore.send { $0.ping() }
        await pingStore.send { $0.ping() }

        #expect(await pongSignals.value == [.ponged(1), .ponged(2)])
        await bus.cancelAll()
    }
}
