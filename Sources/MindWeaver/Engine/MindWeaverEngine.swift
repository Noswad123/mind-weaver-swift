import Foundation

protocol MindWeaverEngine: Sendable {
    func listNotes(limit: Int, search: String?) async throws -> [MWNote]
    func doctor() async throws -> CommandOutput
    func syncNotes() async throws -> CommandOutput
    func validateNotes() async throws -> CommandOutput
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
