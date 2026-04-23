import Foundation

/// The four meditation realms from design.md Section 4.
enum MeditationRealm: Int, CaseIterable, Comparable, CustomStringConvertible {
    case foundation = 1    // 筑基
    case tranquility = 2   // 入静
    case clarity = 3       // 明心
    case flow = 4          // 心流
    
    var displayName: String {
        switch self {
        case .foundation:  return "筑基"
        case .tranquility: return "入静"
        case .clarity:     return "明心"
        case .flow:        return "心流"
        }
    }
    
    var englishName: String {
        switch self {
        case .foundation:  return "Foundation"
        case .tranquility: return "Tranquility"
        case .clarity:     return "Clarity"
        case .flow:        return "Flow"
        }
    }
    
    var description: String { displayName }
    
    /// Levels available at this realm
    var availableLevels: [LevelID] {
        switch self {
        case .foundation:  return [.level1, .level2]
        case .tranquility: return [.level1, .level2, .level3, .level4]
        case .clarity:     return [.level1, .level2, .level3, .level4, .level5, .level6]
        case .flow:        return [.level1, .level2, .level3, .level4, .level5, .level6]
        }
    }
    
    /// SSVEP recognition window in seconds
    var ssvepWindowDuration: TimeInterval {
        switch self {
        case .foundation:  return 4.0
        case .tranquility: return 3.0
        case .clarity:     return 2.0
        case .flow:        return 1.0
        }
    }
    
    /// SSVEP highlight area as fraction of screen (shrinks with advancement)
    var ssvepAreaFraction: Float {
        switch self {
        case .foundation:  return 0.05
        case .tranquility: return 0.04
        case .clarity:     return 0.03
        case .flow:        return 0.02
        }
    }
    
    /// Distractor intensity scale (0.0-1.0)
    var distractorIntensity: Float {
        switch self {
        case .foundation:  return 0.0
        case .tranquility: return 0.5
        case .clarity:     return 0.8
        case .flow:        return 1.0
        }
    }
    
    /// Whether weather effects are enabled
    var weatherEnabled: Bool { self >= .tranquility }
    
    /// Whether 40Hz RIFT hidden mode is available
    var riftModeAvailable: Bool { self >= .clarity }
    
    static func < (lhs: MeditationRealm, rhs: MeditationRealm) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
