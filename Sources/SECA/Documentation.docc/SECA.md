# ``SECA``

Swift Event-driven Composable Architecture — a Swift 6-native alternative to TCA.

## Overview

SECA models your app as a graph of plain Swift structs called **Nodes**. Each node owns a slice of state, exposes mutations as ordinary `mutating` methods, and broadcasts typed **Signals** when something interesting happens. `NodeStore` wraps a node in an actor for thread safety and records every mutation in a **Timeline**.

The framework is layered — adopt only what you need:

- **Core** — `Node` + `NodeStore` is all a small app needs.
- **Signals** — `SignalResponder` lets a node declare which other node's signals it handles; `autoWire(to:)` activates the connection in one line.
- **GlobalStore** — a named singleton container, injectable via `@Store` in SwiftUI.
- **CQRS** — `CommandBus` and `QueryBus` for apps that need decoupled dispatch or cached queries.
- **Macros** — `@Node` and `@GlobalStore` eliminate conformance boilerplate.

## Topics

### Getting started

- <doc:GettingStarted>

### Core

- ``Node``
- ``NodeStore``

### Signals

- ``Signal``
- ``SignalStream``
- ``SignalResponder``
- ``SignalBus``

### GlobalStore

- ``GlobalStore``
- ``StoreRegistry``
- ``LazyNode``

### SwiftUI

- ``Store``
- ``ObservedNode``

### CQRS

- ``Command``
- ``CommandBus``
- ``Query``
- ``QueryBus``
- ``QueryCachePolicy``

### Timeline

- ``Timeline``
- ``TimelineEvent``
- ``Snapshot``

### Macros

- ``Node()``
- ``GlobalStore()``
- ``Query(cache:)``

### Architecture deep-dive

- <doc:Architecture>
