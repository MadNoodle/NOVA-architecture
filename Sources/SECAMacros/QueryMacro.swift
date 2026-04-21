import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @Query macro implementation

/// Implementation of the `@Query` attached macro.
///
/// Roles:
/// - `AccessorMacro` — wraps the getter with caching logic when `cache: .forever`.
/// - `PeerMacro`     — synthesises `private var _query_<name>: T?` backing storage
///                     for `cache: .forever`.
///
/// For `cache: .never` (default) both expansions are no-ops — the macro acts as
/// a pure documentation / intent marker.
public struct QueryMacro: AccessorMacro, PeerMacro {

    // MARK: AccessorMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard cachePolicy(from: attribute) == .forever else { return [] }

        guard
            let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let name    = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            let block   = binding.accessorBlock
        else { return [] }

        let body = extractGetterBody(from: block)

        return [
            """
            get {
                if let _cached = _query_\(raw: name) { return _cached }
                let _result: _ = \(raw: body)
                _query_\(raw: name) = _result
                return _result
            }
            """
        ]
    }

    // MARK: PeerMacro

    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard cachePolicy(from: attribute) == .forever else { return [] }

        guard
            let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let name    = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            let typeAnn = binding.typeAnnotation
        else { return [] }

        let typeName = typeAnn.type.trimmedDescription
        return ["private var _query_\(raw: name): \(raw: typeName)?"]
    }

    // MARK: Helpers

    private enum CachePolicy { case never, forever }

    private static func cachePolicy(from attribute: AttributeSyntax) -> CachePolicy {
        guard
            let args = attribute.arguments?.as(LabeledExprListSyntax.self),
            let cacheArg = args.first(where: { $0.label?.text == "cache" })
        else { return .never }

        return cacheArg.expression.trimmedDescription.contains("forever") ? .forever : .never
    }

    /// Extracts the body statements from either a shorthand getter `{ stmts }`
    /// or an explicit `get { stmts }` accessor block.
    private static func extractGetterBody(from block: AccessorBlockSyntax) -> String {
        switch block.accessors {
        case .getter(let stmts):
            return stmts.trimmedDescription
        case .accessors(let list):
            if let get = list.first(where: { $0.accessorSpecifier.trimmedDescription == "get" }),
               let body = get.body {
                return body.statements.trimmedDescription
            }
            return ""
        }
    }
}
