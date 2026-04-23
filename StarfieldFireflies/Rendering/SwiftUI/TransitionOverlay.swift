//
//  TransitionOverlay.swift
//  StarfieldFireflies
//
//  Scene transition overlay for level switching.
//  Fade-to-black / dissolve animation with customizable duration.
//

import SwiftUI

struct TransitionOverlay: View {

    let isActive: Bool
    let progress: Float  // [0, 1] transition progress
    let style: TransitionStyle

    enum TransitionStyle {
        case fadeToBlack
        case dissolve
        case crossDissolve
    }

    var body: some View {
        ZStack {
            switch style {
            case .fadeToBlack:
                Color.black
                    .opacity(isActive ? Double(progress) : 0.0)

            case .dissolve:
                Color.black
                    .opacity(isActive ? Double(progress) * 0.8 : 0.0)
                    .blur(radius: isActive ? CGFloat(progress) * 20 : 0)

            case .crossDissolve:
                Color.black
                    .opacity(isActive ? Double(smoothstep(0.0, 0.5, progress)) : 0.0)
                    .animation(.easeInOut(duration: 0.3), value: isActive)
            }
        }
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.05), value: progress)
    }

    // MARK: - Helpers

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Transition Coordinator

final class TransitionCoordinator: ObservableObject {

    @Published var isActive = false
    @Published var progress: Float = 0.0
    @Published var style: TransitionOverlay.TransitionStyle = .fadeToBlack

    private var duration: TimeInterval = 1.0
    private var startTime: TimeInterval = 0
    private var onMidpoint: (() -> Void)?
    private var onCompletion: (() -> Void)?
    private var displayLink: CVDisplayLink?
    private var midpointFired = false

    func startTransition(
        duration: TimeInterval = 1.0,
        style: TransitionOverlay.TransitionStyle = .fadeToBlack,
        onMidpoint: @escaping () -> Void,
        onCompletion: @escaping () -> Void = {}
    ) {
        self.duration = duration
        self.style = style
        self.onMidpoint = onMidpoint
        self.onCompletion = onCompletion
        self.startTime = CACurrentMediaTime()
        self.midpointFired = false
        self.isActive = true
        self.progress = 0.0

        startDisplayLink()
    }

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else { return }
        self.displayLink = displayLink

        let coordinator = self
        CVDisplayLinkSetOutputCallback(displayLink, { _, _, _, _, _, userInfo -> CVReturn in
            let coord = Unmanaged<TransitionCoordinator>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async { coord.tick() }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(coordinator).toOpaque())

        CVDisplayLinkStart(displayLink)
    }

    private func tick() {
        let elapsed = Float(CACurrentMediaTime() - startTime)
        let halfDuration = Float(duration) / 2.0

        if elapsed < halfDuration {
            // Phase 1: fade out (0 → 1)
            progress = elapsed / halfDuration
        } else if elapsed < Float(duration) {
            // Fire midpoint callback
            if !midpointFired {
                midpointFired = true
                onMidpoint?()
            }
            // Phase 2: fade in (1 → 0)
            progress = 1.0 - (elapsed - halfDuration) / halfDuration
        } else {
            // Transition complete
            progress = 0.0
            isActive = false
            stopDisplayLink()
            onCompletion?()
        }
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    deinit {
        stopDisplayLink()
    }
}

#if DEBUG
#Preview("Fade to Black") {
    ZStack {
        Color.blue.opacity(0.3)
        TransitionOverlay(isActive: true, progress: 0.7, style: .fadeToBlack)
    }
    .frame(width: 400, height: 300)
}

#Preview("Dissolve") {
    ZStack {
        Color.green.opacity(0.3)
        TransitionOverlay(isActive: true, progress: 0.5, style: .dissolve)
    }
    .frame(width: 400, height: 300)
}
#endif
