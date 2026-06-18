import Foundation

struct ExternalToolStatus: Identifiable, Hashable, Sendable {
    enum Requirement: String, Sendable {
        case required = "Required"
        case optional = "Optional"
    }

    var id: String { name }
    var name: String
    var requirement: Requirement
    var executablePath: String?
    var isAvailable: Bool
    var installCommand: String
    var note: String
}

enum ToolResolver {
    static let homebrewAppleSiliconBin = "/opt/homebrew/bin"
    static let homebrewIntelBin = "/usr/local/bin"

    static func processEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let additions = searchDirectories
        let existing = env["PATH"] ?? ""
        env["PATH"] = (additions + [existing]).filter { !$0.isEmpty }.joined(separator: ":")
        return env
    }

    static func resolve(_ executableName: String, additionalCandidates: [URL] = []) -> URL? {
        for candidate in additionalCandidates where isExecutable(candidate) {
            return candidate
        }

        for directory in resolvedSearchDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executableName)
            if isExecutable(candidate) {
                return candidate
            }
        }

        return nil
    }

    static func status(
        _ executableName: String,
        requirement: ExternalToolStatus.Requirement,
        installCommand: String,
        note: String,
        additionalCandidates: [URL] = []
    ) -> ExternalToolStatus {
        let resolved = resolve(executableName, additionalCandidates: additionalCandidates)
        return ExternalToolStatus(
            name: executableName,
            requirement: requirement,
            executablePath: resolved?.path,
            isAvailable: resolved != nil,
            installCommand: installCommand,
            note: note
        )
    }

    static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private static var searchDirectories: [String] {
        [
            NSString(string: "~/.local/bin").expandingTildeInPath,
            NSString(string: "~/go/bin").expandingTildeInPath,
            homebrewAppleSiliconBin,
            homebrewIntelBin,
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    }

    private static var resolvedSearchDirectories: [String] {
        var seen: Set<String> = []
        return (searchDirectories + pathDirectories).filter { directory in
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
    }

    private static var pathDirectories: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
    }
}

enum ExternalToolCatalog {
    static func statuses() -> [ExternalToolStatus] {
        [
            ToolResolver.status(
                "mw",
                requirement: .required,
                installCommand: "brew install Noswad123/jamal-arcana/mw",
                note: "MindWeaver's required Go engine. Homebrew is preferred for releases."
            ),
            ToolResolver.status(
                "wisp",
                requirement: .optional,
                installCommand: "brew install Noswad123/jamal-arcana/wisp",
                note: "Best external-editing experience when paired with nvim, kitty, and Aerospace."
            ),
            ToolResolver.status(
                "nvim",
                requirement: .optional,
                installCommand: "brew install neovim",
                note: "Preferred terminal editor for raw Markdown editing."
            ),
            ToolResolver.status(
                "kitty",
                requirement: .optional,
                installCommand: "brew install --cask kitty",
                note: "Terminal used by wisp and as a direct nvim fallback."
            ),
            ToolResolver.status(
                "aerospace",
                requirement: .optional,
                installCommand: "brew install --cask nikitabobko/tap/aerospace",
                note: "Optional window positioning layer used by some wisp workflows."
            ),
        ]
    }
}
