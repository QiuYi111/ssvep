import Observation
import Foundation

@Observable
final class AppState {

    var currentScreen: AppScreen = .home

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    init() {
        if !hasCompletedOnboarding {
            currentScreen = .onboarding
        }
    }
}

enum AppScreen: Hashable {
    case onboarding
    case home
    case session(LevelID)
}
