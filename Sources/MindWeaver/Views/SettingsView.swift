import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var confirmDeleteLocalBinary = false

    var body: some View {
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
            }

            Section("Local Development") {
                Text("Rebuild uses `tsync --only mw`, which should write the checked-out MindWeaver CLI to `~/.local/bin/mw`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Rebuild mw") {
                        Task { await appModel.rebuildMWBinary() }
                    }
                    .disabled(appModel.isWorking)

                    Button("Delete ~/.local/bin/mw", role: .destructive) {
                        confirmDeleteLocalBinary = true
                    }
                    .disabled(appModel.isWorking)
                }
            }

            Section("Notes") {
                LabeledContent("Notes directory") {
                    Text(appModel.notesDirectory.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section("Last command output") {
                ScrollView {
                    Text(appModel.commandOutput.isEmpty ? "No output yet." : appModel.commandOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 220)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 720, height: 560)
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
}
