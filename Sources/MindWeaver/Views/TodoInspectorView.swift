import SwiftUI

struct TodoInspectorView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var title = ""
    @State private var area = ""
    @State private var priority = ""
    @State private var energy = ""
    @State private var weight = ""
    @State private var due = ""
    @State private var start = ""
    @State private var estimate = ""
    @State private var rawMetadata = ""
    @State private var useRawMetadata = false

    @State private var bulkArea = ""
    @State private var bulkPriority = ""
    @State private var bulkEnergy = ""
    @State private var bulkWeight = ""
    @State private var bulkDue = ""
    @State private var bulkStart = ""
    @State private var bulkEstimate = ""
    @State private var bulkClear = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let todo = appModel.selectedTodo {
                        singleInspector(todo)
                    } else {
                        emptyState
                    }

                    if !appModel.selectedTodoIDs.isEmpty {
                        Divider()
                        bulkEditor
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()
            CommandOutputView()
        }
        .onAppear { loadSelectedTodo() }
        .onChange(of: appModel.selectedTodoID) { _ in loadSelectedTodo() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Todo Inspector")
                    .font(.title2)
                    .bold()
                Text("Inspect and edit source-backed task-index todo metadata.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appModel.isWorking {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Select a todo")
                .font(.title3)
                .bold()
            Text("Choose a todo row to inspect properties, edit metadata, or open its source note.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func singleInspector(_ todo: MWTodo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Task") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Todo title", text: $title, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Label(todo.displayStatus, systemImage: statusSystemImage(todo.displayStatus))
                            .foregroundStyle(statusColor(todo.displayStatus))
                        Spacer()
                        Button(todo.isDone ? "Mark Incomplete" : "Mark Complete") {
                            Task { await appModel.toggleTodoCompletion(todo) }
                        }
                        .disabled(appModel.isWorking)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Source") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    propertyRow("Note", todo.noteTitle ?? "")
                    propertyRow("Path", todo.path ?? "")
                    propertyRow("Line", String(todo.lineNumber))
                    propertyRow("Source ID", todo.sourceID ?? "")
                    propertyRow("Scope", todo.taskScope ?? "")
                    propertyRow("Task status", todo.displayStatus)
                    propertyRow("Task section", todo.displayTodoSection)
                }
                .textSelection(.enabled)

                HStack {
                    Button("View Source Note") {
                        appModel.openSourceNote(for: todo)
                    }
                    .disabled(todo.noteID == nil)
                }
                .padding(.top, 8)
            }

            GroupBox("Metadata") {
                VStack(alignment: .leading, spacing: 12) {
                    metadataGrid(
                        area: $area,
                        priority: $priority,
                        energy: $energy,
                        weight: $weight,
                        due: $due,
                        start: $start,
                        estimate: $estimate
                    )

                    Toggle("Replace metadata with raw line", isOn: $useRawMetadata)
                    if useRawMetadata {
                        TextField("area: Code p2 e:m due:2026-06-20", text: $rawMetadata, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Effective weight: \(todo.displayEffectiveWeight, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save Todo") {
                            Task { await appModel.updateTodo(todo, patch: singlePatch(original: todo)) }
                        }
                        .disabled(appModel.isWorking || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var bulkEditor: some View {
        GroupBox("Bulk Edit (\(appModel.selectedTodoIDs.count) selected)") {
            VStack(alignment: .leading, spacing: 12) {
                metadataGrid(
                    area: $bulkArea,
                    priority: $bulkPriority,
                    energy: $bulkEnergy,
                    weight: $bulkWeight,
                    due: $bulkDue,
                    start: $bulkStart,
                    estimate: $bulkEstimate
                )

                TextField("Clear keys, comma-separated: due,start,weight", text: $bulkClear)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Only non-empty fields are applied in bulk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply to Selected") {
                        Task { await appModel.updateSelectedTodos(patch: bulkPatch()) }
                    }
                    .disabled(appModel.isWorking)
                }
            }
        }
    }

    private func metadataGrid(
        area: Binding<String>,
        priority: Binding<String>,
        energy: Binding<String>,
        weight: Binding<String>,
        due: Binding<String>,
        start: Binding<String>,
        estimate: Binding<String>
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            editorRow("Area", "Code", area)
            editorRow("Priority", "p1..p5", priority)
            editorRow("Energy", "xsm/s/m/l/xl", energy)
            editorRow("Weight", "optional override", weight)
            editorRow("Due", "YYYY-MM-DD", due)
            editorRow("Start", "YYYY-MM-DD", start)
            editorRow("Estimate", "minutes", estimate)
        }
    }

    private func propertyRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
        }
    }

    private func editorRow(_ label: String, _ prompt: String, _ value: Binding<String>) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            TextField(prompt, text: value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
        }
    }

    private func loadSelectedTodo() {
        guard let todo = appModel.selectedTodo else { return }
        title = todo.title
        area = todo.displayArea
        priority = todo.displayPriority
        energy = todo.displayEnergy
        weight = todo.displayWeightOverride
        due = todo.displayDue
        start = todo.displayStart
        estimate = todo.displayEstimate
        rawMetadata = todo.metadata?.raw ?? ""
        useRawMetadata = false
    }

    private func singlePatch(original: MWTodo) -> MWTodoUpdatePatch {
        var clear: [String] = []
        func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

        if useRawMetadata {
            return MWTodoUpdatePatch(
                title: clean(title) == original.title ? nil : clean(title),
                metadata: clean(rawMetadata)
            )
        }

        func changed(_ newValue: String, _ oldValue: String) -> String? {
            let value = clean(newValue)
            return value == oldValue ? nil : value.nilIfEmpty
        }
        func clearIfEmptied(_ key: String, _ newValue: String, _ oldValue: String) {
            if clean(newValue).isEmpty && !oldValue.isEmpty {
                clear.append(key)
            }
        }

        clearIfEmptied("area", area, original.displayArea)
        clearIfEmptied("priority", priority, original.displayPriority)
        clearIfEmptied("energy", energy, original.displayEnergy)
        clearIfEmptied("weight", weight, original.displayWeightOverride)
        clearIfEmptied("due", due, original.displayDue)
        clearIfEmptied("start", start, original.displayStart)
        clearIfEmptied("estimate", estimate, original.displayEstimate)

        return MWTodoUpdatePatch(
            title: clean(title) == original.title ? nil : clean(title),
            area: changed(area, original.displayArea),
            priority: changed(priority, original.displayPriority),
            energy: changed(energy, original.displayEnergy),
            weight: changed(weight, original.displayWeightOverride),
            due: changed(due, original.displayDue),
            start: changed(start, original.displayStart),
            estimate: changed(estimate, original.displayEstimate),
            clear: clear
        )
    }

    private func bulkPatch() -> MWTodoUpdatePatch {
        func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        let clear = bulkClear
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return MWTodoUpdatePatch(
            area: clean(bulkArea).nilIfEmpty,
            priority: clean(bulkPriority).nilIfEmpty,
            energy: clean(bulkEnergy).nilIfEmpty,
            weight: clean(bulkWeight).nilIfEmpty,
            due: clean(bulkDue).nilIfEmpty,
            start: clean(bulkStart).nilIfEmpty,
            estimate: clean(bulkEstimate).nilIfEmpty,
            clear: clear
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private func statusColor(_ status: String) -> Color {
    switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "done": .green
    case "next": .blue
    case "waiting": .yellow
    case "blocked": .red
    case "inbox": .secondary
    default: .secondary
    }
}

private func statusSystemImage(_ status: String) -> String {
    switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "done": "checkmark.square.fill"
    case "next": "arrow.right.circle.fill"
    case "waiting": "clock.fill"
    case "blocked": "exclamationmark.octagon.fill"
    default: "tray.fill"
    }
}
