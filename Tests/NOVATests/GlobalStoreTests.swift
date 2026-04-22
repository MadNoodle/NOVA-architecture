import Testing
@testable import NOVA

// MARK: - Fixtures

@Node
private struct TaskNode {
    enum Signal: NOVA.Signal { case added(String) }
    var items: [String] = []
    mutating func add(_ item: String) { items.append(item); emit(.added(item)) }
}

@Node
private struct SettingsNode {
    enum Signal: NOVA.Signal {}
    var darkMode = false
    mutating func toggle() { darkMode.toggle() }
}

private final class TestStore: GlobalStore, @unchecked Sendable {
    let tasks    = NodeStore<TaskNode>()
    let settings = NodeStore<SettingsNode>()
    @LazyNode var premium: NodeStore<TaskNode>  // reuse TaskNode as a stand-in
}

// MARK: - StoreRegistry

@Suite("StoreRegistry")
struct StoreRegistryTests {

    @Test("resolve returns nil before registration")
    func resolveBeforeRegister() {
        let registry = StoreRegistry()  // fresh instance, not shared
        #expect(registry.resolve(TestStore.self) == nil)
    }

    @Test("register then resolve returns the same instance")
    func registerAndResolve() {
        let registry = StoreRegistry()
        let store = TestStore()
        registry.register(store)
        #expect(registry.resolve(TestStore.self) === store)
    }

    @Test("register replaces a previous instance")
    func registerReplaces() {
        let registry = StoreRegistry()
        let first  = TestStore()
        let second = TestStore()
        registry.register(first)
        registry.register(second)
        #expect(registry.resolve(TestStore.self) === second)
    }

    @Test("unregister removes the instance")
    func unregister() {
        let registry = StoreRegistry()
        registry.register(TestStore())
        registry.unregister(TestStore.self)
        #expect(registry.resolve(TestStore.self) == nil)
    }
}

// MARK: - LazyNode

@Suite("LazyNode")
struct LazyNodeTests {

    @Test("isLoaded is false before first access")
    func notLoadedInitially() {
        let store = TestStore()
        #expect(store.$premium.isLoaded == false)
    }

    @Test("accessing wrappedValue creates the NodeStore")
    func firstAccessCreates() {
        let store = TestStore()
        _ = store.premium          // triggers lazy init
        #expect(store.$premium.isLoaded == true)
    }

    @Test("repeated accesses return the same NodeStore instance")
    func sameInstanceOnRepeatAccess() async {
        let store = TestStore()
        let first  = store.premium
        let second = store.premium
        // NodeStore is an actor (reference type) — identity check via ObjectIdentifier
        #expect(ObjectIdentifier(first) == ObjectIdentifier(second))
    }

    @Test("LazyNode store is functional — can send mutations")
    func lazyStoreIsFunctional() async {
        let store = TestStore()
        await store.premium.send { $0.add("hello") }
        let items = await store.premium.state.items
        #expect(items == ["hello"])
    }
}

// MARK: - @Node macro integration with GlobalStore

@Suite("Node macro + GlobalStore integration")
struct NodeMacroIntegrationTests {

    @Test("@Node struct works inside a GlobalStore")
    func nodeInStore() async {
        let store = TestStore()
        await store.tasks.send { $0.add("buy milk") }
        await store.settings.send { $0.toggle() }

        let items      = await store.tasks.state.items
        let darkMode   = await store.settings.state.darkMode

        #expect(items == ["buy milk"])
        #expect(darkMode == true)
    }

    @Test("SignalBus wires two NodeStores inside a GlobalStore")
    func interNodeWiringInStore() async {
        let store = TestStore()
        let bus   = SignalBus()

        // Mirror every added task into the premium (lazy) store
        await bus.observe(store.tasks) { signal in
            if case .added(let item) = signal {
                await store.premium.send { $0.add("copy: \(item)") }
            }
        }

        // Subscribe before emitting so no yield is needed to warm up the Task.
        let premiumSub = store.premium.signals.subscribe()
        let echoes = Task<[String], Never> {
            var results: [String] = []
            for await signal in premiumSub {
                if case .added(let item) = signal { results.append(item) }
                if results.count == 2 { break }
            }
            return results
        }

        await store.tasks.send { $0.add("write tests") }
        await store.tasks.send { $0.add("ship it") }

        #expect(await echoes.value == ["copy: write tests", "copy: ship it"])
        await bus.cancelAll()
    }
}
