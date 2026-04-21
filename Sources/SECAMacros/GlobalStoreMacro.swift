import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @GlobalStore macro implementation

/// Implementation of the `@GlobalStore` attached macro.
///
/// Roles:
/// - `ExtensionMacro` — emits `extension T: GlobalStore {}`.
/// - `MemberMacro`   — synthesises a default `init()` that auto-registers the
///                     store in `StoreRegistry` if no user-defined init is present.
public struct GlobalStoreMacro: ExtensionMacro, MemberMacro {

    // MARK: ExtensionMacro — adds GlobalStore conformance

    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let ext: DeclSyntax = "extension \(type.trimmed): GlobalStore {}"
        return [ext.cast(ExtensionDeclSyntax.self)]
    }

    // MARK: MemberMacro — synthesises init() with auto-registration

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Only add init() if none is already defined.
        let hasInit = declaration.memberBlock.members.contains { item in
            item.decl.is(InitializerDeclSyntax.self)
        }
        guard !hasInit else { return [] }

        // `StoreRegistry.shared.register(self)` is placed at the END of the
        // generated init body. Stored properties with default values (the typical
        // pattern for GlobalStore subclasses) are initialised by their property
        // initialisers before the init body runs, so `self` is fully formed here.
        // If you need complex setup, define your own init and call register(self)
        // at the end after all properties are ready.
        return [
            """
            public init() {
                StoreRegistry.shared.register(self)
            }
            """
        ]
    }
}
