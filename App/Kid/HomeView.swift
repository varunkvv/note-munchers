import NoteCore
import SwiftUI

/// The kid's start screen: a big play button. No text.
struct HomeView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Theme.paper.ignoresSafeArea()
                PlayButton(size: s * 0.3) { model.startPractice() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            ParentGate { model.showParent = true }
        }
    }
}

struct PlayButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.button)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: size * 0.04)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}
