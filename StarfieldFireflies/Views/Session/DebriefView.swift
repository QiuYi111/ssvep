import SwiftUI

struct DebriefView: View {
    let level: LevelID
    let focusDuration: TimeInterval
    let flowMoments: Int
    let peakAttention: Float
    let attentionWaveform: [Float]
    let onDismiss: () -> Void

    @State private var mandalaScale: CGFloat = 0.01
    @State private var mandalaRotation: Double = -30
    @State private var contentOpacity: Double = 0
    @State private var metricsOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focusRatio: CGFloat {
        CGFloat(min(1.0, focusDuration / level.trainingDuration))
    }

    private var resilienceScore: Float {
        guard !attentionWaveform.isEmpty else { return 0 }
        let recoveries = attentionWaveform.enumerated().reduce(0) { count, entry in
            guard entry.offset > 0 else { return count }
            let prev = attentionWaveform[entry.offset - 1]
            let curr = entry.element
            return (prev < 0.4 && curr >= 0.6) ? count + 1 : count
        }
        return min(1.0, Float(recoveries) / Float(max(1, attentionWaveform.count)) * 20)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.010, green: 0.012, blue: 0.024),
                    Color(red: 0.028, green: 0.034, blue: 0.062),
                    Color(red: 0.010, green: 0.014, blue: 0.026)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            DebriefStarfield()
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 32) {
                    mandalaSection
                    levelTitle
                    metricsRow
                    dismissButton
                }
                .padding(.horizontal, 48)
                .padding(.top, 50)
                .padding(.bottom, 60)
            }
        }
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.3 : 1.0)) {
                contentOpacity = 1.0
            }

            withAnimation(
                .spring(response: reduceMotion ? 0.3 : 1.8, dampingFraction: 0.6)
            ) {
                mandalaScale = 1.0
                mandalaRotation = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.3 : 1.2)) {
                withAnimation(.easeOut(duration: 0.8)) {
                    metricsOpacity = 1.0
                }
            }
        }
    }

    private var mandalaSection: some View {
        MandalaCanvasView(
            waveform: attentionWaveform,
            accentColor: level.cardConfig.color,
            symmetryFolds: 8
        )
        .frame(width: 360, height: 360)
        .scaleEffect(mandalaScale)
        .rotationEffect(.degrees(mandalaRotation))
        .accessibilityLabel("心念图谱")
        .accessibilityValue("本次训练的注意力曼陀罗")
    }

    private var levelTitle: some View {
        VStack(spacing: 6) {
            Text(level.displayName)
                .font(.system(size: 24, weight: .ultraLight, design: .serif))
                .foregroundStyle(.white.opacity(0.9))

            Text("心念图谱")
                .font(.system(size: 13, weight: .thin, design: .serif))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 24) {
            TranceDepthGauge(ratio: focusRatio)
            ResilienceShield(score: resilienceScore)
            FlowMomentsView(count: flowMoments)
            PeakAttentionView(value: peakAttention)
        }
        .frame(maxWidth: 620)
        .opacity(metricsOpacity)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .light))
                Text("返回星空")
                    .font(.system(size: 15, weight: .ultraLight, design: .serif))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(metricsOpacity)
        .padding(.top, 12)
    }
}

private struct MandalaCanvasView: View {
    let waveform: [Float]
    let accentColor: Color
    let symmetryFolds: Int

    var body: some View {
        Canvas { ctx, size in
            guard !waveform.isEmpty else {
                drawEmptyMandala(ctx: ctx, size: size)
                return
            }

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2 - 16
            let folds = symmetryFolds
            let sectorAngle = .pi * 2 / Double(folds)
            let samplesPerSector = max(1, waveform.count / folds)

            for fold in 0..<folds {
                let baseAngle = sectorAngle * Double(fold)

                let petalColor = Color(
                    red: 0.80,
                    green: 0.86 + Double(fold % 2) * 0.05,
                    blue: 0.22 + Double(fold % 3) * 0.08
                )

                let petalPath = buildPetalPath(
                    samplesPerSector: samplesPerSector,
                    fold: fold,
                    folds: folds,
                    sectorAngle: sectorAngle,
                    maxRadius: maxRadius
                )

                let rotatedPetal = petalPath.applying(
                    CGAffineTransform(rotationAngle: baseAngle)
                        .translatedBy(x: center.x, y: center.y)
                )

                ctx.opacity = 0.35
                ctx.fill(rotatedPetal, with: .color(petalColor))
                ctx.opacity = 0.7
                ctx.stroke(rotatedPetal, with: .color(petalColor.opacity(0.9)), lineWidth: 1.2)

                let mirrorPetal = petalPath.applying(
                    CGAffineTransform(translationX: -center.x, y: -center.y)
                        .scaledBy(x: 1, y: -1)
                        .rotated(by: baseAngle)
                        .translatedBy(x: center.x, y: center.y)
                )

                ctx.opacity = 0.2
                ctx.fill(mirrorPetal, with: .color(petalColor))
                ctx.opacity = 0.5
                ctx.stroke(mirrorPetal, with: .color(petalColor.opacity(0.6)), lineWidth: 0.8)
            }

            ctx.opacity = 1

            let coreR: CGFloat = 8
            let coreGrad = Gradient(colors: [
                Color(red: 0.93, green: 0.90, blue: 0.55).opacity(0.7),
                accentColor.opacity(0.3),
                .clear
            ])
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - coreR * 4, y: center.y - coreR * 4, width: coreR * 8, height: coreR * 8)),
                with: .radialGradient(coreGrad, center: center, startRadius: 0, endRadius: coreR * 4)
            )
        }
    }

    private func buildPetalPath(
        samplesPerSector: Int,
        fold: Int,
        folds: Int,
        sectorAngle: Double,
        maxRadius: CGFloat
    ) -> Path {
        var petalPath = Path()
        for i in 0..<min(samplesPerSector, waveform.count) {
            let idx = min(i + fold * samplesPerSector, waveform.count - 1)
            let value = waveform[idx]
            let normalizedAngle = sectorAngle * Double(i) / Double(samplesPerSector)

            let outerR = CGFloat(value) * maxRadius * 0.8 + maxRadius * 0.15
            let px = cos(normalizedAngle) * outerR
            let py = sin(normalizedAngle) * outerR

            if i == 0 {
                petalPath.move(to: CGPoint(x: px, y: py))
            } else {
                petalPath.addLine(to: CGPoint(x: px, y: py))
            }
        }
        return petalPath
    }

    private func drawEmptyMandala(ctx: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height)
        let accent = Color(red: 0.93, green: 0.86, blue: 0.54)

        for i in 0..<7 {
            let r = base * (0.08 + Double(i) * 0.055)
            ctx.stroke(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .color(accent.opacity(0.08 + Double(i) * 0.015)),
                lineWidth: i == 3 ? 1.2 : 0.7
            )
        }

        for i in 0..<48 {
            let angle = Double(i) / 48.0 * .pi * 2
            let r1 = base * 0.07
            let r2 = base * (0.33 + Double(i % 5) * 0.006)
            var path = Path()
            path.move(to: CGPoint(x: center.x + cos(angle) * r1, y: center.y + sin(angle) * r1))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * r2, y: center.y + sin(angle) * r2))
            ctx.stroke(path, with: .color(accent.opacity(i % 4 == 0 ? 0.16 : 0.055)), lineWidth: i % 4 == 0 ? 0.8 : 0.45)
        }

        let core = CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)
        ctx.fill(
            Path(ellipseIn: core),
            with: .radialGradient(
                Gradient(colors: [accent.opacity(0.72), accent.opacity(0.16), .clear]),
                center: center,
                startRadius: 0,
                endRadius: 34
            )
        )
    }
}

private struct DebriefStarfield: View {
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<120 {
                let x = CGFloat((i * 73) % 997) / 997.0 * size.width
                let y = CGFloat((i * 47) % 991) / 991.0 * size.height
                let radius = CGFloat(1 + (i % 3)) * 0.35
                let opacity = Double(0.04 + CGFloat(i % 7) * 0.015)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                    with: .color(.white.opacity(opacity))
                )
            }

            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - 210, y: center.y - 210, width: 420, height: 420)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.78, green: 0.82, blue: 0.38).opacity(0.11),
                        Color(red: 0.20, green: 0.36, blue: 0.48).opacity(0.05),
                        .clear
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: 210
                )
            )
        }
    }
}

private struct TranceDepthGauge: View {
    let ratio: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 3)
                    .frame(width: 52, height: 52)

                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.80, green: 0.86, blue: 0.22).opacity(0.5),
                                Color(red: 0.93, green: 0.90, blue: 0.55)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))
            }

            Text("定力深度")
                .font(.system(size: 11, weight: .thin, design: .serif))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("定力深度 \(Int(ratio * 100))%")
    }
}

private struct ResilienceShield: View {
    let score: Float

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: "shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        RadialGradient(
                            colors: [
                                Color(red: 0.60, green: 0.70, blue: 0.90).opacity(Double(score)),
                                Color(red: 0.30, green: 0.35, blue: 0.50).opacity(0.3)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 14
                        )
                    )
                    .frame(width: 52, height: 52)
            }

            Text("抗扰韧性")
                .font(.system(size: 11, weight: .thin, design: .serif))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("抗扰韧性")
    }
}

private struct FlowMomentsView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(0..<min(count, 5), id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.93, green: 0.85, blue: 0.55).opacity(0.7))
                        .offset(x: CGFloat(i - min(count, 5) / 2) * 10, y: CGFloat(i % 2 == 0 ? -4 : 4))
                }
                .frame(width: 52, height: 52)
            }

            Text("心流时刻")
                .font(.system(size: 11, weight: .thin, design: .serif))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("心流时刻 \(count)")
    }
}

private struct PeakAttentionView: View {
    let value: Float

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.93, green: 0.85, blue: 0.55).opacity(Double(value) * 0.8),
                                Color.white.opacity(0.04)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(Double(value) * 0.9 + 0.1))
            }

            Text("巅峰专注")
                .font(.system(size: 11, weight: .thin, design: .serif))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("巅峰专注")
    }
}
