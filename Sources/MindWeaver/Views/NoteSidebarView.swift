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
                            Text("Matching notes that include all selected domains.")
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
        VStack(alignment: .leading, spacing: 12) {
            Label("Graph Preview", systemImage: SidebarMode.graph.systemImage)
                .font(.headline)

            Text("The graph renderer is a placeholder for now. It uses the currently visible notes to sketch a small node/edge map in the main pane.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview nodes")
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.secondary)

                ForEach(Array(appModel.visibleNotes.prefix(8))) { note in
                    Button {
                        appModel.select(note)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(appModel.selectedNoteID == note.id ? Color.accentColor : Color.secondary)
                            Text(note.title)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
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

    private func domainBackground(_ domain: String) -> some ShapeStyle {
        appModel.selectedDomains.contains(domain) ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12)
    }

    private func explorerModeBackground(_ mode: SidebarMode) -> some ShapeStyle {
        appModel.sidebarMode == mode ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.10)
    }
}
