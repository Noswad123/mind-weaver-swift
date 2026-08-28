import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var notes: [MWNote] = []
    @Published var todos: [MWTodo] = []
    @Published var graph: MWGraph = MWGraph(nodes: [], edges: [], meta: nil)
    @Published private(set) var graphRevision: Int = 0
    @Published var graphDepth: Int = 1
    @Published var graphLimit: Int = 100_000
    @Published var graphForceStrength: Double = 1.0
    @Published var graphResetToken: Int = 0
    @Published var graphFocusedNodeID: String?
    @Published private(set) var graphNodesByID: [String: MWGraphNode] = [:]
    @Published private(set) var graphAdjacency: [String: Set<String>] = [:]
    @Published private(set) var graphDegreeByID: [String: Int] = [:]
    @Published private(set) var graphDomainCounts: [String: Int] = [:]
    @Published var selectedNoteID: MWNote.ID?
    @Published var selectedTodoID: MWTodo.ID?
    @Published var selectedTodoIDs: Set<MWTodo.ID> = []
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .all
    @Published var sidebarMode: SidebarMode = .notes
    @Published var showDashboard = true
    @Published private(set) var lastViewedNoteIDs: [MWNote.ID] = []
    @Published var searchText = ""
    @Published var selectedDomains: Set<String> = []
    @Published var domainOptions: [String] = []
    @Published var statusMessage = "Ready"
    @Published var commandOutput = ""
    @Published var isWorking = false
    @Published var isComputingGraphLayout = false
    @Published var markdownWorkspace: MarkdownWorkspace?
    @Published var markdownFileTree: [MarkdownFileNode] = []
    @Published var selectedMarkdownFileURL: URL?
    @Published var markdownEditorText = ""
    @Published private(set) var markdownLastSavedText = ""
    @Published var markdownEditorDisplayMode: MarkdownEditorDisplayMode = .split
    @Published var readabilityScale: CGFloat = AppModel.loadReadabilityScale() {
        didSet {
            let clamped = AppModel.clampReadabilityScale(readabilityScale)
            if clamped != readabilityScale {
                readabilityScale = clamped
                return
            }
            UserDefaults.standard.set(Double(readabilityScale), forKey: AppModel.readabilityScaleDefaultsKey)
        }
    }
    @Published var notesDirectory: URL
    @Published var needsNotesDirectorySelection: Bool
    @Published var mwBinaryStatus: MWBinaryStatus = .unresolved
    @Published var readinessReport: MWReadinessReport = .notRun
    @Published var externalToolStatuses: [ExternalToolStatus] = ExternalToolCatalog.statuses()

    private static let readabilityScaleDefaultsKey = "readabilityScale"
    private static let readabilityScaleRange: ClosedRange<CGFloat> = 0.85...1.6
    private static let readabilityScaleStep: CGFloat = 0.1

    private let noteFetchLimit = 5_000
    private let engine: any MindWeaverEngine
    private var loadedGraphSearch: String?
    private var loadedGraphDomain: String?
    private var isClearingFilters = false

    init(engine: any MindWeaverEngine = MWCLIEngine()) {
        self.engine = engine
        self.notesDirectory = MindWeaverPaths.notesDirectory()
        self.needsNotesDirectorySelection = !MindWeaverPaths.hasStoredNotesDirectory()

        Task {
            await refreshBinaryStatus()
            if needsNotesDirectorySelection {
                statusMessage = "Choose notes directory"
                commandOutput = "Mind Weaver needs a notes directory before running mw commands. Suggested directory: \(notesDirectory.path)"
            } else {
                let ready = await runReadinessCheck()
                if ready {
                    await refreshNotes()
                }
            }
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

    var recentlyViewedNotes: [MWNote] {
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let recent = lastViewedNoteIDs.compactMap { notesByID[$0] }
        if recent.count >= 5 { return Array(recent.prefix(5)) }

        let recentIDs = Set(recent.map(\.id))
        return Array((recent + notes.filter { !recentIDs.contains($0.id) }).prefix(5))
    }

    var highestPriorityTodos: [MWTodo] {
        Array(todos
            .filter { !$0.isDone }
            .sorted { lhs, rhs in
                let lhsRank = todoPriorityRank(lhs)
                let rhsRank = todoPriorityRank(rhs)
                if lhsRank != rhsRank { return lhsRank > rhsRank }
                if lhs.displayEffectiveWeight != rhs.displayEffectiveWeight { return lhs.displayEffectiveWeight > rhs.displayEffectiveWeight }
                if lhs.displayDue != rhs.displayDue { return dueSortKey(lhs.displayDue) < dueSortKey(rhs.displayDue) }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(5))
    }

    var dashboardNote: MWNote? {
        notes.first { note in
            let path = note.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path == "dashboard.md"
                || path.hasSuffix("/dashboard.md")
                || note.title.localizedCaseInsensitiveCompare("dashboard") == .orderedSame
        }
    }

    var isBusy: Bool {
        isWorking || isComputingGraphLayout
    }

    var isMarkdownWorkspace: Bool {
        markdownWorkspace != nil
    }

    var selectedMarkdownFileName: String {
        selectedMarkdownFileURL?.lastPathComponent ?? "No Markdown file selected"
    }

    var selectedMarkdownDisplayPath: String {
        selectedMarkdownFileURL?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            ?? markdownWorkspace?.displayPath
            ?? ""
    }

    var isMarkdownDirty: Bool {
        markdownEditorText != markdownLastSavedText
    }

    var canSaveMarkdownDocument: Bool {
        selectedMarkdownFileURL != nil && isMarkdownDirty
    }

    var readabilityPercentage: Int {
        Int((readabilityScale * 100).rounded())
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

    var visibleGraph: MWGraph {
        guard !selectedDomains.isEmpty else { return graph }

        let nodes = graph.nodes.filter(graphNodeMatchesSelectedDomains)
        let visibleNodeIDs = Set(nodes.map(\.id))
        let edges = graph.edges.filter { visibleNodeIDs.contains($0.source) && visibleNodeIDs.contains($0.target) }
        return MWGraph(nodes: nodes, edges: edges, meta: graph.meta)
    }

    func select(_ note: MWNote) {
        selectedNoteID = note.id
        selectedTodoID = nil
        recordViewedNoteID(note.id)

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
        guard !needsNotesDirectorySelection else {
            statusMessage = "Choose notes directory"
            commandOutput = "Select a notes directory before running mw commands."
            return
        }

        await runWork("Loading notes") {
            mwBinaryStatus = await engine.binaryStatus()
            externalToolStatuses = ExternalToolCatalog.statuses()
            let loaded = try await engine.listNotes(limit: noteFetchLimit, search: nil)
            let loadedTodos = try await engine.listTodos()
            mwBinaryStatus = await engine.binaryStatus()
            externalToolStatuses = ExternalToolCatalog.statuses()
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
        externalToolStatuses = ExternalToolCatalog.statuses()
    }

    @discardableResult
    func runReadinessCheck() async -> Bool {
        isWorking = true
        statusMessage = "Checking mw readiness"
        mwBinaryStatus = await engine.binaryStatus()
        externalToolStatuses = ExternalToolCatalog.statuses()
        let report = await engine.readinessCheck()
        readinessReport = report
        mwBinaryStatus = report.binaryStatus
        statusMessage = report.isReady ? "mw is ready" : "mw readiness issues"
        commandOutput = report.displayText
        isWorking = false
        return report.isReady
    }

    func openExternally(_ note: MWNote) {
        guard let fileURL = resolvedFileURL(for: note) else {
            statusMessage = "Cannot resolve note file"
            commandOutput = "No local file path is available for \(note.title)."
            return
        }

        Task {
            await runCommand("Opening external editor") {
                try await ExternalEditorLauncher.open(fileURL)
            }
            await refreshBinaryStatus()
        }
    }

    func deleteLocalMWBinary() async {
        await runCommand("Deleting ~/.local/bin/mw") {
            try await engine.deleteLocalBinary()
        }
        await refreshBinaryStatus()
    }

    func syncNotes() async {
        guard !needsNotesDirectorySelection else {
            statusMessage = "Choose notes directory"
            commandOutput = "Select a notes directory before running mw notes sync."
            return
        }

        await runCommand("Running mw notes sync") {
            try await engine.syncNotes()
        }
        await refreshNotes()
    }

    func validateNotes() async {
        guard !needsNotesDirectorySelection else {
            statusMessage = "Choose notes directory"
            commandOutput = "Select a notes directory before running mw notes validate --all."
            return
        }

        await runCommand("Running mw notes validate --all") {
            try await engine.validateNotes()
        }
    }

    func refreshGraph() async {
        guard !needsNotesDirectorySelection else {
            statusMessage = "Choose notes directory"
            commandOutput = "Select a notes directory before loading the graph."
            return
        }

        await runWork("Loading graph") {
            let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let domain = graphDomainFilter
            let loaded = try await engine.queryGraph(
                search: search,
                domain: domain,
                depth: graphDepth,
                limit: graphLimit
            )
            rebuildGraphIndexes(for: loaded)
            graph = loaded
            graphRevision += 1
            loadedGraphSearch = search
            loadedGraphDomain = domain
            if let graphFocusedNodeID, !loaded.nodes.contains(where: { $0.id == graphFocusedNodeID }) {
                self.graphFocusedNodeID = nil
            }
            statusMessage = "Loaded graph with \(loaded.nodes.count) nodes and \(loaded.edges.count) edges"
            commandOutput = graphCommandDescription(search: search, domain: domain)
        }
    }

    func resetGraphLayout() {
        graphResetToken += 1
    }

    func toggleDashboard() {
        showDashboard.toggle()
    }

    func toggleSidebar() {
        sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
    }

    func focusMarkdownSourceEditor() {
        markdownEditorDisplayMode = .source
        showDashboard = false
        statusMessage = "Focused Markdown editor"
    }

    func focusMarkdownPreview() {
        markdownEditorDisplayMode = .preview
        showDashboard = false
        statusMessage = "Focused rendered Markdown"
    }

    func toggleMarkdownPreviewFocus() {
        if markdownEditorDisplayMode == .preview {
            splitMarkdownEditorAndPreview()
        } else {
            focusMarkdownPreview()
        }
    }

    func toggleMarkdownSourceFocus() {
        if markdownEditorDisplayMode == .source {
            splitMarkdownEditorAndPreview()
        } else {
            focusMarkdownSourceEditor()
        }
    }

    func splitMarkdownEditorAndPreview() {
        markdownEditorDisplayMode = .split
        showDashboard = false
        statusMessage = "Split Markdown editor and preview"
    }

    func increaseReadability() {
        adjustReadability(by: Self.readabilityScaleStep)
    }

    func decreaseReadability() {
        adjustReadability(by: -Self.readabilityScaleStep)
    }

    func resetReadability() {
        readabilityScale = 1.0
        statusMessage = "Readability reset to 100%"
    }

    func openMarkdownWorkspace() {
        guard confirmDiscardUnsavedMarkdownChanges() else { return }

        let panel = NSOpenPanel()
        panel.title = "Open Markdown File or Folder"
        panel.message = "Choose a Markdown file or a folder containing Markdown files. This will not change your default Mind Weaver notes directory."
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openMarkdownWorkspace(at: url)
    }

    func openDefaultNotesWorkspace() {
        guard confirmDiscardUnsavedMarkdownChanges() else { return }
        markdownWorkspace = nil
        markdownFileTree = []
        selectedMarkdownFileURL = nil
        markdownEditorText = ""
        markdownLastSavedText = ""
        statusMessage = "Default notes workspace"
        if notes.isEmpty, !needsNotesDirectorySelection {
            Task { await refreshNotes() }
        }
    }

    func selectMarkdownFile(_ url: URL) {
        guard confirmDiscardUnsavedMarkdownChanges() else { return }
        loadMarkdownDocument(url.standardizedFileURL)
    }

    func saveMarkdownDocument() {
        guard let selectedMarkdownFileURL else { return }

        do {
            try markdownEditorText.write(to: selectedMarkdownFileURL, atomically: true, encoding: .utf8)
            markdownLastSavedText = markdownEditorText
            statusMessage = "Saved \(selectedMarkdownFileURL.lastPathComponent)"
            commandOutput = selectedMarkdownFileURL.path
        } catch {
            statusMessage = "Save failed"
            commandOutput = error.localizedDescription
        }
    }

    @discardableResult
    func openMarkdownLink(target rawTarget: String) -> Bool {
        guard let linkedFileURL = resolveMarkdownLink(target: rawTarget) else {
            let target = normalizedNoteLinkTarget(rawTarget)
            statusMessage = "Markdown link not found"
            commandOutput = target.isEmpty ? rawTarget : target
            return false
        }

        guard confirmDiscardUnsavedMarkdownChanges() else { return false }
        loadMarkdownDocument(linkedFileURL)
        return true
    }

    private func adjustReadability(by delta: CGFloat) {
        readabilityScale = Self.clampReadabilityScale(readabilityScale + delta)
        statusMessage = "Readability set to \(readabilityPercentage)%"
    }

    private func openMarkdownWorkspace(at url: URL) {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory)
        guard exists else {
            statusMessage = "Markdown path not found"
            commandOutput = standardized.path
            return
        }

        let workspace = MarkdownWorkspace(kind: isDirectory.boolValue ? .folder : .file, rootURL: standardized)

        do {
            let tree = try MarkdownFileNode.tree(for: workspace)
            guard let firstFile = MarkdownFileNode.firstMarkdownFile(in: tree) else {
                statusMessage = "No Markdown files found"
                commandOutput = "No .md or .markdown files found in \(workspace.displayPath)."
                return
            }

            markdownWorkspace = workspace
            markdownFileTree = tree
            showDashboard = false
            sidebarMode = .files
            loadMarkdownDocument(firstFile)
            statusMessage = workspace.kind == .folder ? "Opened Markdown folder" : "Opened Markdown file"
            commandOutput = workspace.displayPath
        } catch {
            statusMessage = "Open failed"
            commandOutput = error.localizedDescription
        }
    }

    private func loadMarkdownDocument(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            selectedMarkdownFileURL = url.standardizedFileURL
            markdownEditorText = content
            markdownLastSavedText = content
            statusMessage = "Loaded \(url.lastPathComponent)"
            commandOutput = url.path
        } catch {
            selectedMarkdownFileURL = nil
            markdownEditorText = ""
            markdownLastSavedText = ""
            statusMessage = "Could not load Markdown file"
            commandOutput = error.localizedDescription
        }
    }

    private func resolveMarkdownLink(target rawTarget: String) -> URL? {
        guard let workspace = markdownWorkspace,
              let selectedMarkdownFileURL else { return nil }

        let target = normalizedNoteLinkTarget(rawTarget)
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        if let fileURL = URL(string: target), fileURL.isFileURL {
            return markdownFileExists(fileURL) ? fileURL.standardizedFileURL : nil
        }

        guard !isExternalLinkTarget(target) else { return nil }

        let sourceDirectory = selectedMarkdownFileURL.deletingLastPathComponent()
        let workspaceBase = workspace.kind == .folder ? workspace.rootURL : workspace.rootURL.deletingLastPathComponent()
        let candidateBases: [URL]
        if target.hasPrefix("/") {
            candidateBases = [URL(fileURLWithPath: target)]
        } else {
            candidateBases = [
                sourceDirectory.appendingPathComponent(target),
                workspaceBase.appendingPathComponent(target),
            ]
        }

        for candidate in candidateBases {
            if let resolved = resolveMarkdownCandidate(candidate) {
                return resolved
            }
        }

        return resolveMarkdownWikilinkLikeTarget(target)
    }

    private func resolveMarkdownCandidate(_ candidate: URL) -> URL? {
        let standardized = candidate.standardizedFileURL

        if markdownFileExists(standardized) {
            return standardized
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue {
            for indexName in ["README.md", "readme.md", "index.md"] {
                let indexURL = standardized.appendingPathComponent(indexName)
                if markdownFileExists(indexURL) {
                    return indexURL.standardizedFileURL
                }
            }
        }

        guard standardized.pathExtension.isEmpty else { return nil }
        for ext in ["md", "markdown"] {
            let withExtension = standardized.appendingPathExtension(ext)
            if markdownFileExists(withExtension) {
                return withExtension.standardizedFileURL
            }
        }

        return nil
    }

    private func resolveMarkdownWikilinkLikeTarget(_ target: String) -> URL? {
        let normalizedTarget = normalizePath(target).lowercased()
        let targetBasename = URL(fileURLWithPath: normalizedTarget).lastPathComponent
        let targetStem = stripMarkdownFileExtension(targetBasename)

        return allMarkdownFileURLs(in: markdownFileTree).first { url in
            let normalizedPath = normalizePath(url.path).lowercased()
            let basename = url.lastPathComponent.lowercased()
            let stem = stripMarkdownFileExtension(basename)
            return normalizedPath == normalizedTarget
                || normalizedPath.hasSuffix("/\(normalizedTarget)")
                || basename == targetBasename
                || stem == targetStem
        }
    }

    private func allMarkdownFileURLs(in nodes: [MarkdownFileNode]) -> [URL] {
        nodes.flatMap { node -> [URL] in
            if node.isFolder {
                return allMarkdownFileURLs(in: node.children ?? [])
            }
            return [node.url.standardizedFileURL]
        }
    }

    private func markdownFileExists(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.standardizedFileURL.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func confirmDiscardUnsavedMarkdownChanges() -> Bool {
        guard isMarkdownDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "\(selectedMarkdownFileName) has unsaved changes. Save them before continuing?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveMarkdownDocument()
            return !isMarkdownDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func showDashboardView() {
        showDashboard = true
    }

    func dismissDashboard() {
        showDashboard = false
    }

    func setGraphLayoutComputing(_ isComputing: Bool) {
        isComputingGraphLayout = isComputing
    }

    func confirmNotesDirectory() {
        guard directoryExists(notesDirectory) else {
            statusMessage = "Notes directory not found"
            commandOutput = "Choose an existing notes directory or create one first: \(notesDirectory.path)"
            return
        }

        setNotesDirectory(notesDirectory)
    }

    func resetNotesDirectorySetup() {
        MindWeaverPaths.clearNotesDirectory()
        notesDirectory = MindWeaverPaths.notesDirectory()
        needsNotesDirectorySelection = true
        notes = []
        todos = []
        graph = MWGraph(nodes: [], edges: [], meta: nil)
        selectedNoteID = nil
        selectedTodoID = nil
        selectedTodoIDs = []
        domainOptions = []
        readinessReport = .notRun
        statusMessage = "Choose notes directory"
        commandOutput = "Notes directory selection was reset. Choose a directory to continue."
    }

    func copyDiagnosticsToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText(), forType: .string)
        statusMessage = "Diagnostics copied"
    }

    func chooseNotesDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Mind Weaver Notes Directory"
        panel.message = "Select the Markdown notes directory that mw should read and mutate."
        panel.prompt = "Use Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = notesDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setNotesDirectory(url)
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

    func visibleGraphNeighbors(of nodeID: String) -> Set<String> {
        guard let node = graphNodesByID[nodeID], graphNodeMatchesSelectedDomains(node) else { return [] }
        return graphAdjacency[nodeID, default: []].filter { neighborID in
            graphNodesByID[neighborID].map(graphNodeMatchesSelectedDomains) ?? false
        }
    }

    func visibleGraphDegree(of nodeID: String) -> Int {
        visibleGraphNeighbors(of: nodeID).count
    }

    func graphNodeMatchesSelectedDomains(_ node: MWGraphNode) -> Bool {
        guard !selectedDomains.isEmpty else { return true }
        let nodeDomains = Set(node.domains.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return selectedDomains.contains { selected in
            nodeDomains.contains(selected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    func dominantGraphDomain(for node: MWGraphNode) -> String? {
        node.domains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                let lhsCount = graphDomainCounts[lhs, default: 0]
                let rhsCount = graphDomainCounts[rhs, default: 0]
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .first
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

    func enterGraphNode(_ node: MWGraphNode) {
        guard let noteID = node.noteID else { return }
        graphFocusedNodeID = node.id
        sidebarMode = .notes
        select(noteID: String(noteID))
    }

    func enterFocusedGraphNode() {
        guard let graphFocusedNodeID, let node = graphNodesByID[graphFocusedNodeID] else { return }
        enterGraphNode(node)
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

    @discardableResult
    func openNoteLink(target rawTarget: String, from source: MWNote) -> Bool {
        guard let note = resolveNoteLink(target: rawTarget, from: source) else { return false }
        sidebarMode = .notes
        select(note)
        return true
    }

    func resolveNoteLink(target rawTarget: String, from source: MWNote) -> MWNote? {
        let target = normalizedNoteLinkTarget(rawTarget)
        guard !target.isEmpty, !isExternalLinkTarget(target) else { return nil }

        let targetLower = target.lowercased()
        let targetWithoutExtension = stripMarkdownExtension(targetLower)
        let sourceDirectory = source.path.flatMap { path -> String? in
            let directory = NSString(string: path).deletingLastPathComponent
            return directory.isEmpty || directory == "." ? nil : directory
        }
        let relativePath = sourceDirectory.map { normalizePath("\($0)/\(target)") }
        let normalizedTargetPath = normalizePath(target)

        return notes.first { note in
            let id = note.id.lowercased()
            let uid = note.uid?.lowercased()
            let title = note.title.lowercased()
            let path = note.path.map(normalizePath)?.lowercased()
            let basename = path.map { NSString(string: $0).lastPathComponent.lowercased() }
            let basenameWithoutExtension = basename.map(stripMarkdownExtension)

            return id == targetLower
                || uid == targetLower
                || title == targetLower
                || path == normalizedTargetPath.lowercased()
                || path == relativePath?.lowercased()
                || path == "\(normalizedTargetPath).md".lowercased()
                || path == relativePath.map { "\($0).md" }?.lowercased()
                || basename == targetLower
                || basenameWithoutExtension == targetWithoutExtension
        }
    }

    func toggleDomain(_ domain: String) {
        if selectedDomains.contains(domain) {
            selectedDomains.remove(domain)
        } else {
            selectedDomains.insert(domain)
        }

        refreshGraphIfSelectedDomainsOutgrewLoadedDomain()
    }

    func clearFilters() {
        let graphWasLoadedWithFilters = loadedGraphSearch != nil || loadedGraphDomain != nil
        let graphViewHasActiveFilters = sidebarMode == .graph
            && (!searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedDomains.isEmpty)
        let shouldRefreshGraph = graphWasLoadedWithFilters || graphViewHasActiveFilters

        isClearingFilters = true
        searchText = ""
        selectedDomains = []
        isClearingFilters = false

        if shouldRefreshGraph {
            Task { await refreshGraph() }
        }
    }

    func refreshGraphIfSearchWasCleared() {
        guard !isClearingFilters,
              sidebarMode == .graph,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              loadedGraphSearch != nil else { return }

        Task { await refreshGraph() }
    }

    private func recordViewedNoteID(_ noteID: MWNote.ID) {
        lastViewedNoteIDs.removeAll { $0 == noteID }
        lastViewedNoteIDs.insert(noteID, at: 0)
        if lastViewedNoteIDs.count > 50 {
            lastViewedNoteIDs = Array(lastViewedNoteIDs.prefix(50))
        }
    }

    private func setNotesDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard directoryExists(standardized) else {
            statusMessage = "Notes directory not found"
            commandOutput = "Choose an existing notes directory: \(standardized.path)"
            return
        }

        MindWeaverPaths.saveNotesDirectory(standardized)
        notesDirectory = standardized
        needsNotesDirectorySelection = false
        notes = []
        todos = []
        graph = MWGraph(nodes: [], edges: [], meta: nil)
        selectedNoteID = nil
        selectedTodoID = nil
        selectedTodoIDs = []
        domainOptions = []
        statusMessage = "Notes directory set"
        commandOutput = "NOTES_DIR=\(standardized.path)"
        Task {
            let ready = await runReadinessCheck()
            if ready {
                await refreshNotes()
            }
        }
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func diagnosticsText() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let toolLines = externalToolStatuses.map { tool in
            "- \(tool.name): \(tool.isAvailable ? tool.executablePath ?? "found" : "missing")"
        }.joined(separator: "\n")

        return """
        Mind Weaver Diagnostics
        app version: \(appVersion) (\(build))
        notes directory: \(notesDirectory.path)
        needs notes directory selection: \(needsNotesDirectorySelection)

        mw binary:
        source: \(mwBinaryStatus.source.rawValue)
        path: \(mwBinaryStatus.executablePath)
        executable: \(mwBinaryStatus.isExecutable)

        readiness:
        \(readinessReport.displayText)

        external tools:
        \(toolLines)

        status:
        \(statusMessage)

        last command output:
        \(commandOutput)
        """
    }

    private func todoPriorityRank(_ todo: MWTodo) -> Int {
        let priority = todo.displayPriority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if priority.isEmpty { return 0 }

        if priority == "urgent" || priority == "critical" { return 120 }
        if priority == "high" { return 100 }
        if priority == "medium" { return 60 }
        if priority == "low" { return 20 }

        if priority.hasPrefix("p"), let value = Int(priority.dropFirst()) {
            return max(0, 110 - value * 10)
        }
        if let value = Int(priority) {
            return max(0, 110 - value * 10)
        }
        return 10
    }

    private func dueSortKey(_ due: String) -> String {
        due.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "9999-99-99" : due
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

    private func refreshGraphIfSelectedDomainsOutgrewLoadedDomain() {
        guard sidebarMode == .graph,
              let loadedGraphDomain else { return }

        let loaded = normalizedGraphDomain(loadedGraphDomain)
        let selected = Set(selectedDomains.map(normalizedGraphDomain))
        guard selected.count != 1 || !selected.contains(loaded) else { return }

        Task { await refreshGraph() }
    }

    private func normalizedGraphDomain(_ domain: String) -> String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func graphCommandDescription(search: String?, domain: String?) -> String {
        var parts = ["mw", "query", "graph", "--depth", String(graphDepth), "--limit", String(graphLimit)]
        if let search {
            parts.append(contentsOf: ["--search", search])
        }
        if let domain {
            parts.append(contentsOf: ["--domain", domain])
        }
        return parts.joined(separator: " ")
    }

    private func rebuildGraphIndexes(for graph: MWGraph) {
        graphNodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var adjacency = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, Set<String>()) })
        let nodeIDs = Set(graph.nodes.map(\.id))
        var domainCounts: [String: Int] = [:]

        for edge in graph.edges where nodeIDs.contains(edge.source) && nodeIDs.contains(edge.target) && edge.source != edge.target {
            adjacency[edge.source, default: []].insert(edge.target)
            adjacency[edge.target, default: []].insert(edge.source)
        }

        graphAdjacency = adjacency
        graphDegreeByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, adjacency[$0.id, default: []].count) })

        for node in graph.nodes {
            for domain in node.domains.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !domain.isEmpty {
                domainCounts[domain, default: 0] += 1
            }
        }
        graphDomainCounts = domainCounts
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

    private static func loadReadabilityScale() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: readabilityScaleDefaultsKey)
        guard stored > 0 else { return 1.0 }
        return clampReadabilityScale(CGFloat(stored))
    }

    private static func clampReadabilityScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, readabilityScaleRange.lowerBound), readabilityScaleRange.upperBound)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private func normalizedNoteLinkTarget(_ rawTarget: String) -> String {
    var target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    if target.hasPrefix("<"), target.hasSuffix(">") {
        target = String(target.dropFirst().dropLast())
    }
    if let pipe = target.firstIndex(of: "|") {
        target = String(target[..<pipe])
    }
    if let hash = target.firstIndex(of: "#") {
        target = String(target[..<hash])
    }
    return target.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? target
}

private func isExternalLinkTarget(_ target: String) -> Bool {
    let lower = target.lowercased()
    return lower.hasPrefix("http://")
        || lower.hasPrefix("https://")
        || lower.hasPrefix("mailto:")
        || lower.hasPrefix("tel:")
        || lower.hasPrefix("file://")
}

private func normalizePath(_ path: String) -> String {
    let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardized.path
    }

    var parts: [String] = []
    for part in expanded.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true) {
        switch part {
        case ".":
            continue
        case "..":
            if !parts.isEmpty { parts.removeLast() }
        default:
            parts.append(String(part))
        }
    }
    return parts.joined(separator: "/")
}

private func stripMarkdownExtension(_ value: String) -> String {
    value.hasSuffix(".md") ? String(value.dropLast(3)) : value
}

private func stripMarkdownFileExtension(_ value: String) -> String {
    if value.hasSuffix(".markdown") {
        return String(value.dropLast(9))
    }
    if value.hasSuffix(".md") {
        return String(value.dropLast(3))
    }
    return value
}
