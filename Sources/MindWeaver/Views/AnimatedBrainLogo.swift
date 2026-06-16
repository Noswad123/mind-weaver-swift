import Combine
import AppKit
import SwiftUI

struct AnimatedBrainLogo: View {
    var isAnimating: Bool
    var size: CGFloat = 88

    @State private var frameCursor = 0

    private let pulseSequence = [0, 1, 2, 3, 2, 1]

    var body: some View {
        ZStack {
            if isAnimating, let frameImage = currentBreathingFrameImage {
                breathingBrainFrame(frameImage)
            } else if let logo = logoImageResource {
                logoImage(logo)
            } else if let frameImage = currentBreathingFrameImage {
                breathingBrainFrame(frameImage)
            } else {
                fallbackGlyph
            }
        }
        .padding(max(2, size * 0.035))
        .frame(width: size, height: size)
        .background {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MWTheme.bgPanel2.opacity(0.96), MWTheme.bgVoid.opacity(0.98)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.62
                    )
                )
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [MWTheme.frostSoft, MWTheme.pinkSignal.opacity(0.80), MWTheme.emberHot, MWTheme.frostSoft],
                        center: .center
                    ),
                    lineWidth: max(1.2, size * 0.035)
                )
                .opacity(isAnimating ? 0.88 : 0.62)
        }
        .overlay {
            Circle()
                .stroke(MWTheme.bgVoid.opacity(0.88), lineWidth: max(0.8, size * 0.015))
                .padding(max(2, size * 0.045))
        }
        .shadow(color: glowColor.opacity(isAnimating ? 0.46 : 0.22), radius: isAnimating ? 18 : 10)
        .animation(.easeInOut(duration: 0.22), value: frameCursor)
        .onAppear { frameCursor = 0 }
        .onChange(of: isAnimating) { active in
            if !active { frameCursor = 0 }
        }
        .onReceive(Timer.publish(every: 0.24, on: .main, in: .common).autoconnect()) { _ in
            guard isAnimating else { return }
            frameCursor = (frameCursor + 1) % pulseSequence.count
        }
        .accessibilityLabel(isAnimating ? "Mind Weaver breathing brain working" : "Mind Weaver logo")
    }

    private func breathingBrainFrame(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }

    private func logoImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }

    private var fallbackGlyph: some View {
        Image(systemName: "brain.head.profile")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.purple, .cyan)
            .padding(size * 0.12)
    }

    private var currentBreathingFrameImage: NSImage? {
        let frame = pulseSequence[frameCursor % pulseSequence.count]
        return croppedBreathingFrame(frame)
    }

    private var logoImageResource: NSImage? {
        imageResource(named: "mind-weaver-logo")
    }

    private func imageResource(named name: String) -> NSImage? {
        guard let url = resourceBundle.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private func croppedBreathingFrame(_ frame: Int) -> NSImage? {
        guard let sheet = imageResource(named: "breath-brain"),
              let cgImage = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let frameWidth = cgImage.width / 2
        let frameHeight = cgImage.height / 2
        guard frameWidth > 0, frameHeight > 0 else { return nil }

        let column = frame % 2
        let row = frame / 2
        let cropRect = CGRect(
            x: column * frameWidth,
            y: row * frameHeight,
            width: frameWidth,
            height: frameHeight
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return NSImage(
            cgImage: cropped,
            size: CGSize(width: CGFloat(frameWidth), height: CGFloat(frameHeight))
        )
    }

    private var glowColor: Color {
        isAnimating ? Color(red: 0.72, green: 0.52, blue: 1.0) : Color(red: 0.42, green: 0.70, blue: 1.0)
    }

    private var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}
