import Foundation

struct CommandOutput: Sendable, Hashable {
    var command: String
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var succeeded: Bool { exitCode == 0 }

    var displayText: String {
        let output = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return output.isEmpty ? "No output" : output
    }
}
