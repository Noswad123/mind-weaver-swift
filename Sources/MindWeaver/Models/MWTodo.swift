import Foundation

struct MWTodo: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var noteTitle: String?
    var noteID: String?
    var path: String?
    var sourceID: String?
    var taskScope: String?
    var todoSection: String?
    var section: String?
    var status: String?
    var rawStatus: String?
    var lineNumber: Int
    var isDone: Bool
    var metadata: MWTodoMetadata?
    var area: String?
    var priority: String?
    var energy: String?
    var weightOverride: String?
    var due: String?
    var start: String?
    var estimate: String?
    var effectiveWeight: Double?

    var displayArea: String { area ?? metadata?.area ?? section ?? "" }
    var displayStatus: String { metadata?.status ?? status ?? (isDone ? "Done" : (todoSection ?? metadata?.todoSection ?? "Inbox")) }
    var displayTodoSection: String { todoSection ?? metadata?.todoSection ?? "" }
    var displayPriority: String { priority ?? metadata?.priority ?? "" }
    var displayEnergy: String { energy ?? metadata?.energy ?? "" }
    var displayWeightOverride: String { weightOverride ?? metadata?.weightOverride ?? "" }
    var displayDue: String { due ?? metadata?.due ?? "" }
    var displayStart: String { start ?? metadata?.start ?? "" }
    var displayEstimate: String { estimate ?? metadata?.estimate ?? "" }
    var displayEffectiveWeight: Double { effectiveWeight ?? metadata?.effectiveWeight ?? 0 }
}

struct MWTodoMetadata: Hashable, Codable, Sendable {
    var status: String?
    var todoSection: String?
    var area: String?
    var priority: String?
    var energy: String?
    var weightOverride: String?
    var due: String?
    var start: String?
    var estimate: String?
    var raw: String?
    var effectiveWeight: Double?
    var defaultPriority: String?
    var defaultEnergy: String?
}

struct MWTodoUpdatePatch: Sendable {
    var title: String?
    var area: String?
    var priority: String?
    var energy: String?
    var weight: String?
    var due: String?
    var start: String?
    var estimate: String?
    var metadata: String?
    var clear: [String] = []
}
