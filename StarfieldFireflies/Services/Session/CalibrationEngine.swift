import Foundation
import Combine

struct CalibrationData {
    let meanAttention: Float
    let variance: Float
    let settleDuration: TimeInterval
}

final class CalibrationEngine: ObservableObject {
    @Published private(set) var progress: Float = 0.0
    @Published private(set) var isComplete: Bool = false
    @Published private(set) var calibrationData: CalibrationData?

    private let settleDuration: TimeInterval = 5.0
    private let calibrationWindow: TimeInterval
    private var startTime: Date?
    private var samples: [Float] = []
    private var timer: Timer?

    var totalDuration: TimeInterval {
        settleDuration + calibrationWindow
    }

    init(calibrationDuration: TimeInterval = 10.0) {
        self.calibrationWindow = calibrationDuration
    }

    func start(provider: AttentionProvider) {
        samples.removeAll()
        progress = 0.0
        isComplete = false
        calibrationData = nil
        startTime = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick(provider: provider)
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(provider: AttentionProvider) {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        let totalProgress = Float(elapsed / totalDuration)
        progress = min(totalProgress, 1.0)

        if elapsed >= totalDuration {
            finish()
        }
    }

    func ingestSample(_ value: Float) {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)

        guard elapsed >= settleDuration else { return }

        samples.append(value)
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        isComplete = true
        progress = 1.0

        guard !samples.isEmpty else {
            calibrationData = CalibrationData(meanAttention: 0.5, variance: 0.01, settleDuration: settleDuration)
            return
        }

        let mean = samples.reduce(0, +) / Float(samples.count)
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(samples.count)

        calibrationData = CalibrationData(
            meanAttention: mean,
            variance: variance,
            settleDuration: settleDuration
        )
    }
}
