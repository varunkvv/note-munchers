import NoteCore
import SwiftUI

/// His path through the level (plans/2026-10-16-progress-and-tunes.md, section 1): one
/// stepping stone per lesson, a flag at the end for the next level. Done stones are full,
/// the one he's on fills partway (`MasteryEngine.levelProgress`, which never goes
/// backwards). No numbers: the kid only ever sees the level number, in words, on home.
///
/// Two sizes. Home: big, with one of his munchers standing on his stone. The practice
/// lane: a thin quiet row of tiny stones, still except a short pop when a stone fills at
/// a lesson's end. The level-up splash walks the muncher to the flag.
struct LevelPathPainter {
    var stones: [Double]
    var current: Int?
    /// Where the muncher stands in stone units: 0 the first stone, `stones.count` the
    /// flag. nil = no muncher (the lane).
    var muncherAt: Double?
    var muncher: MuncherLook?
    var muncherFluency = 0.5
    /// A stone that just filled, and how far its pop is (0...1).
    var pop: (stone: Int, t: Double)?
    /// The flag going up when he reaches it (0 down ... 1 flying).
    var flag = 0.0
    var tiny = false

    static let done = Theme.button
    static let empty = Color(red: 0.88, green: 0.84, blue: 0.76)
    static let edge = Color(red: 0.62, green: 0.57, blue: 0.5)
    static let pennant = Theme.song

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let n = stones.count
        guard n > 0 else { return }
        let step = size.width / (CGFloat(n) + 1)
        let w = min(step * (tiny ? 0.62 : 0.74), tiny ? size.height * 1.4 : size.height * 0.5)
        let h = w * 0.52
        // stones sit along the bottom (the muncher and the flag stand above them)
        let base = size.height - h * (tiny ? 0.65 : 0.8)
        func center(_ i: Int) -> CGPoint {
            // a gentle wave, so it reads as a path and not a bar
            let wave = tiny ? 0 : (i.isMultiple(of: 2) ? -h * 0.18 : h * 0.18)
            return CGPoint(x: step * (CGFloat(i) + 0.5), y: base + wave)
        }
        let flagFoot = CGPoint(x: step * (CGFloat(n) + 0.5), y: base)

        // a dotted trail behind the stones, up to the flag
        var trail = Path()
        trail.move(to: center(0))
        for i in 1..<n { trail.addLine(to: center(i)) }
        trail.addLine(to: flagFoot)
        context.stroke(trail, with: .color(Self.edge.opacity(0.35)),
                       style: StrokeStyle(lineWidth: tiny ? 1.5 : 3, lineCap: .round, dash: tiny ? [2, 4] : [3, 9]))

        for i in 0..<n {
            var s = context
            let c = center(i)
            if let pop, pop.stone == i {
                // a short pop: up a little past full size and back
                let k = 1 + 0.35 * sin(.pi * min(1, max(0, pop.t)))
                s.translateBy(x: c.x, y: c.y)
                s.scaleBy(x: k, y: k)
                s.translateBy(x: -c.x, y: -c.y)
            }
            drawStone(&s, rect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), fill: stones[i], isCurrent: i == current)
        }
        drawFlag(&context, foot: flagFoot, height: min(base - 5, h * (tiny ? 2.1 : 2.6)), reached: stones.allSatisfy { $0 >= 1 })

        if let muncherAt, let muncher {
            // stands on a stone, or hops between them (the splash's walk to the flag)
            let i = Int(muncherAt.rounded(.down))
            let t = muncherAt - Double(i)
            let from = i >= n ? flagFoot : center(i)
            let to = i + 1 >= n ? flagFoot : center(i + 1)
            let x = from.x + (to.x - from.x) * t
            let y = from.y + (to.y - from.y) * t
            let side = w * 1.6
            let lift = side * 0.32 * sin(.pi * t)
            // at the flag he stands just before the pole, so the pennant shows going up
            let dx = muncherAt >= Double(n) - 0.001 ? -w * 0.85 : 0
            // feet on the stone's far edge, so its fill shows in front of him
            let rect = CGRect(x: x - side / 2 + dx, y: y - h * 0.32 - side - lift, width: side, height: side)
            var pose = MuncherPose(fluency: muncherFluency)
            pose.mouthOpen = t > 0.05 && t < 0.95 ? 0.5 : 0
            MuncherPainter(look: muncher, pose: pose, growth: 0.8...1.0).draw(in: &context, rect: rect)
        }
    }

    private func drawStone(_ context: inout GraphicsContext, rect: CGRect, fill: Double, isCurrent: Bool) {
        let shape = Path(ellipseIn: rect)
        context.fill(shape, with: .color(Self.empty))
        if fill > 0 {
            var inside = context
            inside.clip(to: shape)
            // fills from the left, the way he walks
            inside.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * min(1, fill), height: rect.height)),
                        with: .color(Self.done))
        }
        let line: CGFloat = tiny ? 1.5 : 3
        if isCurrent {
            context.stroke(shape, with: .color(Self.done.mix(with: .black, by: 0.25)), lineWidth: line * 1.6)
        } else {
            context.stroke(shape, with: .color(fill >= 1 ? Self.done.mix(with: .black, by: 0.2) : Self.edge.opacity(0.6)), lineWidth: line)
        }
    }

    private func drawFlag(_ context: inout GraphicsContext, foot: CGPoint, height: CGFloat, reached: Bool) {
        let pole = Path { p in
            p.move(to: foot)
            p.addLine(to: CGPoint(x: foot.x, y: foot.y - height))
        }
        context.stroke(pole, with: .color(Self.edge), style: StrokeStyle(lineWidth: tiny ? 2 : 4, lineCap: .round))
        // the pennant: half way down the pole until he gets there, then at the top
        let up = reached ? max(0.55, flag) : 0.55 + 0.45 * flag
        let top = foot.y - height * (0.45 + 0.55 * up)
        let size = height * 0.42
        let pennant = Path { p in
            p.move(to: CGPoint(x: foot.x, y: top))
            p.addLine(to: CGPoint(x: foot.x + size * 1.15, y: top + size * 0.42))
            p.addLine(to: CGPoint(x: foot.x, y: top + size * 0.84))
            p.closeSubpath()
        }
        context.fill(pennant, with: .color(Self.pennant))
        context.fill(Path(ellipseIn: CGRect(x: foot.x - 4, y: foot.y - height - 4, width: 8, height: 8)), with: .color(Self.edge))
    }

    /// The muncher that stands on his stone: his most grown one, so it's the same one
    /// from day to day (until another grows past it).
    static func guide(_ engine: MasteryEngine) -> NoteKey? {
        engine.metNotes.max { a, b in
            let fa = engine.stats(for: a).peakFluency, fb = engine.stats(for: b).peakFluency
            return fa != fb ? fa < fb : a > b
        }
    }
}

/// Home: "Level 2" in words over his path, with his muncher on his stone.
struct HomeLevelPath: View {
    let engine: MasteryEngine
    let width: CGFloat

    @Environment(MuncherColors.self) private var colors

    var body: some View {
        let path = engine.levelProgress
        let guide = LevelPathPainter.guide(engine)
        VStack(spacing: 2) {
            Text("Level \(path.level)")
                .font(Theme.kidFont(width * 0.12, weight: .heavy))
                .foregroundStyle(Theme.kidText)
            Canvas { context, size in
                LevelPathPainter(
                    stones: path.stones, current: path.current, muncherAt: path.current.map(Double.init),
                    muncher: guide.map { colors.look($0.id) }, muncherFluency: guide.map { engine.stats(for: $0).peakFluency } ?? 0.5
                ).draw(in: &context, size: size)
            }
            .frame(width: width, height: width * 0.42)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(path.level)")
    }
}

/// The practice lane: a thin row of tiny stones. It only moves when a lesson finishes:
/// that stone pops as it fills. Reduce motion: it just fills.
struct LaneLevelPath: View {
    let controller: PracticeController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop: (stone: Int, start: Date)?

    static let popLength = 0.45

    var body: some View {
        let engine = controller.session.engine
        let path = engine.levelProgress
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pop == nil)) { timeline in
            Canvas { context, size in
                let t = pop.map { timeline.date.timeIntervalSince($0.start) / (Self.popLength * controller.timeScale) }
                LevelPathPainter(stones: path.stones, current: path.current,
                                 pop: pop.flatMap { p in t.map { (stone: p.stone, t: $0) } }, tiny: true)
                    .draw(in: &context, size: size)
            }
        }
        .onChange(of: controller.session.summary.completedLessons.count) {
            // a lesson in this level just filled. the last one of a level gets the splash instead
            guard !reduceMotion, let done = controller.session.summary.completedLessons.last,
                  let i = engine.curriculum.level(path.level)?.lessons.firstIndex(where: { $0.id == done }) else { return }
            pop = (i, Date())
            Task {
                try? await Task.sleep(for: .seconds(Self.popLength * controller.timeScale + 0.05))
                pop = nil
            }
        }
        .accessibilityHidden(true)
    }
}
