import SwiftUI

struct NoteSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 10) {
            controls

            switch appModel.sidebarMode {
            case .notes:
                notesList
            case .todos:
                todosList
            case .files:
                fileExplorer
            case .graph:
                graphExplorer
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(appModel.visibleNotes.count)/\(appModel.notes.count) notes • \(appModel.visibleTodos.count)/\(appModel.todos.count) todos")
                    .font(.caption)
                    .bold()

                Text(appModel.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .bottom])
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Explorer View")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(SidebarMode.allCases) { mode in
                        Button {
                            appModel.sidebarMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.systemImage)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(explorerModeBackground(mode), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            DisclosureGroup("Filters") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search", text: $appModel.searchText)
                        .textFieldStyle(.roundedBorder)

                    if !appModel.availableDomains.isEmpty {
                        Text("Domains")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.secondary)

                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                                ForEach(appModel.availableDomains, id: \.self) { domain in
                                    Button {
                                        appModel.toggleDomain(domain)
                                    } label: {
                                        Text(domain)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundStyle(domainForeground(domain))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .frame(maxWidth: .infinity)
                                            .background(domainBackground(domain), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 140)

                        if !appModel.selectedDomains.isEmpty {
                            Text(appModel.sidebarMode == .graph ? "Graph nodes matching any selected domain." : "Matching notes that include all selected domains.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Clear Filters") {
                        appModel.clearFilters()
                    }
                    .disabled(appModel.searchText.isEmpty && appModel.selectedDomains.isEmpty)
                }
                .padding(.top, 8)
            }

            if appModel.sidebarMode == .graph {
                DisclosureGroup("Graph Settings") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Depth \(appModel.graphDepth)", value: $appModel.graphDepth, in: 0...4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Force \(appModel.graphForceStrength, specifier: "%.1f")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Slider(value: $appModel.graphForceStrength, in: 0.2...2.0)
                        }

                        HStack {
                            Button("Refresh Graph") {
                                Task { await appModel.refreshGraph() }
                            }
                            Button("Reset Layout") {
                                appModel.resetGraphLayout()
                            }
                        }

                        Text("Rendered \(appModel.visibleGraph.nodes.count) nodes • \(appModel.visibleGraph.edges.count) edges")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding([.top, .horizontal])
    }

    private var notesList: some View {
        List(appModel.visibleNotes) { note in
            noteRow(note)
        }
    }

    private var todosList: some View {
        List {
            if let dashboard = appModel.dashboardNote {
                Button {
                    appModel.select(dashboard)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "rectangle.grid.1x2")
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("dashboard.md")
                                .fontWeight(.semibold)

                            Text(dashboard.displayPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .listRowBackground(appModel.selectedNoteID == dashboard.id ? Color.accentColor.opacity(0.16) : Color.clear)
            }

            ForEach(appModel.visibleTodos) { todo in
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        appModel.toggleTodoSelection(todo)
                    } label: {
                        Image(systemName: appModel.selectedTodoIDs.contains(todo.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(appModel.selectedTodoIDs.contains(todo.id) ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Select for bulk edit")

                    Button {
                        Task {
                            await appModel.toggleTodoCompletion(todo)
                        }
                    } label: {
                        Image(systemName: todo.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(todo.isDone ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(appModel.isWorking)
                    .help(todo.isDone ? "Mark incomplete" : "Mark complete")

                    Button {
                        appModel.selectTodo(todo)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(todo.title)
                                .strikethrough(todo.isDone)
                                .foregroundStyle(todo.isDone ? .secondary : .primary)
                                .lineLimit(3)

                            Text([todo.noteTitle, todo.path.map { "line \(todo.lineNumber) • \($0)" }].compactMap { $0 }.joined(separator: "\n"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Label(todo.displayStatus, systemImage: sidebarStatusSystemImage(todo.displayStatus))
                                .font(.caption2)
                                .foregroundStyle(sidebarStatusColor(todo.displayStatus))

                            todoMetadataSummary(todo)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 3)
                .listRowBackground(appModel.selectedTodoID == todo.id ? Color.accentColor.opacity(0.16) : Color.clear)
            }
        }
    }

    private func todoMetadataSummary(_ todo: MWTodo) -> some View {
        let parts = [
            todo.displayArea.isEmpty ? nil : "area:\(todo.displayArea)",
            todo.displayTodoSection.isEmpty ? nil : "section:\(todo.displayTodoSection)",
            todo.displayPriority.isEmpty ? nil : todo.displayPriority,
            todo.displayEnergy.isEmpty ? nil : "e:\(todo.displayEnergy)",
            todo.displayDue.isEmpty ? nil : "due:\(todo.displayDue)",
            todo.displayStart.isEmpty ? nil : "start:\(todo.displayStart)",
            todo.displayEstimate.isEmpty ? nil : "est:\(todo.displayEstimate)",
            todo.displayEffectiveWeight > 0 ? String(format: "w:%.2f", todo.displayEffectiveWeight) : nil,
        ].compactMap { $0 }

        return Text(parts.joined(separator: "  "))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private func sidebarStatusColor(_ status: String) -> Color {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done": .green
        case "next": .blue
        case "waiting": .yellow
        case "blocked": .red
        case "inbox": .secondary
        default: .secondary
        }
    }

    private func sidebarStatusSystemImage(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "done": "checkmark.square.fill"
        case "next": "arrow.right.circle.fill"
        case "waiting": "clock.fill"
        case "blocked": "exclamationmark.octagon.fill"
        default: "tray.fill"
        }
    }

    private var fileExplorer: some View {
        List {
            OutlineGroup(appModel.fileTree, children: \.children) { node in
                Button {
                    if let noteID = node.noteID {
                        appModel.select(noteID: noteID)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: node.isFolder ? "folder" : "doc.text")
                            .foregroundStyle(node.isFolder ? .blue : .secondary)
                        Text(node.name)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(node.noteID == nil)
            }
        }
    }

    private var graphExplorer: some View {
        List {
            Section("Results") {
                Text("Rendered graph nodes ordered by current selection and link neighborhood.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let selected = selectedGraphNode {
                Section("Selected") {
                    graphNodeRow(selected, role: .selected)

                    Button {
                        appModel.enterGraphNode(selected)
                    } label: {
                        Label("Enter Selected Node", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selected.noteID == nil)
                    .keyboardShortcut(.return, modifiers: [])
                }

                let connected = connectedGraphNodes(to: selected)
                if !connected.isEmpty {
                    Section("Connected (\(connected.count))") {
                        ForEach(connected) { node in
                            graphNodeRow(node, role: .connected)
                        }
                    }
                }

                let others = graphResultNodes(excluding: Set(([selected.id] + connected.map(\.id))))
                if !others.isEmpty {
                    Section("Other Results") {
                        ForEach(Array(others.prefix(80))) { node in
                            graphNodeRow(node, role: .other)
                        }
                    }
                }
            } else {
                Section("All Results") {
                    ForEach(Array(graphResultNodes(excluding: Set<String>()).prefix(120))) { node in
                        graphNodeRow(node, role: .other)
                    }
                }
            }
        }
    }

    private enum GraphSidebarRole {
        case selected
        case connected
        case other
    }

    private var selectedGraphNode: MWGraphNode? {
        guard let focused = appModel.graphFocusedNodeID else { return nil }
        guard let node = appModel.graphNodesByID[focused], appModel.graphNodeMatchesSelectedDomains(node) else { return nil }
        return node
    }

    private func connectedGraphNodes(to selected: MWGraphNode) -> [MWGraphNode] {
        let ids = appModel.visibleGraphNeighbors(of: selected.id)

        return appModel.visibleGraph.nodes
            .filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                graphDegree(lhs.id) == graphDegree(rhs.id)
                    ? lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                    : graphDegree(lhs.id) > graphDegree(rhs.id)
            }
    }

    private func graphResultNodes(excluding excluded: Set<String>) -> [MWGraphNode] {
        appModel.visibleGraph.nodes
            .filter { !excluded.contains($0.id) }
            .sorted { lhs, rhs in
                if (lhs.matched ?? false) != (rhs.matched ?? false) { return lhs.matched == true }
                if graphDegree(lhs.id) != graphDegree(rhs.id) { return graphDegree(lhs.id) > graphDegree(rhs.id) }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
    }

    private func graphDegree(_ nodeID: String) -> Int {
        appModel.visibleGraphDegree(of: nodeID)
    }

    private func graphNodeRow(_ node: MWGraphNode, role: GraphSidebarRole) -> some View {
        Button {
            if role == .selected {
                appModel.enterGraphNode(node)
            } else {
                appModel.focusGraphNode(node.id)
                if let noteID = node.noteID {
                    appModel.select(noteID: String(noteID))
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: graphNodeIcon(role))
                    .font(.system(size: 9))
                    .foregroundStyle(graphNodeColor(node, role: role))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(node.label)
                        .fontWeight(role == .selected ? .semibold : .regular)
                        .lineLimit(1)

                    if let path = node.path, !path.isEmpty {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if role == .connected {
                        Text("connected • degree \(graphDegree(node.id))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(node.noteID == nil)
        .listRowBackground(role == .selected ? Color.yellow.opacity(0.18) : Color.clear)
    }

    private func graphNodeIcon(_ role: GraphSidebarRole) -> String {
        switch role {
        case .selected: "largecircle.fill.circle"
        case .connected: "circle.hexagongrid.fill"
        case .other: "circle.fill"
        }
    }

    private func graphNodeColor(_ node: MWGraphNode, role: GraphSidebarRole) -> Color {
        switch role {
        case .selected: Color(red: 1.0, green: 0.72, blue: 0.18)
        case .connected: Color(red: 0.18, green: 0.88, blue: 0.95)
        case .other:
            appModel.dominantGraphDomain(for: node).map(DomainColorPalette.color(for:)) ?? .secondary
        }
    }

    private func noteRow(_ note: MWNote) -> some View {
        Button {
            appModel.select(note)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(note.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !note.domains.isEmpty || !note.tags.isEmpty {
                    Text((note.domains + note.tags.map { "#\($0)" }).joined(separator: "  "))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .listRowBackground(appModel.selectedNoteID == note.id ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private func domainBackground(_ domain: String) -> Color {
        if appModel.selectedDomains.contains(domain) {
            return DomainColorPalette.averageColor(for: appModel.selectedDomains)?.opacity(0.58)
                ?? DomainColorPalette.color(for: domain).opacity(0.58)
        }
        return DomainColorPalette.color(for: domain).opacity(0.16)
    }

    private func domainForeground(_ domain: String) -> Color {
        appModel.selectedDomains.contains(domain) ? .primary : .secondary
    }

    private func explorerModeBackground(_ mode: SidebarMode) -> some ShapeStyle {
        appModel.sidebarMode == mode ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.10)
    }
}
