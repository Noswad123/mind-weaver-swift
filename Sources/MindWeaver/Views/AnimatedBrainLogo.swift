import SwiftUI

struct AnimatedBrainLogo: View {
    var isAnimating: Bool
    var size: CGFloat = 88

    @State private var memoryFlameColors: [Color] = AnimatedBrainLogo.restingColors

    private static let restingColors: [Color] = [
        Color(red: 0.36, green: 0.60, blue: 0.95),
        Color(red: 0.52, green: 0.72, blue: 1.00),
        Color(red: 0.44, green: 0.82, blue: 0.78),
        Color(red: 0.72, green: 0.56, blue: 0.96),
        Color(red: 0.95, green: 0.62, blue: 0.38),
        Color(red: 0.86, green: 0.46, blue: 0.78),
        Color(red: 1.00, green: 0.88, blue: 0.38),
    ]

    private let memoryKnots: [CGPoint] = [
        CGPoint(x: 0.28, y: 0.30),
        CGPoint(x: 0.50, y: 0.23),
        CGPoint(x: 0.72, y: 0.30),
        CGPoint(x: 0.34, y: 0.52),
        CGPoint(x: 0.58, y: 0.48),
        CGPoint(x: 0.76, y: 0.62),
        CGPoint(x: 0.44, y: 0.75),
    ]

    private let connections: [(Int, Int)] = [
        (0, 1), (1, 2), (0, 3), (1, 4), (2, 5), (3, 4), (4, 5), (3, 6), (5, 6),
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height)
            let origin = CGPoint(x: (canvasSize.width - scale) / 2, y: (canvasSize.height - scale) / 2)
            let frameWidth = max(1.2, scale * 0.035)
            let threadWidth = max(0.8, scale * 0.016)
            let glow = activeGlowColor.opacity(isAnimating ? 0.48 : 0.24)
            let frameColor = Color(red: 0.95, green: 0.76, blue: 0.34).opacity(isAnimating ? 0.88 : 0.66)
            let threadColor = Color(red: 0.55, green: 0.86, blue: 1.0).opacity(isAnimating ? 0.62 : 0.38)
            let points = memoryKnots.map { point in
                CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
            }

            let aura = Path(ellipseIn: CGRect(x: origin.x + scale * 0.10, y: origin.y + scale * 0.08, width: scale * 0.80, height: scale * 0.84))
            context.stroke(aura, with: .color(glow), lineWidth: max(1, scale * 0.018))

            var loom = Path()
            loom.move(to: CGPoint(x: origin.x + scale * 0.20, y: origin.y + scale * 0.20))
            loom.addQuadCurve(to: CGPoint(x: origin.x + scale * 0.80, y: origin.y + scale * 0.20), control: CGPoint(x: origin.x + scale * 0.50, y: origin.y + scale * 0.07))
            loom.move(to: CGPoint(x: origin.x + scale * 0.20, y: origin.y + scale * 0.20))
            loom.addLine(to: CGPoint(x: origin.x + scale * 0.20, y: origin.y + scale * 0.80))
            loom.move(to: CGPoint(x: origin.x + scale * 0.80, y: origin.y + scale * 0.20))
            loom.addLine(to: CGPoint(x: origin.x + scale * 0.80, y: origin.y + scale * 0.80))
            loom.move(to: CGPoint(x: origin.x + scale * 0.24, y: origin.y + scale * 0.82))
            loom.addQuadCurve(to: CGPoint(x: origin.x + scale * 0.76, y: origin.y + scale * 0.82), control: CGPoint(x: origin.x + scale * 0.50, y: origin.y + scale * 0.92))
            context.stroke(loom, with: .color(frameColor), lineWidth: frameWidth)

            for x in stride(from: 0.30, through: 0.70, by: 0.10) {
                var thread = Path()
                thread.move(to: CGPoint(x: origin.x + scale * x, y: origin.y + scale * 0.21))
                thread.addQuadCurve(
                    to: CGPoint(x: origin.x + scale * (0.82 - x * 0.45), y: origin.y + scale * 0.80),
                    control: CGPoint(x: origin.x + scale * (x + 0.06 * sin(x * 20)), y: origin.y + scale * 0.52)
                )
                context.stroke(thread, with: .color(threadColor), lineWidth: threadWidth)
            }

            var weave = Path()
            for connection in connections where connection.0 < points.count && connection.1 < points.count {
                let source = points[connection.0]
                let target = points[connection.1]
                let midpoint = CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
                weave.move(to: source)
                weave.addQuadCurve(to: target, control: CGPoint(x: midpoint.x, y: midpoint.y - scale * 0.045))
            }
            context.stroke(weave, with: .color(activeGlowColor.opacity(isAnimating ? 0.52 : 0.28)), lineWidth: threadWidth)

            for (index, point) in points.enumerated() {
                let color = memoryFlameColors[index % memoryFlameColors.count]
                drawMemoryFlame(at: point, color: color, scale: scale, isAnimating: isAnimating, context: &context)
            }

            var spark = Path()
            spark.move(to: CGPoint(x: origin.x + scale * 0.17, y: origin.y + scale * 0.13))
            spark.addLine(to: CGPoint(x: origin.x + scale * 0.23, y: origin.y + scale * 0.19))
            spark.move(to: CGPoint(x: origin.x + scale * 0.23, y: origin.y + scale * 0.13))
            spark.addLine(to: CGPoint(x: origin.x + scale * 0.17, y: origin.y + scale * 0.19))
            context.stroke(spark, with: .color((memoryFlameColors.last ?? .yellow).opacity(0.86)), lineWidth: max(0.8, scale * 0.018))
        }
        .frame(width: size, height: size)
        .shadow(color: activeGlowColor.opacity(isAnimating ? 0.48 : 0.18), radius: isAnimating ? 18 : 10)
        .animation(.easeInOut(duration: 0.28), value: memoryFlameColors)
        .onAppear { memoryFlameColors = isAnimating ? randomColors() : Self.restingColors }
        .onChange(of: isAnimating) { active in
            memoryFlameColors = active ? randomColors() : Self.restingColors
        }
        .onReceive(Timer.publish(every: 0.34, on: .main, in: .common).autoconnect()) { _ in
            guard isAnimating else { return }
            memoryFlameColors = randomColors()
        }
        .accessibilityLabel(isAnimating ? "Mind Weaver memory loom working" : "Mind Weaver memory loom logo")
    }

    private var activeGlowColor: Color {
        memoryFlameColors.first ?? Color.accentColor
    }

    private func drawMemoryFlame(at point: CGPoint, color: Color, scale: CGFloat, isAnimating: Bool, context: inout GraphicsContext) {
        let radius = scale * (isAnimating ? 0.045 : 0.036)
        let glowRect = CGRect(x: point.x - radius * 1.8, y: point.y - radius * 1.8, width: radius * 3.6, height: radius * 3.6)
        context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(isAnimating ? 0.20 : 0.10)))

        var flame = Path()
        flame.move(to: CGPoint(x: point.x, y: point.y - radius * 1.45))
        flame.addQuadCurve(to: CGPoint(x: point.x + radius * 0.78, y: point.y + radius * 0.40), control: CGPoint(x: point.x + radius * 1.08, y: point.y - radius * 0.58))
        flame.addQuadCurve(to: CGPoint(x: point.x, y: point.y + radius * 1.12), control: CGPoint(x: point.x + radius * 0.22, y: point.y + radius * 1.04))
        flame.addQuadCurve(to: CGPoint(x: point.x - radius * 0.78, y: point.y + radius * 0.40), control: CGPoint(x: point.x - radius * 0.22, y: point.y + radius * 1.04))
        flame.addQuadCurve(to: CGPoint(x: point.x, y: point.y - radius * 1.45), control: CGPoint(x: point.x - radius * 1.08, y: point.y - radius * 0.58))
        context.fill(flame, with: .color(color.opacity(isAnimating ? 0.96 : 0.78)))

        let coreRadius = radius * 0.34
        let core = CGRect(x: point.x - coreRadius, y: point.y - coreRadius * 0.25, width: coreRadius * 2, height: coreRadius * 2)
        context.fill(Path(ellipseIn: core), with: .color(.white.opacity(isAnimating ? 0.74 : 0.46)))
    }

    private func randomColors() -> [Color] {
        memoryFlameColors.indices.map { _ in
            Color(
                hue: Double.random(in: 0...1),
                saturation: Double.random(in: 0.58...0.92),
                brightness: Double.random(in: 0.72...1.0)
            )
        }
    }
}
