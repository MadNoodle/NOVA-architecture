import Testing
@testable import SECA

// MARK: - Fixture

private struct ItemNode: Node {
    enum Signal: Sendable, Equatable { case updated(Int) }
    var value = 0
    mutating func set(_ v: Int) { value = v; emit(.updated(v)) }
}

// MARK: - NodeCollection tests

@Suite("NodeCollection")
struct NodeCollectionTests {

    // MARK: add / remove / subscript

    @Test("add returns a NodeStore and makes id visible")
    func addMakesIDVisible() async {
        let col = NodeCollection<ItemNode>()
        let store = await col.add(id: "a")
        let ids = await col.currentSnapshot().ids
        #expect(ids == [AnyHashable("a")])
        let fetched = await col["a"]
        #expect(fetched === store)
    }

    @Test("add is idempotent — same ID returns the same store")
    func addIdempotent() async {
        let col = NodeCollection<ItemNode>()
        let s1 = await col.add(id: 1)
        let s2 = await col.add(id: 1)
        #expect(s1 === s2)
        let ids = await col.currentSnapshot().ids
        #expect(ids.count == 1)
    }

    @Test("ids are in insertion order")
    func insertionOrder() async {
        let col = NodeCollection<ItemNode>()
        await col.add(id: "z")
        await col.add(id: "a")
        await col.add(id: "m")
        let ids = await col.currentSnapshot().ids
        #expect(ids == [AnyHashable("z"), AnyHashable("a"), AnyHashable("m")])
    }

    @Test("remove eliminates the store and its ID")
    func removeEliminates() async {
        let col = NodeCollection<ItemNode>()
        await col.add(id: "x")
        await col.remove(id: "x")
        let ids = await col.currentSnapshot().ids
        #expect(ids.isEmpty)
        let fetched = await col["x"]
        #expect(fetched == nil)
    }

    @Test("remove on absent ID is a no-op")
    func removeAbsent() async {
        let col = NodeCollection<ItemNode>()
        await col.add(id: "keep")
        await col.remove(id: "ghost")           // absent — should not crash
        let ids = await col.currentSnapshot().ids
        #expect(ids == [AnyHashable("keep")])
    }

    @Test("subscript returns nil for unknown ID")
    func subscriptUnknown() async {
        let col = NodeCollection<ItemNode>()
        let result = await col["nope"]
        #expect(result == nil)
    }

    // MARK: currentSnapshot

    @Test("currentSnapshot reflects current ids and stores atomically")
    func snapshotAtomic() async {
        let col = NodeCollection<ItemNode>()
        let s1 = await col.add(id: 1)
        let s2 = await col.add(id: 2)
        let snap = await col.currentSnapshot()
        #expect(snap.ids == [AnyHashable(1), AnyHashable(2)])
        #expect(snap.stores[AnyHashable(1)] === s1)
        #expect(snap.stores[AnyHashable(2)] === s2)
    }

    // MARK: collectionStream

    @Test("collectionStream fires on add")
    func streamFiresOnAdd() async {
        let col = NodeCollection<ItemNode>()
        let sub = col.collectionStream.subscribe()
        let counter = CallCounter()
        let task = Task {
            for await _ in sub { await counter.increment(); break }
        }
        await col.add(id: "trigger")
        await waitUntil { await counter.value >= 1 }
        task.cancel()
        #expect(await counter.value >= 1)
    }

    @Test("collectionStream fires on remove")
    func streamFiresOnRemove() async {
        let col = NodeCollection<ItemNode>()
        await col.add(id: "r")
        let sub = col.collectionStream.subscribe()
        let counter = CallCounter()
        let task = Task {
            for await _ in sub { await counter.increment(); break }
        }
        await col.remove(id: "r")
        await waitUntil { await counter.value >= 1 }
        task.cancel()
        #expect(await counter.value >= 1)
    }

    // MARK: observeAll

    @Test("observeAll forwards signals from existing stores")
    func observeAllExisting() async {
        let col = NodeCollection<ItemNode>()
        let store = await col.add(id: "s")

        let counter = CallCounter()
        await col.observeAll { _ in await counter.increment() }

        await store.send { $0.set(42) }
        await waitUntil { await counter.value >= 1 }
        #expect(await counter.value == 1)
    }

    @Test("observeAll auto-wires stores added after the call")
    func observeAllFuture() async {
        let col = NodeCollection<ItemNode>()
        let counter = CallCounter()
        await col.observeAll { _ in await counter.increment() }

        // Store added AFTER observeAll — must also be wired
        let store = await col.add(id: "late")
        await store.send { $0.set(7) }
        await waitUntil { await counter.value >= 1 }
        #expect(await counter.value == 1)
    }

    @Test("observeAll replaces previous handler — second handler fires")
    func observeAllReplaces() async {
        let col = NodeCollection<ItemNode>()
        let store = await col.add(id: "s")

        let second = CallCounter()
        await col.observeAll { _ in }                              // first — discarded
        await col.observeAll { _ in await second.increment() }    // second — active

        await store.send { $0.set(1) }
        await waitUntil { await second.value >= 1 }
        // The second handler must fire; cooperative cancellation makes the first
        // handler's exact call count non-deterministic, so we only assert second.
        #expect(await second.value == 1)
    }

    @Test("remove cancels the forwarding task for that store")
    func removeCancelsForwarding() async {
        let col = NodeCollection<ItemNode>()
        let store = await col.add(id: "gone")
        let counter = CallCounter()
        await col.observeAll { _ in await counter.increment() }

        await col.remove(id: "gone")
        // Yield cooperative execution so the cancelled forwarding task exits
        // its loop before we emit the next signal.
        try? await Task.sleep(for: .milliseconds(10))

        // Mutations on the detached store should NOT reach the handler
        await store.send { $0.set(99) }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await counter.value == 0)
    }

    @Test("stores are isolated — mutating one does not affect others")
    func storeIsolation() async {
        let col = NodeCollection<ItemNode>()
        let a = await col.add(id: "a")
        let b = await col.add(id: "b")

        await a.send { $0.set(10) }
        let aVal = await a.state.value
        let bVal = await b.state.value
        #expect(aVal == 10)
        #expect(bVal == 0)
    }
}
