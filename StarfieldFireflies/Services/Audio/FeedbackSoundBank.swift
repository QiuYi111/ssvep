import AVFoundation

private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
    Swift.min(Swift.max(value, min), max)
}

enum FeedbackEventType: Sendable {
    case rewardChime
    case distractionAlert
    case flowStateEntrance
    case levelComplete
}

private struct FeedbackEvent {
    let type: FeedbackEventType
    let timestamp: Float
}

private struct FlowNote {
    var frequency: Float
    let duration: Float
    var elapsed: Float
}

private let bowlHarmonics: [(ratio: Float, amplitude: Float, decay: Float)] = [
    (1.0,   1.0,  0.4),
    (2.76,  0.5,  0.8),
    (4.72,  0.25, 1.2),
    (6.34,  0.12, 1.8),
    (8.91,  0.06, 2.5),
]

private var bowlBaseFreq: Float = 396.0

final class FeedbackNode {
    private var sourceNode: AVAudioSourceNode!
    private var eventQueue: [FeedbackEvent] = []
    private let queueLock = NSLock()

    private var bowlPhases: [Float] = [0, 0, 0, 0, 0]
    private var bowlAmplitudes: [Float] = [0, 0, 0, 0, 0]
    private var bowlActive = false

    private var alertPhase: Float = 0.0
    private var alertAmplitude: Float = 0.0
    private var alertActive = false

    private var flowNotes: [FlowNote] = []
    private var flowNoteIndex = 0
    private var flowNotePhase: Float = 0.0
    private var flowActive = false

    private let sampleRate: Float = 48000.0

    var node: AVAudioSourceNode { sourceNode }

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, abl in
            guard let self else { return noErr }
            self.renderEffects(frameCount: frameCount, abl: abl)
            return noErr
        }
    }

    func trigger(_ type: FeedbackEventType) {
        queueLock.lock()
        eventQueue.append(FeedbackEvent(type: type, timestamp: 0))
        queueLock.unlock()
    }

    func setBowlBaseFrequency(_ freq: Float) {
        bowlBaseFreq = freq
    }

    private func dequeueEvents() -> [FeedbackEvent] {
        queueLock.lock()
        let events = eventQueue
        eventQueue.removeAll()
        queueLock.unlock()
        return events
    }

    private func renderEffects(frameCount: UInt32, abl: UnsafeMutablePointer<AudioBufferList>) {
        let buf = UnsafeMutableAudioBufferListPointer(abl)
        guard buf.count >= 2,
              let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
              let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        let frames = Int(frameCount)
        let dt: Float = 1.0 / sampleRate

        let events = dequeueEvents()
        for event in events {
            handleEvent(event)
        }

        for i in 0..<frames {
            var sampleL: Float = 0.0
            var sampleR: Float = 0.0

            if bowlActive {
                let bowlSample = renderBowlSample(dt: dt)
                sampleL += bowlSample * 0.7
                sampleR += bowlSample * 1.0
            }

            if alertActive {
                let alertSample = renderAlertSample(dt: dt)
                sampleL += alertSample
                sampleR += alertSample
            }

            if flowActive {
                let (flowL, flowR) = renderFlowSample(dt: dt)
                sampleL += flowL
                sampleR += flowR
            }

            lPtr[i] = sampleL
            rPtr[i] = sampleR
        }
    }

    private func handleEvent(_ event: FeedbackEvent) {
        switch event.type {
        case .rewardChime:
            startBowl()
        case .distractionAlert:
            startAlert()
        case .flowStateEntrance:
            startFlowSequence()
        case .levelComplete:
            startLevelComplete()
        }
    }

    private func startBowl() {
        bowlActive = true
        for i in 0..<bowlPhases.count {
            bowlPhases[i] = 0.0
            bowlAmplitudes[i] = bowlHarmonics[i].amplitude
        }
    }

    private func renderBowlSample(dt: Float) -> Float {
        var sample: Float = 0.0
        var allDecayed = true

        for i in 0..<bowlHarmonics.count {
            guard bowlAmplitudes[i] > 0.001 else { continue }
            allDecayed = false

            let h = bowlHarmonics[i]
            let freq = bowlBaseFreq * h.ratio
            let beatFreq: Float = 0.3 * Float(i)
            let freqMod = freq + sinf(bowlPhases[i] * 0.001) * beatFreq

            bowlPhases[i] += 2.0 * .pi * freqMod * dt
            if bowlPhases[i] > 65536.0 { bowlPhases[i] -= 65536.0 }

            bowlAmplitudes[i] *= (1.0 - h.decay * dt)
            sample += sinf(bowlPhases[i]) * bowlAmplitudes[i]
        }

        if allDecayed { bowlActive = false }

        return sample * 0.25
    }

    private func startAlert() {
        alertActive = true
        alertPhase = 0.0
        alertAmplitude = 0.12
    }

    private func renderAlertSample(dt: Float) -> Float {
        let freq1: Float = 330.0
        let freq2: Float = 352.0

        alertPhase += 2.0 * .pi * freq1 * dt

        let tone1 = sinf(alertPhase) * alertAmplitude
        let tone2 = sinf(alertPhase * (freq2 / freq1)) * alertAmplitude * 0.7

        alertAmplitude *= (1.0 - 4.0 * dt)

        let sample = (tone1 + tone2) * 0.3

        if alertAmplitude < 0.001 { alertActive = false }

        return sample
    }

    private func startFlowSequence() {
        flowActive = true
        flowNoteIndex = 0
        flowNotes = [
            FlowNote(frequency: 261.63, duration: 0.4, elapsed: 0.0),
            FlowNote(frequency: 329.63, duration: 0.4, elapsed: 0.0),
            FlowNote(frequency: 392.00, duration: 0.8, elapsed: 0.0),
        ]
        flowNotePhase = 0.0
    }

    private func renderFlowSample(dt: Float) -> (Float, Float) {
        guard flowNoteIndex < flowNotes.count else {
            flowActive = false
            return (0, 0)
        }

        flowNotes[flowNoteIndex].elapsed += dt

        let note = flowNotes[flowNoteIndex]
        flowNotePhase += 2.0 * .pi * note.frequency * dt
        let tone = sinf(flowNotePhase) + sinf(flowNotePhase * 2.0) * 0.15 + sinf(flowNotePhase * 3.0) * 0.05

        let progress = note.elapsed / note.duration
        let env: Float
        if progress < 0.05 {
            env = progress / 0.05
        } else if progress < 0.2 {
            env = 1.0
        } else {
            env = 1.0 - (progress - 0.2) / 0.8
        }
        let clampedEnv = max(env, 0.0)

        let sample = tone * clampedEnv * 0.1

        if note.elapsed >= note.duration {
            flowNoteIndex += 1
            if flowNoteIndex >= flowNotes.count {
                flowActive = false
            }
        }

        let pan = Float(flowNoteIndex) / Float(max(flowNotes.count - 1, 1))
        return (sample * (1.0 - pan * 0.6), sample * (0.4 + pan * 0.6))
    }

    private func startLevelComplete() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.0) { [weak self] in
            self?.trigger(.rewardChime)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.trigger(.rewardChime)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.trigger(.rewardChime)
        }
    }
}
