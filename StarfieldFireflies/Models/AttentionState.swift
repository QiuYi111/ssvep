import SwiftUI

enum AttentionState: Equatable, Hashable {
    case focused
    case neutral
    case distracted

    var normalizedValue: Float {
        switch self {
        case .focused:    return  1.0
        case .neutral:    return  0.0
        case .distracted: return -1.0
        }
    }

    var displayColor: Color {
        switch self {
        case .focused:    return Color.cyan.opacity(0.8)
        case .neutral:    return Color.white.opacity(0.5)
        case .distracted: return Color.orange.opacity(0.6)
        }
    }

    var simdColor: SIMD3<Float> {
        switch self {
        case .focused:    return SIMD3<Float>(0.0, 0.8, 1.0)
        case .neutral:    return SIMD3<Float>(0.5, 0.5, 0.5)
        case .distracted: return SIMD3<Float>(1.0, 0.5, 0.0)
        }
    }

    var glowIntensity: Float {
        switch self {
        case .focused:    return 1.0
        case .neutral:    return 0.4
        case .distracted: return 0.15
        }
    }

    var bloomStrength: Float {
        switch self {
        case .focused:    return 1.5
        case .neutral:    return 0.6
        case .distracted: return 0.2
        }
    }
}
