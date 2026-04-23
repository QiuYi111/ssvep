import Foundation

struct AttentionSample {
    let timestamp: TimeInterval
    let ssvepSNR: Float
    let attentionScore: Float
    let rawSSVEPAmplitude: Float
    let isReliable: Bool

    enum Source {
        case eeg
        case simulated
        case keyboard
    }

    let source: Source

    init(
        timestamp: TimeInterval,
        ssvepSNR: Float,
        attentionScore: Float,
        rawSSVEPAmplitude: Float,
        isReliable: Bool,
        source: Source = .simulated
    ) {
        self.timestamp = timestamp
        self.ssvepSNR = ssvepSNR
        self.attentionScore = attentionScore
        self.rawSSVEPAmplitude = rawSSVEPAmplitude
        self.isReliable = isReliable
        self.source = source
    }

    static func makeSimulated(
        timestamp: TimeInterval,
        score: Float,
        snr: Float,
        amplitude: Float
    ) -> AttentionSample {
        AttentionSample(
            timestamp: timestamp,
            ssvepSNR: snr,
            attentionScore: score,
            rawSSVEPAmplitude: amplitude,
            isReliable: score > 0.2,
            source: .simulated
        )
    }
}
