import Foundation

/// Marker protocol for app-level stores that own a collection of `NodeStore`s.
///
/// Conform your store to `GlobalStore`, register it once at app startup via
/// `StoreRegistry`, then inject it into SwiftUI views with `@Store`.
///
/// ```swift
/// @Observable
/// final class AppStore: GlobalStore {
///     let counter = NodeStore<CounterNode>()
///     let log     = NodeStore<LogNode>()
///     @LazyNode var premium: NodeStore<PremiumNode>
///     let bus     = SignalBus()
/// }
///
/// // At app startup:
/// StoreRegistry.shared.register(AppStore())
/// ```
public protocol GlobalStore: AnyObject, Sendable {}

// MARK: - StoreRegistry

/// Maps `GlobalStore` types to their singleton instances.
///
/// Register once at app launch; resolve anywhere via
/// `StoreRegistry.shared.resolve(_:)` or the `@Store` property wrapper.
public final class StoreRegistry: @unchecked Sendable {

    /// The process-wide registry.
    public static let shared = StoreRegistry()

    private var storage: [ObjectIdentifier: any GlobalStore] = [:]
    private let lock = NSLock()

    init() {}

    /// Registers `store` as the singleton for its type.
    /// Replaces any previously registered instance of the same type.
    public func register<S: GlobalStore>(_ store: S) {
        lock.withLock { storage[ObjectIdentifier(S.self)] = store }
    }

    /// Returns the registered singleton for `S`, or `nil` if none was registered.
    public func resolve<S: GlobalStore>(_ type: S.Type = S.self) -> S? {
        lock.withLock { storage[ObjectIdentifier(type)] as? S }
    }

    /// Removes the registered singleton for `S`.
    /// Primarily useful in tests to reset state between test cases.
    public func unregister<S: GlobalStore>(_ type: S.Type) {
        lock.withLock { _ = storage.removeValue(forKey: ObjectIdentifier(type)) }
    }
}
