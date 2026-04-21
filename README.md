# SECA

**Swift Event-driven Composable Architecture** — a Swift 6-native alternative to TCA.

SECA models your app as a graph of plain Swift structs called **Nodes**. Each node owns a slice of state, exposes mutations as ordinary `mutating func`, and broadcasts typed **Signals** when something interesting happens. Zero external runtime dependencies.

---

## Features

- **Plain structs as state** — no reducers, no action enums, just `mutating func`
- **Typed signals** — inter-node communication via `AsyncSequence`, not callbacks
- **`SignalResponder`** — nodes declare their own signal dependencies; `GlobalStore` wires them in one line
- **Built-in time travel** — every mutation is recorded; `undo()`, `redo()`, `replay(to:)` out of the box
- **SwiftUI-ready** — `@Store`, `@ObservedNode`, `@LazyNode` property wrappers
- **Macro-powered** — `@Node` eliminates conformance boilerplate
- **CQRS optional** — `CommandBus` and `QueryBus` are available for apps that need decoupled dispatch or cached queries
- **Swift 6 strict concurrency** — zero data-race warnings, actor-isolated by default

---

## Requirements

| Platform | Minimum |
|---|---|
| iOS | 17+ |
| macOS | 14+ |
| watchOS | 10+ |
| visionOS | 1+ |
| Swift | 6.2+ |

---

## Installation

Add SECA to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SECA.git", from: "0.5.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["SECA"]),
]
```

---

## Quick Start

### 1. Define a Node

```swift
import SECA

@Node
struct CounterNode {
    enum Signal: SECA.Signal { case incremented(Int) }

    var count = 0
    mutating func increment() { count += 1; emit(.incremented(count)) }
    mutating func reset()     { count = 0 }
}
```

### 2. React to signals in another Node

Declare signal dependencies on the node that cares — not in the store.

```swift
@Node
struct LogNode: SignalResponder {
    typealias Source = CounterNode

    var entries: [String] = []

    mutating func receive(_ signal: CounterNode.Signal) {
        switch signal {
        case .incremented(let v): entries.append("count → \(v)")
        }
    }
}
```

### 3. Wire everything in a GlobalStore

```swift
final class AppStore: GlobalStore {
    let counter = NodeStore<CounterNode>()
    let log     = NodeStore<LogNode>()

    init() {
        _routing = log.autoWire(to: counter)   // one line — declared by LogNode
        StoreRegistry.shared.register(self)
    }

    private let _routing: Task<Void, Never>
}
```

### 4. Use it in SwiftUI

```swift
struct CounterView: View {
    @Store var store: AppStore

    var body: some View {
        VStack {
            Text("\(store.counter.state.count)")
            Button("+") { Task { await store.counter.send { $0.increment() } } }
            Button("↩") { Task { await store.counter.undo() } }
        }
    }
}
```

---

## Architecture

SECA is built from five orthogonal concepts. Adopt them incrementally — a small app needs only `Node` + `NodeStore`.

```
┌─────────────────────────────────────────────────────┐
│                      SwiftUI                        │
│             @Store  @ObservedNode  @LazyNode        │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                   GlobalStore                       │
│           StoreRegistry  ·  autoWire(to:)           │
└──────┬──────────────────────────┬───────────────────┘
       │                          │
┌──────▼──────┐          ┌────────▼──────────────┐
│ NodeStore   │  signals  │  SignalResponder       │
│ (actor)     │ ────────► │  receive(_:) on Node  │
│  timeline   │          └───────────────────────┘
└──────┬──────┘
       │
┌──────▼──────┐
│    Node     │  plain struct · mutating methods · emit()
└─────────────┘
```

### Node

The unit of business logic. A plain `Sendable` struct — state lives here, mutations are `mutating func`, side-effects are typed `Signal`s emitted with `emit()`.

### NodeStore

An actor that owns a node's value. Serialises writes, fans signals out to subscribers, and records every mutation snapshot in a `Timeline`.

```swift
await store.send { $0.increment() }
let previous = await store.undo()   // returns restored state
let snap = store.timeline.snapshot()
```

### Signals and SignalResponder

Signals are emitted inside mutations and broadcast via an `AsyncSequence` stream. Any node can declare that it receives signals from another:

```swift
extension AnalyticsNode: SignalResponder {
    typealias Source = PurchaseNode

    mutating func receive(_ signal: PurchaseNode.Signal) {
        if case .completed(let order) = signal { track(order) }
    }
}

// GlobalStore wires it in one line:
_routing = analytics.autoWire(to: purchases)
```

For advanced topologies (fan-out, filtering, cross-process) `SignalBus` is still available.

### Timeline

Every `send(_:)` is recorded automatically. Full time-travel with no extra setup:

```swift
await store.undo()                   // revert last mutation
await store.redo()                   // re-apply
await store.replay(to: oneMinuteAgo) // jump to a point in time
let snap = store.timeline.snapshot() // immutable export for tests / analytics
```

### CQRS (optional)

`CommandBus` and `QueryBus` are available for apps that need decoupled dispatch, middleware, or cached query results. They are not required for the core patterns.

---

## Testing

Nodes are plain structs — no mocking needed. Feed a `NodeStore` directly in tests.

```swift
@Test("increment emits signal")
func incrementEmitsSignal() async {
    let store = NodeStore<CounterNode>()
    let collector = Task {
        var out: [CounterNode.Signal] = []
        for await s in store.signals.subscribe() {
            out.append(s)
            if out.count == 2 { break }
        }
        return out
    }
    await store.send { $0.increment() }
    await store.send { $0.increment() }
    #expect(await collector.value == [.incremented(1), .incremented(2)])
}
```

---

## License

MIT. See [LICENSE](LICENSE).
