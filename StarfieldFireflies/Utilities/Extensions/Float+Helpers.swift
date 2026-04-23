import Foundation

extension Float {
    static func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    func lerp(to other: Float, t: Float) -> Float {
        self + (other - self) * t
    }

    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }

    static func remap(
        value: Float,
        fromLow: Float,
        fromHigh: Float,
        toLow: Float,
        toHigh: Float
    ) -> Float {
        let t = (value - fromLow) / (fromHigh - fromLow)
        return toLow + t * (toHigh - toLow)
    }

    func remap(
        fromLow: Float,
        fromHigh: Float,
        toLow: Float,
        toHigh: Float
    ) -> Float {
        Float.remap(value: self, fromLow: fromLow, fromHigh: fromHigh, toLow: toLow, toHigh: toHigh)
    }

    var degreesToRadians: Float {
        self * Float.pi / 180.0
    }

    var radiansToDegrees: Float {
        self * 180.0 / Float.pi
    }

    static func random(in range: ClosedRange<Float>, seed: inout UInt64) -> Float {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let x = seed >> 33
        return Float(x) / Float(UInt64(1) << 31) * (range.upperBound - range.lowerBound) + range.lowerBound
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
