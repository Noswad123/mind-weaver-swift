import SwiftUI

struct NoteSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 10) {
            TextField("Search notes", text: $appModel.searchText)
                .textFieldStyle(.roundedBorder)
                .padding([.top, .horizontal])

            List(appModel.visibleNotes) { note in
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

                        if !note.tags.isEmpty {
                            Text(note.tags.map { "#\($0)" }.joined(separator: " "))
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

            VStack(alignment: .leading, spacing: 4) {
                Text("\(appModel.notes.count) notes")
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
}
