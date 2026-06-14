import AppKit
import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let note = appModel.selectedNote {
                noteHeader(note)

                Divider()

                HSplitView {
                    ScrollView {
                        Text(note.content.isEmpty ? "This note was returned without content. Try running mw notes sync, then refresh." : note.content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }

                    MarkdownPreview(markdown: note.content)
                        .frame(minWidth: 320)
                }
            } else {
                emptyState
            }

            Divider()

            CommandOutputView()
        }
    }

    private func noteHeader(_ note: MWNote) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.title2)
                    .bold()

                Text(note.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Reveal in Finder") {
                reveal(note)
            }
            .disabled(note.path == nil)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("Mind Weaver")
                .font(.title2)
                .bold()

            Text("A native SwiftUI shell around the Go mw engine.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reveal(_ note: MWNote) {
        guard let path = note.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)])
    }
}

struct MarkdownPreview: View {
    var markdown: String

    var body: some View {
        ScrollView {
            if markdown.isEmpty {
                Text("Markdown preview will appear here when mw returns note content.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if let attributed = try? AttributedString(markdown: markdown) {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                Text(markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
