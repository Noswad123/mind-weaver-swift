import Foundation

struct MWNote: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var uid: String?
    var path: String?
    var title: String
    var content: String
    var tags: [String]

    var displayPath: String {
        path?.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "No path from mw"
    }

    init(
        id: String,
        uid: String? = nil,
        path: String? = nil,
        title: String,
        content: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.uid = uid
        self.path = path
        self.title = title
        self.content = content
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)

        let id = container.decodeFlexibleString(for: ["id", "ID"])
            ?? container.decodeFlexibleString(for: ["uid", "UID"])
            ?? UUID().uuidString

        self.id = id
        self.uid = container.decodeFlexibleString(for: ["uid", "UID"])
        self.path = container.decodeFlexibleString(for: ["path", "Path"])
        self.title = container.decodeFlexibleString(for: ["title", "Title"]) ?? "Untitled"
        self.content = container.decodeFlexibleString(for: ["content", "Content"]) ?? ""
        self.tags = container.decodeFlexibleStringArray(for: ["tags", "Tags"])
    }
}
