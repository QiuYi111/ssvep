import Foundation
import Combine

final class SessionController: ObservableObject {
    @Published private(set) var currentPhase: SessionPhase?
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var isActive: Bool = false

    let levelID: LevelID
    private let trainingDuration: TimeInterval

    private var attentionProvider: SimulatedAttention?
    private var attentionManager: AttentionManager?
    private var calibrationEngine: CalibrationEngine?

    private var phaseTimer: Timer?
    private var sessionStartTime: Date?
    private var phaseStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    init(levelID: LevelID) {
        self.levelID = levelID
        self.trainingDuration = levelID.trainingDuration
    }

    var attentionManagerInstance: AttentionManager? {
        attentionManager
    }

    var calibrationEngineInstance: CalibrationEngine? {
        calibrationEngine
    }

    func startSession() {
        isActive = true
        sessionStartTime = Date()

        let provider = SimulatedAttention(levelID: levelID, sessionDuration: trainingDuration)
        attentionProvider = provider

        let manager = AttentionManager(provider: provider)
        attentionManager = manager

        manager.feedbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleFeedbackState(state)
            }
            .store(in: &cancellables)

        enterPhase(.calibration)
    }

    func stopSession() {
        phaseTimer?.invalidate()
        phaseTimer = nil
        attentionProvider?.stop()
        AudioEngineManager.shared.stopEngine()
        HapticEngine.shared.playDistractionNudge()
        isActive = false
        currentPhase = nil
    }

    private func enterPhase(_ phase: SessionPhase) {
        currentPhase = phase
        phaseStartTime = Date()

        switch phase {
        case .calibration:
            startCalibration()
        case .immersion:
            startImmersion()
        case .training:
            startTraining()
        case .debrief:
            startDebrief()
        }
    }

    private func startCalibration() {
        let calibrationDuration = levelID.calibrationDuration

        let calibration = CalibrationEngine(calibrationDuration: calibrationDuration)
        calibrationEngine = calibration

        attentionProvider?.start()

        let provider = attentionProvider!
        var sampleCancellable: AnyCancellable?
        sampleCancellable = provider.attentionValue
            .sink { [weak self] value in
                self?.calibrationEngine?.ingestSample(Float(value))
            }

        phaseTimer = Timer.scheduledTimer(withTimeInterval: calibrationDuration, repeats: false) { [weak self] _ in
            sampleCancellable?.cancel()
            self?.calibrationEngine?.stop()
            if let next = self?.currentPhase?.next {
                self?.enterPhase(next)
            }
        }

        startTickTimer()
    }

    private func startImmersion() {
        let audioManager = AudioEngineManager.shared
        let config = LevelAudioConfig.forLevel(levelID)

        do {
            try audioManager.startEngine()
            audioManager.switchToLevel(config, animate: true)
        } catch { }

        let immersionDuration: TimeInterval = 5.0
        phaseTimer = Timer.scheduledTimer(withTimeInterval: immersionDuration, repeats: false) { [weak self] _ in
            if let next = self?.currentPhase?.next {
                self?.enterPhase(next)
            }
        }

        startTickTimer()
    }

    private func startTraining() {
        let provider = attentionProvider!
        let manager = attentionManager!

        provider.start()

        manager.feedbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                AudioEngineManager.shared.updateFromAttention(state.brightness)
            }
            .store(in: &cancellables)

        phaseTimer = Timer.scheduledTimer(withTimeInterval: trainingDuration, repeats: false) { [weak self] _ in
            self?.attentionProvider?.stop()
            if let next = self?.currentPhase?.next {
                self?.enterPhase(next)
            }
        }

        startTickTimer()
    }

    private func startDebrief() {
        let cooldownDuration: TimeInterval = 10.0
        phaseTimer = Timer.scheduledTimer(withTimeInterval: cooldownDuration, repeats: false) { [weak self] _ in
            self?.stopSession()
        }

        startTickTimer()
    }

    private func startTickTimer() {
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickTime()
        }
        RunLoop.current.add(phaseTimer!, forMode: .common)
    }

    private func tickTime() {
        guard let start = phaseStartTime else { return }
        elapsedTime = Date().timeIntervalSince(start)

        let totalDuration = totalDurationForCurrentPhase()
        remainingTime = max(0, totalDuration - elapsedTime)
    }

    private func totalDurationForCurrentPhase() -> TimeInterval {
        guard let phase = currentPhase else { return 0 }
        switch phase {
        case .calibration:
            return levelID.calibrationDuration
        case .immersion:
            return 5.0
        case .training:
            return trainingDuration
        case .debrief:
            return 10.0
        }
    }

    private func handleFeedbackState(_ state: FeedbackState) {
        switch state.feedbackTrigger {
        case .rewardChime:
            AudioEngineManager.shared.feedbackNode.trigger(.rewardChime)
            HapticEngine.shared.playAttentionPulse(intensity: state.brightness)
        case .distractionAlert:
            AudioEngineManager.shared.feedbackNode.trigger(.distractionAlert)
            HapticEngine.shared.playDistractionNudge()
        case .flowStateEntrance:
            AudioEngineManager.shared.feedbackNode.trigger(.flowStateEntrance)
            HapticEngine.shared.playFocusLock()
        case .levelComplete:
            AudioEngineManager.shared.feedbackNode.trigger(.levelComplete)
        case .none:
            break
        }
    }
}
