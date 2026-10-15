import NoteCore
import SwiftUI

/// A new muncher hatches and he picks its colour (autonomy: it's his muncher).
/// Big egg in the middle, then the pale baby and six big colour swatches. Tapping a
/// swatch colours it, it does a happy hop, and practice carries on. No text, and no
/// clock: the session waits for him.
struct HatchView: View {
    let controller: PracticeController
    let id: ItemID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var hatched = false
    @State private var chosen: Int?
    @State private var hop = false

    private var hatchLength: Double { 2.2 * controller.timeScale }

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Theme.paper.opacity(0.97).ignoresSafeArea()
                VStack(spacing: s * 0.06) {
                    TimelineView(.animation(paused: hatched)) { timeline in
                        Canvas { context, size in
                            let rect = CGRect(origin: .zero, size: size)
                            if hatched {
                                let look = chosen.map { MuncherLook(id: id, colorIndex: $0) } ?? .uncolored(id: id)
                                MuncherPainter(look: look, pose: MuncherPose(fluency: 0.15, mouthOpen: chosen == nil ? 0 : 0.5))
                                    .draw(in: &context, rect: rect)
                            } else {
                                let p = timeline.date.timeIntervalSince(start) / hatchLength
                                EggPainter(look: MuncherLook(id: id), progress: min(1, p)).draw(in: &context, rect: rect, id: id)
                            }
                        }
                    }
                    .frame(width: s * 0.42, height: s * 0.42)
                    .scaleEffect(hop ? 1.12 : 1, anchor: .bottom)
                    .offset(y: hop ? -s * 0.04 : 0)

                    HStack(spacing: s * 0.035) {
                        ForEach(MuncherLook.pickable, id: \.self) { index in
                            Button {
                                pick(index)
                            } label: {
                                Circle()
                                    .fill(MuncherLook.swatch(index))
                                    .overlay(Circle().stroke(.white, lineWidth: chosen == index ? 8 : 0))
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                                    .frame(width: s * 0.11, height: s * 0.11)
                                    .scaleEffect(chosen == index ? 1.15 : 1)
                            }
                            .buttonStyle(.plain)
                            .disabled(chosen != nil)
                        }
                    }
                    .opacity(hatched ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: id) {
            start = Date()
            hatched = false
            chosen = nil
            try? await Task.sleep(for: .seconds(hatchLength * 0.55))
            controller.playHatchPop()
            try? await Task.sleep(for: .seconds(hatchLength * 0.45))
            withAnimation(.easeOut(duration: 0.3)) { hatched = true }
            controller.sayPickColor()
            #if DEBUG
            if let wait = controller.demoAutoPick {
                try? await Task.sleep(for: .seconds(wait))
                if chosen == nil, !Task.isCancelled {
                    pick(MuncherLook.pickable[Int(MuncherLook.fnv1a(id) % UInt64(MuncherLook.pickable.count))])
                }
            }
            #endif
        }
    }

    private func pick(_ index: Int) {
        guard chosen == nil else { return }
        withAnimation(.spring(duration: 0.25)) { chosen = index }
        controller.playHatchPop()
        if !reduceMotion {
            withAnimation(.spring(duration: 0.3, bounce: 0.6).delay(0.15)) { hop = true }
            withAnimation(.spring(duration: 0.3, bounce: 0.4).delay(0.5)) { hop = false }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.1 * controller.timeScale))
            controller.chooseColor(index, for: id)
        }
    }
}
