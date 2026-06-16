import Foundation

enum ExternalEditorLauncher {
    static func open(_ fileURL: URL) async throws -> CommandOutput {
        await Task.detached(priority: .userInitiated) {
            let wisp = ToolResolver.resolve("wisp")
            let nvim = ToolResolver.resolve("nvim")
            let kitty = ToolResolver.resolve("kitty")
            let aerospace = ToolResolver.resolve("aerospace")
            var failures: [CommandOutput] = []

            func attempt(_ label: String, _ operation: () throws -> CommandOutput) -> CommandOutput? {
                do {
                    let output = try operation()
                    if output.succeeded { return output }
                    failures.append(output)
                    return nil
                } catch {
                    failures.append(CommandOutput(command: label, exitCode: 127, stdout: "", stderr: error.localizedDescription))
                    return nil
                }
            }

            if wisp != nil, nvim != nil, kitty != nil, aerospace != nil {
                if let output = attempt("wisp nvim", {
                    try run(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["wisp", "nvim", fileURL.path],
                    fallbackDescription: "wisp nvim"
                    )
                }) { return output }
            }

            if let kitty, nvim != nil {
                if let output = attempt("kitty --detach nvim", {
                    try run(
                    executableURL: kitty,
                    arguments: ["--detach", "nvim", fileURL.path],
                    fallbackDescription: "kitty --detach nvim"
                    )
                }) { return output }
            }

            if let nvim {
                if let output = attempt("Terminal nvim", {
                    try openTerminal(command: "\(shellQuote(nvim.path)) \(shellQuote(fileURL.path))")
                }) {
                    return output
                }
            }

            if let editorCommand = preferredGUIEditorCommand(for: fileURL) {
                if let output = attempt("$VISUAL/$EDITOR", {
                    try run(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: ["-lc", editorCommand],
                    fallbackDescription: "$VISUAL/$EDITOR"
                    )
                }) { return output }
            }

            if let output = attempt("TextEdit fallback", {
                try run(
                executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-e", fileURL.path],
                fallbackDescription: "TextEdit fallback"
                )
            }) { return output }

            return combinedFailure(failures)
        }.value
    }

    private static func preferredGUIEditorCommand(for fileURL: URL) -> String? {
        let env = ProcessInfo.processInfo.environment
        let raw = (env["VISUAL"] ?? env["EDITOR"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let executable = raw.split(separator: " ").first.map(String.init) ?? raw
        let basename = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let guiEditors = Set(["open", "code", "cursor", "subl", "mate", "bbedit", "zed"])
        guard guiEditors.contains(basename) else { return nil }

        return "\(raw) \(shellQuote(fileURL.path))"
    }

    private static func openTerminal(command: String) throws -> CommandOutput {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to activate\ntell application \"Terminal\" to do script \"\(escaped)\""
        return try run(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script],
            fallbackDescription: "Terminal nvim"
        )
    }

    private static func run(executableURL: URL, arguments: [String], fallbackDescription: String) throws -> CommandOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ToolResolver.processEnvironment()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let command = ([executableURL.path] + arguments).joined(separator: " ")
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let note = "Opened with \(fallbackDescription)."

        return CommandOutput(
            command: command,
            exitCode: process.terminationStatus,
            stdout: stdout.isEmpty ? note : "\(note)\n\(stdout)",
            stderr: stderr
        )
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func combinedFailure(_ failures: [CommandOutput]) -> CommandOutput {
        CommandOutput(
            command: "Open external editor fallback chain",
            exitCode: failures.last?.exitCode ?? 1,
            stdout: "All external editor fallbacks failed.",
            stderr: failures.map { "[\($0.command)]\n\($0.displayText)" }.joined(separator: "\n\n")
        )
    }
}
