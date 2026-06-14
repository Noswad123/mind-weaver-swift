import Foundation

actor MWCLIEngine: MindWeaverEngine {
    private let executableURL: URL
    private let leadingArguments: [String]

    init() {
        if let bundled = Bundle.main.url(forResource: "mw", withExtension: nil) {
            self.executableURL = bundled
            self.leadingArguments = []
        } else {
            self.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            self.leadingArguments = ["mw"]
        }
    }

    func listNotes(limit: Int = 100, search: String? = nil) async throws -> [MWNote] {
        var args = ["query", "notes", "--format", "json", "--limit", String(limit)]

        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--search", search])
        }

        let output = try await run(args)
        guard output.succeeded else { throw MindWeaverEngineError.commandFailed(output) }

        do {
            return try JSONDecoder().decode([MWNote].self, from: Data(output.stdout.utf8))
        } catch {
            throw MindWeaverEngineError.invalidJSON(command: output.command, output: output.displayText)
        }
    }

    func doctor() async throws -> CommandOutput {
        try await run(["doctor"])
    }

    func syncNotes() async throws -> CommandOutput {
        try await run(["notes", "sync"])
    }

    func validateNotes() async throws -> CommandOutput {
        try await run(["notes", "validate", "--all"])
    }

    private func run(_ arguments: [String]) async throws -> CommandOutput {
        let executableURL = self.executableURL
        let allArguments = leadingArguments + arguments

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let stdoutURL = temporaryDirectory.appendingPathComponent("mind-weaver-stdout-\(UUID().uuidString).log")
            let stderrURL = temporaryDirectory.appendingPathComponent("mind-weaver-stderr-\(UUID().uuidString).log")

            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)

            defer {
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }

            process.executableURL = executableURL
            process.arguments = allArguments
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            try stdout.close()
            try stderr.close()

            let stdoutData = try Data(contentsOf: stdoutURL)
            let stderrData = try Data(contentsOf: stderrURL)

            return CommandOutput(
                command: ([executableURL.path] + allArguments).joined(separator: " "),
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }.value
    }
}
