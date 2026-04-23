import Foundation
import Combine

final class UserProfile: ObservableObject {

    static let shared = UserProfile()

    @Published var completedLevels: Set<Int> {
        didSet {
            UserDefaults.standard.set(Array(completedLevels), forKey: "completedLevels")
        }
    }

    @Published var bestScores: [Int: Float] {
        didSet {
            for (level, score) in bestScores {
                let key = "bestScore_level\(level)"
                let previous = UserDefaults.standard.float(forKey: key)
                if score > previous {
                    UserDefaults.standard.set(score, forKey: key)
                }
            }
        }
    }

    @Published var totalSessions: Int {
        didSet {
            UserDefaults.standard.set(totalSessions, forKey: "totalSessions")
        }
    }

    @Published var totalTrainingTime: TimeInterval {
        didSet {
            UserDefaults.standard.set(totalTrainingTime, forKey: "totalTrainingTime")
        }
    }

    @Published var prefersReducedMotion: Bool {
        didSet {
            UserDefaults.standard.set(prefersReducedMotion, forKey: "prefersReducedMotion")
        }
    }

    @Published var prefersHaptics: Bool {
        didSet {
            UserDefaults.standard.set(prefersHaptics, forKey: "prefersHaptics")
        }
    }

    @Published var currentRealm: MeditationRealm {
        didSet { UserDefaults.standard.set(currentRealm.rawValue, forKey: "currentRealm") }
    }

    @Published var consecutiveLowDistractionSessions: Int {
        didSet { UserDefaults.standard.set(consecutiveLowDistractionSessions, forKey: "consecutiveLowDistractionSessions") }
    }

    @Published var hasSurvivedStormLevel: Bool {
        didSet { UserDefaults.standard.set(hasSurvivedStormLevel, forKey: "hasSurvivedStormLevel") }
    }

    @Published var recentDistractionRatios: [Float] {
        didSet {
            if recentDistractionRatios.count > 10 {
                recentDistractionRatios = Array(recentDistractionRatios.suffix(10))
            }
            UserDefaults.standard.set(recentDistractionRatios, forKey: "recentDistractionRatios")
        }
    }

    private init() {
        let stored = UserDefaults.standard.object(forKey: "completedLevels") as? [Int] ?? []
        self.completedLevels = Set(stored)

        var scores: [Int: Float] = [:]
        for level in 1...6 {
            let key = "bestScore_level\(level)"
            let val = UserDefaults.standard.float(forKey: key)
            if val > 0 { scores[level] = val }
        }
        self.bestScores = scores

        self.totalSessions = UserDefaults.standard.integer(forKey: "totalSessions")
        self.totalTrainingTime = UserDefaults.standard.double(forKey: "totalTrainingTime")
        self.prefersReducedMotion = UserDefaults.standard.bool(forKey: "prefersReducedMotion")

        if UserDefaults.standard.object(forKey: "prefersHaptics") == nil {
            self.prefersHaptics = true
        } else {
            self.prefersHaptics = UserDefaults.standard.bool(forKey: "prefersHaptics")
        }

        self.currentRealm = MeditationRealm(rawValue: UserDefaults.standard.integer(forKey: "currentRealm")) ?? .foundation
        self.consecutiveLowDistractionSessions = UserDefaults.standard.integer(forKey: "consecutiveLowDistractionSessions")
        self.hasSurvivedStormLevel = UserDefaults.standard.bool(forKey: "hasSurvivedStormLevel")
        self.recentDistractionRatios = UserDefaults.standard.array(forKey: "recentDistractionRatios") as? [Float] ?? []
    }

    func saveBestScore(levelID: LevelID, score: Float) {
        let key = "bestScore_level\(levelID.rawValue)"
        let previous = UserDefaults.standard.float(forKey: key)
        if score > previous {
            UserDefaults.standard.set(score, forKey: key)
            bestScores[levelID.rawValue] = score
        }
    }

    func bestScore(for levelID: LevelID) -> Float {
        bestScores[levelID.rawValue] ?? 0.0
    }

    func markLevelCompleted(_ levelID: LevelID) {
        completedLevels.insert(levelID.rawValue)
    }

    func incrementSessions() {
        totalSessions += 1
    }

    func addTrainingTime(_ seconds: TimeInterval) {
        totalTrainingTime += seconds
    }

    func recordSessionCompletion(levelID: LevelID, focusRatio: Float, distractionRatio: Float) {
        recentDistractionRatios.append(distractionRatio)

        if distractionRatio < 0.20 {
            consecutiveLowDistractionSessions += 1
        } else {
            consecutiveLowDistractionSessions = 0
        }

        if currentRealm == .foundation && consecutiveLowDistractionSessions >= 5 {
            advanceRealm()
        }

        if levelID == .level5 && focusRatio > 0.7 && !hasSurvivedStormLevel {
            hasSurvivedStormLevel = true
        }
        if currentRealm == .tranquility && hasSurvivedStormLevel {
            advanceRealm()
        }

        if currentRealm == .clarity && recentDistractionRatios.count >= 10 {
            let avgDistraction = recentDistractionRatios.suffix(10).reduce(0, +) / 10.0
            if avgDistraction < 0.10 {
                advanceRealm()
            }
        }
    }

    private func advanceRealm() {
        if let next = MeditationRealm(rawValue: currentRealm.rawValue + 1) {
            currentRealm = next
        }
    }

    func isLevelAvailable(_ level: LevelID) -> Bool {
        currentRealm.availableLevels.contains(level)
    }

    func totalTrainingTimeString() -> String {
        let total = Int(totalTrainingTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }
}
