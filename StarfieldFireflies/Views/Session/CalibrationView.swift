import SwiftUI

struct CalibrationView: View {
    let duration: TimeInterval
    let onComplete: () -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var ringAngles: [Double] = [0, 0, 0, 0, 0]
    @State private var signalQuality: Double = 0
    @State private var sweepPhase: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var textVisible: Bool = false
    @State private var completed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tickTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let ringSpeeds: [Double] = [0.15, -0.25, 0.4, -0.6, 0.9]

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.06)
                .ignoresSafeArea()

            AstrolabeRenderer(
                ringAngles: ringAngles,
                signalQuality: signalQuality,
                sweepPhase: sweepPhase,
                elapsed: elapsed,
                duration: duration
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            flashOverlay

            VStack {
                Spacer()
                Text("正在与宇宙的频率共鸣…")
                    .font(.system(size: 18, weight: .ultraLight, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.80, green: 0.86, blue: 0.22).opacity(0.9),
                                Color(red: 0.93, green: 0.85, blue: 0.55).opacity(0.7)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(textVisible ? 1 : 0)
                    .animation(.easeIn(duration: 1.5), value: textVisible)
                    .padding(.bottom, 80)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                textVisible = true
            }
        }
        .onReceive(tickTimer) { _ in
            let dt: Double = 1.0 / 60.0
            elapsed += dt
            let progress = elapsed / duration

            signalQuality = min(1.0, progress < 0.15
                ? progress / 0.15 * 0.6
                : 0.6 + (progress - 0.15) / 0.85 * 0.4
            )

            if !reduceMotion {
                for i in 0..<5 {
                    ringAngles[i] += ringSpeeds[i]
                }
                sweepPhase += 0.15
            }

            if progress >= 1.0 && !completed {
                completed = true
                textVisible = false
                withAnimation(.easeIn(duration: 0.6)) {
                    flashOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onComplete()
                }
            }
        }
        .accessibilityLabel("校准阶段")
        .accessibilityValue("星象仪校准中")
    }

    private var flashOverlay: some View {
        RadialGradient(
            colors: [
                Color(red: 1.0, green: 0.95, blue: 0.7).opacity(flashOpacity),
                Color(red: 0.80, green: 0.72, blue: 0.22).opacity(flashOpacity * 0.3),
                .clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 400
        )
        .allowsHitTesting(false)
    }
}

private struct AstrolabeRenderer: View {
    let ringAngles: [Double]
    let signalQuality: Double
    let sweepPhase: Double
    let elapsed: TimeInterval
    let duration: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) * 0.42
            let progress = elapsed / duration

            let glowR = maxR * 0.6
            let glowGrad = Gradient(colors: [
                golden.opacity(0.08 + signalQuality * 0.07),
                golden.opacity(0.02),
                .clear
            ])
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2)),
                with: .radialGradient(glowGrad, center: center, startRadius: 0, endRadius: glowR)
            )

            for i in 0..<5 {
                let ringProgress = max(0, min(1, (progress - Double(i) * 0.08) / 0.3))
                let ringRadius = maxR * (0.25 + Double(i) * 0.15) * ringProgress
                let lineW: CGFloat = i == 0 ? 2.5 : (i < 3 ? 1.8 : 1.2)
                let tickCount = (i + 3) * 6
                let ringOpacity = signalQuality * (0.3 + 0.5 * ringProgress)
                let ringColor = i % 2 == 0 ? golden.opacity(ringOpacity) : silver.opacity(ringOpacity)

                let ringRect = CGRect(x: -ringRadius, y: -ringRadius, width: ringRadius * 2, height: ringRadius * 2)
                let ringPath = Path(ellipseIn: ringRect)
                let rotatedRing = ringPath.applying(CGAffineTransform(rotationAngle: ringAngles[i] * .pi / 180.0))
                let centeredRing = rotatedRing.applying(CGAffineTransform(translationX: center.x, y: center.y))

                ctx.stroke(centeredRing, with: .color(ringColor), lineWidth: lineW)

                drawTicks(ctx: ctx, center: center, ringRadius: ringRadius, angle: ringAngles[i], tickCount: tickCount, ringOpacity: ringOpacity)

                if i == 0 && progress > 0.15 && progress < 0.85 {
                    drawSweepGlow(ctx: ctx, center: center, ringRadius: ringRadius)
                }
            }

            drawCenterJewel(ctx: ctx, center: center)
            drawNoise(ctx: ctx, center: center, maxR: maxR)
        }
    }

    private func drawTicks(ctx: GraphicsContext, center: CGPoint, ringRadius: CGFloat, angle: Double, tickCount: Int, ringOpacity: Double) {
        for t in 0..<tickCount {
            let tickAngle = Double(t) / Double(tickCount) * .pi * 2 + (angle * .pi / 180.0)
            let isMajor = t % max(1, tickCount / 6) == 0
            let tickLen: CGFloat = isMajor ? 8 : 4

            let x1 = center.x + cos(tickAngle) * (ringRadius - tickLen)
            let y1 = center.y + sin(tickAngle) * (ringRadius - tickLen)
            let x2 = center.x + cos(tickAngle) * ringRadius
            let y2 = center.y + sin(tickAngle) * ringRadius

            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x1, y: y1))
            tickPath.addLine(to: CGPoint(x: x2, y: y2))

            let tickOpacity = isMajor ? ringOpacity * 1.2 : ringOpacity * 0.5
            ctx.stroke(tickPath, with: .color(golden.opacity(min(1, tickOpacity))), lineWidth: isMajor ? 1.5 : 0.8)
        }
    }

    private func drawSweepGlow(ctx: GraphicsContext, center: CGPoint, ringRadius: CGFloat) {
        let sweepAngle = sweepPhase.truncatingRemainder(dividingBy: .pi * 2)
        let sx = center.x + cos(sweepAngle) * (ringRadius + 4)
        let sy = center.y + sin(sweepAngle) * (ringRadius + 4)

        let grad = Gradient(colors: [
            Color(red: 0.93, green: 0.85, blue: 0.55).opacity(0.8),
            golden.opacity(0.2),
            .clear
        ])
        ctx.fill(
            Path(ellipseIn: CGRect(x: sx - 12, y: sy - 12, width: 24, height: 24)),
            with: .radialGradient(grad, center: CGPoint(x: sx, y: sy), startRadius: 0, endRadius: 12)
        )
    }

    private func drawCenterJewel(ctx: GraphicsContext, center: CGPoint) {
        let jewelR: CGFloat = 6 + CGFloat(signalQuality * 4)
        let grad = Gradient(colors: [
            Color(red: 1.0, green: 0.95, blue: 0.7).opacity(0.9),
            golden.opacity(0.5),
            .clear
        ])
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - jewelR, y: center.y - jewelR, width: jewelR * 2, height: jewelR * 2)),
            with: .radialGradient(grad, center: center, startRadius: 0, endRadius: jewelR * 2)
        )
    }

    private func drawNoise(ctx: GraphicsContext, center: CGPoint, maxR: CGFloat) {
        guard signalQuality < 0.5 else { return }
        for _ in 0..<Int((1 - signalQuality) * 30) {
            let nx = CGFloat.random(in: center.x - maxR...center.x + maxR)
            let ny = CGFloat.random(in: center.y - maxR...center.y + maxR)
            let dist = hypot(nx - center.x, ny - center.y)
            if dist < maxR {
                let noiseSize = CGFloat.random(in: 1...3)
                let alpha = Double.random(in: 0.1...0.4)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: nx, y: ny, width: noiseSize, height: noiseSize)),
                    with: .color(Color.white.opacity(alpha * 0.3))
                )
            }
        }
    }

    private var golden: Color {
        Color(red: 0.80, green: 0.72, blue: 0.22)
    }

    private var silver: Color {
        Color(red: 0.72, green: 0.78, blue: 0.88)
    }
}
