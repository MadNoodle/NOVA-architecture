import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @GlobalStore macro implementation

/// Implementation of the `@GlobalStore` attached macro.
///
/// Roles:
/// - `ExtensionMacro` — emits `extension T: GlobalStore {}`.
/// - `MemberMacro`   — synthesises a default `init()`. When `autoRegister` is
///                     `true` (the default), the init calls
///                     `StoreRegistry.shared.register(self)`.
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

    // MARK: MemberMacro — synthesises init() with optional auto-registration

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

        // Read the `autoRegister` argument (defaults to true when absent).
        let autoRegister = extractBoolArgument("autoRegister", from: attribute) ?? true

        if autoRegister {
            // `StoreRegistry.shared.register(self)` is placed at the END of the
            // generated init body. Stored properties with default values (the typical
            // pattern for GlobalStore subclasses) are initialised by their property
            // initialisers before the init body runs, so `self` is fully formed here.
            return [
                """
                public init() {
                    StoreRegistry.shared.register(self)
                }
                """
            ]
        } else {
            // Environment-path stores opt out of auto-registration.
            return [
                """
                public init() {}
                """
            ]
        }
    }
}

// MARK: - Argument extraction helper

/// Reads a `Bool` literal argument from a macro attribute by parameter label.
/// Returns `nil` if the argument is absent or not a bool literal.
private func extractBoolArgument(
    _ label: String,
    from attribute: AttributeSyntax
) -> Bool? {
    guard
        case .argumentList(let args) = attribute.arguments,
        let arg = args.first(where: { $0.label?.text == label }),
        let boolLit = arg.expression.as(BooleanLiteralExprSyntax.self)
    else { return nil }
    return boolLit.literal.tokenKind == .keyword(.true)
}
