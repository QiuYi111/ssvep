import Foundation
import Combine

/// Mediates raw attention Doubles from AttentionProvider into FeedbackState
/// consumed by MetalRenderer, AudioEngine, and HapticEngine.
final class AttentionManager {

    private let _feedbackSubject = CurrentValueSubject<FeedbackState, Never>(.neutral)
    var feedbackState: AnyPublisher<FeedbackState, Never> {
        _feedbackSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var currentFeedbackState: FeedbackState {
        _feedbackSubject.value
    }

    var currentAttentionScore: Float = 0.0

    private var cancellables = Set<AnyCancellable>()
    private var previousBand: AttentionBand = .scattered

    private var highAttentionStart: Date?
    private var stableHighStart: Date?
    private var prevAttentionForDrop: Float = 0.5

    init(provider: AttentionProvider) {
        provider.attentionValue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.processAttention(value)
            }
            .store(in: &cancellables)
    }

    private func processAttention(_ rawValue: Double) {
        let attention = Float(rawValue)
        currentAttentionScore = attention
        let band = AttentionBand.from(rawValue)

        let trigger = computeTrigger(attention: attention, band: band)
        previousBand = band

        let state = mapToFeedbackState(attention: attention, trigger: trigger)
        _feedbackSubject.send(state)
    }

    // MARK: - Trigger Detection

    private func computeTrigger(attention: Float, band: AttentionBand) -> FeedbackTriggerType {
        let now = Date()

        if band == .deepFlow && previousBand != .deepFlow {
            highAttentionStart = now
        }
        if attention > 0.85 {
            if highAttentionStart == nil { highAttentionStart = now }
            if let start = highAttentionStart, now.timeIntervalSince(start) > 3.0 {
                highAttentionStart = nil
                return .flowStateEntrance
            }
        } else {
            highAttentionStart = nil
        }

        if attention < 0.3 && (prevAttentionForDrop - attention) > 0.2 {
            prevAttentionForDrop = attention
            return .distractionAlert
        }
        prevAttentionForDrop = attention

        if attention > 0.8 {
            if stableHighStart == nil { stableHighStart = now }
            if let start = stableHighStart, now.timeIntervalSince(start) > 10.0 {
                stableHighStart = nil
                return .rewardChime
            }
        } else {
            stableHighStart = nil
        }

        return .none
    }

    // MARK: - Attention → FeedbackState Mapping

    private func mapToFeedbackState(attention: Float, trigger: FeedbackTriggerType) -> FeedbackState {
        let a = max(0.0, min(1.0, attention))

        let brightness = smoothstep(0.2, 0.8, a)
        let particleSpeed = 0.1 + a * 0.9
        let glowIntensity = smoothstep(0.3, 0.9, a) * 1.5
        let colorTemperature = smoothstep(0.2, 0.7, a)
        let vignetteStrength = 1.0 - smoothstep(0.2, 0.7, a)

        let audioLowPassCutoff = 200.0 + a * a * 17800.0
        let binauralBeatGain = lerp(0.3, 0.7, sqrtf(a))
        let ambientVolume = smoothstep(0.1, 0.6, a)

        return FeedbackState(
            brightness: brightness,
            particleSpeed: particleSpeed,
            glowIntensity: glowIntensity,
            colorTemperature: colorTemperature,
            vignetteStrength: vignetteStrength,
            audioLowPassCutoff: audioLowPassCutoff,
            binauralBeatGain: binauralBeatGain,
            ambientVolume: ambientVolume,
            feedbackTrigger: trigger
        )
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    func reset() {
        _feedbackSubject.send(.neutral)
        currentAttentionScore = 0.0
        previousBand = .scattered
        highAttentionStart = nil
        stableHighStart = nil
        prevAttentionForDrop = 0.5
    }
}
