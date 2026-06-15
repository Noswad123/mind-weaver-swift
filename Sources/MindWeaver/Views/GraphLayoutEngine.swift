import CoreGraphics
import Foundation

struct GraphLayoutPoint: Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct GraphLayoutSize: Sendable {
    var width: Double
    var height: Double

    init(_ size: CGSize) {
        self.width = Double(size.width)
        self.height = Double(size.height)
    }
}

actor GraphLayoutEngine {
    private let nodeSpacing: Double = 170

    func solve(
        graph: MWGraph,
        initialPositions: [String: GraphLayoutPoint],
        contentSize: GraphLayoutSize,
        forceStrength: Double,
        iterations requestedIterations: Int? = nil
    ) async throws -> [String: GraphLayoutPoint] {
        let topology = LayoutTopology(graph: graph)
        let nodes = graph.nodes
        guard !nodes.isEmpty else { return [:] }

        let center = GraphLayoutPoint(x: contentSize.width / 2, y: contentSize.height / 2)
        var positions = initialPositions
        for node in nodes where positions[node.id] == nil {
            positions[node.id] = center
        }

        var velocities = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, LayoutVector.zero) })
        let componentAnchors = componentAnchorPoints(topology: topology, size: contentSize)
        let isolatedAnchors = isolatedAnchorPoints(topology: topology, size: contentSize)
        let ids = Set(nodes.map(\.id))
        let cellSize = nodeSpacing * 2.4
        let iterations = requestedIterations ?? (graph.nodes.count > 2_500 ? 42 : 58)

        for iteration in 0..<iterations {
            if Task.isCancelled { throw CancellationError() }
            let energy = max(0.12, pow(0.982, Double(iteration)))
            var forces = Dictionary(uniqueKeysWithValues: ids.map { ($0, LayoutVector.zero) })
            var cells: [String: [String]] = [:]

            for node in nodes {
                guard let point = positions[node.id] else { continue }
                cells[spatialKey(point, cellSize: cellSize), default: []].append(node.id)
            }

            let neighborOffsets = [-1, 0, 1]
            for node in nodes {
                guard let point = positions[node.id] else { continue }
                let cx = Int(floor(point.x / cellSize))
                let cy = Int(floor(point.y / cellSize))
                for dx in neighborOffsets {
                    for dy in neighborOffsets {
                        for otherID in cells["\(cx + dx),\(cy + dy)", default: []] where otherID > node.id {
                            guard let other = positions[otherID] else { continue }
                            applyRepulsion(from: node.id, at: point, to: otherID, at: other, topology: topology, forces: &forces)
                        }
                    }
                }
            }

            applyComponentRepulsion(topology: topology, positions: positions, forces: &forces)

            for edge in graph.edges {
                guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
                applySpring(sourceID: edge.source, source: source, targetID: edge.target, target: target, topology: topology, forces: &forces)
            }

            applyParentOrbitForces(topology: topology, positions: positions, forces: &forces)
            applyHubClusterForces(topology: topology, positions: positions, forces: &forces)

            for node in nodes {
                guard let point = positions[node.id] else { continue }
                if topology.degree[node.id, default: 0] == 0 {
                    let target = isolatedAnchors[node.id] ?? peripheralPoint(for: node.id, topology: topology, size: contentSize)
                    applyTargetForce(nodeID: node.id, point: point, target: target, strength: 0.00058, forces: &forces)
                } else if let componentIndex = topology.componentIndexByNodeID[node.id] {
                    let target = componentAnchors[componentIndex] ?? center
                    let componentSize = topology.connectedComponents.indices.contains(componentIndex) ? topology.connectedComponents[componentIndex].count : 1
                    let strength = componentGravityStrength(componentIndex: componentIndex, componentSize: componentSize)
                    applyTargetForce(nodeID: node.id, point: point, target: target, strength: strength, forces: &forces)
                } else {
                    applyTargetForce(nodeID: node.id, point: point, target: center, strength: 0.00014, forces: &forces)
                }
            }

            let damping = 0.84
            let maxVelocity = 34.0
            for node in nodes {
                guard var point = positions[node.id] else { continue }
                var velocity = velocities[node.id] ?? .zero
                let force = forces[node.id] ?? .zero
                velocity.dx = (velocity.dx + force.dx * forceStrength * energy) * damping
                velocity.dy = (velocity.dy + force.dy * forceStrength * energy) * damping
                velocity = clampedVelocity(velocity, max: maxVelocity)
                point.x += velocity.dx
                point.y += velocity.dy
                positions[node.id] = point
                velocities[node.id] = velocity
            }
        }

        return positions
    }

    private func spatialKey(_ point: GraphLayoutPoint, cellSize: Double) -> String {
        "\(Int(floor(point.x / cellSize))),\(Int(floor(point.y / cellSize)))"
    }

    private func componentGravityStrength(componentIndex: Int, componentSize: Int) -> Double {
        let size = Double(max(1, componentSize))
        if size > 500 {
            return 0.000018
        }
        if size > 150 {
            return 0.000035
        }
        let base = componentIndex == 0 ? 0.000075 : 0.00014
        return base / max(1.0, sqrt(size) * 0.12)
    }

    private func componentAnchorPoints(topology: LayoutTopology, size: GraphLayoutSize) -> [Int: GraphLayoutPoint] {
        let center = GraphLayoutPoint(x: size.width / 2, y: size.height / 2)
        let coordinates = hexCoordinates(count: topology.connectedComponents.count)
        let largestComponentSize = topology.connectedComponents.map(\.count).max() ?? 1
        let maxAnchorSpacing = min(size.width, size.height) * 0.28
        let anchorSpacing = min(maxAnchorSpacing, max(nodeSpacing * 3.2, sqrt(Double(largestComponentSize)) * nodeSpacing * 0.78))
        var out: [Int: GraphLayoutPoint] = [:]
        for index in topology.connectedComponents.indices {
            out[index] = axialToPoint(coordinates[index], center: center, spacing: anchorSpacing)
        }
        return out
    }

    private func isolatedAnchorPoints(topology: LayoutTopology, size: GraphLayoutSize) -> [String: GraphLayoutPoint] {
        guard !topology.isolated.isEmpty else { return [:] }
        let center = GraphLayoutPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = max(nodeSpacing * 2.5, min(size.width, size.height) * 0.46)
        let ringGap = nodeSpacing * 0.75
        let capacity = max(12, Int((2 * Double.pi * outerRadius) / (nodeSpacing * 0.85)))
        var out: [String: GraphLayoutPoint] = [:]
        for (index, nodeID) in topology.isolated.enumerated() {
            let ring = index / capacity
            let slot = index % capacity
            let radius = max(nodeSpacing * 2.2, outerRadius - Double(ring) * ringGap)
            let angle = (2 * Double.pi * Double(slot) / Double(capacity)) + Double(ring) * 0.31
            out[nodeID] = GraphLayoutPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        return out
    }

    private func hexCoordinates(count: Int) -> [(q: Int, r: Int)] {
        guard count > 0 else { return [] }
        var coordinates: [(q: Int, r: Int)] = [(0, 0)]
        guard count > 1 else { return coordinates }
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

    private func axialToPoint(_ coordinate: (q: Int, r: Int), center: GraphLayoutPoint, spacing: Double) -> GraphLayoutPoint {
        let q = Double(coordinate.q)
        let r = Double(coordinate.r)
        let hexRadius = spacing / sqrt(3)
        let x = hexRadius * (sqrt(3) * q + (sqrt(3) / 2) * r)
        let y = hexRadius * (1.5 * r)
        return GraphLayoutPoint(x: center.x + x, y: center.y + y)
    }

    private func applyRepulsion(from id: String, at point: GraphLayoutPoint, to otherID: String, at other: GraphLayoutPoint, topology: LayoutTopology, forces: inout [String: LayoutVector]) {
        var dx = point.x - other.x
        var dy = point.y - other.y
        var distanceSquared = dx * dx + dy * dy
        if distanceSquared < 0.01 {
            let seed = Double(abs(id.hashValue ^ otherID.hashValue) % 360) * Double.pi / 180
            dx = cos(seed)
            dy = sin(seed)
            distanceSquared = dx * dx + dy * dy
        }
        let distance = max(12, sqrt(distanceSquared))
        let mass = nodeRepulsionMass(id, topology: topology) + nodeRepulsionMass(otherID, topology: topology)
        let connected = topology.adjacency[id, default: []].contains(otherID)
        let sharedHub = topology.primaryHubByNodeID[id] != nil && topology.primaryHubByNodeID[id] == topology.primaryHubByNodeID[otherID]
        let sharedHubSize = topology.primaryHubByNodeID[id].flatMap { topology.hubGroups[$0]?.count } ?? 1
        let sharedHubScale = sharedHub ? min(1.9, 1.20 + sqrt(Double(sharedHubSize)) * 0.045) : 1.0
        let rangeMultiplier = connected ? 0.82 : (sharedHub ? sharedHubScale : 1.04)
        let strengthMultiplier = connected ? 0.35 : (sharedHub ? min(2.1, 1.35 + sqrt(Double(sharedHubSize)) * 0.035) : 1.22)
        let range = nodeSpacing * min(5.4, (1.12 + mass * 0.18) * rangeMultiplier)
        guard distance < range else { return }
        let strength = min(12.0, ((4_800 * mass) / (distance * distance)) * strengthMultiplier)
        let fx = (dx / distance) * strength
        let fy = (dy / distance) * strength
        forces[id, default: .zero].dx += fx
        forces[id, default: .zero].dy += fy
        forces[otherID, default: .zero].dx -= fx
        forces[otherID, default: .zero].dy -= fy
    }

    private func nodeRepulsionMass(_ nodeID: String, topology: LayoutTopology) -> Double {
        let degreeMass = sqrt(Double(max(1, topology.degree[nodeID, default: 0]))) * 0.42
        let componentSize: Int
        if let componentIndex = topology.componentIndexByNodeID[nodeID], topology.connectedComponents.indices.contains(componentIndex) {
            componentSize = topology.connectedComponents[componentIndex].count
        } else {
            componentSize = 1
        }
        let clusterMass = log2(Double(max(2, componentSize))) * 0.36
        return 1.0 + min(3.5, degreeMass) + min(4.0, clusterMass)
    }

    private func applyComponentRepulsion(topology: LayoutTopology, positions: [String: GraphLayoutPoint], forces: inout [String: LayoutVector]) {
        guard topology.connectedComponents.count > 1 else { return }
        let bodies: [ComponentBody] = topology.connectedComponents.enumerated().compactMap { index, component in
            let points = component.compactMap { positions[$0] }
            guard !points.isEmpty else { return nil }
            let center = GraphLayoutPoint(
                x: points.reduce(0) { $0 + $1.x } / Double(points.count),
                y: points.reduce(0) { $0 + $1.y } / Double(points.count)
            )
            let count = Double(max(1, component.count))
            return ComponentBody(index: index, nodeIDs: component, center: center, mass: sqrt(count), radius: sqrt(count) * nodeSpacing * 0.48)
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
                    let angle = Double((a.index + 1) * (b.index + 3)).truncatingRemainder(dividingBy: 17) / 17 * 2 * Double.pi
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
                    forces[nodeID, default: .zero].dx += ux * forceOnA
                    forces[nodeID, default: .zero].dy += uy * forceOnA
                }
                for nodeID in b.nodeIDs {
                    forces[nodeID, default: .zero].dx -= ux * forceOnB
                    forces[nodeID, default: .zero].dy -= uy * forceOnB
                }
            }
        }
    }

    private func applySpring(sourceID: String, source: GraphLayoutPoint, targetID: String, target: GraphLayoutPoint, topology: LayoutTopology, forces: inout [String: LayoutVector]) {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distance = max(1, hypot(dx, dy))
        let desired = desiredSpringLength(sourceID: sourceID, targetID: targetID, topology: topology)
        let maxDegree = Double(max(topology.degree[sourceID, default: 1], topology.degree[targetID, default: 1]))
        let stiffness = max(0.014, 0.028 - min(0.012, log2(maxDegree + 1) * 0.0018))
        let strength = (distance - desired) * stiffness
        let fx = (dx / distance) * strength
        let fy = (dy / distance) * strength
        forces[sourceID, default: .zero].dx += fx
        forces[sourceID, default: .zero].dy += fy
        forces[targetID, default: .zero].dx -= fx
        forces[targetID, default: .zero].dy -= fy
    }

    private func desiredSpringLength(sourceID: String, targetID: String, topology: LayoutTopology) -> Double {
        let sourceDegree = Double(max(1, topology.degree[sourceID, default: 1]))
        let targetDegree = Double(max(1, topology.degree[targetID, default: 1]))
        let hubDegree = max(sourceDegree, targetDegree)
        let childHubDegree = min(sourceDegree, targetDegree)
        let hubFactor = min(1.55, log2(hubDegree + 1) * 0.20)
        let hubToHubFactor = childHubDegree >= 4 ? min(1.25, log2(childHubDegree + 1) * 0.26) : 0
        let sameHub = topology.primaryHubByNodeID[sourceID] != nil && topology.primaryHubByNodeID[sourceID] == topology.primaryHubByNodeID[targetID]
        let sameHubFactor = sameHub ? 0.18 : 0
        return nodeSpacing * (0.78 + hubFactor + hubToHubFactor + sameHubFactor)
    }

    private func applyParentOrbitForces(topology: LayoutTopology, positions: [String: GraphLayoutPoint], forces: inout [String: LayoutVector]) {
        for nodeID in topology.nodesByID.keys {
            guard let parentID = orbitParent(for: nodeID, topology: topology),
                  parentID != nodeID,
                  let point = positions[nodeID],
                  let parent = positions[parentID] else { continue }

            let desiredRadius = parentOrbitRadius(nodeID: nodeID, parentID: parentID, topology: topology)
            let childDegree = topology.degree[nodeID, default: 0]
            let childGroupSize = topology.hubGroups[nodeID]?.count ?? 1
            let isChildHub = childDegree >= 4 || childGroupSize >= 5
            let strength = isChildHub ? 0.006 : 0.010
            applyOrbitForce(
                nodeID: nodeID,
                point: point,
                parentID: parentID,
                parent: parent,
                desiredRadius: desiredRadius,
                strength: strength,
                parentCounterScale: isChildHub ? 0.025 : 0.055,
                forces: &forces
            )
        }
    }

    private func orbitParent(for nodeID: String, topology: LayoutTopology) -> String? {
        if let primaryHub = topology.primaryHubByNodeID[nodeID], primaryHub != nodeID {
            return primaryHub
        }

        let nodeDegree = topology.degree[nodeID, default: 0]
        return topology.adjacency[nodeID, default: []]
            .filter { topology.degree[$0, default: 0] > nodeDegree }
            .sorted { lhs, rhs in
                let lhsDegree = topology.degree[lhs, default: 0]
                let rhsDegree = topology.degree[rhs, default: 0]
                if lhsDegree != rhsDegree { return lhsDegree > rhsDegree }
                return (topology.nodesByID[lhs]?.label ?? lhs).localizedCaseInsensitiveCompare(topology.nodesByID[rhs]?.label ?? rhs) == .orderedAscending
            }
            .first
    }

    private func parentOrbitRadius(nodeID: String, parentID: String, topology: LayoutTopology) -> Double {
        let parentGroupSize = Double(max(1, topology.hubGroups[parentID]?.count ?? 1))
        let parentDegree = Double(max(1, topology.degree[parentID, default: 1]))
        let childDegree = Double(max(1, topology.degree[nodeID, default: 1]))
        let childGroupSize = Double(max(1, topology.hubGroups[nodeID]?.count ?? 1))
        let childIsHub = childDegree >= 4 || childGroupSize >= 5
        let parentScale = 0.88 + sqrt(parentGroupSize) * 0.050 + log2(parentDegree + 1) * 0.085
        let childHubScale = childIsHub ? min(1.8, sqrt(childGroupSize) * 0.11 + log2(childDegree + 1) * 0.18) : 0
        return nodeSpacing * min(5.8, parentScale + childHubScale)
    }

    private func applyOrbitForce(nodeID: String, point: GraphLayoutPoint, parentID: String, parent: GraphLayoutPoint, desiredRadius: Double, strength: Double, parentCounterScale: Double, forces: inout [String: LayoutVector]) {
        var dx = parent.x - point.x
        var dy = parent.y - point.y
        var distance = hypot(dx, dy)
        if distance < 1 {
            let seed = Double(abs(nodeID.hashValue ^ parentID.hashValue) % 360) * Double.pi / 180
            dx = cos(seed)
            dy = sin(seed)
            distance = max(1, hypot(dx, dy))
        }

        let delta = distance - desiredRadius
        let fx = (dx / distance) * delta * strength
        let fy = (dy / distance) * delta * strength
        forces[nodeID, default: .zero].dx += fx
        forces[nodeID, default: .zero].dy += fy
        forces[parentID, default: .zero].dx -= fx * parentCounterScale
        forces[parentID, default: .zero].dy -= fy * parentCounterScale
    }

    private func applyHubClusterForces(topology: LayoutTopology, positions: [String: GraphLayoutPoint], forces: inout [String: LayoutVector]) {
        let groups = topology.hubGroups
            .filter { hubID, members in members.count >= 5 && topology.degree[hubID, default: 0] >= 4 && positions[hubID] != nil }
            .sorted { $0.value.count > $1.value.count }
            .prefix(40)
        guard !groups.isEmpty else { return }

        for (hubID, members) in groups {
            guard let hubPoint = positions[hubID] else { continue }
            let count = Double(members.count)
            let hubDegree = Double(max(1, topology.degree[hubID, default: 1]))
            let desiredRadius = nodeSpacing * min(5.8, 1.00 + sqrt(count) * 0.14 + log2(hubDegree + 1) * 0.18)
            let annulusStrength = min(0.020, 0.007 + sqrt(count) * 0.0010)

            for memberID in members where memberID != hubID {
                guard let memberPoint = positions[memberID] else { continue }
                applyAnnularHubForce(nodeID: memberID, point: memberPoint, hubID: hubID, hub: hubPoint, desiredRadius: desiredRadius, strength: annulusStrength, forces: &forces)
            }

            applyHubExternalRepulsion(hubID: hubID, members: members, center: hubPoint, desiredRadius: desiredRadius, topology: topology, positions: positions, forces: &forces)
        }

        applyHubBodyRepulsion(groups: Array(groups), positions: positions, forces: &forces)
    }

    private func applyHubBodyRepulsion(groups: [(key: String, value: [String])], positions: [String: GraphLayoutPoint], forces: inout [String: LayoutVector]) {
        let bodies: [ComponentBody] = groups.enumerated().compactMap { index, pair in
            let memberPoints = pair.value.compactMap { positions[$0] }
            guard !memberPoints.isEmpty else { return nil }
            let center = GraphLayoutPoint(
                x: memberPoints.reduce(0) { $0 + $1.x } / Double(memberPoints.count),
                y: memberPoints.reduce(0) { $0 + $1.y } / Double(memberPoints.count)
            )
            let radius = nodeSpacing * min(6.5, 1.25 + sqrt(Double(pair.value.count)) * 0.34)
            return ComponentBody(index: index, nodeIDs: pair.value, center: center, mass: sqrt(Double(pair.value.count)), radius: radius)
        }
        guard bodies.count > 1 else { return }

        for i in bodies.indices {
            for j in bodies.index(after: i)..<bodies.count {
                let a = bodies[i]
                let b = bodies[j]
                var dx = a.center.x - b.center.x
                var dy = a.center.y - b.center.y
                var distance = hypot(dx, dy)
                if distance < 1 {
                    let angle = Double((a.index + 5) * (b.index + 11)).truncatingRemainder(dividingBy: 23) / 23 * 2 * Double.pi
                    dx = cos(angle)
                    dy = sin(angle)
                    distance = 1
                }
                let desiredDistance = a.radius + b.radius + nodeSpacing * 1.1
                guard distance < desiredDistance else { continue }
                let overlap = (desiredDistance - distance) / desiredDistance
                let ux = dx / distance
                let uy = dy / distance
                let forceOnA = min(5.5, overlap * b.mass * 0.42)
                let forceOnB = min(5.5, overlap * a.mass * 0.42)
                for nodeID in a.nodeIDs {
                    forces[nodeID, default: .zero].dx += ux * forceOnA
                    forces[nodeID, default: .zero].dy += uy * forceOnA
                }
                for nodeID in b.nodeIDs {
                    forces[nodeID, default: .zero].dx -= ux * forceOnB
                    forces[nodeID, default: .zero].dy -= uy * forceOnB
                }
            }
        }
    }

    private func applyAnnularHubForce(nodeID: String, point: GraphLayoutPoint, hubID: String, hub: GraphLayoutPoint, desiredRadius: Double, strength: Double, forces: inout [String: LayoutVector]) {
        var dx = hub.x - point.x
        var dy = hub.y - point.y
        var distance = hypot(dx, dy)
        if distance < 1 {
            let seed = Double(abs(nodeID.hashValue ^ hubID.hashValue) % 360) * Double.pi / 180
            dx = cos(seed)
            dy = sin(seed)
            distance = max(1, hypot(dx, dy))
        }
        let delta = distance - desiredRadius
        let fx = (dx / distance) * delta * strength
        let fy = (dy / distance) * delta * strength
        forces[nodeID, default: .zero].dx += fx
        forces[nodeID, default: .zero].dy += fy
        forces[hubID, default: .zero].dx -= fx * 0.10
        forces[hubID, default: .zero].dy -= fy * 0.10
    }

    private func applyHubExternalRepulsion(hubID: String, members: [String], center: GraphLayoutPoint, desiredRadius: Double, topology: LayoutTopology, positions: [String: GraphLayoutPoint], forces: inout [String: LayoutVector]) {
        let memberSet = Set(members)
        let groupMass = sqrt(Double(members.count))
        let repelRadius = desiredRadius + nodeSpacing * min(3.4, 1.6 + groupMass * 0.16)
        for (nodeID, point) in positions where !memberSet.contains(nodeID) {
            guard !topology.adjacency[hubID, default: []].contains(nodeID) else { continue }
            var dx = point.x - center.x
            var dy = point.y - center.y
            var distance = hypot(dx, dy)
            guard distance < repelRadius else { continue }
            if distance < 1 {
                let seed = Double(abs(nodeID.hashValue ^ hubID.hashValue) % 360) * Double.pi / 180
                dx = cos(seed)
                dy = sin(seed)
                distance = max(1, hypot(dx, dy))
            }
            let overlap = (repelRadius - distance) / repelRadius
            let force = min(7.0, overlap * groupMass * 0.68)
            let ux = dx / distance
            let uy = dy / distance
            forces[nodeID, default: .zero].dx += ux * force
            forces[nodeID, default: .zero].dy += uy * force
            let counterForce = force / Double(max(1, members.count)) * 0.20
            for memberID in members {
                forces[memberID, default: .zero].dx -= ux * counterForce
                forces[memberID, default: .zero].dy -= uy * counterForce
            }
        }
    }

    private func applyTargetForce(nodeID: String, point: GraphLayoutPoint, target: GraphLayoutPoint, strength: Double, forces: inout [String: LayoutVector]) {
        forces[nodeID, default: .zero].dx += (target.x - point.x) * strength
        forces[nodeID, default: .zero].dy += (target.y - point.y) * strength
    }

    private func peripheralPoint(for nodeID: String, topology: LayoutTopology, size: GraphLayoutSize) -> GraphLayoutPoint {
        let center = GraphLayoutPoint(x: size.width / 2, y: size.height / 2)
        let sortedIDs = topology.isolated.isEmpty ? [nodeID] : topology.isolated
        let index = sortedIDs.firstIndex(of: nodeID) ?? 0
        let radius = max(nodeSpacing * 2.5, min(size.width, size.height) * 0.46)
        let angle = 2 * Double.pi * Double(index) / Double(max(1, sortedIDs.count))
        return GraphLayoutPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func clampedVelocity(_ velocity: LayoutVector, max: Double) -> LayoutVector {
        let magnitude = hypot(velocity.dx, velocity.dy)
        guard magnitude > max, magnitude > 0 else { return velocity }
        return LayoutVector(dx: velocity.dx / magnitude * max, dy: velocity.dy / magnitude * max)
    }

}

private struct LayoutVector: Sendable {
    var dx: Double
    var dy: Double

    static let zero = LayoutVector(dx: 0, dy: 0)
}

private struct ComponentBody: Sendable {
    let index: Int
    let nodeIDs: [String]
    let center: GraphLayoutPoint
    let mass: Double
    let radius: Double
}

private struct LayoutTopology: Sendable {
    let nodesByID: [String: MWGraphNode]
    let adjacency: [String: Set<String>]
    let degree: [String: Int]
    let connectedComponents: [[String]]
    let isolated: [String]
    let componentIndexByNodeID: [String: Int]
    let primaryHubByNodeID: [String: String]
    let hubGroups: [String: [String]]

    init(graph: MWGraph) {
        let nodes = graph.nodes
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let nodeIDs = Set(nodes.map(\.id))
        var adjacency = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, Set<String>()) })

        for edge in graph.edges where nodeIDs.contains(edge.source) && nodeIDs.contains(edge.target) && edge.source != edge.target {
            adjacency[edge.source, default: []].insert(edge.target)
            adjacency[edge.target, default: []].insert(edge.source)
        }

        let degree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, adjacency[$0.id, default: []].count) })
        let sortedNodes = nodes.sorted { lhs, rhs in
            if (lhs.matched ?? false) != (rhs.matched ?? false) { return lhs.matched == true }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }

        var visited = Set<String>()
        var components: [[String]] = []
        for node in sortedNodes where !visited.contains(node.id) {
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

        let connectedComponents = components.filter { component in component.contains { degree[$0, default: 0] > 0 } }
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
            for nodeID in component { componentIndexByNodeID[nodeID] = index }
        }

        var primaryHubByNodeID: [String: String] = [:]
        var hubGroups: [String: [String]] = [:]
        for node in nodes where degree[node.id, default: 0] > 0 {
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

        self.nodesByID = nodesByID
        self.adjacency = adjacency
        self.degree = degree
        self.connectedComponents = connectedComponents
        self.isolated = isolated
        self.componentIndexByNodeID = componentIndexByNodeID
        self.primaryHubByNodeID = primaryHubByNodeID
        self.hubGroups = hubGroups
    }
}
