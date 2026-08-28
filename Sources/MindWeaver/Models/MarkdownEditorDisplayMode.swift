import Foundation

enum MarkdownEditorDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case source = "Source"
    case preview = "Preview"
    case split = "Split"

    var id: String { rawValue }
}
