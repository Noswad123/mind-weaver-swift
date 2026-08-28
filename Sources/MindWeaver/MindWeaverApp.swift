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
        WindowGroup("") {
            ContentView()
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
                .tint(MWTheme.emberHot)
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appModel.saveMarkdownDocument()
                }
                .disabled(!appModel.canSaveMarkdownDocument)

                Divider()

                Button(appModel.sidebarVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                    appModel.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandMenu("Markdown") {
                Button(appModel.markdownEditorDisplayMode == .source ? "Return to Split View" : "Focus Editor") {
                    appModel.toggleMarkdownSourceFocus()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!appModel.isMarkdownWorkspace)

                Button(appModel.markdownEditorDisplayMode == .preview ? "Return to Split View" : "Focus Rendered Markdown") {
                    appModel.toggleMarkdownPreviewFocus()
                }
                .keyboardShortcut("m", modifiers: [.command])
                .disabled(!appModel.isMarkdownWorkspace)
            }

            CommandGroup(after: .newItem) {
                Button("Open Markdown File or Folder…") {
                    appModel.openMarkdownWorkspace()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Default Notes Workspace") {
                    appModel.openDefaultNotesWorkspace()
                }
                .disabled(!appModel.isMarkdownWorkspace)

                Divider()

                Button("Refresh Notes") {
                    Task { await appModel.refreshNotes() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appModel.isMarkdownWorkspace)

                Button("Run mw notes sync") {
                    Task { await appModel.syncNotes() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appModel.isMarkdownWorkspace)

                Divider()

                Button("Increase Readability") {
                    appModel.increaseReadability()
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Readability") {
                    appModel.decreaseReadability()
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Readability") {
                    appModel.resetReadability()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}
