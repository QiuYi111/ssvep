import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    var body: some View {
        ZStack {
            backgroundLayer
            StarfieldHomeCanvas()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                titleSection

                LevelGridView { level in
                    appState.currentScreen = .session(level)
                }
                .frame(maxWidth: 860)
                .padding(.horizontal, 40)

                Spacer(minLength: 20)
            }
            .padding(.top, 54)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")
            }
        }
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.06, green: 0.06, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text("星空与萤火")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.92, blue: 0.68),
                            Color(red: 0.72, green: 0.82, blue: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("在星光中找到专注的力量")
                .font(.system(size: 15, weight: .light, design: .serif))
                .foregroundStyle(.white.opacity(0.56))

            Text(UserProfile.shared.currentRealm.displayName)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(Color(red: 0.80, green: 0.86, blue: 0.22).opacity(0.76))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.06))
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .padding(.top, 8)
        }
    }
}

private struct StarfieldHomeCanvas: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let horizonY = size.height * 0.72

                for i in 0..<120 {
                    let seed = Double(i)
                    let x = CGFloat(fract(sin(seed * 12.9898) * 43758.5453)) * size.width
                    let y = CGFloat(fract(sin(seed * 78.233) * 21413.1415)) * horizonY
                    let twinkle = 0.35 + 0.65 * (sin(time * (0.5 + seed.truncatingRemainder(dividingBy: 5) * 0.12) + seed) * 0.5 + 0.5)
                    let radius = CGFloat(0.6 + fract(sin(seed * 3.17) * 97.13) * 1.4)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(.white.opacity(0.08 * twinkle))
                    )
                }

                let glowCenter = CGPoint(x: size.width * 0.52, y: size.height * 0.36)
                let glowRadius = min(size.width, size.height) * 0.38
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: glowCenter.x - glowRadius,
                        y: glowCenter.y - glowRadius,
                        width: glowRadius * 2,
                        height: glowRadius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.80, green: 0.86, blue: 0.22).opacity(0.08),
                            Color(red: 0.54, green: 0.70, blue: 0.98).opacity(0.035),
                            .clear
                        ]),
                        center: glowCenter,
                        startRadius: 0,
                        endRadius: glowRadius
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}
