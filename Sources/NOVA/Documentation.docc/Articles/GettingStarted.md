# Getting Started with SECA

Build a working counter app from scratch in minutes.

## Overview

This article walks through the three steps every SECA app follows:

1. Define a **Node** — a plain struct that holds state and emits signals.
2. Wrap it in a **GlobalStore** and register it at startup.
3. Bind it to a **SwiftUI view**.

A fourth step shows how a second node reacts to the first using ``SignalResponder``.

## Step 1 — Define a Node

A node is a `Sendable` struct that conforms to ``Node``. Use the ``Node()`` macro to generate the conformance and a default `init()` automatically.

```swift
import NOVA

@Node
struct CounterNode {
    enum Signal: NOVA.Signal {
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
```

Calling ``NodeContext/emit(_:)`` inside a mutation broadcasts the signal to every subscriber of the store's ``NodeStore/signals`` stream. Calls outside a ``NodeStore/send(_:)`` context are silently dropped.

## Step 2 — React to signals in another Node

Conform a second node to ``SignalResponder`` to declare that it handles signals from `CounterNode`. The routing logic lives here — not in the store.

```swift
@Node
struct LogNode: SignalResponder {
    typealias Source = CounterNode

    var entries: [String] = []

    mutating func receive(_ signal: CounterNode.Signal) {
        switch signal {
        case .incremented(let v): entries.append("count → \(v)")
        case .reset:              entries.append("reset")
        }
    }

    mutating func clear() { entries.removeAll() }
}
```

## Step 3 — Create a GlobalStore

A ``GlobalStore`` is a reference-type container (typically `final class`) that owns one ``NodeStore`` per node and wires signal routing in `init`.

```swift
import NOVA

final class AppStore: GlobalStore {
    let counter = NodeStore<CounterNode>()
    let log     = NodeStore<LogNode>()

    init() {
        // log.receive(_:) is called for every signal counter emits.
        _routing = log.autoWire(to: counter)
        StoreRegistry.shared.register(self)
    }

    private let _routing: Task<Void, Never>
}
```

Register the store once at startup — before any view is created:

```swift
@main
struct MyApp: App {
    private let store = AppStore()

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

## Step 4 — Bind to SwiftUI

The ``Store`` property wrapper resolves the registered singleton from ``StoreRegistry``. Call mutations directly on the node store — no bus needed.

```swift
struct CounterView: View {
    @Store var app: AppStore

    var body: some View {
        VStack(spacing: 16) {
            Text("\(app.counter.state.count)")
                .font(.largeTitle)

            HStack {
                Button("+") {
                    Task { await app.counter.send { $0.increment() } }
                }
                Button("Reset") {
                    Task { await app.counter.send { $0.reset() } }
                }
                Button("↩ Undo") {
                    Task { await app.counter.undo() }
                }
            }

            // Log entries update automatically via SignalResponder
            List(app.log.state.entries, id: \.self) { Text($0) }
        }
    }
}
```

> Note: `app.counter.state` is actor-isolated. SwiftUI reads it on the main actor via `@ObservedNode` — that is safe as long as you never write to it from outside `send(_:)`.

## What's next

- Explore the full architecture in <doc:Architecture>.
- Add a cached query with ``QueryBus`` and ``QueryCachePolicy/forever``.
- Export history with ``Timeline/snapshot()`` for debugging or analytics.
- Use ``SignalBus`` for fan-out to multiple handlers or dynamic routing.
