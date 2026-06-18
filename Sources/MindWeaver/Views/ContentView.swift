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

            if appModel.needsNotesDirectorySelection {
                NotesDirectoryOnboardingView()
                    .environmentObject(appModel)
                    .zIndex(20)
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

private struct NotesDirectoryOnboardingView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack {
            MWTheme.bgVoid.opacity(0.88)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Label("Choose your notes directory", systemImage: "folder.badge.gearshape")
                    .font(.title2.bold())
                    .foregroundStyle(MWTheme.emberHot)

                Text("Mind Weaver needs an app-selected Markdown notes directory before it runs mw commands. The app will pass this path to mw as NOTES_DIR.")
                    .foregroundStyle(MWTheme.text)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested directory")
                        .font(.caption.bold())
                        .foregroundStyle(MWTheme.textMuted)

                    Text(appModel.notesDirectory.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(MWTheme.frostSoft)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MWTheme.coldFill, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack {
                    Button("Choose Directory…") {
                        appModel.chooseNotesDirectory()
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Use Suggested Directory") {
                        appModel.confirmNotesDirectory()
                    }

                    Spacer()
                }
            }
            .padding(28)
            .frame(width: 560)
            .background(MWTheme.panelFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MWTheme.emberHot.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
        }
    }
}
