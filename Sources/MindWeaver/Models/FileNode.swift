import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var noteID: MWNote.ID?
    var children: [FileNode]?

    var isFolder: Bool { children != nil }

    static func tree(from notes: [MWNote]) -> [FileNode] {
        var root = TreeBuilderNode(name: "", path: "")

        for note in notes {
            guard let path = note.path, !path.isEmpty else { continue }
            root.insert(parts: path.split(separator: "/").map(String.init), noteID: note.id)
        }

        return root.children.values
            .map { $0.fileNode }
            .sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}

private struct TreeBuilderNode {
    var name: String
    var path: String
    var noteID: MWNote.ID?
    var children: [String: TreeBuilderNode] = [:]

    mutating func insert(parts: [String], noteID: MWNote.ID) {
        guard let first = parts.first else { return }
        let childPath = path.isEmpty ? first : path + "/" + first

        if parts.count == 1 {
            children[first] = TreeBuilderNode(name: first, path: childPath, noteID: noteID)
            return
        }

        var child = children[first] ?? TreeBuilderNode(name: first, path: childPath)
        child.insert(parts: Array(parts.dropFirst()), noteID: noteID)
        children[first] = child
    }

    var fileNode: FileNode {
        if children.isEmpty {
            return FileNode(name: name, path: path, noteID: noteID, children: nil)
        }

        let sortedChildren = children.values
            .map { $0.fileNode }
            .sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return FileNode(name: name, path: path, noteID: noteID, children: sortedChildren)
    }
}
