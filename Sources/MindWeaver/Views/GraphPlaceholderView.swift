import SwiftUI

struct GraphPlaceholderView: View {
    @EnvironmentObject private var appModel: AppModel

    private var graphNotes: [MWNote] {
        Array(appModel.visibleNotes.prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            GeometryReader { geometry in
                ZStack {
                    Canvas { context, size in
                        let points = nodePoints(in: size, count: graphNotes.count)

                        guard points.count > 1 else { return }

                        var path = Path()
                        for index in 0..<(points.count - 1) {
                            path.move(to: points[index])
                            path.addLine(to: points[index + 1])
                        }

                        if points.count > 3 {
                            path.move(to: points[0])
                            path.addLine(to: points[3])
                            path.move(to: points[1])
                            path.addLine(to: points[points.count - 1])
                        }

                        context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1.5)
                    }

                    ForEach(Array(graphNotes.enumerated()), id: \.element.id) { index, note in
                        let point = nodePoints(in: geometry.size, count: graphNotes.count)[index]
                        GraphNodeView(note: note, isSelected: appModel.selectedNoteID == note.id)
                            .position(point)
                            .onTapGesture {
                                appModel.select(note)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            Divider()
            CommandOutputView()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Graph Preview")
                    .font(.title2)
                    .bold()

                Text("Placeholder node/edge rendering. Later this should be powered by `mw` graph/projection JSON instead of local placeholder layout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(graphNotes.count) nodes")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding()
    }

    private func nodePoints(in size: CGSize, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(90, min(size.width, size.height) * 0.32)

        if count == 1 {
            return [center]
        }

        return (0..<count).map { index in
            let angle = (Double(index) / Double(count)) * .pi * 2 - .pi / 2
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }
}

private struct GraphNodeView: View {
    var note: MWNote
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.blue.opacity(0.75))
                .frame(width: isSelected ? 34 : 26, height: isSelected ? 34 : 26)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 2)
                }
                .shadow(radius: isSelected ? 8 : 3)

            Text(note.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 120)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .contentShape(Rectangle())
    }
}
