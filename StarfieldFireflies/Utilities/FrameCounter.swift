import Foundation
import Accelerate

struct FrameCounter {

    private(set) var frameIndex: UInt64 = 0

    let targetFPS: Int = 120

    private static let lutSize = 4096
    private static let sinLUT: [Float] = {
        var table = [Float](repeating: 0, count: lutSize)
        for i in 0..<lutSize {
            table[i] = sinf(Float(i) / Float(lutSize) * 2.0 * Float.pi)
        }
        return table
    }()

    mutating func increment() {
        frameIndex &+= 1
    }

    func shouldToggleForFrequency(_ frequency: Float) -> Bool {
        let framesPerHalfCycle = Float(targetFPS) / frequency
        let halfCyclePosition = Float(frameIndex % UInt64(framesPerHalfCycle * 2.0))

        let prevPhase = halfCyclePosition - 1.0
        let currPhase = halfCyclePosition

        let prevSign = sinLookup(phase: prevPhase / framesPerHalfCycle)
        let currSign = sinLookup(phase: currPhase / framesPerHalfCycle)

        return prevSign * currSign <= 0
    }

    func stimulusIntensity(frequency: Float) -> Float {
        let framesPerCycle = Float(targetFPS) / frequency
        let phaseInCycle = Float(frameIndex % UInt64(framesPerCycle))
        let normalizedPhase = phaseInCycle / framesPerCycle

        return (sinLookup(phase: normalizedPhase) + 1.0) * 0.5
    }

    func stimulusState(frequency: Int) -> Bool {
        let framesPerFullCycle = UInt64(2 * targetFPS / frequency)
        return (frameIndex / framesPerFullCycle) % 2 == 0
    }

    mutating func reset() {
        frameIndex = 0
    }

    private func sinLookup(phase: Float) -> Float {
        let wrapped = phase - floor(phase)
        let index = Int(wrapped * Float(Self.lutSize)) & (Self.lutSize - 1)
        return Self.sinLUT[index]
    }
}
