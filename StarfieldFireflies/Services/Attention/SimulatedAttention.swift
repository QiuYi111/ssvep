import Foundation
import Combine

// MARK: - Distraction Event Types

enum RecoveryCurve: String, CaseIterable {
    case linear
    case exponential
    case sigmoid
}

enum DistractionType: String, CaseIterable {
    case mildDrift
    case external
    case fatigue
    case tsunami
}

struct DistractionEvent {
    let startTime: TimeInterval
    let duration: TimeInterval
    let depth: Float
    let recoveryCurve: RecoveryCurve
    let type: DistractionType
}

// MARK: - Attention Personality Profile

struct AttentionProfile {
    let baseline: Float
    let focusTrend: Float
    let distractibility: Float
    let recoveryRate: Float
    let noiseAmplitude: Float
}

// MARK: - Realm Distraction Configuration

struct RealmDistractionConfig {
    let minInterval: Float
    let maxInterval: Float
    let depthRange: ClosedRange<Float>
    let possibleTypes: [DistractionType]
}

// MARK: - SimulatedAttention

final class SimulatedAttention: AttentionProvider {

    private let _attentionSubject = CurrentValueSubject<Double, Never>(0.3)
    var attentionValue: AnyPublisher<Double, Never> {
        _attentionSubject.eraseToAnyPublisher()
    }

    private let _feedbackSubject = CurrentValueSubject<FeedbackState, Never>(.neutral)
    var feedbackState: AnyPublisher<FeedbackState, Never> {
        _feedbackSubject.eraseToAnyPublisher()
    }

    var currentAttention: Float = 0.3
    var onAttentionUpdate: ((Float) -> Void)?

    let sessionDuration: TimeInterval
    let levelID: LevelID

    private var baselineAttention: Float
    private var focusTrend: Float
    private var distractibility: Float
    private var recoveryRate: Float
    private var noiseAmplitude: Float

    private var sessionStartTime: Date?
    private var timer: Timer?
    private var activeDistraction: DistractionEvent?
    private var distractionSchedule: [DistractionEvent] = []
    private var distractionScheduleIndex: Int = 0
    private var attentionHistory: [Float] = []
    private let historyMaxSamples = 300

    var manualOverrideActive = false
    var manualAttentionValue: Float = 1.0

    private let updateInterval: TimeInterval = 1.0 / 30.0

    init(levelID: LevelID, sessionDuration: TimeInterval = 300) {
        self.levelID = levelID
        self.sessionDuration = sessionDuration

        let profile = Self.profileForLevel(levelID)
        self.baselineAttention = profile.baseline
        self.focusTrend = profile.focusTrend
        self.distractibility = profile.distractibility
        self.recoveryRate = profile.recoveryRate
        self.noiseAmplitude = profile.noiseAmplitude
    }

    // MARK: - AttentionProvider

    func start() {
        sessionStartTime = Date()
        currentAttention = 0.3
        attentionHistory.removeAll()
        distractionSchedule = generateDistractionSchedule()
        distractionScheduleIndex = 0
        activeDistraction = nil

        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateAttention()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sessionStartTime = nil
    }

    // MARK: - Level Personality Profiles

    static func profileForLevel(_ levelID: LevelID) -> AttentionProfile {
        switch levelID {
        case .level1:
            return AttentionProfile(baseline: 0.50, focusTrend: 0.08, distractibility: 0.15,
                                    recoveryRate: 0.80, noiseAmplitude: 0.02)
        case .level2:
            return AttentionProfile(baseline: 0.45, focusTrend: 0.10, distractibility: 0.20,
                                    recoveryRate: 0.70, noiseAmplitude: 0.03)
        case .level3:
            return AttentionProfile(baseline: 0.40, focusTrend: 0.12, distractibility: 0.35,
                                    recoveryRate: 0.55, noiseAmplitude: 0.03)
        case .level4:
            return AttentionProfile(baseline: 0.35, focusTrend: 0.15, distractibility: 0.45,
                                    recoveryRate: 0.50, noiseAmplitude: 0.04)
        case .level5:
            return AttentionProfile(baseline: 0.38, focusTrend: 0.18, distractibility: 0.55,
                                    recoveryRate: 0.40, noiseAmplitude: 0.04)
        case .level6:
            return AttentionProfile(baseline: 0.35, focusTrend: 0.20, distractibility: 0.65,
                                    recoveryRate: 0.35, noiseAmplitude: 0.05)
        }
    }

    static func realmConfig(for levelID: LevelID) -> RealmDistractionConfig {
        switch levelID {
        case .level1, .level2:
            return RealmDistractionConfig(minInterval: 30, maxInterval: 60,
                                          depthRange: 0.2...0.4,
                                          possibleTypes: [.mildDrift, .fatigue])
        case .level3, .level4:
            return RealmDistractionConfig(minInterval: 15, maxInterval: 30,
                                          depthRange: 0.3...0.6,
                                          possibleTypes: [.mildDrift, .external, .fatigue])
        case .level5, .level6:
            return RealmDistractionConfig(minInterval: 10, maxInterval: 20,
                                          depthRange: 0.4...0.8,
                                          possibleTypes: [.external, .fatigue, .tsunami])
        }
    }

    // MARK: - Distraction Schedule Generation

    private func generateDistractionSchedule() -> [DistractionEvent] {
        var events: [DistractionEvent] = []
        var currentTime: TimeInterval = 5.0
        let config = Self.realmConfig(for: levelID)

        while currentTime < sessionDuration - 10 {
            let interval = TimeInterval(Float.random(in: config.minInterval...config.maxInterval))
            currentTime += interval

            let depth = Float.random(in: config.depthRange)
            let duration = TimeInterval(2.0 + Double(depth) * 6.0)
            let recoveryCurve: RecoveryCurve = depth > 0.6 ? .sigmoid : (depth > 0.4 ? .exponential : .linear)
            let type = config.possibleTypes.randomElement() ?? .mildDrift

            if type == .tsunami {
                continue
            }

            events.append(DistractionEvent(
                startTime: currentTime,
                duration: duration,
                depth: depth,
                recoveryCurve: recoveryCurve,
                type: type
            ))
        }

        if levelID == .level5 || levelID == .level6 {
            if Float.random(in: 0...1) < 0.15 {
                let tsunamiTime = Double(sessionDuration) * Double.random(in: 0.4...0.7)
                events.append(DistractionEvent(
                    startTime: tsunamiTime,
                    duration: TimeInterval(Float.random(in: 6...8)),
                    depth: Float.random(in: 0.7...0.8),
                    recoveryCurve: .sigmoid,
                    type: .tsunami
                ))
            }
        }

        return events.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Core Update Loop (30 Hz)

    private func updateAttention() {
        guard let startTime = sessionStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let progress = Float(elapsed / sessionDuration)

        let baseAttention = calculateProgressiveFocus(progress: progress)

        var distractionModifier: Float = 0.0
        if let event = activeDistraction {
            let eventProgress = Float((elapsed - event.startTime) / event.duration)
            if eventProgress >= 1.0 {
                activeDistraction = nil
            } else {
                distractionModifier = calculateDistractionImpact(
                    depth: event.depth,
                    progress: min(eventProgress, 1.0),
                    recoveryCurve: event.recoveryCurve
                )
            }
        }

        checkDistractionTrigger(elapsed: elapsed)

        let noise = Float.random(in: -noiseAmplitude...noiseAmplitude)
        let breathWave = sinf(Float(elapsed) * 0.3 * .pi * 2) * 0.015

        var rawAttention = baseAttention - distractionModifier + noise + breathWave

        if manualOverrideActive {
            rawAttention = manualAttentionValue
        }

        let clamped = max(0.0, min(1.0, rawAttention))

        let alpha: Float = 0.3
        currentAttention = currentAttention * (1.0 - alpha) + clamped * alpha

        attentionHistory.append(currentAttention)
        if attentionHistory.count > historyMaxSamples {
            attentionHistory.removeFirst()
        }

        onAttentionUpdate?(currentAttention)
        _attentionSubject.send(Double(currentAttention))
    }

    // MARK: - Progressive Focus Curve (Hermite Interpolation)

    private func calculateProgressiveFocus(progress: Float) -> Float {
        let keyframes: [(Float, Float)] = [
            (0.00, baselineAttention * 0.85),
            (0.20, baselineAttention),
            (0.50, baselineAttention + focusTrend * 0.5),
            (0.85, baselineAttention + focusTrend * 0.9),
            (1.00, baselineAttention + focusTrend * 0.7),
        ]

        guard let idx = keyframes.lastIndex(where: { $0.0 <= progress }) else {
            return keyframes.last!.1
        }
        if idx == keyframes.count - 1 { return keyframes[idx].1 }

        let (t0, v0) = keyframes[idx]
        let (t1, v1) = keyframes[idx + 1]

        let t = (progress - t0) / (t1 - t0)
        let s = t * t * (3.0 - 2.0 * t)

        return v0 + (v1 - v0) * s
    }

    // MARK: - Distraction Impact

    private func calculateDistractionImpact(
        depth: Float,
        progress: Float,
        recoveryCurve: RecoveryCurve
    ) -> Float {
        switch recoveryCurve {
        case .linear:
            if progress < 0.4 {
                return depth * (progress / 0.4)
            } else {
                return depth * (1.0 - (progress - 0.4) / 0.6)
            }

        case .exponential:
            let attack = depth * (1.0 - expf(-5.0 * progress))
            let release = depth * expf(-3.0 * max(0, progress - 0.3))
            return max(attack, release)

        case .sigmoid:
            if progress < 0.3 {
                return depth * smoothstep(0.0, 0.3, progress)
            } else if progress < 0.5 {
                return depth
            } else {
                return depth * (1.0 - smoothstep(0.5, 1.0, progress))
            }
        }
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    // MARK: - Distraction Trigger Check

    private func checkDistractionTrigger(elapsed: TimeInterval) {
        guard activeDistraction == nil else { return }
        guard distractionScheduleIndex < distractionSchedule.count else { return }

        let nextEvent = distractionSchedule[distractionScheduleIndex]
        if elapsed >= nextEvent.startTime {
            activeDistraction = nextEvent
            distractionScheduleIndex += 1
        }
    }

    // MARK: - Manual Override (Demo)

    func triggerManualDistraction() {
        let event = DistractionEvent(
            startTime: Date().timeIntervalSince(sessionStartTime ?? Date()),
            duration: TimeInterval(Float.random(in: 3...7)),
            depth: Float.random(in: 0.3...0.7),
            recoveryCurve: [.linear, .exponential, .sigmoid].randomElement()!,
            type: [.mildDrift, .external, .fatigue].randomElement()!
        )
        activeDistraction = event
    }
}
