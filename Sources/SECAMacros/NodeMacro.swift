import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics

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

        // Scan for methods that call emit() without being marked `mutating`.
        // Uses AST traversal to avoid false positives from comments/strings.
        for member in declaration.memberBlock.members {
            guard let fn = member.decl.as(FunctionDeclSyntax.self),
                  let body = fn.body else { continue }
            let isMutating = fn.modifiers.contains {
                $0.name.tokenKind == .keyword(.mutating)
            }
            guard !isMutating, containsEmitCall(in: body) else { continue }

            // Build corrected declaration with `mutating` inserted after
            // access modifiers (public/internal/private) to produce
            // `public mutating func` rather than `mutating public func`.
            var mods = fn.modifiers
            let accessIdx = mods.lastIndex(where: {
                [.keyword(.public), .keyword(.internal),
                 .keyword(.private), .keyword(.fileprivate)]
                    .contains($0.name.tokenKind)
            })
            let insertAt = accessIdx.map { mods.index(after: $0) } ?? mods.startIndex
            mods.insert(DeclModifierSyntax(name: .keyword(.mutating)), at: insertAt)
            let corrected = fn.with(\.modifiers, mods)

            context.diagnose(Diagnostic(
                node: fn.name,
                message: SECADiagnostic.missingMutating(method: fn.name.text),
                fixIts: [FixIt(
                    message: SECAFixIt.addMutating,
                    changes: [.replace(oldNode: Syntax(fn), newNode: Syntax(corrected))]
                )]
            ))
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
