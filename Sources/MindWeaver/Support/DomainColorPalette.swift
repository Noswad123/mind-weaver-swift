import SwiftUI

struct DomainRGB: Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

enum DomainColorPalette {
    static func color(for domain: String) -> Color {
        let rgb = rgb(for: domain)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func averageColor(for domains: some Collection<String>) -> Color? {
        let sortedDomains = domains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        guard !sortedDomains.isEmpty else { return nil }

        let total = sortedDomains.reduce(DomainRGB(red: 0, green: 0, blue: 0)) { partial, domain in
            let rgb = rgb(for: domain)
            return DomainRGB(red: partial.red + rgb.red, green: partial.green + rgb.green, blue: partial.blue + rgb.blue)
        }
        let count = Double(sortedDomains.count)
        return Color(red: total.red / count, green: total.green / count, blue: total.blue / count)
    }

    static func rgb(for domain: String) -> DomainRGB {
        let hash = stableHash(domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let hue = Double(hash % 360) / 360.0
        let saturation = 0.58 + Double((hash >> 9) % 28) / 100.0
        let brightness = 0.72 + Double((hash >> 17) % 22) / 100.0
        return hsbToRGB(hue: hue, saturation: saturation, brightness: min(0.92, brightness))
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func hsbToRGB(hue: Double, saturation: Double, brightness: Double) -> DomainRGB {
        let scaledHue = (hue.truncatingRemainder(dividingBy: 1.0)) * 6.0
        let sector = Int(floor(scaledHue))
        let fraction = scaledHue - Double(sector)
        let p = brightness * (1.0 - saturation)
        let q = brightness * (1.0 - saturation * fraction)
        let t = brightness * (1.0 - saturation * (1.0 - fraction))

        switch sector % 6 {
        case 0: return DomainRGB(red: brightness, green: t, blue: p)
        case 1: return DomainRGB(red: q, green: brightness, blue: p)
        case 2: return DomainRGB(red: p, green: brightness, blue: t)
        case 3: return DomainRGB(red: p, green: q, blue: brightness)
        case 4: return DomainRGB(red: t, green: p, blue: brightness)
        default: return DomainRGB(red: brightness, green: p, blue: q)
        }
    }
}
