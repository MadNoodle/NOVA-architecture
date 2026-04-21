import Testing
@testable import SECA

// MARK: - Fixtures

private struct PingNode: Node {
    enum Signal: Sendable, Equatable { case pinged(Int) }
    var count = 0
    mutating func ping() { count += 1; emit(.pinged(count)) }
    init() {}
}

private struct PongNode: Node {
    enum Signal: Sendable, Equatable { case ponged(Int) }
    var received = 0
    mutating func pong(_ value: Int) { received = value; emit(.ponged(value)) }
    init() {}
}

// MARK: - SignalStream tests

@Suite("SignalStream")
struct SignalStreamTests {

    @Test("Single subscriber receives all signals")
    func singleSubscriber() async {
        let stream = SignalStream<Int>()
        let sub = stream.subscribe()

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
        // Task cancellation — not a natural `break` — is what triggers
        // AsyncStream.Continuation.onTermination, which removes the subscriber.
        let t = Task { for await _ in sub1 { } }
        t.cancel()
        await t.value
        await waitUntil { stream.subscriberCount == 1 }
        #expect(stream.subscriberCount == 1)
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

        // Subscribe BEFORE the Task so no yield is needed to warm up the
        // subscription before emitting.
        let sub = pingStore.signals.subscribe()
        let received = Task<[PingNode.Signal], Never> {
            var results: [PingNode.Signal] = []
            for await signal in sub {
                results.append(signal)
                if results.count == 2 { break }
            }
            return results
        }

        await pingStore.send { $0.ping() }
        await pingStore.send { $0.ping() }

        #expect(await received.value == [.pinged(1), .pinged(2)])
        await bus.cancelAll()
    }

    @Test("cancel stops routing for a specific store")
    func cancelStopsRouting() async {
        let store   = NodeStore<PingNode>()
        let bus     = SignalBus()
        let counter = CallCounter()

        await bus.observe(store) { _ in await counter.increment() }

        await store.send { $0.ping() }
        await waitUntil { await counter.value == 1 }

        await bus.cancel(store)
        let before = await counter.value

        await store.send { $0.ping() }
        // Allow time for any stray delivery, then assert no change.
        try? await Task.sleep(for: .milliseconds(50))
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

        // Subscribe before emitting so no yield is needed.
        let pongSub = pongStore.signals.subscribe()
        let pongSignals = Task<[PongNode.Signal], Never> {
            var results: [PongNode.Signal] = []
            for await signal in pongSub {
                results.append(signal)
                if results.count == 2 { break }
            }
            return results
        }

        await pingStore.send { $0.ping() }
        await pingStore.send { $0.ping() }

        #expect(await pongSignals.value == [.ponged(1), .ponged(2)])
        await bus.cancelAll()
    }
}

// MARK: - SignalResponder fixtures

private struct Src1: Node {
    enum Signal: SECA.Signal, Equatable { case fired(Int) }
    var x = 0
    mutating func fire() { x += 1; emit(.fired(x)) }
    init() {}
}

private struct Src2: Node {
    enum Signal: SECA.Signal, Equatable { case burst(String) }
    mutating func burst(_ s: String) { emit(.burst(s)) }
    init() {}
}

private struct MultiSink: Node {
    enum Signal: SECA.Signal {}
    var log: [String] = []
    mutating func onSrc1(_ sig: Src1.Signal) {
        if case .fired(let n) = sig { log.append("s1:\(n)") }
    }
    mutating func onSrc2(_ sig: Src2.Signal) {
        if case .burst(let s) = sig { log.append("s2:\(s)") }
    }
    init() {}
}

private struct EchoNode: Node, SignalResponder {
    typealias Source = Src1
    enum Signal: SECA.Signal {}
    var echoed: [Int] = []
    mutating func receive(_ signal: Src1.Signal) {
        if case .fired(let n) = signal { echoed.append(n) }
    }
    init() {}
}

// MARK: - SignalResponder tests

@Suite("SignalResponder")
struct SignalResponderTests {

    @Test("protocol-based autoWire routes signals to receive(_:)")
    func protocolBasedRouting() async {
        let src   = NodeStore<Src1>()
        let echo  = NodeStore<EchoNode>()
        let wires = WireTasks()

        wires += echo.autoWire(to: src)

        await src.send { $0.fire() }
        await src.send { $0.fire() }

        await waitUntil { await echo.state.echoed.count == 2 }
        #expect(await echo.state.echoed == [1, 2])
    }

    @Test("closure-based autoWire routes signals to an arbitrary handler")
    func closureBasedRouting() async {
        let src   = NodeStore<Src1>()
        let sink  = NodeStore<MultiSink>()
        let wires = WireTasks()

        wires += sink.autoWire(to: src) { $0.onSrc1($1) }

        await src.send { $0.fire() }
        await waitUntil { await sink.state.log.count == 1 }
        #expect(await sink.state.log == ["s1:1"])
    }

    @Test("multi-source: two autoWire calls on the same destination node")
    func multiSource() async {
        let src1  = NodeStore<Src1>()
        let src2  = NodeStore<Src2>()
        let sink  = NodeStore<MultiSink>()
        let wires = WireTasks()

        wires += sink.autoWire(to: src1) { $0.onSrc1($1) }
        wires += sink.autoWire(to: src2) { $0.onSrc2($1) }

        await src1.send { $0.fire() }
        await src2.send { $0.burst("hello") }

        await waitUntil { await sink.state.log.count == 2 }

        let log = await sink.state.log
        #expect(log.contains("s1:1"))
        #expect(log.contains("s2:hello"))
    }

    @Test("WireTasks cancels routing on deinit")
    func wireTasksCancelsOnDeinit() async {
        let src  = NodeStore<Src1>()
        let echo = NodeStore<EchoNode>()

        do {
            let wires = WireTasks()
            wires += echo.autoWire(to: src)
            await src.send { $0.fire() }
            await waitUntil { await echo.state.echoed.count == 1 }
        }
        // wires is deinit'd — routing task is cancelled

        let countBefore = await echo.state.echoed.count
        await src.send { $0.fire() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await echo.state.echoed.count == countBefore)
    }
}
