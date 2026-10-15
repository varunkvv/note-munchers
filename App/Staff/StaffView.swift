import NoteCore
import SwiftUI

/// The staff, drawn big and calm for a kid with slight astigmatism: thick lines,
/// ledger lines as heavy as the staff and wider than the head, filled oversized heads,
/// near-black on warm paper. Clefs come from Bravura, everything else is a path.
struct StaffView: View {
    let spec: StaffSpec
    var item: PracticeItem?
    /// Notes before this index are drawn as already played.
    var doneCount = 0
    var effects: StaffEffects?
    var style = StaffStyle()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: effects?.isEmpty ?? true)) { timeline in
            Canvas { context, size in
                let geometry = StaffGeometry(spec: spec, size: size, style: style)
                var painter = StaffPainter(
                    geo: geometry, style: style, effects: effects?.effects ?? [],
                    now: timeline.date, reduceMotion: reduceMotion
                )
                painter.draw(in: &context, item: item, doneCount: doneCount)
            }
        }
    }
}

struct StaffPainter {
    let geo: StaffGeometry
    let style: StaffStyle
    let effects: [StaffEffects.Effect]
    let now: Date
    let reduceMotion: Bool

    private var g: CGFloat { geo.g }

    mutating func draw(in context: inout GraphicsContext, item: PracticeItem?, doneCount: Int) {
        for clef in geo.spec.clefs {
            if style.spaceTint { drawSpaceTint(&context, clef) }
        }
        for clef in geo.spec.clefs {
            drawLines(&context, clef)
            drawClef(&context, clef)
        }
        if geo.spec.clefs.count > 1 { drawSystemLine(&context) }
        if let item { drawItem(&context, item, doneCount: doneCount) }
    }

    // MARK: staff

    private func drawSpaceTint(_ context: inout GraphicsContext, _ clef: Clef) {
        for space in 0..<4 {
            let top = geo.y(space * 2 + 2, on: clef) + geo.lineWidth / 2
            let bottom = geo.y(space * 2, on: clef) - geo.lineWidth / 2
            let rect = CGRect(x: geo.staffLeft, y: top, width: geo.staffRight - geo.staffLeft, height: bottom - top)
            context.fill(Path(rect), with: .color(Theme.spaceTint.opacity(0.7)))
        }
    }

    private func drawLines(_ context: inout GraphicsContext, _ clef: Clef) {
        var path = Path()
        for line in 0..<5 {
            let y = geo.y(line * 2, on: clef)
            path.move(to: CGPoint(x: geo.staffLeft, y: y))
            path.addLine(to: CGPoint(x: geo.staffRight, y: y))
        }
        context.stroke(path, with: .color(style.ink), style: StrokeStyle(lineWidth: geo.lineWidth, lineCap: .butt))
    }

    private func drawSystemLine(_ context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: geo.staffLeft, y: geo.y(8, on: .treble) - geo.lineWidth / 2))
        path.addLine(to: CGPoint(x: geo.staffLeft, y: geo.y(0, on: .bass) + geo.lineWidth / 2))
        context.stroke(path, with: .color(style.ink), lineWidth: geo.lineWidth * 1.3)
    }

    private func drawClef(_ context: inout GraphicsContext, _ clef: Clef) {
        let glyph: Bravura.Glyph = clef == .treble ? .gClef : .fClef
        let originStep = clef == .treble ? 2 : 6
        let origin = CGPoint(x: geo.clefX, y: geo.y(originStep, on: clef))
        if let path = Bravura.path(glyph, staffSpace: g) {
            context.fill(path.offsetBy(dx: origin.x, dy: origin.y), with: .color(style.ink))
        } else {
            // font missing: a big letter keeps the clefs apart
            let text = Text(clef == .treble ? "G" : "F").font(.system(size: g * 3, weight: .heavy)).foregroundColor(style.ink)
            context.draw(text, at: CGPoint(x: origin.x + g * 1.3, y: origin.y), anchor: .center)
        }
    }

    // MARK: notes

    private func drawItem(_ context: inout GraphicsContext, _ item: PracticeItem, doneCount: Int) {
        let centers = geo.columnCenters(item)
        for (index, center) in centers.enumerated() {
            let wobble = effects.last { $0.kind == .wobble && $0.column == index }
            let dx = reduceMotion ? 0 : wobbleOffset(wobble)
            drawColumn(&context, item: item, index: index, x: center + dx, done: index < doneCount, wobble: wobble)
        }
    }

    private func wobbleOffset(_ effect: StaffEffects.Effect?) -> CGFloat {
        guard let effect else { return 0 }
        let p = effect.progress(at: now)
        return g * 0.22 * CGFloat(sin(p * .pi * 2 * 2.5) * (1 - p))
    }

    /// Head centers for one column. The upper note of a second goes to the right.
    func headCenters(item: PracticeItem, index: Int, x: CGFloat) -> [(CGPoint, StaffPosition)] {
        let positions = item.positions(ofNote: index)
        var result: [(CGPoint, StaffPosition)] = []
        var previous: Int?
        var shifted = false
        for position in positions {
            var hx = x
            if let previous, position.step - previous == 1, !shifted {
                hx += CGFloat(Metrics.headHalfWidth * 2 * 0.92) * g
                shifted = true
            } else {
                shifted = false
            }
            result.append((CGPoint(x: hx, y: geo.y(position.step, on: item.clef)), position))
            previous = position.step
        }
        return result
    }

    private func drawColumn(
        _ context: inout GraphicsContext, item: PracticeItem, index: Int, x: CGFloat, done: Bool,
        wobble: StaffEffects.Effect?
    ) {
        let heads = headCenters(item: item, index: index, x: x)
        let sparkle = effects.last { $0.kind == .sparkle && $0.column == index }
        let glow = effects.last { $0.kind == .glow && $0.column == index }

        // ledger lines: as heavy as the staff, wider than the head
        let ledgerSteps = Set(heads.flatMap { $0.1.ledgerLineSteps })
        if !ledgerSteps.isEmpty {
            let minX = heads.map(\.0.x).min()! - CGFloat(Metrics.headHalfWidth + Metrics.ledgerOverhang) * g
            let maxX = heads.map(\.0.x).max()! + CGFloat(Metrics.headHalfWidth + Metrics.ledgerOverhang) * g
            var path = Path()
            for step in ledgerSteps {
                let y = geo.y(step, on: item.clef)
                path.move(to: CGPoint(x: minX, y: y))
                path.addLine(to: CGPoint(x: maxX, y: y))
            }
            context.stroke(path, with: .color(style.ink), style: StrokeStyle(lineWidth: geo.lineWidth, lineCap: .butt))
        }

        if let glow {
            let p = glow.progress(at: now)
            let pulse = reduceMotion ? 1 : 0.8 + 0.2 * sin(p * .pi * 6)
            for (center, _) in heads {
                let rect = CGRect(x: center.x - g * 1.5, y: center.y - g * 1.15, width: g * 3, height: g * 2.3)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.glow.opacity(0.75 * pulse)))
            }
        }

        if wobble != nil, reduceMotion {
            // no movement: a soft grey ring says "not that one" instead
            for (center, _) in heads {
                let rect = CGRect(x: center.x - g * 1.1, y: center.y - g * 0.9, width: g * 2.2, height: g * 1.8)
                context.stroke(Path(ellipseIn: rect), with: .color(Theme.doneInk.opacity(0.6)), lineWidth: g * 0.12)
            }
        }

        var color = done ? Theme.doneInk : style.ink
        var headAlpha = 1.0
        if let sparkle {
            // the head turns into a little sparkle
            let p = sparkle.progress(at: now)
            color = style.ink
            headAlpha = max(0, 1 - p / 0.35)
            if !reduceMotion {
                drawSparkle(&context, at: heads.map(\.0), progress: p)
            }
        }
        for (center, _) in heads {
            drawHead(&context, at: center, filled: true, color: color.opacity(headAlpha))
        }
    }

    func headPath(at center: CGPoint, rx: Double = Metrics.headRX, ry: Double = Metrics.headRY, tilt: Double = Metrics.headTilt) -> Path {
        let rect = CGRect(x: -CGFloat(rx) * g, y: -CGFloat(ry) * g, width: CGFloat(rx * 2) * g, height: CGFloat(ry * 2) * g)
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: CGFloat(tilt * .pi / 180))
        return Path(ellipseIn: rect).applying(transform)
    }

    private func drawHead(_ context: inout GraphicsContext, at center: CGPoint, filled: Bool, color: Color) {
        if filled {
            context.fill(headPath(at: center), with: .color(color))
        } else {
            // open head (half note): same size, thick outline, small tilted hole
            var path = headPath(at: center)
            path.addPath(headPath(at: center, rx: 0.42, ry: 0.2, tilt: -35))
            context.fill(path, with: .color(color), style: FillStyle(eoFill: true))
        }
    }

    private func drawSparkle(_ context: inout GraphicsContext, at centers: [CGPoint], progress p: Double) {
        let ease = 1 - pow(1 - p, 3)
        for center in centers {
            for k in 0..<7 {
                let angle = Double(k) / 7 * 2 * .pi + 0.3
                let distance = g * CGFloat(0.25 + 1.0 * ease)
                let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                let size = g * CGFloat(0.34 * (1 - p * 0.7))
                context.fill(starPath(at: point, size: size), with: .color(Theme.sparkle.opacity(1 - p * p)))
            }
        }
    }

    private func starPath(at c: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        for i in 0..<8 {
            let r = i.isMultiple(of: 2) ? size : size * 0.35
            let a = Double(i) / 8 * 2 * .pi - .pi / 2
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
