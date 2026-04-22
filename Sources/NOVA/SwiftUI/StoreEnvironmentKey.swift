#if canImport(SwiftUI)
import SwiftUI
import Observation

extension View {
    /// Injects an `@Observable` `GlobalStore` into the SwiftUI environment.
    ///
    /// Child views retrieve it with `@Environment(StoreType.self)`:
    /// ```swift
    /// // At the app root:
    /// @main struct MyApp: App {
    ///     @Observable final class AppStore: GlobalStore { ... }
    ///     let store = AppStore()
    ///     var body: some Scene {
    ///         WindowGroup { RootView().injectStore(store) }
    ///     }
    /// }
    ///
    /// // In any descendant view:
    /// struct CounterView: View {
    ///     @Environment(AppStore.self) private var appStore
    /// }
    /// ```
    ///
    /// **Prefer this over `@Store` / `StoreRegistry` for SwiftUI code.**
    /// The environment path avoids the global singleton, works correctly in
    /// SwiftUI Previews, and requires no teardown in tests.
    ///
    /// - Note: The store **must** be annotated `@Observable` (or use `@GlobalStore`
    ///   which synthesises the conformance). Without `@Observable`, SwiftUI cannot
    ///   propagate the store through the environment and `@Environment` will return
    ///   a default-initialised placeholder. This constraint is enforced at
    ///   compile-time via the `Observable` protocol requirement.
    public func injectStore<S: GlobalStore & Observable>(_ store: S) -> some View {
        environment(store)
    }
}
#endif
