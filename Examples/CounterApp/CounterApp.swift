import SwiftUI
import AppKit
import NOVA

// MARK: - App entry point

@main
struct CounterDemoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private let store = AppStore()

    var body: some Scene {
        WindowGroup("Counter — SECA Demo") {
            ContentView()
        }
        .defaultSize(width: 760, height: 520)
    }
}

// Forces the window to the foreground when launched as an SPM executable
// (no .app bundle = macOS won't auto-activate the window).
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
