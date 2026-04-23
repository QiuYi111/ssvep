import Foundation

enum LevelID: Int, CaseIterable, Identifiable, Hashable {
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4
    case level5 = 5
    case level6 = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .level1: return "涟漪绽放"
        case .level2: return "萤火引路"
        case .level3: return "星图寻迹"
        case .level4: return "真假萤火"
        case .level5: return "飞燕破云"
        case .level6: return "流星试炼"
        }
    }

    var ssvepFrequency: Int {
        switch self {
        case .level1, .level2, .level3, .level4, .level5, .level6:
            return 15
        }
    }

    var distractorFrequency: Int? {
        switch self {
        case .level1, .level2:
            return nil
        case .level3, .level4, .level5, .level6:
            return 20
        }
    }

    var trainingDuration: TimeInterval {
        switch self {
        case .level1: return 120
        case .level2: return 180
        case .level3: return 240
        case .level4: return 300
        case .level5: return 300
        case .level6: return 360
        }
    }

    var calibrationDuration: TimeInterval {
        switch self {
        case .level1: return 3
        case .level2: return 3
        case .level3: return 4
        case .level4: return 4
        case .level5: return 5
        case .level6: return 5
        }
    }

    var particleDensityMultiplier: Float {
        switch self {
        case .level1: return 1.0
        case .level2: return 1.5
        case .level3: return 2.0
        case .level4: return 2.5
        case .level5: return 3.0
        case .level6: return 3.5
        }
    }

    var themeColor: SIMD3<Float> {
        switch self {
        case .level1: return SIMD3<Float>(1.0, 0.91, 0.65)
        case .level2: return SIMD3<Float>(0.80, 0.86, 0.22)
        case .level3: return SIMD3<Float>(1.0, 0.91, 0.65)
        case .level4: return SIMD3<Float>(0.80, 0.86, 0.22)
        case .level5: return SIMD3<Float>(1.0, 0.91, 0.65)
        case .level6: return SIMD3<Float>(1.0, 0.91, 0.65)
        }
    }

    var isUnlocked: Bool {
        UserProfile.shared.currentRealm.availableLevels.contains(self)
    }
}
