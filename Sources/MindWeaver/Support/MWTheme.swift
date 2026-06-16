import SwiftUI

enum MWTheme {
    static let bgVoid = Color(red: 0.020, green: 0.031, blue: 0.071)       // #050812
    static let bgPanel = Color(red: 0.043, green: 0.067, blue: 0.106)      // #0b111b
    static let bgPanel2 = Color(red: 0.063, green: 0.098, blue: 0.145)     // #101925
    static let steel = Color(red: 0.106, green: 0.149, blue: 0.200)        // #1b2633
    static let steelLight = Color(red: 0.204, green: 0.275, blue: 0.357)   // #34465b

    static let ember = Color(red: 1.000, green: 0.541, blue: 0.239)        // #ff8a3d
    static let emberHot = Color(red: 1.000, green: 0.690, blue: 0.404)     // #ffb067
    static let frost = Color(red: 0.153, green: 0.659, blue: 1.000)        // #27a8ff
    static let frostSoft = Color(red: 0.435, green: 0.780, blue: 1.000)    // #6fc7ff
    static let pinkSignal = Color(red: 1.000, green: 0.365, blue: 0.733)   // #ff5dbb
    static let greenSync = Color(red: 0.220, green: 0.902, blue: 0.643)    // #38e6a4
    static let danger = Color(red: 1.000, green: 0.302, blue: 0.369)       // #ff4d5e

    static let text = Color(red: 0.957, green: 0.969, blue: 0.984)         // #f4f7fb
    static let textMuted = Color(red: 0.604, green: 0.663, blue: 0.729)    // #9aa9ba
    static let textDim = Color(red: 0.380, green: 0.447, blue: 0.529)      // #617287

    static var appBackground: some View {
        ZStack {
            bgVoid
            RadialGradient(colors: [pinkSignal.opacity(0.11), .clear], center: UnitPoint(x: 0.18, y: 0.0), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [ember.opacity(0.14), .clear], center: UnitPoint(x: 0.88, y: 0.12), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [frost.opacity(0.12), .clear], center: UnitPoint(x: 0.70, y: 0.90), startRadius: 0, endRadius: 460)
            LinearGradient(colors: [Color.white.opacity(0.035), .clear], startPoint: .topLeading, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    static var panelFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(
            colors: [bgPanel2.opacity(0.96), bgVoid.opacity(0.98)],
            startPoint: .top,
            endPoint: .bottom
        ))
    }

    static var selectedFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(
            colors: [ember.opacity(0.32), bgVoid.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }

    static var coldFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(
            colors: [frost.opacity(0.16), bgPanel.opacity(0.96)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }
}

struct MWPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var isSelected = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? MWTheme.selectedFill : MWTheme.panelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(isSelected ? MWTheme.emberHot.opacity(0.70) : MWTheme.frostSoft.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.45), radius: 22, y: 12)
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.035), lineWidth: 1)
                    }
            }
    }
}

extension View {
    func mwPanel(cornerRadius: CGFloat = 18, isSelected: Bool = false) -> some View {
        modifier(MWPanelModifier(cornerRadius: cornerRadius, isSelected: isSelected))
    }

    func mwScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { MWTheme.appBackground }
    }
}
