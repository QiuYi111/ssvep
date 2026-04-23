import Foundation
import Combine

// MARK: - FeedbackState
/// The 9-parameter output struct consumed by MetalRenderer, AudioEngine, and HapticEngine.
/// Produced by AttentionManager from a raw attention Double.
struct FeedbackState: Equatable {
    /// 0.0–1.0: scene overall brightness/saturation
    let brightness: Float
    /// 0.0–1.0: firefly particle speed multiplier
    let particleSpeed: Float
    /// 0.0–2.0: bloom / glow post-processing strength
    let glowIntensity: Float
    /// 0.0–1.0: colour temperature shift (0 = warm, 1 = cool)
    let colorTemperature: Float
    /// 0.0–1.0: vignette overlay strength
    let vignetteStrength: Float
    /// Hz: dynamic low-pass filter cutoff (200–18 000)
    let audioLowPassCutoff: Float
    /// 0.0–1.0: binaural beat gain
    let binauralBeatGain: Float
    /// 0.0–1.0: ambient soundscape volume
    let ambientVolume: Float
    /// Type of feedback event that should be triggered
    let feedbackTrigger: FeedbackTriggerType

    static let neutral: FeedbackState = .init(
        brightness: 0.3,
        particleSpeed: 0.3,
        glowIntensity: 0.4,
        colorTemperature: 0.5,
        vignetteStrength: 0.6,
        audioLowPassCutoff: 2000,
        binauralBeatGain: 0.5,
        ambientVolume: 0.2,
        feedbackTrigger: .none
    )
}

// MARK: - FeedbackTriggerType
enum FeedbackTriggerType: Equatable {
    case none
    case rewardChime
    case distractionAlert
    case flowStateEntrance
    case levelComplete
}

// MARK: - AttentionState (extended)
/// Maps raw attention 0.0–1.0 into one of four qualitative bands.
enum AttentionBand: Equatable, CaseIterable {
    case scattered   // < 0.30
    case wandering   // 0.30 – 0.60
    case focused     // 0.60 – 0.80
    case deepFlow    // > 0.80

    static func from(_ value: Double) -> AttentionBand {
        if value > 0.80 { return .deepFlow }
        if value > 0.60 { return .focused }
        if value > 0.30 { return .wandering }
        return .scattered
    }
}

// MARK: - AttentionProvider Protocol
/// Abstraction over any attention data source.
/// Demo: SimulatedAttention. Future: real EEG hardware.
protocol AttentionProvider: AnyObject {
    /// Continuous attention value stream (0.0–1.0), published at ~30 Hz.
    var attentionValue: AnyPublisher<Double, Never> { get }

    /// Discrete feedback state computed from attention, published on value change.
    var feedbackState: AnyPublisher<FeedbackState, Never> { get }

    /// Begin producing attention data.
    func start()

    /// Stop producing attention data.
    func stop()
}
