import SwiftUI

struct SessionHUDView: View {
    let elapsedTime: TimeInterval
    let opacity: Double
    let isVisible: Bool

    var body: some View {
        VStack {
            Text(formattedTime)
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.3))
                )
                .padding(.top, 24)

            Spacer()
        }
        .opacity(isVisible ? opacity : 0.0)
        .animation(.easeOut(duration: 1.0), value: isVisible)
        .accessibilityHidden(true)
    }

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
