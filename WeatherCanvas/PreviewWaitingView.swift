import SwiftUI

/// Feedback for the selected preview, without covering its editing controls.
struct PreviewWaitingView: View {
    let title: String
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion && isActive {
                Ellipse()
                    .fill(.linearGradient(colors: [.orange.opacity(0.18), .purple.opacity(0.24), .clear],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 210, height: 110)
                    .blur(radius: 35)
                    .phaseAnimator([false, true]) { light, expanded in
                        light.scaleEffect(expanded ? 1.1 : 0.95)
                            .opacity(expanded ? 0.85 : 0.4)
                    } animation: { _ in .easeInOut(duration: 3.8) }
                    .accessibilityHidden(true)
            }
            VStack(spacing: 14) {
                if reduceMotion || !isActive {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .light))
                        .symbolEffect(.breathe)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(.primary)
            .padding(24)
        }
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
