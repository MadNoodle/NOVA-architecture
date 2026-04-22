/// Marker protocol for mutation requests in the CQRS pattern.
///
/// Commands modify state and return nothing. Dispatch them through
/// `CommandBus` to keep mutations decoupled from the callers.
///
/// ```swift
/// struct AddEntry: Command { let entry: AnxietyEntry }
/// struct ClearEntries: Command {}
///
/// await bus.send(AddEntry(entry: entry))
/// ```
public protocol Command: Sendable {}

// MARK: - Errors

public enum CommandBusError: Error, Sendable {
    /// No handler was registered for the dispatched command type.
    case noHandlerRegistered(commandType: String)
}
