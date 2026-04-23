// ============================================
// App/StarfieldFirefliesApp.swift
// StarfieldFireflies — 星空与萤火
// ============================================

import SwiftUI

@main
struct StarfieldFirefliesApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    configureWindowForProMotion()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1024, height: 768)
    }
}

// MARK: - Root View

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .onboarding:
                OnboardingView()
            case .home:
                NavigationStack {
                    HomeView()
                }
            case .session(let levelID):
                SessionContainerView(level: levelID)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: appState.currentScreen)
    }
}

// MARK: - Window Configuration

private func configureWindowForProMotion() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        guard let window = NSApplication.shared.windows.first else { return }

        window.backgroundColor = .black
        window.isOpaque = true
        window.styleMask.remove(.resizable)
    }
}
