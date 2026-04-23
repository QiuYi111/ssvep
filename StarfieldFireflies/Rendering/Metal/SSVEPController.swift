import Foundation
import simd

// MARK: - SSVEP State (per-frame output)

struct SSVEPState {
    var targetOpacity: Float
    var distractorOpacity: Float
    var advancedOpacity: Float
    var targetActive: Bool
    var distractorActive: Bool
    var advancedActive: Bool
    var frameIndex: UInt64
}

// MARK: - SSVEP Channel

struct SSVEPChannel {
    var frequency: Int
    let label: String
    let waveType: SSVEPWaveType
    var minOpacity: Float
    var maxOpacity: Float
    var enabled: Bool

    var phaseStep: Float {
        Float(2.0 * Double.pi) * Float(frequency) / Float(SSVEPController.refreshRate)
    }
}

enum SSVEPWaveType {
    case sine
    case square
}

// MARK: - SSVEP Metal Buffer Layout (matches Shared.metal SSVEPParams)

struct SSVEPParamsMetal {
    var targetOpacity: Float
    var distractorOpacity: Float
    var advancedOpacity: Float
    var attentionLevel: Float
    var deltaTime: Float
    var guidingPulse: Float
    var riftMode: Float
    var _alignPad: Float = 0
    var frameIndex: UInt64
    var padding: Float
}

// MARK: - Attention State Metal Layout (matches Shared.metal AttentionState)

struct AttentionStateMetal {
    var level: Float
    var targetPositionX: Float
    var targetPositionY: Float
    var transitionSpeed: Float
}

// MARK: - SSVEPController

final class SSVEPController {

    static let refreshRate: Int = 120

    private(set) var targetChannel: SSVEPChannel
    private(set) var distractorChannel: SSVEPChannel
    private(set) var advancedChannel: SSVEPChannel

    private var frameCount: UInt64 = 0
    private var targetPhase: Float = 0.0
    private var distractorPhase: Float = 0.0
    private var advancedPhase: Float = 0.0

    private let sinLUT: [Float]
    private static let lutResolution: Int = 4096

    var simulatedAttention: Float = 0.7
    var guidingPulseActive: Bool = false

    init() {
        targetChannel = SSVEPChannel(
            frequency: 15, label: "target", waveType: .sine,
            minOpacity: 0.6, maxOpacity: 1.0, enabled: true
        )
        distractorChannel = SSVEPChannel(
            frequency: 20, label: "distractor", waveType: .sine,
            minOpacity: 0.6, maxOpacity: 1.0, enabled: false
        )
        advancedChannel = SSVEPChannel(
            frequency: 40, label: "advanced", waveType: .sine,
            minOpacity: 0.6, maxOpacity: 1.0, enabled: false
        )

        let res = Self.lutResolution
        sinLUT = (0..<res).map { i in
            sin(2.0 * Float.pi * Float(i) / Float(res))
        }
    }

    // MARK: - Per-frame update (MUST be called before rendering)

    func onFrame() {
        frameCount &+= 1
        targetPhase += targetChannel.phaseStep
        distractorPhase += distractorChannel.phaseStep
        advancedPhase += advancedChannel.phaseStep

        if frameCount % 120 == 0 {
            let twoPi = Float(2.0 * Double.pi)
            targetPhase = targetPhase.truncatingRemainder(dividingBy: twoPi)
            distractorPhase = distractorPhase.truncatingRemainder(dividingBy: twoPi)
            advancedPhase = advancedPhase.truncatingRemainder(dividingBy: twoPi)
        }
    }

    // MARK: - Current state for rendering

    var currentState: SSVEPState {
        SSVEPState(
            targetOpacity: targetChannel.enabled
                ? opacityForChannel(targetChannel, phase: targetPhase) : 1.0,
            distractorOpacity: distractorChannel.enabled
                ? opacityForChannel(distractorChannel, phase: distractorPhase) : 1.0,
            advancedOpacity: advancedChannel.enabled
                ? opacityForChannel(advancedChannel, phase: advancedPhase) : 1.0,
            targetActive: squareWaveActive(targetChannel, phase: targetPhase),
            distractorActive: squareWaveActive(distractorChannel, phase: distractorPhase),
            advancedActive: squareWaveActive(advancedChannel, phase: advancedPhase),
            frameIndex: frameCount
        )
    }

    // MARK: - Per-frequency intensity for attention-driven overlay

    func stimulusIntensity(forFrequency frequency: Float, attentionValue: Float, elapsedTime: Float) -> Float {
        let phase = frequency * elapsedTime * 2.0 * Float.pi
        let sinVal = fastSin(phase)
        let mid: Float = 0.8
        let amplitude: Float = 0.2
        let baseOpacity = mid + amplitude * sinVal
        let attentionModulation = 0.6 + (1.0 - 0.6) * attentionValue
        return baseOpacity * attentionModulation
    }

    // MARK: - Dynamic difficulty

    func updateDifficulty(targetRange: (min: Float, max: Float), distractorBrightness: Float) {
        targetChannel.minOpacity = targetRange.min
        targetChannel.maxOpacity = targetRange.max

        if distractorChannel.enabled {
            distractorChannel.minOpacity = targetRange.min * distractorBrightness
            distractorChannel.maxOpacity = targetRange.max * distractorBrightness
        }
    }

    // MARK: - Level configuration

    func configureForLevel(_ level: Int) {
        reset()
        targetChannel.enabled = true

        switch level {
        case 1:
            targetChannel.frequency = 15
            distractorChannel.enabled = false
            advancedChannel.enabled = false
        case 2:
            targetChannel.frequency = 15
            distractorChannel.enabled = false
            advancedChannel.enabled = false
        case 3:
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.enabled = false
        case 4:
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.enabled = false
        case 5:
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.enabled = false
        case 6:
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.frequency = 40
            advancedChannel.enabled = true
        default:
            break
        }
    }

    // MARK: - RIFT Mode (Rapid Invisible Frequency Tagging)

    private var riftModeEnabled: Bool = false

    var riftModeActive: Bool { riftModeEnabled }

    func enableRIFTMode(_ enabled: Bool) {
        riftModeEnabled = enabled
        if enabled {
            targetChannel.frequency = 40
            targetChannel.minOpacity = 0.95
            targetChannel.maxOpacity = 1.0
            if distractorChannel.enabled {
                distractorChannel.frequency = 56
                distractorChannel.minOpacity = 0.96
                distractorChannel.maxOpacity = 1.0
            }
        } else {
            targetChannel.minOpacity = 0.6
            targetChannel.maxOpacity = 1.0
            if distractorChannel.enabled {
                distractorChannel.minOpacity = 0.6
                distractorChannel.maxOpacity = 1.0
            }
        }
    }

    func reset() {
        frameCount = 0
        targetPhase = 0.0
        distractorPhase = 0.0
        advancedPhase = 0.0
    }

    // MARK: - Internal

    private func opacityForChannel(_ channel: SSVEPChannel, phase: Float) -> Float {
        let range = channel.maxOpacity - channel.minOpacity
        let mid = (channel.maxOpacity + channel.minOpacity) / 2.0
        let sinValue = fastSin(phase)
        return mid + (range / 2.0) * sinValue
    }

    private func squareWaveActive(_ channel: SSVEPChannel, phase: Float) -> Bool {
        guard channel.enabled else { return false }
        let twoPi = Float(2.0 * Double.pi)
        let normalizedPhase = phase.truncatingRemainder(dividingBy: twoPi)
        let positive = normalizedPhase < 0 ? normalizedPhase + twoPi : normalizedPhase
        return positive < Float.pi
    }

    private func fastSin(_ x: Float) -> Float {
        let twoPi = Float(2.0 * Double.pi)
        let normalizedX = x.truncatingRemainder(dividingBy: twoPi)
        let positiveX = normalizedX < 0 ? normalizedX + twoPi : normalizedX
        let index = Int((positiveX / twoPi) * Float(Self.lutResolution)) % Self.lutResolution
        return sinLUT[index]
    }
}
