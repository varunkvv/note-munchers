import NoteCore
import SwiftUI

/// The side lane on the practice screen. On each right note, that note's muncher pops
/// in and gobbles it (the note hops in from the staff side). It shows the note he just
/// played, never the next one, so a muncher can't give the answer away. All the
/// movement stays in the lane, never on the staff.
struct MuncherLane: View {
    let controller: PracticeController
    /// Room kept clear at the far end of the lane (the play button): the bottom in the
    /// landscape side lane, the trailing end in the portrait strip.
    var reserved: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MuncherColors.self) private var colors
    @State private var gobbleStart: Date?
    /// the munchers on show before the last swap (they fade out) and when it started
    @State private var leaving: [NoteKey] = []
    @State private var swapStart: Date?

    static let gobbleLength = 0.9
    /// a different muncher swapping in: the new one pops up in front of the old one
    static let popLength = 0.3
    /// A muncher's size at fluency 0 and 1, as a share of the lane's width. Big enough
    /// to see the chomp from the piano bench, with room to grow.
    static let growth = 0.6...0.8

    private var scale: Double { controller.timeScale }

    var body: some View {
        let busy = gobbleStart != nil || swapStart != nil
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion && !busy)) { timeline in
            Canvas { context, size in
                draw(&context, size: size, now: timeline.date)
            }
        }
        .background(RoundedRectangle(cornerRadius: 28).fill(Theme.lane))
        .padding(12)
        .onChange(of: controller.gobbleCount) {
            gobbleStart = Date()
        }
        .onChange(of: controller.eaten) { old, _ in
            // a different note's muncher pops in. the same one again just eats
            leaving = old
            swapStart = Date()
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        var bounds = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        if size.height >= size.width {
            bounds.size.height = max(bounds.width * 0.6, bounds.height - reserved)
        } else {
            bounds.size.width = max(bounds.height * 0.6, bounds.width - reserved)
        }
        var t = 1.0
        if let swapStart {
            t = min(1, now.timeIntervalSince(swapStart) / (Self.popLength * scale))
        }
        if t < 1, !leaving.isEmpty {
            // the old muncher shrinks and fades behind the new one, so the lane is
            // never empty and the two never blur into one. reduce motion: a plain cross-fade
            let x = min(1, max(0, (t - 0.1) / 0.4))
            let k = reduceMotion ? t : x * x * (3 - 2 * x)
            var old = context
            old.opacity = 1 - k
            drawMunchers(&old, keys: leaving, in: bounds, now: now, pop: reduceMotion ? 1 : 1 - 0.3 * k, eating: false)
        }
        // the muncher(s) of the note he just played. nothing before his first right key
        let keys = controller.eaten
        guard !keys.isEmpty else { return }
        // the new one pops up in front, from its feet, a little past full size and back
        var new = context
        new.opacity = reduceMotion ? t : min(1, t / 0.15)
        drawMunchers(&new, keys: keys, in: bounds, now: now, pop: reduceMotion ? 1 : Self.popScale(t), eating: true)
    }

    /// 0.55 -> a little past 1 -> 1, like a friendly "boing"
    static func popScale(_ t: Double) -> Double {
        let c = 1.7
        let x = t - 1
        return 0.55 + 0.45 * (1 + (c + 1) * x * x * x + c * x * x)
    }

    /// One muncher, or two along the lane (a dyad: in the landscape side lane the
    /// higher note's muncher is on top). Each gets the lane's full width, so two at
    /// once are as big as one.
    private func drawMunchers(_ context: inout GraphicsContext, keys: [NoteKey], in bounds: CGRect, now: Date, pop: Double, eating: Bool) {
        let tall = bounds.height >= bounds.width
        let ordered = tall ? Array(keys.reversed()) : keys
        let count = CGFloat(ordered.count)
        let slot = (tall ? bounds.height : bounds.width) / count
        let across = tall ? bounds.width : bounds.height
        let side = min(across, slot * (ordered.count == 1 ? 0.8 : 1))
        for (i, key) in ordered.enumerated() {
            let along = (tall ? bounds.minY : bounds.minX) + slot * (CGFloat(i) + 0.5)
            let center = tall ? CGPoint(x: bounds.midX, y: along) : CGPoint(x: along, y: bounds.midY)
            let square = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            var muncher = context
            if pop != 1 {
                // grow from its feet, so it pops up out of the lane's floor
                let anchor = CGPoint(x: square.midX, y: square.maxY)
                muncher.translateBy(x: anchor.x, y: anchor.y)
                muncher.scaleBy(x: pop, y: pop)
                muncher.translateBy(x: -anchor.x, y: -anchor.y)
            }
            drawMuncher(&muncher, id: key.id, in: square, now: now, phase: Double(i) * 0.6, eating: eating)
        }
    }

    private func drawMuncher(_ context: inout GraphicsContext, id: ItemID, in square: CGRect, now: Date, phase: Double, eating: Bool) {
        var pose = MuncherPose(fluency: controller.session.engine.stats(for: id).peakFluency)
        if !reduceMotion {
            pose.bob = 3 * sin(now.timeIntervalSinceReferenceDate * 2 * .pi / 2.4 + phase)
        }
        if eating, let gobbleStart {
            let t = now.timeIntervalSince(gobbleStart) / (Self.gobbleLength * scale)
            if t < 1 {
                if t < 0.5 {
                    pose.noteFlight = reduceMotion ? nil : t / 0.5
                    pose.mouthOpen = 0.25 + 0.75 * t / 0.5
                } else if t < 0.62 {
                    pose.mouthOpen = 1 - (t - 0.5) / 0.12
                }
                if t >= 0.5, t < 0.8 {
                    pose.squash = sin(.pi * (t - 0.5) / 0.3)
                }
            }
        }
        MuncherPainter(look: colors.look(id), pose: pose, growth: Self.growth).draw(in: &context, rect: square)
    }
}
