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
        // bar lines between measures (rhythm items), under everything else
        if !Metrics.barLinesAfter(item).isEmpty {
            var bars = Path()
            for i in Metrics.barLinesAfter(item) {
                let x = (centers[i] + centers[i + 1]) / 2
                bars.move(to: CGPoint(x: x, y: geo.y(8, on: item.clef) - geo.lineWidth / 2))
                bars.addLine(to: CGPoint(x: x, y: geo.y(0, on: item.clef) + geo.lineWidth / 2))
            }
            context.stroke(bars, with: .color(style.ink), lineWidth: geo.lineWidth)
        }
        var xs: [CGFloat] = []
        for (index, center) in centers.enumerated() {
            let wobble = effects.last { $0.kind == .wobble && $0.column == index }
            let dx = reduceMotion ? 0 : wobbleOffset(wobble)
            xs.append(center + dx)
            drawColumn(&context, item: item, index: index, x: center + dx, done: index < doneCount, wobble: wobble)
        }
        if item.isRhythm {
            drawStems(&context, item: item, xs: xs, doneCount: doneCount)
        }
    }

    // MARK: stems, flags, beams

    struct Stem {
        var x: CGFloat
        /// where it leaves the head
        var attachY: CGFloat
        /// the free end (or where the beam is)
        var tipY: CGFloat
        var up: Bool
    }

    /// A stem on the head's right edge going up, or its left edge going down. The
    /// tilted head's edge point sits a little off center, so the stem starts there.
    func stem(item: PracticeItem, index: Int, x: CGFloat, up: Bool) -> Stem {
        let ys = item.positions(ofNote: index).map { geo.y($0.step, on: item.clef) }
        let lowest = ys.max() ?? 0, highest = ys.min() ?? 0
        let width = CGFloat(Metrics.stemWidth) * g
        let edge = CGFloat(Metrics.headHalfWidth) * g - width / 2
        let length = CGFloat(Metrics.stemLength) * g
        if up {
            return Stem(x: x + edge, attachY: lowest - 0.12 * g, tipY: highest - length, up: true)
        }
        return Stem(x: x - edge, attachY: highest + 0.12 * g, tipY: lowest + length, up: false)
    }

    private func drawStems(_ context: inout GraphicsContext, item: PracticeItem, xs: [CGFloat], doneCount: Int) {
        let ups = Metrics.stemsUp(item)
        var stems = item.notes.indices.map { stem(item: item, index: $0, x: xs[$0], up: ups[$0]) }
        let width = CGFloat(Metrics.stemWidth) * g
        let thickness = CGFloat(Metrics.beamThickness) * g
        func color(_ i: Int) -> Color { i < doneCount ? Theme.doneInk : style.ink }

        // beams: one per eighth pair. sloped a little with the notes, never steeply,
        // and moved out so neither stem gets shorter than the normal length
        let pairs = item.beamedPairStarts
        for i in pairs {
            let j = i + 1
            let maxSlope = 0.5 * g
            let delta = max(-maxSlope, min(maxSlope, stems[j].tipY - stems[i].tipY))
            let start = stems[i].up ? min(stems[i].tipY, stems[j].tipY - delta) : max(stems[i].tipY, stems[j].tipY - delta)
            stems[i].tipY = start
            stems[j].tipY = start + delta
            let inward: CGFloat = stems[i].up ? thickness : -thickness
            var beam = Path()
            beam.move(to: CGPoint(x: stems[i].x - width / 2, y: stems[i].tipY))
            beam.addLine(to: CGPoint(x: stems[j].x + width / 2, y: stems[j].tipY))
            beam.addLine(to: CGPoint(x: stems[j].x + width / 2, y: stems[j].tipY + inward))
            beam.addLine(to: CGPoint(x: stems[i].x - width / 2, y: stems[i].tipY + inward))
            beam.closeSubpath()
            context.fill(beam, with: .color(j < doneCount ? Theme.doneInk : style.ink))
        }

        let beamed = Set(pairs + pairs.map { $0 + 1 })
        for (i, stem) in stems.enumerated() {
            var line = Path()
            line.move(to: CGPoint(x: stem.x, y: stem.attachY))
            line.addLine(to: CGPoint(x: stem.x, y: stem.tipY))
            context.stroke(line, with: .color(color(i)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            if item.notes[i].value == .eighth, !beamed.contains(i) {
                context.fill(flagPath(stem), with: .color(color(i)))
            }
        }
    }

    /// An eighth-note flag: a thick curl off the stem's free end.
    private func flagPath(_ stem: Stem) -> Path {
        let s: CGFloat = stem.up ? 1 : -1 // flags hang down from an up stem, up from a down stem
        let x = stem.x - CGFloat(Metrics.stemWidth) * g / 2
        let y = stem.tipY
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addCurve(
            to: CGPoint(x: x + 0.95 * g, y: y + s * 2.2 * g),
            control1: CGPoint(x: x + 0.1 * g, y: y + s * 0.9 * g),
            control2: CGPoint(x: x + 1.25 * g, y: y + s * 1.2 * g)
        )
        path.addCurve(
            to: CGPoint(x: x, y: y + s * 1.0 * g),
            control1: CGPoint(x: x + 0.85 * g, y: y + s * 1.55 * g),
            control2: CGPoint(x: x + 0.25 * g, y: y + s * 1.2 * g)
        )
        path.closeSubpath()
        return path
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

        // a glowing (rhythm nudge) note stays in full ink so it stands out from the played ones
        var color = done && glow == nil ? Theme.doneInk : style.ink
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
        let filled = !(item.notes[index].value?.hasOpenHead ?? false)
        for (center, _) in heads {
            drawHead(&context, at: center, filled: filled, color: color.opacity(headAlpha))
        }
        drawChordGaps(&context, heads: heads, alpha: headAlpha)
    }

    /// Heads a third apart touch. A thin paper-colored gap between them keeps a chord
    /// from blurring into one blob. Clipped to the two heads, so it never cuts a staff line.
    private func drawChordGaps(_ context: inout GraphicsContext, heads: [(CGPoint, StaffPosition)], alpha: Double) {
        guard heads.count > 1, alpha > 0 else { return }
        for (lower, upper) in zip(heads, heads.dropFirst()) where upper.1.step - lower.1.step == 2 && upper.0.x == lower.0.x {
            // along the heads' tilt, through the middle of where they touch
            let mid = CGPoint(x: lower.0.x, y: (lower.0.y + upper.0.y) / 2)
            let angle = Metrics.headTilt * .pi / 180
            let dx = cos(angle) * g, dy = sin(angle) * g
            var gap = Path()
            gap.move(to: CGPoint(x: mid.x - dx, y: mid.y - dy))
            gap.addLine(to: CGPoint(x: mid.x + dx, y: mid.y + dy))
            var both = headPath(at: lower.0)
            both.addPath(headPath(at: upper.0))
            context.drawLayer { layer in
                layer.clip(to: both)
                layer.stroke(gap, with: .color(style.paper.opacity(alpha)), lineWidth: max(1.5, g * 0.09))
            }
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
            path.addPath(headPath(at: center, rx: 0.4, ry: 0.19, tilt: -35))
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
