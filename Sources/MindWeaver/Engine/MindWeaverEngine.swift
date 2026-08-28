import Foundation

protocol MindWeaverEngine: Sendable {
    func binaryStatus() async -> MWBinaryStatus
    func readinessCheck() async -> MWReadinessReport
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

struct MWReadinessReport: Hashable, Sendable {
    var binaryStatus: MWBinaryStatus
    var minimumVersion: String
    var checks: [MWCapabilityCheck]

    var isReady: Bool {
        binaryStatus.isExecutable && checks.allSatisfy { !$0.required || $0.succeeded }
    }

    var summary: String {
        isReady ? "mw is ready" : "mw is missing required capabilities"
    }

    var displayText: String {
        var lines = [
            "mw readiness: \(summary)",
            "minimum mw version: \(minimumVersion)",
            "resolved binary: \(binaryStatus.displayName)",
            "executable: \(binaryStatus.isExecutable ? "yes" : "no")",
            "",
        ]

        lines.append(contentsOf: checks.map { check in
            let marker = check.succeeded ? "✓" : (check.required ? "✗" : "!")
            return "\(marker) \(check.name) — \(check.command)\n  \(check.message)"
        })
        return lines.joined(separator: "\n")
    }

    static let notRun = MWReadinessReport(
        binaryStatus: .unresolved,
        minimumVersion: MindWeaverRequirements.minimumMWVersion,
        checks: []
    )
}

struct MWCapabilityCheck: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var command: String
    var required: Bool
    var succeeded: Bool
    var message: String
}

enum MindWeaverRequirements {
    static let minimumMWVersion = "0.1.0"
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
