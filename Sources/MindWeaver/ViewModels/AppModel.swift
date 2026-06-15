import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var notes: [MWNote] = []
    @Published var todos: [MWTodo] = []
    @Published var graph: MWGraph = MWGraph(nodes: [], edges: [], meta: nil)
    @Published var graphDepth: Int = 1
    @Published var graphLimit: Int = 100_000
    @Published var graphForceStrength: Double = 1.0
    @Published var graphResetToken: Int = 0
    @Published var graphFocusedNodeID: String?
    @Published private(set) var graphNodesByID: [String: MWGraphNode] = [:]
    @Published private(set) var graphAdjacency: [String: Set<String>] = [:]
    @Published private(set) var graphDegreeByID: [String: Int] = [:]
    @Published var selectedNoteID: MWNote.ID?
    @Published var selectedTodoID: MWTodo.ID?
    @Published var selectedTodoIDs: Set<MWTodo.ID> = []
    @Published var sidebarMode: SidebarMode = .notes
    @Published var searchText = ""
    @Published var selectedDomains: Set<String> = []
    @Published var domainOptions: [String] = []
    @Published var statusMessage = "Ready"
    @Published var commandOutput = ""
    @Published var isWorking = false
    @Published var notesDirectory: URL
    @Published var mwBinaryStatus: MWBinaryStatus = .unresolved

    private let noteFetchLimit = 5_000
    private let engine: any MindWeaverEngine

    init(engine: any MindWeaverEngine = MWCLIEngine()) {
        self.engine = engine
        self.notesDirectory = MindWeaverPaths.notesDirectory()

        Task {
            await refreshBinaryStatus()
            await refreshNotes()
        }
    }

    var selectedNote: MWNote? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    var selectedTodo: MWTodo? {
        guard let selectedTodoID else { return nil }
        return todos.first { $0.id == selectedTodoID }
    }

    var selectedTodos: [MWTodo] {
        todos.filter { selectedTodoIDs.contains($0.id) }
    }

    var dashboardNote: MWNote? {
        notes.first { note in
            let path = note.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path == "dashboard.md"
                || path.hasSuffix("/dashboard.md")
                || note.title.localizedCaseInsensitiveCompare("dashboard") == .orderedSame
        }
    }

    var visibleNotes: [MWNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return notes.filter { note in
            let matchesSearch = query.isEmpty
                || note.title.lowercased().contains(query)
                || note.displayPath.lowercased().contains(query)
                || note.content.lowercased().contains(query)
                || note.tags.contains { $0.lowercased().contains(query) }
                || note.domains.contains { $0.lowercased().contains(query) }

            let matchesDomains = selectedDomains.isEmpty
                || selectedDomains.allSatisfy { selected in note.domains.contains(selected) }

            return matchesSearch && matchesDomains
        }
    }

    var visibleTodos: [MWTodo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visibleNoteIDs = Set(visibleNotes.map(\.id))

        return todos.filter { todo in
            let matchesSearch = query.isEmpty
                || todo.title.lowercased().contains(query)
                || (todo.noteTitle?.lowercased().contains(query) ?? false)
                || (todo.path?.lowercased().contains(query) ?? false)

            let matchesDomains = selectedDomains.isEmpty
                || (todo.noteID.map { visibleNoteIDs.contains($0) } ?? false)

            return matchesSearch && matchesDomains
        }
    }

    var availableDomains: [String] {
        if !domainOptions.isEmpty {
            return domainOptions
        }

        return Array(Set(notes.flatMap(\.domains))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var fileTree: [FileNode] {
        FileNode.tree(from: visibleNotes)
    }

    var graphDomainFilter: String? {
        selectedDomains.count == 1 ? selectedDomains.first : nil
    }

    func select(_ note: MWNote) {
        selectedNoteID = note.id
        selectedTodoID = nil

        Task {
            await loadContent(for: note)
        }
    }

    func selectTodo(_ todo: MWTodo) {
        selectedTodoID = todo.id
        if selectedTodoIDs.isEmpty {
            selectedTodoIDs = [todo.id]
        }
    }

    func toggleTodoSelection(_ todo: MWTodo) {
        if selectedTodoIDs.contains(todo.id) {
            selectedTodoIDs.remove(todo.id)
        } else {
            selectedTodoIDs.insert(todo.id)
        }
        if selectedTodoID == nil || selectedTodoID == todo.id {
            selectedTodoID = selectedTodoIDs.contains(todo.id) ? todo.id : selectedTodoIDs.first
        }
    }

    func refreshNotes() async {
        await runWork("Loading notes") {
            mwBinaryStatus = await engine.binaryStatus()
            let loaded = try await engine.listNotes(limit: noteFetchLimit, search: nil)
            let loadedTodos = try await engine.listTodos()
            mwBinaryStatus = await engine.binaryStatus()
            notes = loaded
            todos = loadedTodos
            selectedTodoIDs = selectedTodoIDs.intersection(Set(loadedTodos.map(\.id)))
            if let selectedTodoID, !loadedTodos.contains(where: { $0.id == selectedTodoID }) {
                self.selectedTodoID = selectedTodoIDs.first
            }
            domainOptions = await loadDomainOptions(fallbackNotes: loaded)
            if selectedNoteID == nil {
                selectedNoteID = loaded.first?.id
            }
            statusMessage = "Loaded \(loaded.count) notes and \(loadedTodos.count) todos"
            commandOutput = "mw query notes --format json --limit \(noteFetchLimit)\nmw query todos"

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

    func refreshBinaryStatus() async {
        mwBinaryStatus = await engine.binaryStatus()
    }

    func rebuildMWBinary() async {
        await runCommand("Rebuilding mw via tsync --only mw") {
            try await engine.rebuildLocalBinary()
        }
        await refreshBinaryStatus()
    }

    func deleteLocalMWBinary() async {
        await runCommand("Deleting ~/.local/bin/mw") {
            try await engine.deleteLocalBinary()
        }
        await refreshBinaryStatus()
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

    func refreshGraph() async {
        await runWork("Loading graph") {
            let loaded = try await engine.queryGraph(
                search: searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                domain: graphDomainFilter,
                depth: graphDepth,
                limit: graphLimit
            )
            rebuildGraphIndexes(for: loaded)
            graph = loaded
            if let graphFocusedNodeID, !loaded.nodes.contains(where: { $0.id == graphFocusedNodeID }) {
                self.graphFocusedNodeID = nil
            }
            statusMessage = "Loaded graph with \(loaded.nodes.count) nodes and \(loaded.edges.count) edges"
            commandOutput = "mw query graph --depth \(graphDepth) --limit \(graphLimit)"
        }
    }

    func resetGraphLayout() {
        graphResetToken += 1
    }

    func focusGraphNode(_ nodeID: String?) {
        graphFocusedNodeID = nodeID
    }

    func graphNeighbors(of nodeID: String) -> Set<String> {
        graphAdjacency[nodeID, default: []]
    }

    func graphDegree(of nodeID: String) -> Int {
        graphDegreeByID[nodeID, default: 0]
    }

    func clearSelection() {
        selectedNoteID = nil
        selectedTodoID = nil
        graphFocusedNodeID = nil
    }

    func toggleTodoCompletion(_ todo: MWTodo) async {
        await runWork("Toggling todo") {
            let output = try await engine.toggleTodo(id: todo.id)
            try await reloadTodosPreservingSelection()

            let affectedNoteIDs = Set([todo.noteID, dashboardNote?.id].compactMap { id in
                let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            })

            for noteID in affectedNoteIDs {
                if let index = notes.firstIndex(where: { $0.id == noteID }) {
                    notes[index].content = ""
                }
            }

            if let selectedNoteID, affectedNoteIDs.contains(selectedNoteID), let index = notes.firstIndex(where: { $0.id == selectedNoteID }) {
                notes[index] = try await engine.getNote(id: selectedNoteID)
            }

            statusMessage = "Todo toggled"
            commandOutput = output.displayText + "\nmw query todos"
        }
    }

    func updateTodo(_ todo: MWTodo, patch: MWTodoUpdatePatch) async {
        await updateTodos(ids: [todo.id], patch: patch)
    }

    func updateSelectedTodos(patch: MWTodoUpdatePatch) async {
        let ids = Array(selectedTodoIDs).sorted()
        guard !ids.isEmpty else { return }
        await updateTodos(ids: ids, patch: patch)
    }

    func openSourceNote(for todo: MWTodo) {
        sidebarMode = .notes
        select(noteID: todo.noteID)
    }

    func resolvedFileURL(for note: MWNote) -> URL? {
        guard let path = note.path, !path.isEmpty else { return nil }

        let expandedPath = NSString(string: path).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }

        return notesDirectory.appendingPathComponent(expandedPath).standardizedFileURL
    }

    func select(noteID: MWNote.ID?) {
        guard let noteID, let note = notes.first(where: { $0.id == noteID }) else { return }
        select(note)
    }

    func toggleDomain(_ domain: String) {
        if selectedDomains.contains(domain) {
            selectedDomains.remove(domain)
        } else {
            selectedDomains.insert(domain)
        }
    }

    func clearFilters() {
        searchText = ""
        selectedDomains = []
    }

    private func loadDomainOptions(fallbackNotes: [MWNote]) async -> [String] {
        do {
            let domains = try await engine.listDomains()
            if !domains.isEmpty {
                return domains
            }
        } catch {
            // Older mw binaries may not have `mw query domains` yet. Fall back
            // only to domains already returned by `mw query notes`; do not read
            // or parse local markdown frontmatter in the Swift app.
        }

        return Array(Set(fallbackNotes.flatMap(\.domains))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func rebuildGraphIndexes(for graph: MWGraph) {
        graphNodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var adjacency = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, Set<String>()) })
        let nodeIDs = Set(graph.nodes.map(\.id))

        for edge in graph.edges where nodeIDs.contains(edge.source) && nodeIDs.contains(edge.target) && edge.source != edge.target {
            adjacency[edge.source, default: []].insert(edge.target)
            adjacency[edge.target, default: []].insert(edge.source)
        }

        graphAdjacency = adjacency
        graphDegreeByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, adjacency[$0.id, default: []].count) })
    }

    private func updateTodos(ids: [String], patch: MWTodoUpdatePatch) async {
        await runWork("Updating todo metadata") {
            let output = try await engine.updateTodos(ids: ids, patch: patch)
            try await reloadTodosPreservingSelection()
            invalidateTodoRelatedNotes(ids: ids)
            statusMessage = "Updated \(ids.count) todo(s)"
            commandOutput = output.displayText + "\nmw query todos"
        }
    }

    private func reloadTodosPreservingSelection() async throws {
        let loadedTodos = try await engine.listTodos()
        todos = loadedTodos
        selectedTodoIDs = selectedTodoIDs.intersection(Set(loadedTodos.map(\.id)))
        if let selectedTodoID, !loadedTodos.contains(where: { $0.id == selectedTodoID }) {
            self.selectedTodoID = selectedTodoIDs.first
        }
    }

    private func invalidateTodoRelatedNotes(ids: [String]) {
        let affectedTodoNoteIDs = todos
            .filter { ids.contains($0.id) }
            .compactMap(\.noteID)
        let affectedNoteIDs = Set((affectedTodoNoteIDs + [dashboardNote?.id].compactMap { $0 }).filter { !$0.isEmpty })

        for noteID in affectedNoteIDs {
            if let index = notes.firstIndex(where: { $0.id == noteID }) {
                notes[index].content = ""
            }
        }
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
