import SwiftUI

/// A SwiftUI property wrapper that resolves a `GlobalStore` singleton from
/// `StoreRegistry` and makes it available inside a view.
///
/// ## Usage
///
/// Register the store **once** at app startup, then bind in any view:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     let store = AppStore()
///     var body: some Scene {
///         WindowGroup { RootView() }
///             .registeringStore(store)   // preferred
///     }
/// }
///
/// struct RootView: View {
///     @Store var store: AppStore
///     var body: some View {
///         Text("\(store.counter.state.count) taps")
///     }
/// }
/// ```
///
/// ## Registration options
///
/// **Option A — View modifier (recommended):**
/// ```swift
/// WindowGroup { RootView() }
///     .registeringStore(AppStore())
/// ```
///
/// **Option B — Manual (at app startup):**
/// ```swift
/// StoreRegistry.shared.register(AppStore())
/// ```
///
/// If no store is registered when `@Store` first resolves the type, the app
/// will crash with a clear diagnostic message. This is intentional — missing
/// registration is a programming error, not a recoverable runtime condition.
@propertyWrapper
public struct Store<S: GlobalStore>: DynamicProperty {

    private let instance: S

    public var wrappedValue: S { instance }

    public init() {
        guard let resolved = StoreRegistry.shared.resolve(S.self) else {
            fatalError(
                """
                [NOVA] @Store failed to resolve \(S.self).

                You must register the store before any view that uses @Store appears.
                Choose one of:

                  1. Add .registeringStore(AppStore()) to your root scene (recommended).
                  2. Call StoreRegistry.shared.register(AppStore()) in App.init().

                For tests, call StoreRegistry.shared.register(_:) in setUp() and
                StoreRegistry.shared.unregister(\(S.self).self) in tearDown().
                """
            )
        }
        self.instance = resolved
    }
}

// MARK: - View modifier

extension View {
    /// Registers `store` in `StoreRegistry` so every descendant that uses `@Store` can
    /// resolve the same instance.
    ///
    /// ```swift
    /// // In your App struct — hold the store in a `let` property, not inline:
    /// struct MyApp: App {
    ///     let store = AppStore()          // ← retained here, created once
    ///     var body: some Scene {
    ///         WindowGroup { RootView().registeringStore(store) }
    ///     }
    /// }
    /// ```
    ///
    /// > Important: Do **not** construct the store inline (e.g. `.registeringStore(AppStore())`).
    /// > SwiftUI can evaluate a view's body multiple times; each evaluation would create a fresh
    /// > store and overwrite the registry, silently discarding previous state. Always hold the
    /// > store as a `let` constant on the `App` struct (or pass it from the call site).
    ///
    /// Registration happens synchronously during modifier application, so `@Store` in any child
    /// view's `init` will find the instance immediately — no timing gap.
    public func registeringStore<S: GlobalStore>(_ store: S) -> some View {
        StoreRegistry.shared.register(store)
        return self
    }
}
