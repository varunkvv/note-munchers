import NoteCore
import SwiftUI

/// The side lane on the practice screen. The current item's muncher lives here and
/// gobbles each right note (the note hops in from the staff side). All the movement
/// stays in the lane, never on the staff.
struct MuncherLane: View {
    let controller: PracticeController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MuncherColors.self) private var colors
    @State private var gobbleStart: Date?
    @State private var shownID: ItemID?

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
        .onChange(of: controller.item?.id, initial: true) { _, id in
            if let id { shownID = id }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        // the current item's muncher, or the last one shown (paused, session over)
        guard let id = controller.item?.id ?? shownID else { return }
        let side = min(bounds.width, bounds.height * 0.8)
        let square = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        var pose = MuncherPose(fluency: controller.session.engine.stats(for: id).peakFluency)
        if !reduceMotion {
            pose.bob = 3 * sin(now.timeIntervalSinceReferenceDate * 2 * .pi / 2.4)
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
