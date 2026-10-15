import NoteCore
import SwiftUI

/// The side lane on the practice screen. The current item's muncher lives here and
/// gobbles each right note (the note hops in from the staff side). Eggs hatch here
/// when a new note unlocks. All the movement stays in the lane, never on the staff.
struct MuncherLane: View {
    let controller: PracticeController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gobbleStart: Date?
    @State private var hatchStart: Date?
    @State private var shownID: ItemID?

    static let gobbleLength = 0.9
    static let hatchDelay = 0.8
    static let hatchLength = 2.0

    private var scale: Double { controller.timeScale }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion && gobbleStart == nil && hatchStart == nil)) { timeline in
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
        .task(id: controller.hatching.first) {
            guard let id = controller.hatching.first else {
                hatchStart = nil
                return
            }
            try? await Task.sleep(for: .seconds(Self.hatchDelay * scale))
            hatchStart = Date()
            try? await Task.sleep(for: .seconds(Self.hatchLength * scale))
            hatchStart = nil
            controller.hatched(id)
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        let tall = size.height > size.width
        var muncherRect = bounds
        var eggRect: CGRect?
        if let hatchStart, controller.hatching.first != nil {
            let progress = now.timeIntervalSince(hatchStart) / (Self.hatchLength * scale)
            if tall {
                muncherRect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height * 0.5)
                eggRect = CGRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height * 0.5)
            } else {
                muncherRect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width * 0.5, height: bounds.height)
                eggRect = CGRect(x: bounds.midX, y: bounds.minY, width: bounds.width * 0.5, height: bounds.height)
            }
            if let eggRect, let id = controller.hatching.first {
                let side = min(eggRect.width, eggRect.height) * 0.9
                let square = CGRect(x: eggRect.midX - side / 2, y: eggRect.midY - side / 2, width: side, height: side)
                EggPainter(look: MuncherLook(id: id), progress: min(1, max(0, progress))).draw(in: &context, rect: square, id: id)
            }
        }

        guard let id = shownID else { return }
        let side = min(muncherRect.width, muncherRect.height * 0.8)
        let square = CGRect(x: muncherRect.midX - side / 2, y: muncherRect.midY - side / 2, width: side, height: side)
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
        MuncherPainter(look: MuncherLook(id: id), pose: pose).draw(in: &context, rect: square)
    }
}
