import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.10)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingPage(
                        icon: "sparkles",
                        title: "欢迎来到星空与萤火",
                        description: "一段关于专注力的旅程\n在星光与萤火中找到内心的宁静",
                        accentColor: .cyan
                    )
                    .tag(0)

                    OnboardingPage(
                        icon: "eye",
                        title: "让目光融入星光",
                        description: "屏幕上的光点会以特定频率闪烁\n让目光自然地落在光点上",
                        accentColor: .cyan
                    )
                    .tag(1)

                    OnboardingPage(
                        icon: "star.fill",
                        title: "你的专注，点亮萤火",
                        description: "当你专注时，星空会变得明亮\n萤火虫会向你聚拢",
                        accentColor: .yellow
                    )
                    .tag(2)

                    OnboardingPage(
                        icon: "heart.fill",
                        title: "准备好了吗？",
                        description: "选择一个关卡，开始你的第一段旅程",
                        accentColor: .green
                    )
                    .tag(3)
                }
                .tabViewStyle(.automatic)

                pageIndicator

                if currentPage == 3 {
                    startButton
                } else {
                    skipButton
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(currentPage == index ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeOut(duration: 0.2), value: currentPage)
            }
        }
        .padding(.vertical, 16)
    }

    private var startButton: some View {
        Button {
            appState.hasCompletedOnboarding = true
            withAnimation(.easeInOut(duration: 0.6)) {
                appState.currentScreen = .home
            }
        } label: {
            Text("开始旅程")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.cyan.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("开始旅程")
        .accessibilityHint("完成引导，进入主界面")
    }

    private var skipButton: some View {
        Button {
            appState.hasCompletedOnboarding = true
            withAnimation(.easeInOut(duration: 0.6)) {
                appState.currentScreen = .home
            }
        } label: {
            Text("跳过")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("跳过引导")
    }
}
