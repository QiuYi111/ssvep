import Foundation
import Combine

final class ThermalMonitor {

    enum ThermalLevel: Equatable {
        case nominal
        case fair
        case serious
        case critical

        var particleScaleFactor: Float {
            switch self {
            case .nominal:  return 1.0
            case .fair:     return 0.75
            case .serious:  return 0.5
            case .critical: return 0.25
            }
        }

        var shouldEnableBloom: Bool {
            switch self {
            case .nominal, .fair:   return true
            case .serious, .critical: return false
            }
        }

        var ssvepIntensityScale: Float {
            switch self {
            case .nominal:  return 1.0
            case .fair:     return 0.9
            case .serious:  return 0.8
            case .critical: return 0.7
            }
        }

        var shouldReduceFrameRate: Bool {
            self == .serious || self == .critical
        }
    }

    let thermalLevelPublisher = CurrentValueSubject<ThermalLevel, Never>(.nominal)

    var currentLevel: ThermalLevel {
        thermalLevelPublisher.value
    }

    private var timer: Timer?
    private let checkInterval: TimeInterval

    init(checkInterval: TimeInterval = 5.0) {
        self.checkInterval = checkInterval
    }

    func startMonitoring() {
        checkThermalState()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkThermalState()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkThermalState() {
        let state = ProcessInfo.processInfo.thermalState

        let level: ThermalLevel
        switch state {
        case .nominal:
            level = .nominal
        case .fair:
            level = .fair
        case .serious:
            level = .serious
        case .critical:
            level = .critical
        @unknown default:
            level = .serious
        }

        let previous = thermalLevelPublisher.value
        thermalLevelPublisher.send(level)

        if level != previous {
            print("[ThermalMonitor] State changed: \(previous) → \(level)")
        }
    }
}
