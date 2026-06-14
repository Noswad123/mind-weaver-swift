import Foundation

struct MWBinaryStatus: Hashable, Sendable {
    enum Source: String, Sendable {
        case bundled = "Bundled app resource"
        case localBin = "~/.local/bin"
        case goBin = "~/go/bin"
        case path = "PATH"
        case unresolved = "Unresolved"
    }

    var source: Source
    var executablePath: String
    var displayName: String
    var isExecutable: Bool

    static let unresolved = MWBinaryStatus(
        source: .unresolved,
        executablePath: "mw",
        displayName: "mw not resolved yet",
        isExecutable: false
    )
}
