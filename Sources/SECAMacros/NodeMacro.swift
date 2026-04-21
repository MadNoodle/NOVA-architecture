import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

// MARK: - @Node macro implementation

/// Implementation of the `@Node` attached macro.
///
/// Roles:
/// - `ExtensionMacro`  — emits `extension T: Node {}` so the user doesn't have
///                       to write the conformance manually.
/// - `MemberMacro`     — synthesises `public init() {}` when no default init
///                       is present (required by the `Node` protocol).
public struct NodeMacro: ExtensionMacro, MemberMacro {

    // MARK: ExtensionMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Always emit the conformance extension.
        // The compiler deduplicates conformances that are already present,
        // so this is safe even if the user wrote `: Node` manually.
        let ext: DeclSyntax = "extension \(type.trimmed): Node {}"
        return [ext.cast(ExtensionDeclSyntax.self)]
    }

    // MARK: MemberMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let hasDefaultInit = declaration.memberBlock.members.contains { item in
            guard let initDecl = item.decl.as(InitializerDeclSyntax.self) else { return false }
            return initDecl.signature.parameterClause.parameters.isEmpty
        }
        guard !hasDefaultInit else { return [] }
        return ["public init() {}"]
    }
}

// MARK: - Plugin entry point

@main
struct SECAMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        NodeMacro.self,
        QueryMacro.self,
        GlobalStoreMacro.self,
    ]
}
