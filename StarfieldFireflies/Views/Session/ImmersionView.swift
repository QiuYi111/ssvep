import SwiftUI

struct ImmersionView: View {
    let level: LevelID
    let onComplete: () -> Void

    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.3
    @State private var textOpacity: Double = 0
    @State private var particleOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let totalDuration: Double = 4.0

    private var themeColor: Color {
        let tc = level.themeColor
        return Color(red: Double(tc.x), green: Double(tc.y), blue: Double(tc.z))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ImmersionGlowCanvas(
                themeColor: themeColor,
                glowScale: glowScale,
                glowOpacity: glowOpacity,
                particleOpacity: particleOpacity
            )

            VStack {
                Spacer()
                Text(level.displayName)
                    .font(.system(size: 28, weight: .ultraLight, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
                    .opacity(textOpacity)
                    .padding(.bottom, 80)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                glowOpacity = 1
                glowScale = 1
                textOpacity = 1
                particleOpacity = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    onComplete()
                }
                return
            }

            withAnimation(.easeOut(duration: 2.0)) {
                glowOpacity = 1.0
                glowScale = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeIn(duration: 1.0)) {
                    particleOpacity = 1.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeIn(duration: 1.2)) {
                    textOpacity = 1.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                onComplete()
            }
        }
    }
}

private struct ImmersionGlowCanvas: View {
    let themeColor: Color
    let glowScale: CGFloat
    let glowOpacity: Double
    let particleOpacity: Double

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) * 0.35 * glowScale
            let rect = CGRect(
                x: center.x - maxR,
                y: center.y - maxR,
                width: maxR * 2,
                height: maxR * 2
            )

            if glowOpacity > 0.01 {
                let grad = Gradient(colors: [
                    themeColor.opacity(0.6 * glowOpacity),
                    themeColor.opacity(0.2 * glowOpacity),
                    themeColor.opacity(0.05 * glowOpacity),
                    .clear
                ])
                ctx.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        grad,
                        center: center,
                        startRadius: 0,
                        endRadius: maxR
                    )
                )
            }

            if particleOpacity > 0.01 {
                drawParticles(ctx: ctx, center: center, maxR: maxR)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawParticles(ctx: GraphicsContext, center: CGPoint, maxR: CGFloat) {
        var rng = SeededRandomGenerator(seed: 42)
        for _ in 0..<40 {
            let angle = rng.next() * .pi * 2
            let dist = rng.next() * maxR * 0.9
            let px = center.x + cos(angle) * dist
            let py = center.y + sin(angle) * dist
            let pSize = CGFloat(1.0 + rng.next() * 2.5)
            let alpha = Double(particleOpacity) * Double(0.3 + rng.next() * 0.7)
            ctx.fill(
                Path(ellipseIn: CGRect(x: px - pSize / 2, y: py - pSize / 2, width: pSize, height: pSize)),
                with: .color(Color.white.opacity(alpha))
            )
        }
    }
}

private struct SeededRandomGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(abs(seed) + 1)
    }

    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double((state >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF))
    }
}
