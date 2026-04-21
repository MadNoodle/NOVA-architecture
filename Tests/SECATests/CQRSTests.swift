import Testing
@testable import SECA

// MARK: - Command fixtures

private struct Increment: Command { let amount: Int }
private struct Reset: Command {}
private struct Decrement: Command { let amount: Int }

// MARK: - Query fixtures

private struct GetCount: Query { typealias Result = Int }
private struct GetDoubled: Query { typealias Result = Int }
// Parameterised query — verifies per-instance cache isolation
private struct GetCountForKey: Query {
    typealias Result = Int
    let key: String
}

// MARK: - CommandBus tests

@Suite("CommandBus")
struct CommandBusTests {

    @Test("send dispatches to the registered handler")
    func dispatchesToHandler() async throws {
        let store = NodeStore<CounterNode>()
        let bus   = CommandBus()

        await bus.register(Increment.self) { cmd in
            await store.send { node in
                for _ in 0..<cmd.amount { node.increment() }
            }
        }

        try await bus.send(Increment(amount: 3))
        #expect(await store.state.count == 3)
    }

    @Test("send throws when no handler is registered")
    func throwsWhenNoHandler() async {
        let bus = CommandBus()
        await #expect(throws: CommandBusError.self) {
            try await bus.send(Reset())
        }
    }

    @Test("register replaces the previous handler")
    func registerReplaces() async throws {
        let bus     = CommandBus()
        let counter = CallCounter()

        await bus.register(Reset.self) { _ in await counter.increment() }
        await bus.register(Reset.self) { _ in await counter.increment(); await counter.increment() }

        try await bus.send(Reset())
        #expect(await counter.value == 2)  // second handler was called
    }

    @Test("unregister removes the handler")
    func unregisterRemovesHandler() async {
        let bus = CommandBus()
        await bus.register(Reset.self) { _ in }
        await bus.unregister(Reset.self)
        await #expect(throws: CommandBusError.self) {
            try await bus.send(Reset())
        }
    }

    @Test("multiple command types dispatch independently")
    func multipleTypes() async throws {
        let store = NodeStore<CounterNode>()
        let bus   = CommandBus()

        await bus.register(Increment.self) { cmd in
            await store.send { for _ in 0..<cmd.amount { $0.increment() } }
        }
        await bus.register(Decrement.self) { cmd in
            await store.send { for _ in 0..<cmd.amount { $0.decrement() } }
        }

        try await bus.send(Increment(amount: 5))
        try await bus.send(Decrement(amount: 2))
        #expect(await store.state.count == 3)
    }
}

// MARK: - QueryBus tests

@Suite("QueryBus")
struct QueryBusTests {

    @Test("send returns the handler's result")
    func returnsResult() async throws {
        let store = NodeStore<CounterNode>()
        let bus   = QueryBus()

        await store.send { for _ in 0..<7 { $0.increment() } }

        await bus.register(GetCount.self) { _ in await store.state.count }
        let result = try await bus.send(GetCount())
        #expect(result == 7)
    }

    @Test("send throws when no handler registered")
    func throwsWhenNoHandler() async {
        let bus = QueryBus()
        await #expect(throws: QueryBusError.self) {
            try await bus.send(GetCount())
        }
    }

    @Test("policy .never recomputes every time")
    func neverPolicyRecomputes() async throws {
        let store = NodeStore<CounterNode>()
        let bus   = QueryBus()

        await bus.register(GetCount.self, policy: .never) { _ in await store.state.count }

        await store.send { $0.increment() }
        let first = try await bus.send(GetCount())
        await store.send { $0.increment() }
        let second = try await bus.send(GetCount())

        #expect(first  == 1)
        #expect(second == 2)
    }

    @Test("policy .forever caches the first result")
    func foreverPolicyCaches() async throws {
        let store = NodeStore<CounterNode>()
        let bus   = QueryBus()

        await store.send { $0.increment() }  // count = 1
        await bus.register(GetCount.self, policy: .forever) { _ in await store.state.count }

        let first = try await bus.send(GetCount())
        await store.send { $0.increment() }  // count = 2, but cache unchanged
        let second = try await bus.send(GetCount())

        #expect(first  == 1)
        #expect(second == 1)  // cached value
    }

    @Test("invalidate clears the cache so next send recomputes")
    func invalidateClearsCache() async throws {
        let store = NodeStore<CounterNode>()
        let bus   = QueryBus()

        await store.send { $0.increment() }
        await bus.register(GetCount.self, policy: .forever) { _ in await store.state.count }

        _ = try await bus.send(GetCount())   // primes the cache (count = 1)
        await store.send { $0.increment() }  // count = 2
        await bus.invalidate(GetCount.self)
        let result = try await bus.send(GetCount())

        #expect(result == 2)
    }

    @Test("policy .forever caches independently per query instance")
    func foreverPolicyCachesPerInstance() async throws {
        let bus     = QueryBus()
        let counter = CallCounter()  // actor — safe to mutate from @Sendable closure

        // Handler returns callCount × 10; each genuine handler invocation yields
        // a distinct value, so we can tell whether the cache was used.
        await bus.register(GetCountForKey.self, policy: .forever) { _ in
            await counter.increment()
            return await counter.value * 10
        }

        // First call for "a" — handler invoked (counter = 1 → result = 10)
        let a1 = try await bus.send(GetCountForKey(key: "a"))
        // Second call for "a" — must return the cached result (10), not re-invoke
        let a2 = try await bus.send(GetCountForKey(key: "a"))
        // First call for "b" — different key, handler invoked (counter = 2 → result = 20)
        let b1 = try await bus.send(GetCountForKey(key: "b"))

        #expect(a1 == 10)
        #expect(a2 == 10)                     // cached — must NOT be 20
        #expect(b1 == 20)                     // distinct cache slot for key "b"
        #expect(await counter.value == 2)     // handler called exactly twice
    }

    @Test("invalidateAll clears every cached result")
    func invalidateAllClearsAll() async throws {
        let store = NodeStore<CounterNode>()
        let bus   = QueryBus()

        await bus.register(GetCount.self,   policy: .forever) { _ in await store.state.count }
        await bus.register(GetDoubled.self, policy: .forever) { _ in await store.state.count * 2 }

        await store.send { $0.increment() }
        _ = try await bus.send(GetCount())    // prime both caches
        _ = try await bus.send(GetDoubled())

        await store.send { $0.increment() }   // count = 2
        await bus.invalidateAll()

        #expect(try await bus.send(GetCount())   == 2)
        #expect(try await bus.send(GetDoubled()) == 4)
    }
}

// MARK: - @Query macro expansion tests (in MacroTests.swift companion)
// Actual expansion tests live in MacroTests.swift to stay with XCTest harness.

// MARK: - Shared fixture (reused from NodeTests.swift via same module)

private struct CounterNode: Node {
    enum Signal: Sendable, Equatable {
        case incremented(Int)
        case decremented(Int)
    }
    var count = 0
    mutating func increment() { count += 1; emit(.incremented(count)) }
    mutating func decrement() { count -= 1; emit(.decremented(count)) }
}
