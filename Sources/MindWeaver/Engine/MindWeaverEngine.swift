import Foundation

protocol MindWeaverEngine: Sendable {
    func binaryStatus() async -> MWBinaryStatus
    func listNotes(limit: Int, search: String?) async throws -> [MWNote]
    func listDomains() async throws -> [String]
    func listTodos() async throws -> [MWTodo]
    func queryGraph(search: String?, domain: String?, depth: Int, limit: Int) async throws -> MWGraph
    func toggleTodo(id: String) async throws -> CommandOutput
    func updateTodos(ids: [String], patch: MWTodoUpdatePatch) async throws -> CommandOutput
    func getNote(id: String) async throws -> MWNote
    func doctor() async throws -> CommandOutput
    func syncNotes() async throws -> CommandOutput
    func validateNotes() async throws -> CommandOutput
    func deleteLocalBinary() async throws -> CommandOutput
}

enum MindWeaverEngineError: LocalizedError, Sendable {
    case commandFailed(CommandOutput)
    case invalidJSON(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return "`\(output.command)` failed with exit code \(output.exitCode): \(output.displayText)"
        case .invalidJSON(let command, let output):
            return "`\(command)` did not return decodable JSON: \(output)"
        }
    }
}
