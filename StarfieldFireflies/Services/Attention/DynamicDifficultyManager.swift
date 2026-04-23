import Foundation
import Combine

/// Tracks sustained focus/failure periods and outputs a difficulty multiplier (0.0-1.0).
/// 0.0 = easiest (help the user), 1.0 = hardest (challenge the user).
/// Design doc rules:
///   - Sustained high focus >3min → increase difficulty (narrower SSVEP opacity range)
///   - Sustained low focus (failure) → decrease difficulty (wider SSVEP opacity range, dim distractors)
final class DynamicDifficultyManager {

    // Output: 0.0 (easiest) to 1.0 (hardest), default 0.5
    @Published private(set) var difficultyLevel: Float = 0.5

    private let focusThreshold: Float = 0.7
    private let failureThreshold: Float = 0.3
    private let focusRampDuration: TimeInterval = 180.0
    private let failureRampDuration: TimeInterval = 30.0
    private let adjustmentRate: Float = 0.02

    private var sustainedFocusStart: Date?
    private var sustainedFailureStart: Date?
    private var currentAttention: Float = 0.5

    // MARK: - Per-tick update (call at ~1Hz from timer)

    func onAttentionTick(_ attention: Float) {
        currentAttention = attention
        let now = Date()

        if attention >= focusThreshold {
            if sustainedFocusStart == nil { sustainedFocusStart = now }
            sustainedFailureStart = nil

            if let start = sustainedFocusStart, now.timeIntervalSince(start) >= focusRampDuration {
                difficultyLevel = min(1.0, difficultyLevel + adjustmentRate)
            }
        } else if attention <= failureThreshold {
            if sustainedFailureStart == nil { sustainedFailureStart = now }
            sustainedFocusStart = nil

            if let start = sustainedFailureStart, now.timeIntervalSince(start) >= failureRampDuration {
                difficultyLevel = max(0.0, difficultyLevel - adjustmentRate)
            }
        } else {
            sustainedFocusStart = nil
            sustainedFailureStart = nil
        }
    }

    // MARK: - Difficulty to SSVEP opacity range

    /// Higher difficulty = narrower opacity range (harder to distinguish SSVEP).
    /// At difficulty 0.0: 50%–100% (easy to see). At difficulty 1.0: 70%–95% (subtle).
    var targetOpacityRange: (min: Float, max: Float) {
        let minOpacity = lerp(0.50, 0.70, difficultyLevel)
        let maxOpacity = lerp(1.00, 0.95, difficultyLevel)
        return (minOpacity, maxOpacity)
    }

    /// Higher difficulty = brighter distractors. Lower difficulty = dimmer distractors.
    var distractorBrightnessScale: Float {
        lerp(0.3, 1.0, difficultyLevel)
    }

    /// Whether to show guiding pulses on the target (only when difficulty is very low, i.e. user is struggling).
    var shouldShowGuidingPulse: Bool {
        difficultyLevel < 0.25
    }

    func reset() {
        difficultyLevel = 0.5
        sustainedFocusStart = nil
        sustainedFailureStart = nil
        currentAttention = 0.5
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}
