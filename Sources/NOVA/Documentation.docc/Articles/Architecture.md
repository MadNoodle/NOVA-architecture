# Architecture

How SECA's five layers fit together.

## Overview

SECA is built from five orthogonal concepts. You can adopt them incrementally — a small app might only need `Node` + `NodeStore`, while a larger one benefits from `SignalResponder`, `GlobalStore`, and optionally CQRS on top.

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

          Optional layer:
          ┌──────────────────┐
          │  CQRS            │
          │  CommandBus      │
          │  QueryBus        │
          └──────────────────┘
```

## Node and NodeStore

``Node`` is a protocol — a plain `Sendable` struct with a nested `Signal` type and an `init()`. All business logic lives here as `mutating func` methods. Calling ``NodeContext/emit(_:)`` inside a mutation schedules a signal for broadcast after the mutation completes.

``NodeStore`` is an actor that:

- Holds the node's current value as `state`.
- Routes `emit()` calls made during `send(_:)` to the ``SignalStream`` broadcast.
- Records each post-mutation snapshot in a ``Timeline``.

Because `NodeStore` is an actor, all writes are serialised automatically and reading `state` from any async context is data-race free.

`undo()` and `redo()` return the restored node state (discardable), so callers that need to react to the new value don't need a second `await`:

```swift
if let restored = await store.undo() {
    print("reverted to count \(restored.count)")
}
```

## Signals and SignalResponder

``SignalStream`` is a synchronous multicast — `yield(_:)` is called without `await` inside the actor and immediately fans out to every active `AsyncStream` subscriber.

### Declaring signal dependencies with SignalResponder

For the common case — one node reacting to another's signals — conform the destination node to ``SignalResponder`` and call `autoWire(to:)` in your `GlobalStore`:

```swift
extension LogNode: SignalResponder {
    typealias Source = CounterNode

    mutating func receive(_ signal: CounterNode.Signal) {
        switch signal {
        case .incremented(let v): append(message: "↑ count → \(v)")
        case .reset:              append(message: "reset")
        }
    }
}

// GlobalStore — one line, no Task boilerplate:
_routing = log.autoWire(to: counter)
```

`autoWire(to:)` starts a `Task` that drains the source's signal stream and calls `receive(_:)` inside an isolated `send`. Hold the returned `Task` for the lifetime of the store.

### SignalBus for advanced topologies

``SignalBus`` is still available when you need fan-out to multiple handlers, conditional routing, or dynamic subscription management:

```swift
await bus.observe(purchaseStore) { signal in
    await analyticsStore.send { $0.track(signal) }
    await badgeStore.send { $0.refresh() }
}
```

## GlobalStore and StoreRegistry

``GlobalStore`` is a marker protocol (`: AnyObject, Sendable`). A conforming class acts as the app's single source of truth — it owns `NodeStore` properties and wires signal routing in `init`.

``StoreRegistry`` is a process-wide map from `GlobalStore` type to instance. Register once at startup; resolve anywhere via `@Store` or `StoreRegistry.shared.resolve(_:)`.

``LazyNode`` defers `NodeStore` creation until first access. Useful for premium features or heavy stores that should not be allocated on cold launch.

### Responsibility rules for GlobalStore

| Belongs in GlobalStore | Belongs on Node |
|---|---|
| `autoWire(to:)` calls | Signal handler logic (`receive`) |
| Cross-node coordination (undo + log) | State, mutations, signals |
| `timelineStats` computed from `nonisolated` timeline | Business rules |

Views call mutations directly: `await store.counter.send { $0.increment() }`. There is no need for a `CommandBus` unless your app requires middleware or deferred dispatch.

## CQRS (optional)

**Commands** are `Sendable` structs that represent a mutation intent. Dispatch through ``CommandBus`` when you need decoupled dispatch — for example, dispatching from non-SwiftUI code or adding logging middleware:

```swift
struct ArchiveEntry: Command { let id: UUID }

await commandBus.register(ArchiveEntry.self) { cmd in
    await store.send { $0.archive(id: cmd.id) }
}

try await commandBus.send(ArchiveEntry(id: id))
```

**Queries** are `Sendable` structs that declare a `Result` type. ``QueryBus`` caches results per query instance:

```swift
struct RecentEntries: Query {
    typealias Result = [Entry]
    let limit: Int
}

await queryBus.register(RecentEntries.self, policy: .forever) { q in
    store.state.entries.suffix(q.limit)
}

let recent = try await queryBus.send(RecentEntries(limit: 10))
```

For simpler read access, computed properties on the `GlobalStore` reading from `nonisolated` timeline or state properties are often sufficient and require no registration.

## Timeline

Every `send(_:)` appends a ``TimelineEvent`` (timestamp + full node snapshot) to the store's ``Timeline``. The cursor starts before the first event (at genesis); undo moves it back, redo moves it forward.

```swift
store.timeline.canUndo   // true when there is a previous state
store.timeline.canRedo   // true when there is a future state
store.timeline.events    // all recorded events

await store.undo()               // revert — returns restored state
await store.redo()               // re-apply — returns restored state
await store.replay(to: date)     // non-destructive jump

let snap = store.timeline.snapshot()  // immutable export
```

Mutations after `undo()` discard the redo branch, matching the standard undo model used by text editors.

## Concurrency model

| Type | Isolation |
|---|---|
| `NodeStore<N>` | `actor` — all mutations serialised |
| `SignalBus` | `actor` |
| `CommandBus` | `actor` |
| `QueryBus` | `actor` (cache is actor-isolated) |
| `SignalStream<S>` | `@unchecked Sendable`, `NSLock` |
| `Timeline<N>` | `@unchecked Sendable`, `NSLock` |
| `LazyNode<N>` | `@unchecked Sendable`, `NSLock` |
| `StoreRegistry` | `@unchecked Sendable`, `NSLock` |
| `NodeObserver<N>` | `@MainActor` |

`SignalStream.yield(_:)` uses `NSLock` rather than actor isolation so that signals can be broadcast synchronously inside the `NodeStore` actor's synchronous `send(_:)` — no `await` needed at the emit site.
