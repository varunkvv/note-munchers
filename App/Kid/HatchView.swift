import NoteCore
import SwiftUI

/// A new muncher hatches and he picks its colour (autonomy: it's his muncher).
/// The egg rocks three times, a little more each time, then cracks and a pale baby pops
/// out. Then two big munchers stand side by side: the same muncher in two colours drawn
/// at random from `MuncherLook.pickable`, with "Pick a color!" under them. He taps the
/// one he wants, it does a happy hop, the other fades, and practice carries on. No
/// clock: the session waits for him.
struct HatchView: View {
    let controller: PracticeController
    let id: ItemID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var hatched = false
    /// the two colours he picks between, and the muncher they were drawn for
    @State private var offered: [Int]
    @State private var offeredFor: ItemID
    /// the two munchers have stepped out to the sides
    @State private var spread = false
    @State private var chosen: Int?
    @State private var hop = false
    @State private var centered = false

    init(controller: PracticeController, id: ItemID) {
        self.controller = controller
        self.id = id
        _offered = State(initialValue: Self.drawPair())
        _offeredFor = State(initialValue: id)
    }

    private var hatchLength: Double { 2.2 * controller.timeScale }
    /// the rocks before the crack. They take the place of the first 35% of
    /// `hatchLength` (the old steady wobble), so the crack shows the moment they end
    private var rockLength: Double { reduceMotion ? 0 : Self.rocksEnd * controller.timeScale }
    /// when the crack shows, as hatch progress
    private static let crackAt = 0.35

    /// start, end (seconds, before timeScale) and size (radians) of each rock: about 4,
    /// 7 and 10 degrees, with a short still moment between them
    private static let rocks: [(start: Double, end: Double, size: Double)] = [
        (0.2, 0.6, 0.07), (0.9, 1.35, 0.12), (1.6, 2.1, 0.18),
    ]
    /// the rocks end here, and the crack comes right after
    private static var rocksEnd: Double { rocks.last!.end + 0.1 }

    /// Two different colours, at random.
    static func drawPair() -> [Int] {
        Array(MuncherLook.pickable.shuffled().prefix(2))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let gap = size.width * 0.05
            let side = min(size.height * 0.62, (size.width - 3 * gap) / 2)
            ZStack {
                // fully opaque: the note he's about to meet must not show through
                Theme.paper.ignoresSafeArea()
                if hatched {
                    ForEach(Array(offered.enumerated()), id: \.element) { slot, color in
                        choice(color, slot: slot, side: side, gap: gap, in: size)
                    }
                } else {
                    egg(side: side, in: size)
                }
                // under the two munchers, between their floor and the bottom edge
                Text("Pick a color!")
                    .font(Theme.kidFont(min(60, size.height * 0.07), weight: .heavy))
                    .foregroundStyle(Theme.kidText)
                    .position(x: size.width / 2, y: (size.height / 2 + side / 2 + size.height) / 2)
                    .opacity(hatched && spread && chosen == nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4).delay(hatched && chosen == nil ? 0.35 : 0), value: chosen == nil && spread)
            }
        }
        .task(id: id) {
            if offeredFor != id {
                offered = Self.drawPair()
                offeredFor = id
            }
            start = Date()
            hatched = false
            spread = false
            chosen = nil
            hop = false
            centered = false
            try? await Task.sleep(for: .seconds(rockLength + hatchLength * (0.55 - Self.crackAt)))
            guard !Task.isCancelled else { return }
            controller.playHatchPop()
            try? await Task.sleep(for: .seconds(hatchLength * 0.45))
            guard !Task.isCancelled else { return }
            hatched = true
            // the pale baby steps out into two coloured munchers, one each side
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.35)) { spread = true }
            #if DEBUG
            if let wait = controller.demoAutoPick {
                try? await Task.sleep(for: .seconds(wait))
                if chosen == nil, !Task.isCancelled {
                    // one of the two on screen, never some other colour
                    pick(offered[Int(MuncherLook.fnv1a(id) % UInt64(offered.count))])
                }
            }
            #endif
        }
    }

    /// The egg stands on the same floor as the two munchers he picks from, and the baby
    /// grows into exactly the spot where they start (both together, small, in the
    /// middle), so the hand-over doesn't jump.
    private func egg(side: CGFloat, in size: CGSize) -> some View {
        let floor = size.height / 2 + side / 2
        let small = side * Self.startScale
        // the choice's canvas scaled about its bottom: the muncher is drawn in its top 96%
        let baby = CGRect(x: size.width / 2 - small / 2, y: floor - small, width: small, height: small * 0.96)
        let e = min(size.width, size.height) * 0.42
        let eggRect = CGRect(x: size.width / 2 - e / 2, y: baby.maxY + e * 0.04 - e, width: e, height: e)
        return TimelineView(.animation(paused: hatched)) { timeline in
            Canvas { context, _ in
                let elapsed = timeline.date.timeIntervalSince(start)
                // rocks first, then the crack and the rest of the hatch as before
                let p = elapsed < rockLength ? 0 : Self.crackAt + (elapsed - rockLength) / hatchLength
                // spots in the two colours he'll pick between, and a pale baby inside
                EggPainter(
                    look: .uncolored(id: id), progress: min(1, p), spotColors: offered.map(MuncherLook.swatch),
                    babyRect: baby, babyFluency: Self.fluency,
                    rock: elapsed < rockLength ? Self.rock(at: elapsed / controller.timeScale) : 0
                )
                .draw(in: &context, rect: eggRect, id: id)
            }
        }
    }

    /// The egg's tilt `t` seconds into the rocks: each rock is one smooth tip to the side
    /// and back the other way, starting and ending still.
    static func rock(at t: Double) -> Double {
        guard let r = rocks.first(where: { t >= $0.start && t < $0.end }) else { return 0 }
        let x = (t - r.start) / (r.end - r.start)
        return r.size * sin(2 * .pi * x) * sin(.pi * x)
    }

    /// how big the two munchers are before they step out to the sides
    private static let startScale = 0.45
    /// hatch munchers show who they are from day one
    private static let fluency = 0.15

    private func choice(_ color: Int, slot: Int, side: CGFloat, gap: CGFloat, in size: CGSize) -> some View {
        let isChosen = chosen == color
        let outward = (side + gap) / 2 * (slot == 0 ? -1 : 1)
        let x = size.width / 2 + (spread && !(isChosen && centered) ? outward : 0)
        let look = MuncherLook(id: id, colorIndex: color)
        return Button {
            pick(color)
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || chosen != nil)) { timeline in
                Canvas { context, canvas in
                    // a soft shadow on the floor
                    let floor = CGRect(x: canvas.width * 0.24, y: canvas.height * 0.93, width: canvas.width * 0.52, height: canvas.height * 0.05)
                    context.fill(Path(ellipseIn: floor), with: .color(.black.opacity(0.06)))
                    var pose = MuncherPose(fluency: Self.fluency, mouthOpen: isChosen ? 0.55 : 0)
                    if !reduceMotion, chosen == nil {
                        // the two take turns bobbing, as if each is saying "me!"
                        let phase = timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.6 + Double(slot) * .pi
                        pose.bob = 6 * (1 + sin(phase)) / 2
                    }
                    MuncherPainter(look: look, pose: pose).draw(in: &context, rect: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height * 0.96))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(chosen == nil)
        .scaleEffect(spread ? (hop && isChosen ? 1.1 : 1) : Self.startScale, anchor: .bottom)
        .offset(y: hop && isChosen ? -side * 0.06 : 0)
        .scaleEffect(chosen != nil && !isChosen ? 0.85 : 1)
        .opacity(chosen == nil || isChosen ? 1 : 0)
        .position(x: x, y: size.height / 2)
    }

    private func pick(_ index: Int) {
        guard chosen == nil, hatched else { return }
        withAnimation(.easeOut(duration: 0.35)) { chosen = index }
        controller.playHatchPop()
        if !reduceMotion {
            withAnimation(.spring(duration: 0.3, bounce: 0.6).delay(0.1)) { hop = true }
            withAnimation(.spring(duration: 0.3, bounce: 0.4).delay(0.45)) { hop = false }
            withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.5)) { centered = true }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.1 * controller.timeScale))
            controller.chooseColor(index, for: id)
        }
    }
}
