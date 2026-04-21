import Foundation
import SECA

// MARK: - LogNode

/// Receives signals from `CounterNode` and maintains a timestamped audit log.
@Node
struct LogNode: SignalResponder {

    // MARK: SignalResponder

    typealias Source = CounterNode

    mutating func receive(_ signal: CounterNode.Signal) {
        let (message, kind): (String, Entry.Kind) = switch signal {
        case .incremented(let v): ("↑  count → \(v)",      .increment)
        case .decremented(let v): ("↓  count → \(v)",      .decrement)
        case .reset:              ("⟳  reset to 0",         .reset)
        case .clamped(let v):     ("⚠️  clamped to \(v)",   .clamped)
        }
        append(message: message, kind: kind)
    }

    enum Signal: SECA.Signal {}  // LogNode broadcasts nothing

    // MARK: Entry

    struct Entry: Identifiable, Sendable {
        let id        = UUID()
        let message:  String
        let timestamp: Date
        let kind:     Kind

        enum Kind: Sendable {
            case increment, decrement, reset, clamped, undo, redo
        }
    }

    // MARK: State

    var entries: [Entry] = []

    // MARK: Mutations

    mutating func append(message: String, kind: Entry.Kind) {
        entries.append(Entry(message: message, timestamp: Date(), kind: kind))
    }

    mutating func clear() {
        entries.removeAll()
    }
}
