//
//  OverlayView.swift
//  StarfieldFireflies
//
//  Transparent SwiftUI overlay for breathing guide and ambient text hints.
//  Allows hit-testing to pass through to underlying MetalView.
//

import SwiftUI

struct OverlayView: View {

    let sessionPhase: SessionPhase
    let breathPhase: Float  // [0, 1] animated breath cycle
    let level: LevelID

    var body: some View {
        ZStack {
            // Breathing guide circle (subtle, center of screen)
            if sessionPhase == .training || sessionPhase == .immersion {
                breathingGuide
            }

            // Ambient text hints (fade in/out based on session phase)
            ambientHints
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.0), value: sessionPhase)
    }

    // MARK: - Breathing Guide

    private var breathingGuide: some View {
        Circle()
            .stroke(
                Color.white.opacity(0.08 + Double(breathPhase) * 0.04),
                lineWidth: 1.5
            )
            .frame(
                width: 60 + CGFloat(breathPhase) * 20,
                height: 60 + CGFloat(breathPhase) * 20
            )
            .opacity(sessionPhase == .training ? 0.6 : 0.3)
    }

    // MARK: - Ambient Text Hints

    private var ambientHints: some View {
        VStack {
            Spacer()

            if sessionPhase == .calibration {
                Text("呼吸とともに、リラックスしてください")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.15))
                    .transition(.opacity)
            }

            if sessionPhase == .immersion {
                Text("光に意識を向けてください")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.12))
                    .transition(.opacity)
            }

            Spacer()
                .frame(height: 40)
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black
        OverlayView(
            sessionPhase: .training,
            breathPhase: 0.5,
            level: .level2
        )
    }
    .frame(width: 800, height: 600)
}
#endif
