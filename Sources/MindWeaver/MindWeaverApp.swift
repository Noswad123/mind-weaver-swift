import AppKit
import SwiftUI

@main
struct MindWeaverApp: App {
    @StateObject private var appModel = AppModel()

    init() {
        // `swift run` launches this as a plain executable rather than a bundled
        // .app. Promote it to a foreground GUI app so the window is visible and
        // receives focus when started from a terminal.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Mind Weaver") {
            ContentView()
                .environmentObject(appModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Notes") {
                    Task { await appModel.refreshNotes() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Run mw notes sync") {
                    Task { await appModel.syncNotes() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}
