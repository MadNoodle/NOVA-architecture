import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - Diagnostic messages

struct NOVADiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    /// Emitted when a method calls `emit()` but is not marked `mutating`.
    static func missingMutating(method: String) -> Self {
        .init(
            message: "'\(method)' calls emit() but is not marked 'mutating' — state changes made in this method won't be visible to NodeStore. Mark it 'mutating'.",
            diagnosticID: .init(domain: "NOVA", id: "missingMutating"),
            severity: .warning
        )
    }
}

// MARK: - Fix-it messages

struct NOVAFixIt: FixItMessage {
    let message: String
    let fixItID: MessageID

    static let addMutating = NOVAFixIt(
        message: "Add 'mutating'",
        fixItID: .init(domain: "NOVA", id: "addMutating")
    )
}

// MARK: - AST helpers

/// Returns `true` if `block` contains a direct call to `emit(…)` in its
/// statement list. Uses AST traversal (not string search) to avoid false
/// positives from comments or string literals.
func containsEmitCall(in block: CodeBlockSyntax) -> Bool {
    final class EmitVisitor: SyntaxVisitor {
        var found = false

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self),
               ref.baseName.text == "emit" {
                found = true
                return .skipChildren
            }
            return .visitChildren
        }
    }
    let visitor = EmitVisitor(viewMode: .sourceAccurate)
    visitor.walk(block)
    return visitor.found
}
