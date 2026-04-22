import Testing
import Foundation
@testable import SECA

// MARK: - Fixtures
// Mirror the counter-app nodes inline so this test target stays self-contained.

@Node
private struct Counter {
    enum Signal: SECA.Signal, Equatable {
        case incremented(Int)
        case decremented(Int)
        case reset
        case clamped(to: Int)
    }
    var count   = 0
    var step    = 1
    var minimum = -10
    var maximum =  10

    mutating func increment() {
        let next = count + step
        if next > maximum { count = maximum; emit(.clamped(to: maximum)) }
        else               { count = next;   emit(.incremented(count)) }
    }
    mutating func decrement() {
        let next = count - step
        if next < minimum { count = minimum; emit(.clamped(to: minimum)) }
        else               { count = next;   emit(.decremented(count)) }
    }
    mutating func reset()            { count = 0; emit(.reset) }
    mutating func setStep(_ s: Int) { step = s }

    var isAtMax: Bool { count >= maximum }
    var isAtMin: Bool { count <= minimum }
}

@Node
private struct EventLog {
    enum Signal: SECA.Signal {}
    struct Entry: Sendable, Equatable {
        let message: String
        let kind: Kind
        enum Kind: Sendable, Equatable { case increment, decrement, reset, clamped }
    }
    var entries: [Entry] = []
    mutating func append(_ e: Entry) { entries.append(e) }
    mutating func clear()            { entries.removeAll() }
}

// MARK: - Command & Query types (local to tests)

private struct Inc:     Command {}
private struct Dec:     Command {}
private struct Rst:     Command {}
private struct SetStep: Command { let value: Int }

private struct GetStats: Query {
    typealias Result = (high: Int, low: Int, ops: Int)
}

// MARK: - Counter node unit tests

@Suite("Counter node — unit")
struct CounterNodeTests {

    @Test("default state")
    func defaults() async {
        let store = NodeStore<Counter>()
        let state = await store.state
        #expect(state.count   == 0)
        #expect(state.step    == 1)
        #expect(state.minimum == -10)
        #expect(state.maximum ==  10)
    }

    @Test("increment adds step")
    func incrementByStep() async {
        let store = NodeStore<Counter>()
        await store.send { $0.setStep(3) }
        await store.send { $0.increment() }
        #expect(await store.state.count == 3)
    }

    @Test("decrement subtracts step")
    func decrementByStep() async {
        let store = NodeStore<Counter>()
        await store.send { $0.setStep(2) }
        await store.send { $0.decrement() }
        #expect(await store.state.count == -2)
    }

    @Test("reset returns to 0")
    func resetToZero() async {
        let store = NodeStore<Counter>()
        await store.send { $0.increment() }
        await store.send { $0.increment() }
        await store.send { $0.reset() }
        #expect(await store.state.count == 0)
    }

    @Test("increment is clamped at maximum")
    func clampAtMax() async {
        let store = NodeStore<Counter>()
        for _ in 0..<20 { await store.send { $0.increment() } }
        #expect(await store.state.count == 10)
        #expect(await store.state.isAtMax)
    }

    @Test("decrement is clamped at minimum")
    func clampAtMin() async {
        let store = NodeStore<Counter>()
        for _ in 0..<20 { await store.send { $0.decrement() } }
        #expect(await store.state.count == -10)
        #expect(await store.state.isAtMin)
    }

    @Test("step change affects subsequent mutations")
    func stepChange() async {
        let store = NodeStore<Counter>()
        await store.send { $0.setStep(5) }
        await store.send { $0.increment() }
        #expect(await store.state.count == 5)
        await store.send { $0.setStep(1) }
        await store.send { $0.increment() }
        #expect(await store.state.count == 6)
    }

    @Test("isAtMax and isAtMin reflect boundaries")
    func boundaries() async {
        let store = NodeStore<Counter>()
        #expect(!(await store.state.isAtMax))
        #expect(!(await store.state.isAtMin))

        for _ in 0..<15 { await store.send { $0.increment() } }
        #expect(await store.state.isAtMax)
        #expect(!(await store.state.isAtMin))
    }
}

// MARK: - Signal routing (Counter → EventLog)

@Suite("Counter ↔ EventLog — signal routing")
struct SignalRoutingTests {

    @Test("increment signal is forwarded to log")
    func incrementRouted() async {
        let counterStore = NodeStore<Counter>()
        let logStore     = NodeStore<EventLog>()
        let bus          = SignalBus()

        await bus.observe(counterStore) { signal in
            if case .incremented(let v) = signal {
                await logStore.send { $0.append(.init(message: "↑ \(v)", kind: .increment)) }
            }
        }

        await counterStore.send { $0.increment() }
        await counterStore.send { $0.increment() }

        await waitUntil { await logStore.state.entries.count == 2 }

        let entries = await logStore.state.entries
        #expect(entries.count == 2)
        #expect(entries[0].kind == .increment)
        #expect(entries[1].kind == .increment)

        await bus.cancelAll()
    }

    @Test("all signal types are routed correctly")
    func allSignalsRouted() async {
        let counterStore = NodeStore<Counter>()
        let logStore     = NodeStore<EventLog>()
        let bus          = SignalBus()

        await bus.observe(counterStore) { signal in
            let entry: EventLog.Entry = switch signal {
            case .incremented(let v): .init(message: "↑ \(v)", kind: .increment)
            case .decremented(let v): .init(message: "↓ \(v)", kind: .decrement)
            case .reset:              .init(message: "⟳",       kind: .reset)
            case .clamped(let v):     .init(message: "⚠️ \(v)", kind: .clamped)
            }
            await logStore.send { $0.append(entry) }
        }

        await counterStore.send { $0.increment() }   // .incremented
        await counterStore.send { $0.decrement() }   // .decremented
        await counterStore.send { $0.decrement() }   // .decremented
        await counterStore.send { $0.reset() }       // .reset
        for _ in 0..<15 {
            await counterStore.send { $0.increment() }  // last few → .clamped
        }

        await waitUntil { await logStore.state.entries.contains { $0.kind == .clamped } }

        let entries = await logStore.state.entries
        #expect(entries.contains { $0.kind == .increment })
        #expect(entries.contains { $0.kind == .decrement })
        #expect(entries.contains { $0.kind == .reset })
        #expect(entries.contains { $0.kind == .clamped })

        await bus.cancelAll()
    }

    @Test("clearing log does not affect counter")
    func clearLogIsolated() async {
        let counterStore = NodeStore<Counter>()
        let logStore     = NodeStore<EventLog>()
        let bus          = SignalBus()

        await bus.observe(counterStore) { signal in
            if case .incremented(let v) = signal {
                await logStore.send { $0.append(.init(message: "\(v)", kind: .increment)) }
            }
        }

        await counterStore.send { $0.increment() }
        await waitUntil { await logStore.state.entries.count == 1 }
        #expect(await logStore.state.entries.count == 1)

        await logStore.send { $0.clear() }
        #expect(await logStore.state.entries.isEmpty)
        #expect(await counterStore.state.count == 1)   // counter unchanged

        await bus.cancelAll()
    }
}

// MARK: - CommandBus integration

@Suite("Counter — CommandBus")
struct CounterCommandBusTests {

    private func makeWiredBus(
        counterStore: NodeStore<Counter>
    ) async -> CommandBus {
        let bus = CommandBus()
        await bus.register(Inc.self)     { _ in await counterStore.send { $0.increment() } }
        await bus.register(Dec.self)     { _ in await counterStore.send { $0.decrement() } }
        await bus.register(Rst.self)     { _ in await counterStore.send { $0.reset() } }
        await bus.register(SetStep.self) { cmd in await counterStore.send { $0.setStep(cmd.value) } }
        return bus
    }

    @Test("Inc command increments the counter")
    func incCommand() async throws {
        let store = NodeStore<Counter>()
        let bus   = await makeWiredBus(counterStore: store)
        try await bus.send(Inc())
        try await bus.send(Inc())
        #expect(await store.state.count == 2)
    }

    @Test("Dec command decrements the counter")
    func decCommand() async throws {
        let store = NodeStore<Counter>()
        let bus   = await makeWiredBus(counterStore: store)
        try await bus.send(Inc())
        try await bus.send(Dec())
        #expect(await store.state.count == 0)
    }

    @Test("Rst command resets to zero")
    func rstCommand() async throws {
        let store = NodeStore<Counter>()
        let bus   = await makeWiredBus(counterStore: store)
        try await bus.send(Inc())
        try await bus.send(Inc())
        try await bus.send(Rst())
        #expect(await store.state.count == 0)
    }

    @Test("SetStep command changes increment magnitude")
    func setStepCommand() async throws {
        let store = NodeStore<Counter>()
        let bus   = await makeWiredBus(counterStore: store)
        try await bus.send(SetStep(value: 5))
        try await bus.send(Inc())
        #expect(await store.state.count == 5)
    }

    @Test("dispatching unknown command throws noHandlerRegistered")
    func unknownCommandThrows() async {
        let bus = CommandBus()
        await #expect(throws: CommandBusError.self) {
            try await bus.send(Inc())
        }
    }
}

// MARK: - QueryBus integration

@Suite("Counter — QueryBus")
struct CounterQueryBusTests {

    @Test("GetStats returns correct analytics from the timeline")
    func statsQuery() async throws {
        let store    = NodeStore<Counter>()
        let queryBus = QueryBus()

        await queryBus.register(GetStats.self, policy: .never) { _ in
            let events = store.timeline.events
            let values = events.map(\.state.count)
            return (high: values.max() ?? 0, low: values.min() ?? 0, ops: events.count)
        }

        await store.send { $0.increment() }   // 1
        await store.send { $0.increment() }   // 2
        await store.send { $0.decrement() }   // 1
        await store.send { $0.decrement() }   // 0

        let stats = try await queryBus.send(GetStats())
        #expect(stats.high == 2)
        #expect(stats.low  == 0)
        #expect(stats.ops  == 4)
    }

    @Test("policy .forever caches per-instance (no params here — single slot)")
    func cachedStats() async throws {
        let store    = NodeStore<Counter>()
        let counter  = CallCounter()
        let queryBus = QueryBus()

        await queryBus.register(GetStats.self, policy: .forever) { _ in
            await counter.increment()
            let ops = store.timeline.events.count
            return (high: ops, low: 0, ops: ops)
        }

        await store.send { $0.increment() }

        _ = try await queryBus.send(GetStats())  // handler called once → counter = 1
        _ = try await queryBus.send(GetStats())  // cached — counter stays 1

        #expect(await counter.value == 1)
    }

    @Test("invalidate forces recomputation")
    func invalidateForces() async throws {
        let store    = NodeStore<Counter>()
        let queryBus = QueryBus()

        await queryBus.register(GetStats.self, policy: .forever) { _ in
            let ops = store.timeline.events.count
            return (high: ops, low: 0, ops: ops)
        }

        await store.send { $0.increment() }
        let first = try await queryBus.send(GetStats())    // ops = 1, cached

        await store.send { $0.increment() }
        await queryBus.invalidate(GetStats.self)
        let second = try await queryBus.send(GetStats())   // recomputed → ops = 2

        #expect(first.ops  == 1)
        #expect(second.ops == 2)
    }
}

// MARK: - Full undo/redo integration

@Suite("Counter — Timeline undo / redo")
struct CounterTimelineTests {

    @Test("undo reverts last increment")
    func undoIncrement() async {
        let store = NodeStore<Counter>()
        await store.send { $0.increment() }   // count = 1
        await store.send { $0.increment() }   // count = 2
        await store.undo()
        #expect(await store.state.count == 1)
    }

    @Test("redo re-applies undone mutation")
    func redoAfterUndo() async {
        let store = NodeStore<Counter>()
        await store.send { $0.increment() }   // count = 1
        await store.send { $0.increment() }   // count = 2
        await store.undo()                    // count = 1
        await store.redo()                    // count = 2
        #expect(await store.state.count == 2)
    }

    @Test("undo all the way to genesis (count = 0)")
    func undoToGenesis() async {
        let store = NodeStore<Counter>()
        await store.send { $0.increment() }
        await store.send { $0.increment() }
        await store.undo()
        await store.undo()
        #expect(await store.state.count == 0)
        #expect(store.timeline.canUndo == false)
    }

    @Test("mutations after undo clear the redo branch")
    func newMutationClearsRedo() async {
        let store = NodeStore<Counter>()
        await store.send { $0.increment() }   // 1
        await store.send { $0.increment() }   // 2
        await store.undo()                    // back to 1
        await store.send { $0.decrement() }   // branch: 0
        #expect(await store.state.count == 0)
        #expect(store.timeline.canRedo == false)
    }

    @Test("replay moves cursor and enables consistent undo")
    func replayCursorConsistency() async {
        let store = NodeStore<Counter>()
        await store.send { $0.increment() }   // count = 1
        let mark = Date()
        try? await Task.sleep(nanoseconds: 1_000_000)
        await store.send { $0.increment() }   // count = 2
        await store.send { $0.increment() }   // count = 3

        await store.replay(to: mark)
        #expect(await store.state.count == 1)
        #expect(store.timeline.canRedo)    // can move forward

        await store.undo()
        #expect(await store.state.count == 0)   // back to genesis
    }
}

// MARK: - End-to-end scenario

@Suite("Counter App — end-to-end")
struct CounterAppEndToEndTests {

    @Test("full session: increment, clamp, undo, log check")
    func fullSession() async {
        let counterStore = NodeStore<Counter>()
        let logStore     = NodeStore<EventLog>()
        let signalBus    = SignalBus()
        let commandBus   = CommandBus()

        // Wire everything
        await signalBus.observe(counterStore) { signal in
            let entry: EventLog.Entry = switch signal {
            case .incremented(let v): .init(message: "↑ \(v)", kind: .increment)
            case .decremented(let v): .init(message: "↓ \(v)", kind: .decrement)
            case .reset:              .init(message: "⟳",       kind: .reset)
            case .clamped(let v):     .init(message: "⚠️ \(v)", kind: .clamped)
            }
            await logStore.send { $0.append(entry) }
        }
        await commandBus.register(Inc.self) { _ in await counterStore.send { $0.increment() } }
        await commandBus.register(Dec.self) { _ in await counterStore.send { $0.decrement() } }
        await commandBus.register(Rst.self) { _ in await counterStore.send { $0.reset() } }

        // Drive via CommandBus
        for _ in 0..<12 { try? await commandBus.send(Inc()) }  // hits max at 10, then clamped
        try? await commandBus.send(Rst())
        try? await commandBus.send(Dec())
        try? await commandBus.send(Dec())

        await waitUntil { await logStore.state.entries.contains { $0.kind == .decrement } }

        let count   = await counterStore.state.count
        let entries = await logStore.state.entries

        #expect(count == -2)
        #expect(entries.contains { $0.kind == .increment })
        #expect(entries.contains { $0.kind == .clamped  })
        #expect(entries.contains { $0.kind == .reset    })
        #expect(entries.contains { $0.kind == .decrement })

        // Undo twice → back to 0
        await counterStore.undo()
        await counterStore.undo()
        #expect(await counterStore.state.count == 0)

        await signalBus.cancelAll()
    }
}
