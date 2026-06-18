import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var confirmDeleteLocalBinary = false

    var body: some View {
        TabView {
            engineTab
                .tabItem { Label("Engine", systemImage: "terminal") }

            notesTab
                .tabItem { Label("Notes", systemImage: "doc.text") }

            developmentTab
                .tabItem { Label("Development", systemImage: "hammer") }

            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            outputTab
                .tabItem { Label("Output", systemImage: "doc.plaintext") }
        }
        .padding()
        .frame(width: 760, height: 560)
        .task {
            await appModel.refreshBinaryStatus()
        }
        .alert("Delete local mw binary?", isPresented: $confirmDeleteLocalBinary) {
            Button("Delete", role: .destructive) {
                Task { await appModel.deleteLocalMWBinary() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes ~/.local/bin/mw. The app will fall back to another mw binary if one exists, such as Homebrew or a bundled copy.")
        }
    }

    private var engineTab: some View {
        Form {
            Section("mw Engine") {
                LabeledContent("Resolved binary") {
                    Text(appModel.mwBinaryStatus.executablePath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Source") {
                    Text(appModel.mwBinaryStatus.source.rawValue)
                }

                LabeledContent("Executable") {
                    Text(appModel.mwBinaryStatus.isExecutable ? "Yes" : "No")
                        .foregroundStyle(appModel.mwBinaryStatus.isExecutable ? .green : .red)
                }

                HStack {
                    Button("Refresh Binary Status") {
                        Task { await appModel.refreshBinaryStatus() }
                    }

                    Button("Run Doctor") {
                        Task { await appModel.runDoctor() }
                    }
                }

                Text("Release installs expect Homebrew to provide `mw`; local overrides in `~/.local/bin/mw` or `~/go/bin/mw` are preferred when present.")
                    .font(.caption)
                    .foregroundStyle(MWTheme.textMuted)
            }

            Section("Dependency Readiness") {
                ForEach(appModel.externalToolStatuses) { tool in
                    dependencyRow(tool)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private var developmentTab: some View {
        Form {
            Section("Local Binary Override") {
                Text("Mind Weaver prefers `~/.local/bin/mw` over the Homebrew release when that local binary exists. Delete it to fall back to Homebrew or a bundled copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Delete ~/.local/bin/mw", role: .destructive) {
                        confirmDeleteLocalBinary = true
                    }
                    .disabled(appModel.isWorking)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private var notesTab: some View {
        Form {
            Section("Notes") {
                LabeledContent("Notes directory") {
                    Text(appModel.notesDirectory.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Choose Notes Directory") {
                        appModel.chooseNotesDirectory()
                    }

                    if appModel.needsNotesDirectorySelection {
                        Button("Use This Directory") {
                            appModel.confirmNotesDirectory()
                        }
                    }
                }

                Text("The selected directory is persisted by the app and passed to mw as NOTES_DIR for app-launched commands.")
                    .font(.caption)
                    .foregroundStyle(MWTheme.textMuted)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private var shortcutsTab: some View {
        Form {
            Section("Global") {
                shortcutRow("Toggle Dashboard", keys: "⌘D")
                shortcutRow("Toggle Sidebar", keys: "⌘S")
                shortcutRow("Refresh Notes", keys: "⌘R")
                shortcutRow("Run mw notes sync", keys: "⇧⌘S")
                shortcutRow("Increase readability", keys: "⌘+")
                shortcutRow("Decrease readability", keys: "⌘-")
                shortcutRow("Reset readability", keys: "⌘0")
                shortcutRow("Open Settings", keys: "⌘,")
            }

            Section("Graph") {
                shortcutRow("Enter selected graph node", keys: "Return")
                shortcutRow("Zoom around pointer", keys: "⌘ Scroll")
                shortcutRow("Pan graph", keys: "⌘ Drag")
                shortcutRow("Move graph node", keys: "Drag")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private var outputTab: some View {
        Form {
            Section("Last command output") {
                ScrollView {
                    Text(appModel.commandOutput.isEmpty ? "No output yet." : appModel.commandOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 320)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 10)
    }

    private func shortcutRow(_ action: String, keys: String) -> some View {
        LabeledContent(action) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func dependencyRow(_ tool: ExternalToolStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(tool.name, systemImage: tool.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(tool.isAvailable ? MWTheme.greenSync : (tool.requirement == .required ? MWTheme.danger : MWTheme.emberHot))

                Text(tool.requirement.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background((tool.requirement == .required ? MWTheme.danger : MWTheme.frost).opacity(0.16), in: Capsule())

                Spacer()

                Text(tool.isAvailable ? "Found" : "Missing")
                    .font(.caption)
                    .foregroundStyle(tool.isAvailable ? MWTheme.greenSync : MWTheme.textMuted)
            }

            Text(tool.executablePath ?? tool.installCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(tool.isAvailable ? MWTheme.textMuted : MWTheme.frostSoft)

            Text(tool.note)
                .font(.caption2)
                .foregroundStyle(MWTheme.textMuted)
        }
        .padding(.vertical, 4)
    }
}
