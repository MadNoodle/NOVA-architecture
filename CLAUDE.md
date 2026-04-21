# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

SECA (Swift Event-driven Composable Architecture) is an open-source iOS/macOS framework — a Swift 6-native alternative to TCA. It combines Event Sourcing, CQRS, and `@Observable`-based state management with zero external dependencies.

Target platforms: iOS 17+, macOS 14+, watchOS 10+, visionOS 1+. Swift 6 strict concurrency is mandatory from day one.

## Commands

```bash
# Build the package
swift build

# Run all tests
swift test

# Run a single test
swift test --filter SECATests/NodeTests

# Run benchmarks
swift run SECABenchmarks

# Lint (once SwiftLint is configured)
swiftlint
```

## Architecture

Five core concepts, each mapping to a module under `Sources/SECA/`:

### Node (`Core/`)
The unit of business logic. A struct marked with `@Node` becomes `@Observable` and thread-safe via an Actor under the hood. Mutations are called directly as methods — no Action enums. Nodes emit typed `Signal`s instead of dispatching actions.

### GlobalStore (`GlobalStore/`)
A single actor (`@GlobalStore`) that owns all Nodes. `@LazyNode` defers instantiation. SwiftUI views bind via `@Store`. This is the single source of truth for the app.

### Signals (`Signals/`)
Inter-node communication via `AsyncSequence`. A Node calls `emit(.someSignal)`. Other Nodes declare `@Listens(OtherNode.self, on: .someSignal)`. The raw stream is available as `store.nodeX.signals`.

### CQRS (`CQRS/`)
- **Commands** — mutate state, return nothing, dispatched via `bus.send()`
- **Queries** — read-only, cacheable, declared with `@Query(cache: .invalidateOn(\.someProperty))`

### Timeline (`Timeline/`)
Every mutation is recorded automatically. Supports `undo()`, `redo()`, `replay(to:)`, and snapshot export. Tests can replay a `Timeline` fixture against a Node with no mocking needed.

### Macros (`Macros/`)
Swift macros expand `@Node`, `@GlobalStore`, `@Query`, and `@Observed`. Macro expansion tests live in `Tests/SECATests/MacroTests.swift`.

## Quality standards

- Swift 6 strict concurrency — zero concurrency warnings
- Zero external dependencies
- Test coverage > 80%
- DocC documentation on all public APIs
- Zero Xcode warnings
- SwiftLint configured and passing

## Development workflow

Each session targets one roadmap milestone from `SPECS.md`. After implementation: integrate in Xcode, run tests, fix errors, then commit and update the roadmap checklist in `SPECS.md`.
