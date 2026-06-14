import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            NoteSidebarView()
        } detail: {
            if appModel.sidebarMode == .graph {
                GraphPlaceholderView()
            } else if appModel.sidebarMode == .todos {
                TodoInspectorView()
            } else {
                NoteDetailView()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if appModel.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Sync") {
                    Task { await appModel.syncNotes() }
                }

                Button("Validate") {
                    Task { await appModel.validateNotes() }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Settings")
            }
        }
        .frame(minWidth: 1_000, minHeight: 680)
    }

    private func openSettings() {
        // `Cmd-,` is handled by SwiftUI's Settings scene, but toolbar routing
        // through showSettingsWindow:/showPreferencesWindow: is unreliable when
        // the app is launched via `swift run`. Use our retained AppKit settings
        // window directly for the gear button.
        SettingsWindowController.shared.show(appModel: appModel)
    }
}
