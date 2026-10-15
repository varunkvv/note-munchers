import SwiftUI

/// Picture-only "turn on the piano" screen. Shown until a MIDI source shows up,
/// before a session and whenever the piano drops mid-session.
struct TurnOnPianoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Theme.paper.ignoresSafeArea()
                HStack(spacing: s * 0.08) {
                    VStack(spacing: s * 0.03) {
                        Image(systemName: "pianokeys")
                            .font(.system(size: s * 0.26, weight: .regular))
                            .foregroundStyle(Theme.ink)
                        Image(systemName: "cable.connector")
                            .font(.system(size: s * 0.1, weight: .semibold))
                            .foregroundStyle(Theme.parentIcon)
                    }
                    ZStack {
                        Circle()
                            .fill(Theme.button.opacity(pulse ? 0.32 : 0.14))
                            .frame(width: s * 0.36, height: s * 0.36)
                        Image(systemName: "power")
                            .font(.system(size: s * 0.17, weight: .bold))
                            .foregroundStyle(Theme.button)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
