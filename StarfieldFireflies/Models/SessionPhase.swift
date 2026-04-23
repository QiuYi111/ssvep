import Foundation

enum SessionPhase: Equatable, CaseIterable {
    case calibration
    case immersion
    case training
    case debrief

    var next: SessionPhase? {
        switch self {
        case .calibration:  return .immersion
        case .immersion:    return .training
        case .training:     return .debrief
        case .debrief:      return nil
        }
    }

    var displayTitle: String {
        switch self {
        case .calibration:  return "校准"
        case .immersion:    return "沉浸"
        case .training:     return "训练"
        case .debrief:      return "回顾"
        }
    }
}
