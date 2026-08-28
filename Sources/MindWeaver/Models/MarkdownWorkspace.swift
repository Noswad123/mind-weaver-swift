import Foundation

enum MarkdownWorkspaceKind: String, Sendable {
    case file
    case folder
}

struct MarkdownWorkspace: Equatable, Sendable {
    var kind: MarkdownWorkspaceKind
    var rootURL: URL

    var displayName: String {
        rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent
    }

    var displayPath: String {
        rootURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

struct MarkdownFileNode: Identifiable, Hashable, Sendable {
    var id: String { url.standardizedFileURL.path }
    var name: String
    var url: URL
    var children: [MarkdownFileNode]?

    var isFolder: Bool { children != nil }

    static func tree(for workspace: MarkdownWorkspace) throws -> [MarkdownFileNode] {
        switch workspace.kind {
        case .file:
            guard isMarkdownFile(workspace.rootURL) else { return [] }
            return [MarkdownFileNode(name: workspace.rootURL.lastPathComponent, url: workspace.rootURL.standardizedFileURL, children: nil)]
        case .folder:
            return try children(in: workspace.rootURL.standardizedFileURL)
        }
    }

    static func firstMarkdownFile(in nodes: [MarkdownFileNode]) -> URL? {
        for node in nodes {
            if node.isFolder, let children = node.children, let found = firstMarkdownFile(in: children) {
                return found
            }
            if !node.isFolder {
                return node.url
            }
        }
        return nil
    }

    private static func children(in directory: URL) throws -> [MarkdownFileNode] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try urls.compactMap(node(for:))
            .sorted(by: sortFoldersFirst)
    }

    private static func node(for url: URL) throws -> MarkdownFileNode? {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            let children = try children(in: url)
            guard !children.isEmpty else { return nil }
            return MarkdownFileNode(name: url.lastPathComponent, url: url.standardizedFileURL, children: children)
        }

        guard isMarkdownFile(url) else { return nil }
        return MarkdownFileNode(name: url.lastPathComponent, url: url.standardizedFileURL, children: nil)
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private static func sortFoldersFirst(_ lhs: MarkdownFileNode, _ rhs: MarkdownFileNode) -> Bool {
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
