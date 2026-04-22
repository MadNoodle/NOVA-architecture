import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import NOVAMacros

private let testMacros: [String: any Macro.Type] = [
    "Node": NodeMacro.self,
    "GlobalStore": GlobalStoreMacro.self,
]

final class MacroTests: XCTestCase {

    // MARK: Conformance + init synthesis

    func testNodeAddsConformanceAndInit() {
        assertMacroExpansion(
            """
            @Node
            struct CounterNode {
                enum Signal: Sendable { case incremented(Int) }
                var count = 0
            }
            """,
            expandedSource: """
            struct CounterNode {
                enum Signal: Sendable { case incremented(Int) \

            }
                var count = 0

                public init() {
                }
            }

            extension CounterNode: Node {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: Existing init is preserved, not duplicated

    func testNodeDoesNotDuplicateExistingInit() {
        assertMacroExpansion(
            """
            @Node
            struct ManualInitNode {
                enum Signal: Sendable {}
                var value: Int
                init() { value = 42 }
            }
            """,
            expandedSource: """
            struct ManualInitNode {
                enum Signal: Sendable {}
                var value: Int
                init() { value = 42 }
            }

            extension ManualInitNode: Node {
            }
            """,
            macros: testMacros
        )
    }

    // MARK: Works on a minimal node with no stored properties

    func testGlobalStoreAddsConformanceAndInit() {
        assertMacroExpansion(
            """
            @GlobalStore
            class AppStore {
                var value = 0
            }
            """,
            expandedSource: """
            class AppStore {
                var value = 0

                public init() {
                    StoreRegistry.shared.register(self)
                }
            }

            extension AppStore: GlobalStore {
            }
            """,
            macros: testMacros
        )
    }

    func testGlobalStoreDoesNotDuplicateExistingInit() {
        assertMacroExpansion(
            """
            @GlobalStore
            class CustomStore {
                init() {
                    StoreRegistry.shared.register(self)
                }
            }
            """,
            expandedSource: """
            class CustomStore {
                init() {
                    StoreRegistry.shared.register(self)
                }
            }

            extension CustomStore: GlobalStore {
            }
            """,
            macros: testMacros
        )
    }

    func testNodeOnEmptyStruct() {
        assertMacroExpansion(
            """
            @Node
            struct EmptyNode {
                enum Signal: Sendable {}
            }
            """,
            expandedSource: """
            struct EmptyNode {
                enum Signal: Sendable {}

                public init() {
                }
            }

            extension EmptyNode: Node {
            }
            """,
            macros: testMacros
        )
    }
}
