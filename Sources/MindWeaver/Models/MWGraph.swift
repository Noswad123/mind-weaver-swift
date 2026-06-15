import Foundation

struct MWGraph: Codable, Sendable {
    var nodes: [MWGraphNode]
    var edges: [MWGraphEdge]
    var meta: MWGraphMeta?
}

struct MWGraphMeta: Codable, Sendable {
    var seedCount: Int?
    var depth: Int?
    var search: String?
    var domain: String?
}

struct MWGraphNode: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var noteID: Int?
    var uid: String?
    var label: String
    var title: String?
    var path: String?
    var kind: String?
    var tags: [String]
    var domains: [String]
    var matched: Bool?
    var unknown: Bool?
}

struct MWGraphEdge: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var source: String
    var target: String
    var kind: String?
    var label: String?
}
