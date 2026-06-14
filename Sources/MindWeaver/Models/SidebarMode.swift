import Foundation

enum SidebarMode: String, CaseIterable, Identifiable, Sendable {
    case notes = "List"
    case todos = "Todos"
    case files = "File Tree"
    case graph = "Graph"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .notes: "list.bullet"
        case .todos: "checklist"
        case .files: "folder"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }
}
