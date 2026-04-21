/// Marks a class as a SECA `GlobalStore`.
///
/// The macro synthesises:
/// - `GlobalStore` protocol conformance via an extension.
/// - A default `public init()` that auto-registers the instance in
///   `StoreRegistry.shared` if no user-defined `init()` is present.
///
/// ```swift
/// @GlobalStore
/// class AppStore: ObservableObject {
///     @Published var name = "World"
/// }
///
/// // Auto-registered — resolve anywhere:
/// let store = StoreRegistry.shared.resolve(AppStore.self)
/// ```
///
/// If you need custom initialisation, define your own `init()` and call
/// `StoreRegistry.shared.register(self)` yourself:
///
/// ```swift
/// @GlobalStore
/// class DatabaseStore {
///     init(path: String) {
///         self.path = path
///         StoreRegistry.shared.register(self)
///     }
/// }
/// ```
@attached(extension, conformances: GlobalStore)
@attached(member, names: named(init()))
public macro GlobalStore() = #externalMacro(module: "SECAMacros", type: "GlobalStoreMacro")
