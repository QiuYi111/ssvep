import SwiftUI
import Metal

extension Color {

    func toSIMD3() -> SIMD3<Float> {
        let resolved = NSApplication.shared.windows.first?.screen?
            .colorSpace ?? NSColorSpace.genericRGB
        let nsColor = NSColor(self).usingColorSpace(resolved) ?? NSColor(self)

        let r = Float(nsColor.redComponent)
        let g = Float(nsColor.greenComponent)
        let b = Float(nsColor.blueComponent)
        return SIMD3<Float>(r, g, b)
    }

    func toSIMD4(alpha: Float = 1.0) -> SIMD4<Float> {
        let rgb = toSIMD3()
        return SIMD4<Float>(rgb.x, rgb.y, rgb.z, alpha)
    }

    func toMTLClearColor(alpha: Double = 1.0) -> MTLClearColor {
        let nsColor = NSColor(self).usingColorSpace(.genericRGB) ?? NSColor(self)
        return MTLClearColor(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: alpha
        )
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    init(simd3: SIMD3<Float>) {
        self.init(
            .sRGB,
            red: Double(simd3.x),
            green: Double(simd3.y),
            blue: Double(simd3.z),
            opacity: 1.0
        )
    }
}

extension SIMD3 where Scalar == Float {
    func toColor() -> Color {
        Color(
            .sRGB,
            red: Double(x),
            green: Double(y),
            blue: Double(z),
            opacity: 1.0
        )
    }
}

extension MTLClearColor {
    static let black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let transparent = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
}
