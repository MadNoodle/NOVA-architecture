/// Marks a class as a SECA `GlobalStore`.
///
/// The macro synthesises:
/// - `GlobalStore` protocol conformance via an extension.
/// - A default `public init()` if none is defined.
///
/// ## StoreRegistry path (default)
///
/// By default (`autoRegister: true`), the synthesised `init()` calls
/// `StoreRegistry.shared.register(self)` automatically. Resolve anywhere with
/// `@Store` or `StoreRegistry.shared.resolve(AppStore.self)`.
///
/// ```swift
/// @GlobalStore          // autoRegister: true implied
/// @Observable
/// final class AppStore: GlobalStore {
///     let counter = NodeStore<CounterNode>()
/// }
/// ```
///
/// ## SwiftUI Environment path (`autoRegister: false`)
///
/// When using SwiftUI's `@Environment` for dependency injection, opt out of
/// auto-registration to avoid the global singleton entirely:
///
/// ```swift
/// @GlobalStore(autoRegister: false)
/// @Observable
/// final class AppStore: GlobalStore {
///     let counter = NodeStore<CounterNode>()
/// }
///
/// // At the app root:
/// WindowGroup { RootView().injectStore(AppStore()) }
///
/// // In any descendant view:
/// @Environment(AppStore.self) private var appStore
/// ```
///
/// If you need a custom `init()` with parameters, define it yourself and call
/// `StoreRegistry.shared.register(self)` when appropriate:
///
/// ```swift
/// @GlobalStore(autoRegister: false)
/// class DatabaseStore {
///     init(path: String) { self.path = path }
/// }
/// ```
@attached(extension, conformances: GlobalStore)
@attached(member, names: named(init()))
public macro GlobalStore(autoRegister: Bool = true) = #externalMacro(module: "NOVAMacros", type: "GlobalStoreMacro")
