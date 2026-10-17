import NoteCore
import SwiftUI

/// The level-up splash (plans/2026-10-16-progress-and-tunes.md, section 2): he finished a
/// level, so the screen after it is a celebration of what he did.
///
/// Once through, about 4s, then still: a short burst of confetti, the title pops, his
/// munchers hop in turn, his guide muncher hops over the last two stones of the old path
/// to the flag and the flag goes up, then the new level's path fades in with the guide on
/// its first stone. Nothing loops. "Let's go!" carries on with the session (the door
/// still works). The words name the level and what he can do now, never what he is.
///
/// Reduce motion: no burst, no walk, no hops. The old path with the flag up and the
/// guide at it, still.
struct LevelUpView: View {
    let controller: PracticeController
    let moment: PracticeController.LevelUpMoment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MuncherColors.self) private var colors
    @State private var start = Date()
    @State private var settled = false

    /// When everything has stopped moving (seconds, before the demo time scale).
    static let length = 3.9

    /// What he can do now, true for the level he just finished. First grade words.
    static func achievement(finished level: Int) -> String? {
        switch level {
        case 1: "You can read all of G position!"
        case 2: "You can read steps and skips!"
        case 3: "You can read the whole G scale!"
        case 4: "You can read two notes at once!"
        default: nil
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let w = proxy.size.width
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || settled)) { timeline in
                let t = reduceMotion || settled ? Self.length : timeline.date.timeIntervalSince(start) / max(0.01, controller.timeScale)
                ZStack {
                    Theme.paper.ignoresSafeArea()
                    VStack(spacing: s * 0.012) {
                        Spacer(minLength: 0)
                        Text("Level \(moment.level)!")
                            .font(Theme.kidFont(s * 0.12, weight: .heavy))
                            .foregroundStyle(Theme.kidText)
                            .scaleEffect(reduceMotion ? 1 : Self.pop(t))
                        Text("You did it!")
                            .font(Theme.kidFont(s * 0.055, weight: .heavy))
                            .foregroundStyle(Theme.song.mix(with: .black, by: 0.25))
                        if let line = Self.achievement(finished: moment.level - 1) {
                            Text(line)
                                .font(Theme.kidFont(s * 0.036, weight: .bold))
                                .foregroundStyle(Theme.kidTextSoft)
                        }
                        // the home path's shape (0.42 high), a bit flatter: the guide stands above it
                        path(t)
                            .frame(width: min(w * 0.6, s * 0.62), height: min(w * 0.6, s * 0.62) * 0.38)
                        band(t)
                            .frame(width: min(w * 0.5, s * 0.7), height: s * 0.13)
                        SongButton(title: "Let's go!", symbol: "arrow.right", size: min(130, s * 0.13), color: Theme.button) {
                            controller.levelUpDone()
                        }
                        .opacity(reduceMotion ? 1 : min(1, max(0, (t - 0.6) / 0.4)))
                        .padding(.top, s * 0.01)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    if !reduceMotion, t < Self.burstLength + 0.3 {
                        Canvas { context, size in
                            Self.drawBurst(&context, size: size, t: t)
                        }
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Level \(moment.level)! You did it!")
        .task {
            start = Date()
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(Self.length * controller.timeScale + 0.1))
            settled = true
        }
    }

    // MARK: the title

    /// Pops in from 60%, a little past full size and back, in the first half second.
    static func pop(_ t: Double) -> Double {
        let x = min(1, max(0, (t - 0.05) / 0.5))
        guard x < 1 else { return 1 }
        // ease out with one overshoot
        let c = 1.7
        let y = x - 1
        return 0.6 + 0.4 * (1 + (c + 1) * y * y * y + c * y * y)
    }

    // MARK: the path

    /// The old level's path, all stones full, the guide hopping from the stone before the
    /// last to the flag (0.3-1.9s), the flag going up (1.7-2.3s). Then (2.9-3.5s) the new
    /// level's path fades in, the guide on his first stone.
    private func path(_ t: Double) -> some View {
        let n = moment.finishedStones
        let guide = moment.guide
        let look = guide.map { colors.look($0.id) }
        let fluency = guide.flatMap { moment.fluencies[$0] } ?? 0.5
        let walk = min(1, max(0, (t - 0.3) / 1.6))
        let flag = min(1, max(0, (t - 1.7) / 0.6))
        let swap = reduceMotion ? 0 : min(1, max(0, (t - 2.9) / 0.6))
        let from = Double(max(0, n - 2))
        return ZStack {
            Canvas { context, size in
                LevelPathPainter(
                    stones: Array(repeating: 1, count: n), current: nil,
                    muncherAt: from + (Double(n) - from) * walk, muncher: look, muncherFluency: fluency, flag: flag
                ).draw(in: &context, size: size)
            }
            .opacity(1 - swap)
            if swap > 0 {
                Canvas { context, size in
                    LevelPathPainter(
                        stones: moment.path.stones, current: moment.path.current,
                        muncherAt: moment.path.current.map(Double.init) ?? 0, muncher: look, muncherFluency: fluency
                    ).draw(in: &context, size: size)
                }
                .opacity(swap)
            }
        }
    }

    // MARK: the band

    /// His most grown munchers side by side, cheering: two little hops each, one after
    /// the other, mouths open. Then they stand full and happy.
    private func band(_ t: Double) -> some View {
        let band = moment.band
        return Canvas { context, size in
            guard !band.isEmpty else { return }
            let count = CGFloat(band.count)
            let slot = size.width / count
            let side = min(size.height * 0.95, slot * 0.9)
            for (i, key) in band.enumerated() {
                let center = CGPoint(x: slot * (CGFloat(i) + 0.5), y: size.height - side / 2)
                var pose = MuncherPose(fluency: moment.fluencies[key] ?? 0.5)
                var muncher = context
                // hops: 0.45s each, two of them, starting 0.12s after the one before
                let local = t - 0.4 - 0.12 * Double(i)
                if !reduceMotion, local > 0, local < 0.9 {
                    let x = local.truncatingRemainder(dividingBy: 0.45) / 0.45
                    pose.mouthOpen = 0.6
                    muncher.translateBy(x: 0, y: -side * 0.18 * sin(.pi * x))
                    pose.squash = x < 0.15 ? 0.3 * (1 - x / 0.15) : 0
                } else if reduceMotion || local >= 0.9 {
                    pose.full = true
                }
                MuncherPainter(look: colors.look(key.id), pose: pose, growth: 0.7...0.95)
                    .draw(in: &muncher, rect: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            }
        }
    }

    // MARK: the burst

    static let burstLength = 1.9
    static let burstColors: [Color] = [Theme.song, Theme.button, Theme.homeButton, Theme.keyLit, Theme.sparkle,
                                       Color(red: 0.62, green: 0.48, blue: 0.85)]

    /// Confetti thrown up from behind the title, falling and fading. The same pieces
    /// every time (fixed seed), so it reads as one burst, not noise.
    static func drawBurst(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let age = t - 0.1
        guard age > 0, age < burstLength else { return }
        var rng = SeededRandom(seed: 0x1E7E1)
        func roll() -> Double { Double(rng.next() >> 11) * 0x1p-53 }
        let h = size.height
        let origin = CGPoint(x: size.width / 2, y: h * 0.24)
        let gravity = h * 1.5
        for i in 0..<70 {
            let angle = -.pi / 2 + (roll() - 0.5) * 2.4
            let speed = h * (0.55 + 0.6 * roll())
            let delay = roll() * 0.12
            let spin = (roll() - 0.5) * 14
            let color = burstColors[i % burstColors.count]
            let wide = roll() < 0.5
            let a = age - delay
            guard a > 0 else { continue }
            let x = origin.x + cos(angle) * speed * a * 1.25
            let y = origin.y + sin(angle) * speed * a + 0.5 * gravity * a * a
            let fade = min(1, max(0, (burstLength - age) / 0.5))
            var piece = context
            piece.opacity = fade
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(spin * a))
            let rect = wide ? CGRect(x: -9, y: -5, width: 18, height: 10) : CGRect(x: -6, y: -6, width: 12, height: 12)
            piece.fill(wide ? Path(roundedRect: rect, cornerRadius: 3) : Path(ellipseIn: rect), with: .color(color))
        }
    }
}
