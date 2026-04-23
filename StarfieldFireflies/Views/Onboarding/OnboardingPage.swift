import SwiftUI

struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(accentColor)
                .opacity(appeared ? 1.0 : 0.0)
                .offset(y: appeared ? 0 : 20)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 48)
            }
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let delay = reduceMotion ? 0.0 : 0.3
            let duration = reduceMotion ? 0.1 : 0.6
            withAnimation(.easeOut(duration: duration).delay(delay)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}
