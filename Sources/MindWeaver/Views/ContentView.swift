import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView(columnVisibility: $appModel.sidebarVisibility) {
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

            if appModel.showDashboard {
                DashboardView()
                    .environmentObject(appModel)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .move(edge: .top).combined(with: .opacity)))
                    .zIndex(10)
            }

            hiddenKeyboardShortcuts
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                        appModel.toggleDashboard()
                    }
                } label: {
                    AnimatedBrainLogo(isAnimating: appModel.isBusy, size: 56)
                }
                .buttonStyle(.plain)
                .help(appModel.showDashboard ? "Dismiss Dashboard" : "Open Dashboard")
            }

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
        .toolbar(appModel.showDashboard ? .hidden : .visible, for: .windowToolbar)
        .frame(minWidth: 1_000, minHeight: 680)
    }

    private var hiddenKeyboardShortcuts: some View {
        VStack {
            Button("Toggle Dashboard") {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                    appModel.toggleDashboard()
                }
            }
            .keyboardShortcut("d", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func openSettings() {
        // `Cmd-,` is handled by SwiftUI's Settings scene, but toolbar routing
        // through showSettingsWindow:/showPreferencesWindow: is unreliable when
        // the app is launched via `swift run`. Use our retained AppKit settings
        // window directly for the gear button.
        SettingsWindowController.shared.show(appModel: appModel)
    }
}
