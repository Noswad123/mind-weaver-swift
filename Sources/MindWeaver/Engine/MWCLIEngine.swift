import Foundation

actor MWCLIEngine: MindWeaverEngine {
    private var binary = MWBinaryResolver.resolve()

    func binaryStatus() async -> MWBinaryStatus {
        binary.status
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

    func getNote(id: String) async throws -> MWNote {
        let output = try await run(["query", "notes", "--format", "json", "--id", id])
        guard output.succeeded else { throw MindWeaverEngineError.commandFailed(output) }

        do {
            return try JSONDecoder().decode(MWNote.self, from: Data(output.stdout.utf8))
        } catch {
            throw MindWeaverEngineError.invalidJSON(command: output.command, output: output.displayText)
        }
    }

    func listDomains() async throws -> [String] {
        let output = try await run(["query", "domains"])
        guard output.succeeded else { throw MindWeaverEngineError.commandFailed(output) }

        do {
            return try JSONDecoder().decode([String].self, from: Data(output.stdout.utf8))
        } catch {
            throw MindWeaverEngineError.invalidJSON(command: output.command, output: output.displayText)
        }
    }

    func listTodos() async throws -> [MWTodo] {
        let output = try await run(["query", "todos"])
        guard output.succeeded else { throw MindWeaverEngineError.commandFailed(output) }

        do {
            return try JSONDecoder().decode([MWTodo].self, from: Data(output.stdout.utf8))
        } catch {
            throw MindWeaverEngineError.invalidJSON(command: output.command, output: output.displayText)
        }
    }

    func queryGraph(search: String?, domain: String?, depth: Int, limit: Int) async throws -> MWGraph {
        var args = ["query", "graph", "--depth", String(depth), "--limit", String(limit)]
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--search", search])
        }
        if let domain, !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--domain", domain])
        }

        let output = try await run(args)
        guard output.succeeded else { throw MindWeaverEngineError.commandFailed(output) }

        do {
            return try JSONDecoder().decode(MWGraph.self, from: Data(output.stdout.utf8))
        } catch {
            throw MindWeaverEngineError.invalidJSON(command: output.command, output: output.displayText)
        }
    }

    func toggleTodo(id: String) async throws -> CommandOutput {
        let output = try await run(["todos", "toggle", "--id", id])
        guard output.succeeded else { throw MindWeaverEngineError.commandFailed(output) }
        return output
    }

    func updateTodos(ids: [String], patch: MWTodoUpdatePatch) async throws -> CommandOutput {
        var args = ["todos", "update"]
        for id in ids {
            args.append(contentsOf: ["--id", id])
        }
        appendStringFlag("title", patch.title, to: &args)
        appendStringFlag("area", patch.area, to: &args)
        appendStringFlag("priority", patch.priority, to: &args)
        appendStringFlag("energy", patch.energy, to: &args)
        appendStringFlag("weight", patch.weight, to: &args)
        appendStringFlag("due", patch.due, to: &args)
        appendStringFlag("start", patch.start, to: &args)
        appendStringFlag("estimate", patch.estimate, to: &args)
        appendStringFlag("metadata", patch.metadata, to: &args)
        for key in patch.clear {
            args.append(contentsOf: ["--clear", key])
        }

        let output = try await run(args)
        guard output.succeeded else { throw MindWeaverEngineError.commandFailed(output) }
        return output
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

    func rebuildLocalBinary() async throws -> CommandOutput {
        let output = try await runExternal(executableURL: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["tsync", "--only", "mw"])
        binary = MWBinaryResolver.resolve()
        return output
    }

    func deleteLocalBinary() async throws -> CommandOutput {
        let localURL = MWBinaryResolver.localBinaryURL

        return await Task.detached(priority: .userInitiated) {
            let command = "delete \(localURL.path)"
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                return CommandOutput(command: command, exitCode: 0, stdout: "No local mw binary found at \(localURL.path)", stderr: "")
            }

            do {
                try FileManager.default.removeItem(at: localURL)
                return CommandOutput(command: command, exitCode: 0, stdout: "Deleted \(localURL.path)", stderr: "")
            } catch {
                return CommandOutput(command: command, exitCode: 1, stdout: "", stderr: error.localizedDescription)
            }
        }.value
    }

    private func run(_ arguments: [String]) async throws -> CommandOutput {
        binary = MWBinaryResolver.resolve()
        return try await runExternal(executableURL: binary.executableURL, arguments: binary.leadingArguments + arguments)
    }

    private func appendStringFlag(_ name: String, _ value: String?, to args: inout [String]) {
        guard let value else { return }
        args.append(contentsOf: ["--\(name)", value])
    }

    private func runExternal(executableURL: URL, arguments: [String]) async throws -> CommandOutput {
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
            process.arguments = arguments
            process.environment = ToolResolver.processEnvironment()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            try stdout.close()
            try stderr.close()

            let stdoutData = try Data(contentsOf: stdoutURL)
            let stderrData = try Data(contentsOf: stderrURL)

            return CommandOutput(
                command: ([executableURL.path] + arguments).joined(separator: " "),
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }.value
    }
}

private struct MWBinaryResolution: Sendable {
    var executableURL: URL
    var leadingArguments: [String]
    var status: MWBinaryStatus
}

private enum MWBinaryResolver {
    static var localBinaryURL: URL {
        URL(fileURLWithPath: NSString(string: "~/.local/bin/mw").expandingTildeInPath)
    }

    static var goBinaryURL: URL {
        URL(fileURLWithPath: NSString(string: "~/go/bin/mw").expandingTildeInPath)
    }

    static var homebrewAppleSiliconBinaryURL: URL {
        URL(fileURLWithPath: ToolResolver.homebrewAppleSiliconBin).appendingPathComponent("mw")
    }

    static var homebrewIntelBinaryURL: URL {
        URL(fileURLWithPath: ToolResolver.homebrewIntelBin).appendingPathComponent("mw")
    }

    static func resolve() -> MWBinaryResolution {
        if let bundled = Bundle.main.url(forResource: "mw", withExtension: nil), isExecutable(bundled) {
            return resolution(url: bundled, source: .bundled)
        }

        if isExecutable(homebrewAppleSiliconBinaryURL) {
            return resolution(url: homebrewAppleSiliconBinaryURL, source: .homebrew)
        }

        if isExecutable(homebrewIntelBinaryURL) {
            return resolution(url: homebrewIntelBinaryURL, source: .homebrew)
        }

        if isExecutable(localBinaryURL) {
            return resolution(url: localBinaryURL, source: .localBin)
        }

        if isExecutable(goBinaryURL) {
            return resolution(url: goBinaryURL, source: .goBin)
        }

        if let pathURL = findOnPath("mw") {
            return resolution(url: pathURL, source: .path)
        }

        return MWBinaryResolution(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            leadingArguments: ["mw"],
            status: .unresolved
        )
    }

    static func processEnvironment() -> [String: String] {
        ToolResolver.processEnvironment()
    }

    private static func resolution(url: URL, source: MWBinaryStatus.Source) -> MWBinaryResolution {
        MWBinaryResolution(
            executableURL: url,
            leadingArguments: [],
            status: MWBinaryStatus(
                source: source,
                executablePath: url.path,
                displayName: "\(source.rawValue): \(url.path)",
                isExecutable: true
            )
        )
    }

    private static func isExecutable(_ url: URL) -> Bool {
        ToolResolver.isExecutable(url)
    }

    private static func findOnPath(_ executableName: String) -> URL? {
        ToolResolver.resolve(executableName)
    }
}
