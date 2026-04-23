import SwiftUI
import Combine

struct SessionContainerView: View {
    let level: LevelID

    @Environment(AppState.self) private var appState
    @State private var phase: SessionPhase = .calibration
    @State private var elapsedTime: TimeInterval = 0
    @State private var attentionWaveform: [Float] = []
    @State private var focusDuration: TimeInterval = 0
    @State private var flowMoments: Int = 0
    @State private var peakAttention: Float = 0
    @State private var fadeToBlack = false

    // MARK: - Core subsystems

    @State private var renderer: MetalRenderer? = nil
    @State private var simulatedAttention: SimulatedAttention? = nil
    @State private var attentionManager: AttentionManager? = nil
    @State private var difficultyManager: DynamicDifficultyManager? = nil
    @State private var cancellables = Set<AnyCancellable>()
    @State private var thermalMonitor: ThermalMonitor? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .calibration:
                CalibrationView(
                    duration: level.calibrationDuration,
                    onComplete: { advancePhase() }
                )
                .transition(.opacity)

            case .immersion:
                ImmersionView(
                    level: level,
                    onComplete: { advancePhase() }
                )
                .transition(.opacity)

            case .training:
                trainingLayer
                    .transition(.opacity)

            case .debrief:
                DebriefView(
                    level: level,
                    focusDuration: focusDuration,
                    flowMoments: flowMoments,
                    peakAttention: peakAttention,
                    attentionWaveform: attentionWaveform,
                    onDismiss: {
                        stopAllSystems()
                        appState.currentScreen = .home
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.6), value: phase)
        .onReceive(timer) { _ in
            if phase == .training {
                elapsedTime += 1
                collectAttentionTick()
                applyDynamicDifficulty()

                if elapsedTime >= level.trainingDuration {
                    endSession()
                }
            }
        }
        .onDisappear {
            stopAllSystems()
        }
        .onKeyPress(.escape) {
            endSession()
            return .handled
        }
    }

    // MARK: - Training Layer (MetalView only; No-HUD by design)

    private var trainingLayer: some View {
        ZStack {
            if let renderer {
                MetalView(renderer: renderer)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            Color.black.opacity(fadeToBlack ? 1.0 : 0.0)
        }
        .onAppear {
            startTrainingSystems()
        }
        .accessibilityLabel("\(level.displayName) 训练中")
        .accessibilityHint("按下 Escape 可结束本次训练")
    }

    // MARK: - System Lifecycle

    private func startTrainingSystems() {
        // 1. Create Metal renderer and configure for this level
        let newRenderer = MetalRenderer()
        newRenderer.transitionToLevel(level)

        renderer = newRenderer

        let thermal = ThermalMonitor(checkInterval: 5.0)
        thermal.startMonitoring()
        thermalMonitor = thermal
        thermal.thermalLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak newRenderer] level in
                newRenderer?.applyThermalState(level)
            }
            .store(in: &cancellables)

        // 2. Create simulated attention provider
        let simAttention = SimulatedAttention(
            levelID: level,
            sessionDuration: level.trainingDuration
        )
        simulatedAttention = simAttention

        // 3. Create attention manager (maps raw attention → FeedbackState)
        let attnManager = AttentionManager(provider: simAttention)
        attentionManager = attnManager

        let difficulty = DynamicDifficultyManager()
        difficultyManager = difficulty

        // 4. Wire attention → renderer (visual feedback)
        attnManager.feedbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak newRenderer] state in
                newRenderer?.ssvepController.simulatedAttention = state.brightness
            }
            .store(in: &cancellables)

        // 5. Wire attention → audio engine
        simAttention.attentionValue
            .receive(on: DispatchQueue.main)
            .sink { attentionDouble in
                AudioEngineManager.shared.updateFromAttention(Float(attentionDouble))
            }
            .store(in: &cancellables)

        // 6. Wire feedback triggers → sound effects
        attnManager.feedbackState
            .receive(on: DispatchQueue.main)
            .sink { state in
                switch state.feedbackTrigger {
                case .rewardChime:
                    AudioEngineManager.shared.feedbackNode.trigger(.rewardChime)
                case .distractionAlert:
                    AudioEngineManager.shared.feedbackNode.trigger(.distractionAlert)
                case .flowStateEntrance:
                    AudioEngineManager.shared.feedbackNode.trigger(.flowStateEntrance)
                case .levelComplete:
                    AudioEngineManager.shared.feedbackNode.trigger(.levelComplete)
                case .none:
                    break
                }
            }
            .store(in: &cancellables)

        // 7. Start audio engine with level config
        let audioConfig = LevelAudioConfig.forLevel(level)
        AudioEngineManager.shared.switchToLevel(audioConfig, animate: true)
        do {
            try AudioEngineManager.shared.startEngine()
        } catch {
            print("[SessionContainer] Audio engine failed to start: \(error)")
        }

        // 8. Start attention simulation (30 Hz)
        simAttention.start()
    }

    private func stopAllSystems() {
        simulatedAttention?.stop()
        simulatedAttention = nil
        thermalMonitor?.stopMonitoring()
        thermalMonitor = nil
        cancellables.removeAll()
        AudioEngineManager.shared.stopEngine()
        difficultyManager?.reset()
        difficultyManager = nil
        attentionManager = nil
        renderer = nil
    }

    // MARK: - Phase Management

    private func advancePhase() {
        if let next = phase.next {
            withAnimation {
                phase = next
            }
        }
    }

    private func endSession() {
        let totalTicks = Float(attentionWaveform.count)
        let distractedTicks = attentionWaveform.filter { $0 < 0.3 }.count
        let distractionRatio = totalTicks > 0 ? Float(distractedTicks) / totalTicks : 0.0
        let focusRatio = totalTicks > 0 ? Float(focusDuration) / totalTicks : 0.0
        UserProfile.shared.recordSessionCompletion(levelID: level, focusRatio: focusRatio, distractionRatio: distractionRatio)
        UserProfile.shared.saveBestScore(levelID: level, score: peakAttention)
        UserProfile.shared.markLevelCompleted(level)
        UserProfile.shared.incrementSessions()
        UserProfile.shared.addTrainingTime(elapsedTime)

        withAnimation(.easeOut(duration: 1.0)) {
            fadeToBlack = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            AudioEngineManager.shared.feedbackNode.trigger(.levelComplete)
            withAnimation {
                phase = .debrief
                fadeToBlack = false
            }
        }
    }

    // MARK: - Attention Tick (waveform data for debrief)

    private func collectAttentionTick() {
        guard let attnManager = attentionManager else { return }
        let score = attnManager.currentAttentionScore

        attentionWaveform.append(score)

        if score > 0.7 {
            focusDuration += 1
        }
        if score > 0.85 {
            flowMoments += 1
        }
        if score > peakAttention {
            peakAttention = score
        }
    }

    private func applyDynamicDifficulty() {
        guard let attnManager = attentionManager,
              let diffMgr = difficultyManager,
              let rend = renderer else { return }
        diffMgr.onAttentionTick(attnManager.currentAttentionScore)
        rend.ssvepController.updateDifficulty(
            targetRange: diffMgr.targetOpacityRange,
            distractorBrightness: diffMgr.distractorBrightnessScale
        )
        rend.ssvepController.guidingPulseActive = diffMgr.shouldShowGuidingPulse
    }

}
