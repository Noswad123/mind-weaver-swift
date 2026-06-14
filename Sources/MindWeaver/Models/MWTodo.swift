import Foundation

struct MWTodo: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var noteTitle: String?
    var isDone: Bool
}
