import Foundation

enum MindWeaverPaths {
    private static let notesDirectoryDefaultsKey = "notesDirectory"

    static func notesDirectory() -> URL {
        if let storedNotesDir = storedNotesDirectory() {
            return storedNotesDir
        }

        return candidateNotesDirectory()
    }

    static func hasStoredNotesDirectory() -> Bool {
        storedNotesDirectory() != nil
    }

    static func saveNotesDirectory(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: notesDirectoryDefaultsKey)
    }

    private static func storedNotesDirectory() -> URL? {
        let stored = UserDefaults.standard.string(forKey: notesDirectoryDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !stored.isEmpty else { return nil }
        return URL(fileURLWithPath: expandTilde(stored)).standardizedFileURL
    }

    private static func candidateNotesDirectory() -> URL {
        if let envNotesDir = ProcessInfo.processInfo.environment["NOTES_DIR"], !envNotesDir.isEmpty {
            return URL(fileURLWithPath: expandTilde(envNotesDir)).standardizedFileURL
        }

        let configURL = URL(fileURLWithPath: expandTilde("~/.config/mind-weaver/config.toml"))
        if let config = try? String(contentsOf: configURL, encoding: .utf8) {
            for line in config.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("notes_dir") else { continue }

                if let value = scalarValue(from: trimmed) {
                    return URL(fileURLWithPath: expandTilde(value)).standardizedFileURL
                }
            }
        }

        return URL(fileURLWithPath: expandTilde("~/Notes")).standardizedFileURL
    }

    private static func scalarValue(from line: String) -> String? {
        let separator = line.contains("=") ? "=" : ":"
        let parts = line.split(separator: Character(separator), maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        return parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
