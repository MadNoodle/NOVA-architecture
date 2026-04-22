/// Routes `Command` values to their registered async handlers.
///
/// Register one handler per command type, then dispatch from anywhere:
///
/// ```swift
/// let bus = CommandBus()
///
/// await bus.register(AddEntry.self) { cmd in
///     await entriesStore.send { $0.add(cmd.entry) }
/// }
///
/// try await bus.send(AddEntry(entry: newEntry))
/// ```
///
/// Dispatching an unregistered command throws `CommandBusError.noHandlerRegistered`.
public actor CommandBus {

    /// Type-erased handler: accepts `Any` (cast internally) and may throw.
    private typealias Handler = @Sendable (Any) async throws -> Void
    private var handlers: [ObjectIdentifier: Handler] = [:]

    public init() {}

    // MARK: Registration

    /// Registers `handler` to be called whenever a command of type `C` is dispatched.
    /// Replaces any previously registered handler for that type.
    public func register<C: Command>(
        _ type: C.Type = C.self,
        handler: @Sendable @escaping (C) async throws -> Void
    ) {
        handlers[ObjectIdentifier(type)] = { any in
            guard let command = any as? C else { return }
            try await handler(command)
        }
    }

    /// Removes the handler for command type `C`.
    public func unregister<C: Command>(_ type: C.Type) {
        handlers.removeValue(forKey: ObjectIdentifier(type))
    }

    // MARK: Dispatch

    /// Dispatches `command` to its registered handler.
    ///
    /// - Throws: `CommandBusError.noHandlerRegistered` if no handler exists.
    ///           Re-throws any error from the handler itself.
    public func send<C: Command>(_ command: C) async throws {
        guard let handler = handlers[ObjectIdentifier(C.self)] else {
            throw CommandBusError.noHandlerRegistered(commandType: "\(C.self)")
        }
        try await handler(command)
    }
}
