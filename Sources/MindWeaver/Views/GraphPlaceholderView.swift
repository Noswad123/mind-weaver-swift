import AppKit
import SwiftUI

struct GraphPlaceholderView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var isPanningGraph = false
    @State private var scrollMonitor: Any?
    @State private var viewportSize: CGSize = .zero
    @State private var currentContentSize: CGSize = .zero
    @State private var lastHoverPoint: CGPoint?
    @State private var graphPositions: [String: CGPoint] = [:]
    @State private var activeDragNodeID: String?
    @State private var lastAutoFitSignature: String?
    @State private var pendingFitAfterSettle = false
    @State private var layoutTask: Task<Void, Never>?
    @State private var layoutGeneration = 0
    @State private var renderCache = GraphRenderCache.empty
    @State private var lastLayoutResetSignature: String?

    private static let layoutEngine = GraphLayoutEngine()

    private let nodeSpacing: CGFloat = 170

    private struct GraphTopology {
        let nodesByID: [String: MWGraphNode]
        let adjacency: [String: Set<String>]
        let degree: [String: Int]
        let components: [[String]]
        let connectedComponents: [[String]]
        let isolated: [String]
        let componentIndexByNodeID: [String: Int]
        let primaryHubByNodeID: [String: String]
        let hubGroups: [String: [String]]
    }

    private struct GraphRenderCache {
        let signature: String
        let orderedNodes: [MWGraphNode]
        let nodesByID: [String: MWGraphNode]
        let adjacency: [String: Set<String>]
        let noteIDToGraphNodeID: [String: String]

        static let empty = GraphRenderCache(signature: "", orderedNodes: [], nodesByID: [:], adjacency: [:], noteIDToGraphNodeID: [:])
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            GeometryReader { geometry in
                let contentSize = graphContentSize(viewport: geometry.size)
                let centeredOffset = centeredContentOffset(viewport: geometry.size, contentSize: contentSize)

                ZStack(alignment: .topLeading) {
                    graphCanvas(size: contentSize)
                    .frame(width: contentSize.width, height: contentSize.height)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(x: centeredOffset.width + panOffset.width, y: centeredOffset.height + panOffset.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .gesture(graphDragGesture(contentSize: contentSize, centeredOffset: centeredOffset))
                .simultaneousGesture(magnificationGesture)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        lastHoverPoint = location
                    case .ended:
                        lastHoverPoint = nil
                    }
                }
                .background(
                    LinearGradient(
                        colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    Text(isPanningGraph ? "⌘-dragging to pan" : "⌘-drag to pan • ⌘ scroll to zoom")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                }
                .onAppear { updateViewportMetrics(viewport: geometry.size, content: contentSize) }
                .onChange(of: geometry.size) { newSize in
                    updateViewportMetrics(viewport: newSize, content: graphContentSize(viewport: newSize))
                }
                .onChange(of: appModel.graph.nodes.count) { _ in
                    updateViewportMetrics(viewport: geometry.size, content: graphContentSize(viewport: geometry.size))
                }
            }

            Divider()
            CommandOutputView()
        }
        .task {
            if appModel.graph.nodes.isEmpty {
                await appModel.refreshGraph()
            }
        }
        .onAppear {
            installGraphEventMonitors()
            rebuildRenderCacheIfNeeded()
        }
        .onDisappear { removeGraphEventMonitors() }
        .onChange(of: appModel.graphResetToken) { _ in
            resetGraphLayout()
        }
        .onChange(of: appModel.graph.nodes.count) { _ in
            rebuildRenderCacheIfNeeded()
            resetGraphLayout()
        }
        .onChange(of: appModel.graph.edges.count) { _ in
            rebuildRenderCacheIfNeeded()
            resetGraphLayout()
        }
        .onChange(of: appModel.graphForceStrength) { _ in
            scheduleGraphLayout(autoFitAfter: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("All Notes")
                    .font(.title2)
                    .bold()

                Text("Links between notes. Search/domain filters seed the graph; depth expands neighbors from matched nodes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button("−") { setZoom(zoom - 0.15) }
                    .help("Zoom out")
                Text("\(Int(zoom * 100))%")
                    .font(.caption)
                    .frame(width: 44)
                Button("+") { setZoom(zoom + 0.15) }
                    .help("Zoom in")
                Button("Fit") { fitAllNodes() }
                    .help("Zoom to fit all rendered nodes")
            }

            Text("rendered \(appModel.graph.nodes.count) nodes • \(appModel.graph.edges.count) edges")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding()
    }

    private func graphDragGesture(contentSize: CGSize, centeredOffset: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isCommandPressed || isPanningGraph {
                    if !isPanningGraph {
                        isPanningGraph = true
                        activeDragNodeID = nil
                        dragStartOffset = panOffset
                    }
                    panOffset = CGSize(
                        width: dragStartOffset.width + value.translation.width,
                        height: dragStartOffset.height + value.translation.height
                    )
                    return
                }

                let startGraphPoint = graphPoint(
                    from: value.startLocation,
                    centeredOffset: centeredOffset
                )
                if activeDragNodeID == nil,
                   let nearest = nearestNode(to: startGraphPoint, in: contentSize, maxDistance: 90) {
                    activeDragNodeID = nearest.node.id
                }

                guard let activeDragNodeID else { return }
                cancelGraphLayout()
                let currentGraphPoint = graphPoint(
                    from: value.location,
                    centeredOffset: centeredOffset
                )
                graphPositions[activeDragNodeID] = currentGraphPoint
            }
            .onEnded { value in
                if isPanningGraph {
                    isPanningGraph = false
                    dragStartOffset = panOffset
                    return
                }

                if let activeDragNodeID {
                    self.activeDragNodeID = nil
                    let isClick = abs(value.translation.width) < 4 && abs(value.translation.height) < 4
                    if isClick,
                       let node = appModel.graph.nodes.first(where: { $0.id == activeDragNodeID }),
                       let noteID = node.noteID {
                        appModel.focusGraphNode(node.id)
                        appModel.select(noteID: String(noteID))
                    } else {
                        scheduleGraphLayout(autoFitAfter: false)
                    }
                    return
                }

                guard abs(value.translation.width) < 4, abs(value.translation.height) < 4 else { return }
                let clickPoint = graphPoint(from: value.location, centeredOffset: centeredOffset)
                if !selectNearestNode(to: clickPoint, in: contentSize) {
                    appModel.clearSelection()
                }
            }
    }

    private var isCommandPressed: Bool {
        NSEvent.modifierFlags.contains(.command)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let anchor = lastHoverPoint ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
                zoomAround(anchor: anchor, to: baseZoom * value)
            }
            .onEnded { _ in
                baseZoom = zoom
            }
    }

    private func graphContentSize(viewport: CGSize) -> CGSize {
        let rings = max(1, requiredHexRings(for: appModel.graph.nodes.count))
        let diameter = CGFloat(rings * 2 + 3) * nodeSpacing
        return CGSize(
            width: max(viewport.width, diameter + 320),
            height: max(viewport.height, diameter + 320)
        )
    }

    private func centeredContentOffset(viewport: CGSize, contentSize: CGSize) -> CGSize {
        CGSize(
            width: (viewport.width - contentSize.width * zoom) / 2,
            height: (viewport.height - contentSize.height * zoom) / 2
        )
    }

    private func centeredContentOffset(viewport: CGSize, contentSize: CGSize, zoom: CGFloat) -> CGSize {
        CGSize(
            width: (viewport.width - contentSize.width * zoom) / 2,
            height: (viewport.height - contentSize.height * zoom) / 2
        )
    }

    private func graphCanvas(size: CGSize) -> some View {
        Canvas { context, _ in
            let points = nodePoints(in: size)
            let selectedNodeID = appModel.graphFocusedNodeID
            let connectedIDs = selectedNodeID.map { renderCache.adjacency[$0, default: []] } ?? []
            var normalEdgePath = Path()
            var selectedEdgePath = Path()

            for edge in appModel.graph.edges {
                guard let source = points[edge.source], let target = points[edge.target] else { continue }
                let isSelectedEdge = selectedNodeID.map { edge.source == $0 || edge.target == $0 } ?? false
                if isSelectedEdge {
                    selectedEdgePath.move(to: source)
                    selectedEdgePath.addLine(to: target)
                } else {
                    normalEdgePath.move(to: source)
                    normalEdgePath.addLine(to: target)
                }
            }

            let normalEdgeOpacity = selectedNodeID == nil ? 0.34 : 0.10
            context.stroke(normalEdgePath, with: .color(.secondary.opacity(normalEdgeOpacity)), lineWidth: max(0.8, 1.2 / zoom))
            if selectedNodeID != nil {
                context.stroke(selectedEdgePath, with: .color(.white.opacity(0.94)), lineWidth: max(1.8, 2.8 / zoom))
            }

            let shouldDrawLabels = zoom >= 0.65 || appModel.graph.nodes.count <= 350
            for node in orderedGraphNodes() {
                guard let point = points[node.id] else { continue }
                let selected = selectedNodeID == node.id
                let connected = connectedIDs.contains(node.id)
                let matched = node.matched == true
                let radius: CGFloat = selected ? 18 : (matched || connected ? 15 : 12)

                let circleRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: circleRect), with: .color(nodeColor(node, isSelected: selected, isConnectedToSelection: connected, hasSelection: selectedNodeID != nil)))
                context.stroke(Path(ellipseIn: circleRect), with: .color(selected ? .white.opacity(0.98) : .white.opacity(selectedNodeID == nil ? 0.62 : 0.72)), lineWidth: selected ? 3 : (matched || connected ? 2.4 : 1.4))

                if shouldDrawLabels || matched || selected {
                    let text = Text(node.label)
                        .font(.caption)
                        .fontWeight(selected || matched || connected ? .bold : .regular)
                        .foregroundColor(labelColor(isSelected: selected, isConnectedToSelection: connected, hasSelection: selectedNodeID != nil))
                    context.draw(text, at: CGPoint(x: point.x, y: point.y + radius + 16), anchor: .top)
                }
            }
        }
    }

    private func nodePoints(in size: CGSize) -> [String: CGPoint] {
        let nodes = renderCache.orderedNodes.isEmpty ? topologicallyOrderedNodes() : renderCache.orderedNodes
        guard !nodes.isEmpty else { return [:] }

        let nodeIDs = Set(nodes.map(\.id))
        if graphPositions.count == nodes.count && Set(graphPositions.keys) == nodeIDs {
            return graphPositions
        }

        return topologyNodePoints(in: size)
    }

    private func orderedGraphNodes() -> [MWGraphNode] {
        renderCache.orderedNodes.isEmpty ? topologicallyOrderedNodes() : renderCache.orderedNodes
    }

    private func topologyNodePoints(in size: CGSize) -> [String: CGPoint] {
        let topology = graphTopology()
        let nodes = topologicallyOrderedNodes(topology: topology)
        guard !nodes.isEmpty else { return [:] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var out: [String: CGPoint] = [:]

        let componentAnchors = componentAnchorPoints(topology: topology, size: size)
        for (componentIndex, component) in topology.connectedComponents.enumerated() {
            let componentCenter = componentAnchors[componentIndex] ?? center
            let orderedIDs = orderedComponentNodeIDs(component, topology: topology)
            let coordinates = hexCoordinates(count: orderedIDs.count)
            let spacing = componentNodeSpacing(for: orderedIDs.count)
            for (index, nodeID) in orderedIDs.enumerated() {
                guard index < coordinates.count else { continue }
                out[nodeID] = axialToPoint(coordinates[index], center: componentCenter, spacing: spacing)
            }
        }

        let isolatedAnchors = isolatedAnchorPoints(topology: topology, size: size)
        for nodeID in topology.isolated {
            if let point = isolatedAnchors[nodeID] {
                out[nodeID] = point
            }
        }
        return out
    }

    private func topologicallyOrderedNodes() -> [MWGraphNode] {
        topologicallyOrderedNodes(topology: graphTopology())
    }

    private func topologicallyOrderedNodes(topology: GraphTopology) -> [MWGraphNode] {
        let orderedIDs = topology.connectedComponents.flatMap { orderedComponentNodeIDs($0, topology: topology) } + topology.isolated
        return orderedIDs.compactMap { topology.nodesByID[$0] }
    }

    private func labelSortedNodes(_ nodes: [MWGraphNode]) -> [MWGraphNode] {
        nodes.sorted { lhs, rhs in
            if (lhs.matched ?? false) != (rhs.matched ?? false) {
                return lhs.matched == true
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private func graphTopology() -> GraphTopology {
        let nodes = appModel.graph.nodes
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let nodeIDs = Set(nodes.map(\.id))
        var adjacency = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, Set<String>()) })

        for edge in appModel.graph.edges where nodeIDs.contains(edge.source) && nodeIDs.contains(edge.target) && edge.source != edge.target {
            adjacency[edge.source, default: []].insert(edge.target)
            adjacency[edge.target, default: []].insert(edge.source)
        }

        let degree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, adjacency[$0.id, default: []].count) })
        var visited = Set<String>()
        var components: [[String]] = []

        for node in labelSortedNodes(nodes) where !visited.contains(node.id) {
            var queue = [node.id]
            var cursor = 0
            visited.insert(node.id)
            var component: [String] = []

            while cursor < queue.count {
                let id = queue[cursor]
                cursor += 1
                component.append(id)

                let neighbors = adjacency[id, default: []].sorted { lhs, rhs in
                    let lhsDegree = degree[lhs, default: 0]
                    let rhsDegree = degree[rhs, default: 0]
                    if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
                    return (nodesByID[lhs]?.label ?? lhs).localizedCaseInsensitiveCompare(nodesByID[rhs]?.label ?? rhs) == .orderedAscending
                }
                for neighbor in neighbors where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
            components.append(component)
        }

        components.sort { lhs, rhs in
            let lhsMatched = lhs.contains { nodesByID[$0]?.matched == true }
            let rhsMatched = rhs.contains { nodesByID[$0]?.matched == true }
            if lhsMatched != rhsMatched { return lhsMatched }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            let lhsLabel = nodesByID[lhs.first ?? ""]?.label ?? ""
            let rhsLabel = nodesByID[rhs.first ?? ""]?.label ?? ""
            return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
        }

        let connectedComponents = components.filter { component in
            component.contains { degree[$0, default: 0] > 0 }
        }
        let isolated = components
            .filter { component in component.allSatisfy { degree[$0, default: 0] == 0 } }
            .flatMap { $0 }
            .sorted { lhs, rhs in
                let lhsNode = nodesByID[lhs]
                let rhsNode = nodesByID[rhs]
                if (lhsNode?.matched ?? false) != (rhsNode?.matched ?? false) { return lhsNode?.matched == true }
                return (lhsNode?.label ?? lhs).localizedCaseInsensitiveCompare(rhsNode?.label ?? rhs) == .orderedAscending
            }

        var componentIndexByNodeID: [String: Int] = [:]
        for (index, component) in connectedComponents.enumerated() {
            for nodeID in component {
                componentIndexByNodeID[nodeID] = index
            }
        }

        var primaryHubByNodeID: [String: String] = [:]
        var hubGroups: [String: [String]] = [:]
        for node in nodes {
            guard degree[node.id, default: 0] > 0 else { continue }
            let candidates = Array(adjacency[node.id, default: []]) + [node.id]
            let hub = candidates.max { lhs, rhs in
                let lhsDegree = degree[lhs, default: 0]
                let rhsDegree = degree[rhs, default: 0]
                if lhsDegree != rhsDegree { return lhsDegree < rhsDegree }
                return (nodesByID[lhs]?.label ?? lhs).localizedCaseInsensitiveCompare(nodesByID[rhs]?.label ?? rhs) == .orderedDescending
            } ?? node.id
            primaryHubByNodeID[node.id] = hub
            hubGroups[hub, default: []].append(node.id)
        }
        hubGroups = hubGroups.mapValues { members in
            members.sorted { lhs, rhs in
                let lhsDegree = degree[lhs, default: 0]
                let rhsDegree = degree[rhs, default: 0]
                if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
                return (nodesByID[lhs]?.label ?? lhs).localizedCaseInsensitiveCompare(nodesByID[rhs]?.label ?? rhs) == .orderedAscending
            }
        }

        return GraphTopology(
            nodesByID: nodesByID,
            adjacency: adjacency,
            degree: degree,
            components: components,
            connectedComponents: connectedComponents,
            isolated: isolated,
            componentIndexByNodeID: componentIndexByNodeID,
            primaryHubByNodeID: primaryHubByNodeID,
            hubGroups: hubGroups
        )
    }

    private func orderedComponentNodeIDs(_ component: [String], topology: GraphTopology) -> [String] {
        guard !component.isEmpty else { return [] }
        let componentSet = Set(component)
        let seed = component.sorted { lhs, rhs in
            let lhsMatched = topology.nodesByID[lhs]?.matched == true
            let rhsMatched = topology.nodesByID[rhs]?.matched == true
            if lhsMatched != rhsMatched { return lhsMatched }
            let lhsDegree = topology.degree[lhs, default: 0]
            let rhsDegree = topology.degree[rhs, default: 0]
            if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
            return (topology.nodesByID[lhs]?.label ?? lhs).localizedCaseInsensitiveCompare(topology.nodesByID[rhs]?.label ?? rhs) == .orderedAscending
        }.first!

        var ordered: [String] = []
        var visited: Set<String> = [seed]
        var queue: [String] = [seed]
        var cursor = 0

        while cursor < queue.count {
            let id = queue[cursor]
            cursor += 1
            ordered.append(id)

            let neighbors = topology.adjacency[id, default: []]
                .filter { componentSet.contains($0) && !visited.contains($0) }
                .sorted { lhs, rhs in
                    let lhsDegree = topology.degree[lhs, default: 0]
                    let rhsDegree = topology.degree[rhs, default: 0]
                    if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
                    return (topology.nodesByID[lhs]?.label ?? lhs).localizedCaseInsensitiveCompare(topology.nodesByID[rhs]?.label ?? rhs) == .orderedAscending
                }
            for neighbor in neighbors {
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }

        if ordered.count < component.count {
            let remainder = component.filter { !visited.contains($0) }.sorted { lhs, rhs in
                (topology.nodesByID[lhs]?.label ?? lhs).localizedCaseInsensitiveCompare(topology.nodesByID[rhs]?.label ?? rhs) == .orderedAscending
            }
            ordered.append(contentsOf: remainder)
        }
        return ordered
    }

    private func componentAnchorPoints(topology: GraphTopology, size: CGSize) -> [Int: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let coordinates = hexCoordinates(count: topology.connectedComponents.count)
        let largestComponentSize = topology.connectedComponents.map(\.count).max() ?? 1
        let maxAnchorSpacing = min(size.width, size.height) * 0.28
        let anchorSpacing = min(maxAnchorSpacing, max(nodeSpacing * 3.2, sqrt(CGFloat(largestComponentSize)) * nodeSpacing * 0.78))
        var out: [Int: CGPoint] = [:]
        for index in topology.connectedComponents.indices {
            out[index] = axialToPoint(coordinates[index], center: center, spacing: anchorSpacing)
        }
        return out
    }

    private func isolatedAnchorPoints(topology: GraphTopology, size: CGSize) -> [String: CGPoint] {
        guard !topology.isolated.isEmpty else { return [:] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = max(nodeSpacing * 2.5, min(size.width, size.height) * 0.46)
        let ringGap = nodeSpacing * 0.75
        let capacity = max(12, Int((2 * CGFloat.pi * outerRadius) / (nodeSpacing * 0.85)))
        var out: [String: CGPoint] = [:]
        for (index, nodeID) in topology.isolated.enumerated() {
            let ring = index / capacity
            let slot = index % capacity
            let radius = max(nodeSpacing * 2.2, outerRadius - CGFloat(ring) * ringGap)
            let angle = (2 * CGFloat.pi * CGFloat(slot) / CGFloat(capacity)) + CGFloat(ring) * 0.31
            out[nodeID] = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        return out
    }

    private func componentNodeSpacing(for count: Int) -> CGFloat {
        if count > 800 { return nodeSpacing * 0.72 }
        if count > 350 { return nodeSpacing * 0.78 }
        if count > 120 { return nodeSpacing * 0.86 }
        return nodeSpacing
    }

    private func requiredHexRings(for count: Int) -> Int {
        guard count > 1 else { return 1 }
        var rings = 0
        while 1 + (3 * rings * (rings + 1)) < count {
            rings += 1
        }
        return rings
    }

    private func hexCoordinates(count: Int) -> [(q: Int, r: Int)] {
        guard count > 0 else { return [] }
        var coordinates: [(q: Int, r: Int)] = [(0, 0)]
        guard count > 1 else { return coordinates }

        // Axial hex ring traversal. Start at the north-east corner of each
        // ring and walk the six sides exactly once. The previous start point
        // `(radius, 0)` revisited `(0, 0)` on ring 1 and skewed subsequent
        // rings, which made nodes stack and made the lattice look clipped.
        let directions = [(0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1), (1, 0)]
        var radius = 1
        while coordinates.count < count {
            var q = radius
            var r = -radius
            for direction in directions {
                for _ in 0..<radius {
                    if coordinates.count >= count { return coordinates }
                    coordinates.append((q, r))
                    q += direction.0
                    r += direction.1
                }
            }
            radius += 1
        }
        return coordinates
    }

    private func axialToPoint(_ coordinate: (q: Int, r: Int), center: CGPoint, spacing: CGFloat? = nil) -> CGPoint {
        let q = CGFloat(coordinate.q)
        let r = CGFloat(coordinate.r)
        // `nodeSpacing` is the intended center-to-center distance between
        // neighboring nodes. Axial hex math uses a hex radius whose horizontal
        // neighbor distance is sqrt(3) * radius.
        let hexRadius = (spacing ?? nodeSpacing) / sqrt(3)
        let x = hexRadius * (sqrt(3) * q + (sqrt(3) / 2) * r)
        let y = hexRadius * (1.5 * r)
        return CGPoint(x: center.x + x, y: center.y + y)
    }

    @discardableResult
    private func selectNearestNode(to point: CGPoint, in size: CGSize) -> Bool {
        guard let best = nearestNode(to: point, in: size, maxDistance: 90), let noteID = best.node.noteID else { return false }
        appModel.focusGraphNode(best.node.id)
        appModel.select(noteID: String(noteID))
        return true
    }

    private func nearestNode(to point: CGPoint, in size: CGSize, maxDistance: CGFloat) -> (node: MWGraphNode, distance: CGFloat)? {
        let points = nodePoints(in: size)
        var best: (node: MWGraphNode, distance: CGFloat)?
        for node in appModel.graph.nodes {
            guard let nodePoint = points[node.id] else { continue }
            let distance = hypot(nodePoint.x - point.x, nodePoint.y - point.y)
            if best == nil || distance < best!.distance {
                best = (node, distance)
            }
        }
        guard let best, best.distance <= maxDistance else { return nil }
        return best
    }

    private func nodeColor(_ node: MWGraphNode, isSelected: Bool, isConnectedToSelection: Bool, hasSelection: Bool) -> Color {
        if isSelected { return Color(red: 1.0, green: 0.72, blue: 0.18) }
        if hasSelection {
            if isConnectedToSelection { return Color(red: 0.18, green: 0.88, blue: 0.95) }
            return Color(nsColor: .systemGray).opacity(0.48)
        }
        if node.unknown == true || node.label == "unknown" { return .red.opacity(0.78) }
        if node.matched == true { return Color(red: 0.82, green: 0.48, blue: 0.18) }
        if node.domains.contains(where: { $0.caseInsensitiveCompare("recipe") == .orderedSame }) { return Color(red: 0.70, green: 0.36, blue: 0.62) }
        return Color(red: 0.34, green: 0.52, blue: 0.72)
    }

    private func labelColor(isSelected: Bool, isConnectedToSelection: Bool, hasSelection: Bool) -> Color {
        if isSelected || isConnectedToSelection { return .primary }
        return hasSelection ? .secondary.opacity(0.60) : .primary.opacity(0.86)
    }

    private func setZoom(_ value: CGFloat) {
        let anchor = lastHoverPoint ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        zoomAround(anchor: anchor, to: value)
    }

    private func zoomAround(anchor: CGPoint, to value: CGFloat) {
        let oldZoom = zoom
        let newZoom = clampedZoom(value)
        guard viewportSize.width > 0, viewportSize.height > 0, currentContentSize.width > 0, currentContentSize.height > 0 else {
            zoom = newZoom
            baseZoom = newZoom
            return
        }

        let oldCentered = centeredContentOffset(viewport: viewportSize, contentSize: currentContentSize, zoom: oldZoom)
        let newCentered = centeredContentOffset(viewport: viewportSize, contentSize: currentContentSize, zoom: newZoom)
        let graphPoint = CGPoint(
            x: (anchor.x - oldCentered.width - panOffset.width) / oldZoom,
            y: (anchor.y - oldCentered.height - panOffset.height) / oldZoom
        )

        zoom = newZoom
        baseZoom = newZoom
        panOffset = CGSize(
            width: anchor.x - newCentered.width - (graphPoint.x * newZoom),
            height: anchor.y - newCentered.height - (graphPoint.y * newZoom)
        )
        dragStartOffset = panOffset
    }

    private func fitAllNodes() {
        guard viewportSize.width > 0, viewportSize.height > 0, currentContentSize.width > 0, currentContentSize.height > 0 else { return }
        let points = nodePoints(in: currentContentSize)
        guard let bounds = nodeBounds(points: points) else { return }

        let padding: CGFloat = 180
        let availableWidth = max(120, viewportSize.width - padding)
        let availableHeight = max(120, viewportSize.height - padding)
        let boundsWidth = max(1, bounds.width)
        let boundsHeight = max(1, bounds.height)
        let fittedZoom = clampedZoom(min(availableWidth / boundsWidth, availableHeight / boundsHeight))

        zoom = fittedZoom
        baseZoom = fittedZoom

        let centered = centeredContentOffset(viewport: viewportSize, contentSize: currentContentSize, zoom: fittedZoom)
        panOffset = CGSize(
            width: viewportSize.width / 2 - centered.width - bounds.midX * fittedZoom,
            height: viewportSize.height / 2 - centered.height - bounds.midY * fittedZoom
        )
        dragStartOffset = panOffset
    }

    private func nodeBounds(points: [String: CGPoint]) -> CGRect? {
        guard let first = points.values.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y

        for point in points.values {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(3.0, max(0.02, value))
    }

    private func updateViewportMetrics(viewport: CGSize, content: CGSize) {
        viewportSize = viewport
        currentContentSize = content
        rebuildRenderCacheIfNeeded()
        initializeGraphPositionsIfNeeded(contentSize: content)
        autoFitGraphIfNeeded()
    }

    private func autoFitGraphIfNeeded() {
        guard !appModel.graph.nodes.isEmpty else { return }
        let signature = graphAutoFitSignature()
        guard signature != lastAutoFitSignature else { return }
        fitAllNodes()
        lastAutoFitSignature = signature
        scheduleGraphLayout(autoFitAfter: true)
    }

    private func graphAutoFitSignature() -> String {
        "\(appModel.graph.nodes.count):\(appModel.graph.edges.count):\(appModel.graphResetToken)"
    }

    private func graphRenderSignature() -> String {
        "\(appModel.graph.nodes.count):\(appModel.graph.edges.count)"
    }

    private func rebuildRenderCacheIfNeeded(force: Bool = false) {
        let signature = graphRenderSignature()
        guard force || renderCache.signature != signature else { return }
        guard !appModel.graph.nodes.isEmpty else {
            renderCache = .empty
            return
        }

        let topology = graphTopology()
        let orderedNodes = topologicallyOrderedNodes(topology: topology)
        let noteIDToGraphNodeID = Dictionary(uniqueKeysWithValues: appModel.graph.nodes.compactMap { node in
            node.noteID.map { (String($0), node.id) }
        })
        renderCache = GraphRenderCache(
            signature: signature,
            orderedNodes: orderedNodes,
            nodesByID: topology.nodesByID,
            adjacency: topology.adjacency,
            noteIDToGraphNodeID: noteIDToGraphNodeID
        )
        if let focused = appModel.graphFocusedNodeID, topology.nodesByID[focused] == nil {
            appModel.focusGraphNode(nil)
        }
    }

    private func graphPoint(from viewportPoint: CGPoint, centeredOffset: CGSize) -> CGPoint {
        CGPoint(
            x: (viewportPoint.x - centeredOffset.width - panOffset.width) / zoom,
            y: (viewportPoint.y - centeredOffset.height - panOffset.height) / zoom
        )
    }

    private func initializeGraphPositionsIfNeeded(contentSize: CGSize) {
        let nodes = topologicallyOrderedNodes()
        guard !nodes.isEmpty else {
            graphPositions = [:]
            cancelGraphLayout()
            return
        }

        let ids = Set(nodes.map(\.id))
        var positions = graphPositions.filter { ids.contains($0.key) }

        if positions.count != nodes.count {
            let topologyPoints = topologyNodePoints(in: contentSize)
            for node in nodes where positions[node.id] == nil {
                positions[node.id] = topologyPoints[node.id] ?? CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)
            }
            pendingFitAfterSettle = true
        }

        graphPositions = positions
        if pendingFitAfterSettle {
            pendingFitAfterSettle = false
            scheduleGraphLayout(autoFitAfter: true)
        }
    }

    private func resetGraphLayout() {
        guard currentContentSize.width > 0, currentContentSize.height > 0 else { return }
        let signature = graphAutoFitSignature()
        guard signature != lastLayoutResetSignature else { return }
        lastLayoutResetSignature = signature
        graphPositions = topologyNodePoints(in: currentContentSize)
        activeDragNodeID = nil
        lastAutoFitSignature = nil
        autoFitGraphIfNeeded()
    }

    private func scheduleGraphLayout(autoFitAfter: Bool) {
        guard currentContentSize.width > 0,
              currentContentSize.height > 0,
              !appModel.graph.nodes.isEmpty else { return }

        cancelGraphLayout()
        layoutGeneration += 1
        let generation = layoutGeneration
        let graph = appModel.graph
        let contentSize = GraphLayoutSize(currentContentSize)
        let initialPositions = graphPositions.mapValues(GraphLayoutPoint.init)
        let forceStrength = appModel.graphForceStrength
        let quickIterations = graph.nodes.count > 2_500 ? 6 : 8
        let refinedIterations = graph.nodes.count > 2_500 ? 32 : 44

        layoutTask = Task {
            do {
                let coarse = try await Self.layoutEngine.solve(
                    graph: graph,
                    initialPositions: initialPositions,
                    contentSize: contentSize,
                    forceStrength: forceStrength,
                    iterations: quickIterations
                )
                guard !Task.isCancelled, generation == layoutGeneration else { return }
                withAnimation(.easeOut(duration: 0.20)) {
                    graphPositions = coarse.mapValues(\.cgPoint)
                }

                if autoFitAfter {
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled, generation == layoutGeneration else { return }
                    fitAllNodes()
                }

                let refined = try await Self.layoutEngine.solve(
                    graph: graph,
                    initialPositions: coarse,
                    contentSize: contentSize,
                    forceStrength: forceStrength,
                    iterations: refinedIterations
                )
                guard !Task.isCancelled, generation == layoutGeneration else { return }
                withAnimation(.easeOut(duration: 0.46)) {
                    graphPositions = refined.mapValues(\.cgPoint)
                }

                if autoFitAfter {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(480))
                        guard !Task.isCancelled, generation == layoutGeneration else { return }
                        fitAllNodes()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func cancelGraphLayout() {
        layoutTask?.cancel()
        layoutTask = nil
    }

    private func spatialKey(_ point: CGPoint, cellSize: CGFloat) -> String {
        "\(Int(floor(point.x / cellSize))),\(Int(floor(point.y / cellSize)))"
    }

    private func applyRepulsion(from id: String, at point: CGPoint, to otherID: String, at other: CGPoint, topology: GraphTopology, forces: inout [String: CGSize]) {
        var dx = point.x - other.x
        var dy = point.y - other.y
        var distanceSquared = dx * dx + dy * dy
        if distanceSquared < 0.01 {
            dx = CGFloat.random(in: -1...1)
            dy = CGFloat.random(in: -1...1)
            distanceSquared = dx * dx + dy * dy
        }
        let distance = max(12, sqrt(distanceSquared))
        let mass = nodeRepulsionMass(id, topology: topology) + nodeRepulsionMass(otherID, topology: topology)
        let connected = topology.adjacency[id, default: []].contains(otherID)
        let sharedHub = topology.primaryHubByNodeID[id] != nil && topology.primaryHubByNodeID[id] == topology.primaryHubByNodeID[otherID]
        let rangeMultiplier: CGFloat = connected ? 0.82 : (sharedHub ? 1.28 : 1.0)
        let strengthMultiplier: CGFloat = connected ? 0.35 : (sharedHub ? 1.45 : 1.18)
        let range = nodeSpacing * min(4.2, (1.12 + mass * 0.18) * rangeMultiplier)
        guard distance < range else { return }
        let strength = min(12.0, ((4_800 * mass) / (distance * distance)) * strengthMultiplier)
        let fx = (dx / distance) * strength
        let fy = (dy / distance) * strength
        forces[id, default: .zero].width += fx
        forces[id, default: .zero].height += fy
        forces[otherID, default: .zero].width -= fx
        forces[otherID, default: .zero].height -= fy
    }

    private func nodeRepulsionMass(_ nodeID: String, topology: GraphTopology) -> CGFloat {
        let degreeMass = sqrt(CGFloat(max(1, topology.degree[nodeID, default: 0]))) * 0.42
        let componentSize: Int
        if let componentIndex = topology.componentIndexByNodeID[nodeID], topology.connectedComponents.indices.contains(componentIndex) {
            componentSize = topology.connectedComponents[componentIndex].count
        } else {
            componentSize = 1
        }
        let clusterMass = log2(CGFloat(max(2, componentSize))) * 0.36
        return 1.0 + min(3.5, degreeMass) + min(4.0, clusterMass)
    }

    private func applyComponentRepulsion(topology: GraphTopology, positions: [String: CGPoint], forces: inout [String: CGSize]) {
        guard topology.connectedComponents.count > 1 else { return }

        struct ComponentBody {
            let index: Int
            let nodeIDs: [String]
            let center: CGPoint
            let mass: CGFloat
            let radius: CGFloat
        }

        let bodies: [ComponentBody] = topology.connectedComponents.enumerated().compactMap { index, component in
            let points = component.compactMap { positions[$0] }
            guard !points.isEmpty else { return nil }
            let center = CGPoint(
                x: points.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(points.count),
                y: points.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(points.count)
            )
            let count = CGFloat(max(1, component.count))
            return ComponentBody(
                index: index,
                nodeIDs: component,
                center: center,
                mass: sqrt(count),
                radius: sqrt(count) * nodeSpacing * 0.48
            )
        }

        guard bodies.count > 1 else { return }

        for i in 0..<(bodies.count - 1) {
            for j in (i + 1)..<bodies.count {
                let a = bodies[i]
                let b = bodies[j]
                var dx = a.center.x - b.center.x
                var dy = a.center.y - b.center.y
                var distance = hypot(dx, dy)
                if distance < 1 {
                    let angle = CGFloat((a.index + 1) * (b.index + 3)).truncatingRemainder(dividingBy: 17) / 17 * 2 * CGFloat.pi
                    dx = cos(angle)
                    dy = sin(angle)
                    distance = 1
                }

                let desiredDistance = a.radius + b.radius + nodeSpacing * 1.8
                guard distance < desiredDistance else { continue }

                let overlap = (desiredDistance - distance) / desiredDistance
                let forceOnA = min(8.5, overlap * b.mass * 0.95)
                let forceOnB = min(8.5, overlap * a.mass * 0.95)
                let ux = dx / distance
                let uy = dy / distance

                for nodeID in a.nodeIDs {
                    forces[nodeID, default: .zero].width += ux * forceOnA
                    forces[nodeID, default: .zero].height += uy * forceOnA
                }
                for nodeID in b.nodeIDs {
                    forces[nodeID, default: .zero].width -= ux * forceOnB
                    forces[nodeID, default: .zero].height -= uy * forceOnB
                }
            }
        }
    }

    private func applyHubClusterForces(topology: GraphTopology, positions: [String: CGPoint], forces: inout [String: CGSize]) {
        let groups = topology.hubGroups.filter { hubID, members in
            members.count >= 5 && topology.degree[hubID, default: 0] >= 4 && positions[hubID] != nil
        }
        guard !groups.isEmpty else { return }

        for (hubID, members) in groups {
            guard let hubPoint = positions[hubID] else { continue }
            let count = CGFloat(members.count)
            let hubDegree = CGFloat(max(1, topology.degree[hubID, default: 1]))
            let desiredRadius = nodeSpacing * min(4.8, 1.05 + sqrt(count) * 0.12 + log2(hubDegree + 1) * 0.20)
            let annulusStrength = min(0.026, 0.010 + sqrt(count) * 0.0012)

            for memberID in members where memberID != hubID {
                guard let memberPoint = positions[memberID] else { continue }
                applyAnnularHubForce(
                    nodeID: memberID,
                    point: memberPoint,
                    hubID: hubID,
                    hub: hubPoint,
                    desiredRadius: desiredRadius,
                    strength: annulusStrength,
                    forces: &forces
                )
            }

            applyHubExternalRepulsion(
                hubID: hubID,
                members: members,
                center: hubPoint,
                desiredRadius: desiredRadius,
                topology: topology,
                positions: positions,
                forces: &forces
            )
        }
    }

    private func applyAnnularHubForce(nodeID: String, point: CGPoint, hubID: String, hub: CGPoint, desiredRadius: CGFloat, strength: CGFloat, forces: inout [String: CGSize]) {
        var dx = hub.x - point.x
        var dy = hub.y - point.y
        var distance = hypot(dx, dy)
        if distance < 1 {
            dx = CGFloat.random(in: -1...1)
            dy = CGFloat.random(in: -1...1)
            distance = max(1, hypot(dx, dy))
        }

        let delta = distance - desiredRadius
        let fx = (dx / distance) * delta * strength
        let fy = (dy / distance) * delta * strength
        forces[nodeID, default: .zero].width += fx
        forces[nodeID, default: .zero].height += fy
        forces[hubID, default: .zero].width -= fx * 0.10
        forces[hubID, default: .zero].height -= fy * 0.10
    }

    private func applyHubExternalRepulsion(hubID: String, members: [String], center: CGPoint, desiredRadius: CGFloat, topology: GraphTopology, positions: [String: CGPoint], forces: inout [String: CGSize]) {
        let memberSet = Set(members)
        let repelRadius = desiredRadius + nodeSpacing * 2.2
        let groupMass = sqrt(CGFloat(members.count))

        for (nodeID, point) in positions where !memberSet.contains(nodeID) {
            guard !topology.adjacency[hubID, default: []].contains(nodeID) else { continue }
            var dx = point.x - center.x
            var dy = point.y - center.y
            var distance = hypot(dx, dy)
            guard distance < repelRadius else { continue }
            if distance < 1 {
                dx = CGFloat.random(in: -1...1)
                dy = CGFloat.random(in: -1...1)
                distance = max(1, hypot(dx, dy))
            }

            let overlap = (repelRadius - distance) / repelRadius
            let force = min(7.0, overlap * groupMass * 0.72)
            let ux = dx / distance
            let uy = dy / distance
            forces[nodeID, default: .zero].width += ux * force
            forces[nodeID, default: .zero].height += uy * force

            let counterForce = force / CGFloat(max(1, members.count)) * 0.20
            for memberID in members {
                forces[memberID, default: .zero].width -= ux * counterForce
                forces[memberID, default: .zero].height -= uy * counterForce
            }
        }
    }

    private func applySpring(sourceID: String, source: CGPoint, targetID: String, target: CGPoint, topology: GraphTopology, forces: inout [String: CGSize]) {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distance = max(1, hypot(dx, dy))
        let desired = desiredSpringLength(sourceID: sourceID, targetID: targetID, topology: topology)
        let maxDegree = CGFloat(max(topology.degree[sourceID, default: 1], topology.degree[targetID, default: 1]))
        let stiffness = max(0.014, 0.028 - min(0.012, log2(maxDegree + 1) * 0.0018))
        let strength = (distance - desired) * stiffness
        let fx = (dx / distance) * strength
        let fy = (dy / distance) * strength
        forces[sourceID, default: .zero].width += fx
        forces[sourceID, default: .zero].height += fy
        forces[targetID, default: .zero].width -= fx
        forces[targetID, default: .zero].height -= fy
    }

    private func desiredSpringLength(sourceID: String, targetID: String, topology: GraphTopology) -> CGFloat {
        let sourceDegree = CGFloat(max(1, topology.degree[sourceID, default: 1]))
        let targetDegree = CGFloat(max(1, topology.degree[targetID, default: 1]))
        let hubDegree = max(sourceDegree, targetDegree)
        let hubFactor = min(1.35, log2(hubDegree + 1) * 0.18)
        let sameHub = topology.primaryHubByNodeID[sourceID] != nil && topology.primaryHubByNodeID[sourceID] == topology.primaryHubByNodeID[targetID]
        let sameHubFactor: CGFloat = sameHub ? 0.18 : 0
        return nodeSpacing * (0.82 + hubFactor + sameHubFactor)
    }

    private func applyTargetForce(nodeID: String, point: CGPoint, target: CGPoint, strength: CGFloat, forces: inout [String: CGSize]) {
        forces[nodeID, default: .zero].width += (target.x - point.x) * strength
        forces[nodeID, default: .zero].height += (target.y - point.y) * strength
    }

    private func peripheralPoint(for nodeID: String, topology: GraphTopology, size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let sortedIDs = topology.isolated.isEmpty ? [nodeID] : topology.isolated
        let index = sortedIDs.firstIndex(of: nodeID) ?? 0
        let radius = max(nodeSpacing * 2.5, min(size.width, size.height) * 0.46)
        let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(max(1, sortedIDs.count))
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func clampedVelocity(_ velocity: CGSize, max: CGFloat) -> CGSize {
        let magnitude = hypot(velocity.width, velocity.height)
        guard magnitude > max, magnitude > 0 else { return velocity }
        return CGSize(width: velocity.width / magnitude * max, height: velocity.height / magnitude * max)
    }

    private func installGraphEventMonitors() {
        guard scrollMonitor == nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.modifierFlags.contains(.command), let anchor = lastHoverPoint {
                let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.deltaY
                zoomAround(anchor: anchor, to: zoom + (delta * 0.01))
                return nil
            }
            return event
        }
    }

    private func removeGraphEventMonitors() {
        cancelGraphLayout()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        isPanningGraph = false
    }
}
