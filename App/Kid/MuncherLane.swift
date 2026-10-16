import NoteCore
import SwiftUI

/// The side lane on the practice screen. On each right note, that note's muncher pops
/// in and gobbles it (the note hops in from the staff side). It shows the note he just
/// played, never the next one, so a muncher can't give the answer away. All the
/// movement stays in the lane, never on the staff.
struct MuncherLane: View {
    let controller: PracticeController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MuncherColors.self) private var colors
    @State private var gobbleStart: Date?

    static let gobbleLength = 0.9

    private var scale: Double { controller.timeScale }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion && gobbleStart == nil)) { timeline in
            Canvas { context, size in
                draw(&context, size: size, now: timeline.date)
            }
        }
        .background(RoundedRectangle(cornerRadius: 28).fill(Theme.lane))
        .padding(12)
        .onChange(of: controller.gobbleCount) {
            gobbleStart = Date()
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        // the muncher(s) of the note he just played. nothing before his first right key
        let keys = controller.eaten
        guard !keys.isEmpty else { return }
        let side = min(bounds.width / CGFloat(keys.count), bounds.height * 0.8)
        for (i, key) in keys.enumerated() {
            let x = bounds.midX + (CGFloat(i) - CGFloat(keys.count - 1) / 2) * side
            let square = CGRect(x: x - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            drawMuncher(&context, id: key.id, in: square, now: now, phase: Double(i) * 0.6)
        }
    }

    private func drawMuncher(_ context: inout GraphicsContext, id: ItemID, in square: CGRect, now: Date, phase: Double) {
        var pose = MuncherPose(fluency: controller.session.engine.stats(for: id).peakFluency)
        if !reduceMotion {
            pose.bob = 3 * sin(now.timeIntervalSinceReferenceDate * 2 * .pi / 2.4 + phase)
        }
        if let gobbleStart {
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
        MuncherPainter(look: colors.look(id), pose: pose).draw(in: &context, rect: square)
    }
}
