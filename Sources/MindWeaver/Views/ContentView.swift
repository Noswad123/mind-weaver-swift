import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            NoteSidebarView()
        } detail: {
            NoteDetailView()
        }
        .toolbar {
            ToolbarItemGroup {
                if appModel.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Refresh") {
                    Task { await appModel.refreshNotes() }
                }

                Button("Doctor") {
                    Task { await appModel.runDoctor() }
                }

                Button("Sync") {
                    Task { await appModel.syncNotes() }
                }

                Button("Validate") {
                    Task { await appModel.validateNotes() }
                }
            }
        }
        .frame(minWidth: 1_000, minHeight: 680)
    }
}
