import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var notes: [MWNote] = []
    @Published var selectedNoteID: MWNote.ID?
    @Published var searchText = ""
    @Published var statusMessage = "Ready"
    @Published var commandOutput = ""
    @Published var isWorking = false
    @Published var notesDirectory: URL

    private let engine: any MindWeaverEngine

    init(engine: any MindWeaverEngine = MWCLIEngine()) {
        self.engine = engine
        self.notesDirectory = MindWeaverPaths.notesDirectory()

        Task {
            await refreshNotes()
        }
    }

    var selectedNote: MWNote? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    var visibleNotes: [MWNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return notes }

        return notes.filter { note in
            note.title.lowercased().contains(query)
                || note.displayPath.lowercased().contains(query)
                || note.content.lowercased().contains(query)
                || note.tags.contains { $0.lowercased().contains(query) }
        }
    }

    func select(_ note: MWNote) {
        selectedNoteID = note.id

        Task {
            await loadContent(for: note)
        }
    }

    func refreshNotes() async {
        await runWork("Loading notes") {
            let loaded = try await engine.listNotes(limit: 250, search: nil)
            notes = loaded
            if selectedNoteID == nil {
                selectedNoteID = loaded.first?.id
            }
            statusMessage = "Loaded \(loaded.count) notes"
            commandOutput = "mw query notes --format json --limit 250"

            if let selectedNote {
                await loadContent(for: selectedNote)
            }
        }
    }

    func loadContent(for note: MWNote) async {
        guard note.content.isEmpty else { return }

        await runWork("Loading \(note.title)") {
            let detailed = try await engine.getNote(id: note.id)

            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = detailed
            }

            statusMessage = "Loaded \(detailed.title)"
            commandOutput = "mw query notes --format json --id \(note.id)"
        }
    }

    func runDoctor() async {
        await runCommand("Running mw doctor") {
            try await engine.doctor()
        }
    }

    func syncNotes() async {
        await runCommand("Running mw notes sync") {
            try await engine.syncNotes()
        }
        await refreshNotes()
    }

    func validateNotes() async {
        await runCommand("Running mw notes validate --all") {
            try await engine.validateNotes()
        }
    }

    func resolvedFileURL(for note: MWNote) -> URL? {
        guard let path = note.path, !path.isEmpty else { return nil }

        let expandedPath = NSString(string: path).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }

        return notesDirectory.appendingPathComponent(expandedPath).standardizedFileURL
    }

    private func runCommand(_ label: String, operation: () async throws -> CommandOutput) async {
        await runWork(label) {
            let output = try await operation()
            statusMessage = output.succeeded ? "Command finished" : "Command failed with exit code \(output.exitCode)"
            commandOutput = output.displayText
        }
    }

    private func runWork(_ label: String, operation: () async throws -> Void) async {
        isWorking = true
        statusMessage = label

        do {
            try await operation()
        } catch {
            statusMessage = "Error"
            commandOutput = error.localizedDescription
        }

        isWorking = false
    }
}
