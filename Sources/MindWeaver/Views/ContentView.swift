import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            MWTheme.appBackground

            themedShell

            if appModel.showDashboard {
                DashboardView()
                    .environmentObject(appModel)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .move(edge: .top).combined(with: .opacity)))
                    .zIndex(10)
            }

            hiddenKeyboardShortcuts
        }
        .foregroundStyle(MWTheme.text)
        .background { MWTheme.appBackground }
        .background(WindowChromeConfigurator().frame(width: 0, height: 0))
        .toolbar(.hidden, for: .windowToolbar)
        .frame(minWidth: 1_000, minHeight: 680)
    }

    private var themedShell: some View {
        VStack(spacing: 0) {
            if !appModel.showDashboard {
                appTopBar
            }

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
        }
    }

    private var appTopBar: some View {
        ZStack {
            HStack(spacing: 10) {
                Spacer()

                if appModel.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(MWTheme.frostSoft)
                }

                Button("Sync") {
                    Task { await appModel.syncNotes() }
                }

                Button("Validate") {
                    Task { await appModel.validateNotes() }
                }

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Settings")
            }

            Button {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                    appModel.toggleDashboard()
                }
            } label: {
                AnimatedBrainLogo(isAnimating: appModel.isBusy, size: 84)
            }
            .buttonStyle(.plain)
            .help("Open Dashboard")
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .zIndex(2)
        .background {
            ZStack {
                MWTheme.bgVoid
                LinearGradient(
                    colors: [MWTheme.bgPanel2.opacity(0.94), MWTheme.bgVoid.opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MWTheme.frostSoft.opacity(0.18))
                .frame(height: 1)
        }
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
