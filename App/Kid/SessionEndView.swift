import NoteCore
import SwiftUI

/// "look who ate well today": the munchers he fed this session, full and happy,
/// growing from their size before the session to their size now. New ones that
/// hatched get a sparkle. The voice says the line, the screen has no text.
struct SessionEndView: View {
    let summary: SessionSummary
    let onHome: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    struct Fed: Identifiable {
        let id: ItemID
        let before: Double
        let after: Double
        let isNew: Bool
    }

    static func fed(_ summary: SessionSummary) -> [Fed] {
        let new = Set(summary.unlocked)
        var list = summary.practiced.map { Fed(id: $0.id, before: $0.fluencyBefore, after: $0.fluencyAfter, isNew: new.contains($0.id)) }
        for id in summary.unlocked where !list.contains(where: { $0.id == id }) {
            list.append(Fed(id: id, before: 0, after: 0, isNew: true))
        }
        return list
    }

    var body: some View {
        let fed = Self.fed(summary)
        GeometryReader { proxy in
            let columns = max(1, min(fed.count, Int(proxy.size.width / 230)))
            let rows = (fed.count + columns - 1) / columns
            let room = proxy.size.height - 170
            // a session feeds at most its item count, so everything fits without scrolling
            let height = min(280, max(60, (room - 64) / CGFloat(max(1, rows)) - 24))
            ZStack {
                Theme.paper.ignoresSafeArea()
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns), spacing: 24) {
                        ForEach(fed) { item in
                            muncher(item)
                                .frame(height: height)
                        }
                    }
                    .padding(32)
                    .frame(maxHeight: room, alignment: .center)
                    Button(action: onHome) {
                        ZStack {
                            Circle().fill(Theme.button).shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                            Image(systemName: "house.fill")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 110, height: 110)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 28)
                }
            }
        }
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.spring(duration: 1.4, bounce: 0.45).delay(0.7)) { grown = true }
            }
        }
    }

    private func muncher(_ item: Fed) -> some View {
        GrowingMuncher(id: item.id, fluency: grown ? item.after : item.before)
            .overlay(alignment: .topTrailing) {
                if item.isNew {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.sparkle)
                }
            }
    }
}

/// Animates fluency itself, so the muncher is redrawn at full resolution every frame.
/// (A scaleEffect on the Canvas came out blurry: it was rasterized at the small size.)
struct GrowingMuncher: View, Animatable {
    let id: ItemID
    var fluency: Double

    var animatableData: Double {
        get { fluency }
        set { fluency = newValue }
    }

    var body: some View {
        MuncherView(id: id, pose: MuncherPose(fluency: fluency, full: true))
    }
}
