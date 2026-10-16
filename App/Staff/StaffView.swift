import NoteCore
import SwiftUI

/// The staff, drawn calm and clear: lines and ledger lines a little heavier than
/// engraving, ledger lines as heavy as the staff and wider than the head, near-black on
/// warm paper. A screen with a meter is real bars: the time signature, stems on every
/// note but a whole note, open heads for halves and wholes, the dot, rests, bar lines and
/// a final bar line where the staff ends. Clefs, digits, rests and the dot come from
/// Bravura, everything else is a path.
struct StaffView: View {
    let spec: StaffSpec
    var item: PracticeItem?
    /// Notes before this index are drawn as already played.
    var doneCount = 0
    var effects: StaffEffects?
    var style = StaffStyle()
    /// Line gap in points. nil = the biggest that fits (small previews).
    var gap: CGFloat?
    /// The time signature after the clef. A song shows it on its first system only.
    var showsMeter = true
    /// Thin-thick at the end, like the end of a piece. A song's other systems end on a
    /// plain bar line.
    var endsPiece = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: effects?.isEmpty ?? true)) { timeline in
            Canvas { context, size in
                let geometry = StaffGeometry(spec: spec, size: size, style: style, gap: gap)
                var painter = StaffPainter(
                    geo: geometry, style: style, effects: effects?.effects ?? [],
                    now: timeline.date, reduceMotion: reduceMotion, showsMeter: showsMeter, endsPiece: endsPiece
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
    var showsMeter = true
    var endsPiece = true

    private var g: CGFloat { geo.g }

    mutating func draw(in context: inout GraphicsContext, item: PracticeItem?, doneCount: Int) {
        let layout = item.map(geo.layout)
        // a screen in bars ends at its final bar line, like the end of a piece
        let right = layout?.end ?? geo.staffRight
        for clef in geo.spec.clefs {
            if style.spaceTint { drawSpaceTint(&context, clef, right: right) }
        }
        for clef in geo.spec.clefs {
            drawLines(&context, clef, right: right)
            drawClef(&context, clef)
            drawKeySignature(&context, clef)
            if let meter = item?.meter, showsMeter { drawMeter(&context, meter, on: clef) }
        }
        if geo.spec.clefs.count > 1 {
            drawBrace(&context)
            drawSystemLine(&context)
        }
        if let item, let layout { drawItem(&context, item, layout: layout, doneCount: doneCount) }
    }

    // MARK: staff

    private func drawSpaceTint(_ context: inout GraphicsContext, _ clef: Clef, right: CGFloat) {
        for space in 0..<4 {
            let top = geo.y(space * 2 + 2, on: clef) + geo.lineWidth / 2
            let bottom = geo.y(space * 2, on: clef) - geo.lineWidth / 2
            let rect = CGRect(x: geo.staffLeft, y: top, width: right - geo.staffLeft, height: bottom - top)
            context.fill(Path(rect), with: .color(Theme.spaceTint.opacity(0.7)))
        }
    }

    private func drawLines(_ context: inout GraphicsContext, _ clef: Clef, right: CGFloat) {
        var path = Path()
        for line in 0..<5 {
            let y = geo.y(line * 2, on: clef)
            path.move(to: CGPoint(x: geo.staffLeft, y: y))
            path.addLine(to: CGPoint(x: right, y: y))
        }
        context.stroke(path, with: .color(style.ink), style: StrokeStyle(lineWidth: geo.lineWidth, lineCap: .butt))
    }

    private func drawSystemLine(_ context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: geo.staffLeft, y: geo.y(8, on: .treble) - geo.lineWidth / 2))
        path.addLine(to: CGPoint(x: geo.staffLeft, y: geo.y(0, on: .bass) + geo.lineWidth / 2))
        context.stroke(path, with: .color(style.ink), lineWidth: geo.lineWidth * 1.3)
    }

    /// The grand staff's brace, from the top line to the bottom line, just left of the
    /// system line. Stretched evenly, so it keeps the font's shape (thick in the middle).
    private func drawBrace(_ context: inout GraphicsContext) {
        guard let path = Bravura.path(.brace, staffSpace: g) else { return }
        let top = geo.systemTop - geo.lineWidth / 2
        let bottom = geo.systemBottom + geo.lineWidth / 2
        let k = (bottom - top) / (4 * g)
        let right = geo.staffLeft - 0.25 * g
        let x = right - path.boundingRect.maxX * k
        context.fill(path.applying(CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: x, ty: bottom)), with: .color(style.ink))
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

    /// Sharps after the clef (G major: one, on the F line). Drawn with the font's sharp
    /// so it reads like his books.
    private func drawKeySignature(_ context: inout GraphicsContext, _ clef: Clef) {
        for (i, step) in geo.spec.keySignature.sharpSteps(clef).enumerated() {
            let origin = CGPoint(x: geo.keySignatureX + CGFloat(i) * CGFloat(Metrics.sharpWidth) * g, y: geo.y(step, on: clef))
            if let path = Bravura.path(.sharp, staffSpace: g) {
                context.fill(path.offsetBy(dx: origin.x, dy: origin.y), with: .color(style.ink))
            } else {
                let text = Text("#").font(.system(size: g * 2.2, weight: .heavy)).foregroundColor(style.ink)
                context.draw(text, at: CGPoint(x: origin.x + g * 0.5, y: origin.y), anchor: .center)
            }
        }
    }

    /// The time signature after the key signature: the top digit in the top two
    /// spaces, the bottom digit in the bottom two, big and in full ink like the clef.
    private func drawMeter(_ context: inout GraphicsContext, _ meter: Meter, on clef: Clef) {
        for (digit, step) in [(meter.beats, 6), (4, 2)] {
            let y = geo.y(step, on: clef)
            guard let path = Bravura.path(code: Bravura.digit(digit), staffSpace: g) else {
                let text = Text("\(digit)").font(.system(size: g * 2.2, weight: .heavy)).foregroundColor(style.ink)
                context.draw(text, at: CGPoint(x: geo.meterX + g * 0.9, y: y), anchor: .center)
                continue
            }
            // both digits centred on one column, whatever their own widths
            let box = path.boundingRect
            let x = geo.meterX + (CGFloat(Metrics.meterWidth) * g - box.width) / 2 - box.minX
            context.fill(path.offsetBy(dx: x, dy: y), with: .color(style.ink))
        }
    }

    // MARK: notes

    private func drawItem(_ context: inout GraphicsContext, _ item: PracticeItem, layout: ScreenLayout, doneCount: Int) {
        // bar lines through every staff on screen, under everything else
        if !layout.barLines.isEmpty {
            var bars = Path()
            for x in layout.barLines {
                bars.move(to: CGPoint(x: x, y: geo.systemTop - geo.lineWidth / 2))
                bars.addLine(to: CGPoint(x: x, y: geo.systemBottom + geo.lineWidth / 2))
            }
            context.stroke(bars, with: .color(style.ink), lineWidth: geo.lineWidth)
        }
        if let end = layout.end {
            if endsPiece {
                drawFinalBarLine(&context, at: end)
            } else {
                var line = Path()
                line.move(to: CGPoint(x: end, y: geo.systemTop - geo.lineWidth / 2))
                line.addLine(to: CGPoint(x: end, y: geo.systemBottom + geo.lineWidth / 2))
                context.stroke(line, with: .color(style.ink), lineWidth: geo.lineWidth)
            }
        }
        drawRests(&context, item: item, layout: layout, doneCount: doneCount)
        var xs: [CGFloat] = []
        for (index, center) in layout.notes.enumerated() {
            let wobble = effects.last { $0.kind == .wobble && $0.column == index }
            let dx = reduceMotion ? 0 : wobbleOffset(wobble)
            xs.append(center + dx)
            drawColumn(&context, item: item, index: index, x: center + dx, done: index < doneCount, wobble: wobble)
        }
        if item.meter != nil {
            drawStems(&context, item: item, xs: xs, doneCount: doneCount)
        }
    }

    /// Thin then thick, at the end of the screen's last bar: the end, like in his books.
    private func drawFinalBarLine(_ context: inout GraphicsContext, at x: CGFloat) {
        let top = geo.systemTop - geo.lineWidth / 2
        let bottom = geo.systemBottom + geo.lineWidth / 2
        let thick = 0.42 * g
        context.fill(Path(CGRect(x: x - thick, y: top, width: thick, height: bottom - top)), with: .color(style.ink))
        var thin = Path()
        let thinX = x - thick - 0.38 * g - geo.lineWidth / 2
        thin.move(to: CGPoint(x: thinX, y: top))
        thin.addLine(to: CGPoint(x: thinX, y: bottom))
        context.stroke(thin, with: .color(style.ink), lineWidth: geo.lineWidth)
    }

    /// Rests that fill out a bar, and a whole-bar rest on a grand staff's idle staff (the
    /// hand with nothing to play in that bar), like real piano music. Rests in a bar he
    /// has played past go grey with its notes.
    private func drawRests(_ context: inout GraphicsContext, item: PracticeItem, layout: ScreenLayout, doneCount: Int) {
        for (r, rest) in layout.rests.enumerated() {
            if let follow = effects.last(where: { $0.kind == .followRest && $0.column == r }) {
                drawFollow(&context, at: CGPoint(x: rest.x, y: geo.y(4, on: rest.clef)), effect: follow)
            }
            let color = rest.note < doneCount ? Theme.doneInk : style.ink
            drawRest(&context, rest.value, clef: rest.clef, x: rest.x, color: color)
        }
        guard geo.spec.clefs.count > 1 else { return }
        for (b, range) in item.barRanges.enumerated() where b < layout.bars.count {
            let used = Set(item.notes[range].map(\.clef))
            for clef in geo.spec.clefs where !used.contains(clef) {
                let span = layout.bars[b]
                let done = range.upperBound <= doneCount
                drawRest(&context, .whole, clef: clef, x: (span.lowerBound + span.upperBound) / 2, color: done ? Theme.doneInk : style.ink)
            }
        }
    }

    /// One rest centred on `x`: a whole rest hangs from the second line from the top, a
    /// half rest sits on the middle line, a quarter rest is centred on it.
    private func drawRest(_ context: inout GraphicsContext, _ value: NoteValue, clef: Clef, x: CGFloat, color: Color) {
        let (glyph, step): (Bravura.Glyph, Int) = switch value {
        case .whole: (.restWhole, 6)
        case .half: (.restHalf, 4)
        default: (.restQuarter, 4)
        }
        let y = geo.y(step, on: clef)
        guard let path = Bravura.path(glyph, staffSpace: g) else {
            let rect = value == .whole ? CGRect(x: x - 0.55 * g, y: y, width: 1.1 * g, height: 0.5 * g)
                : CGRect(x: x - 0.55 * g, y: y - 0.5 * g, width: 1.1 * g, height: 0.5 * g)
            context.fill(Path(rect), with: .color(color))
            return
        }
        let box = path.boundingRect
        context.fill(path.offsetBy(dx: x - box.midX, dy: y), with: .color(color))
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
        let ys = item.positions(ofNote: index).map { geo.y($0.step, on: item.clef(ofNote: index)) }
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
        for (i, stem) in stems.enumerated() where item.notes[i].value.hasStem {
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
            result.append((CGPoint(x: hx, y: geo.y(position.step, on: item.clef(ofNote: index))), position))
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

        let value: NoteValue? = item.meter == nil ? nil : item.notes[index].value
        let halfWidth = Metrics.headHalfWidth(value)
        // ledger lines: as heavy as the staff, wider than the head
        let ledgerSteps = Set(heads.flatMap { $0.1.ledgerLineSteps })
        if !ledgerSteps.isEmpty {
            let minX = heads.map(\.0.x).min()! - CGFloat(halfWidth + Metrics.ledgerOverhang) * g
            let maxX = heads.map(\.0.x).max()! + CGFloat(halfWidth + Metrics.ledgerOverhang) * g
            var path = Path()
            for step in ledgerSteps {
                let y = geo.y(step, on: item.clef(ofNote: index))
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

        if let follow = effects.last(where: { $0.kind == .follow && $0.column == index }) {
            for (center, _) in heads { drawFollow(&context, at: center, effect: follow) }
        }

        // a glowing (rhythm nudge) note stays in full ink so it stands out from the played ones
        let color = done && glow == nil ? Theme.doneInk : style.ink
        if value?.isDotted == true {
            for (center, position) in heads {
                drawDot(&context, head: center, position: position, color: color)
            }
        }
        guard let sparkle else {
            for (center, _) in heads {
                drawHead(&context, at: center, value: value, color: color)
            }
            drawChordGaps(&context, heads: heads, alpha: 1)
            return
        }
        // the head turns into a little sparkle, and its played (grey) self fades in under
        // the stars, so it never blinks out
        let p = sparkle.progress(at: now)
        let inkAlpha = max(0, 1 - p / 0.35)
        let x = min(1, max(0, (p - 0.05) / 0.3))
        let restAlpha = x * x * (3 - 2 * x)
        for (center, _) in heads {
            drawHead(&context, at: center, value: value, color: color.opacity(restAlpha))
            drawHead(&context, at: center, value: value, color: style.ink.opacity(inkAlpha))
        }
        drawChordGaps(&context, heads: heads, alpha: max(inkAlpha, restAlpha))
        if !reduceMotion {
            drawSparkle(&context, at: heads.map(\.0), progress: p)
        }
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

    /// nil value: a plain filled head (tiny staffs).
    private func drawHead(_ context: inout GraphicsContext, at center: CGPoint, value: NoteValue?, color: Color) {
        switch value {
        case .whole?:
            // wider and rounder than the others, with a hole leaning the other way
            var path = headPath(at: center, rx: Metrics.wholeRX, ry: Metrics.wholeRY, tilt: -8)
            path.addPath(headPath(at: center, rx: 0.36, ry: 0.27, tilt: 50))
            context.fill(path, with: .color(color), style: FillStyle(eoFill: true))
        case let v? where v.hasOpenHead:
            // open head (half, dotted half): same size, thick outline, small tilted hole
            var path = headPath(at: center)
            path.addPath(headPath(at: center, rx: 0.4, ry: 0.19, tilt: -35))
            context.fill(path, with: .color(color), style: FillStyle(eoFill: true))
        default:
            context.fill(headPath(at: center), with: .color(color))
        }
    }

    /// The dot after a dotted half: in the space the head is in, or the space above a
    /// head on a line.
    private func drawDot(_ context: inout GraphicsContext, head: CGPoint, position: StaffPosition, color: Color) {
        let lift: CGFloat = position.isOnLine ? g / 2 : 0
        let center = CGPoint(x: head.x + CGFloat(Metrics.headHalfWidth + Metrics.dotOffset) * g, y: head.y - lift)
        let r = CGFloat(Metrics.dotRadius) * g
        if let path = Bravura.path(.dot, staffSpace: g) {
            let box = path.boundingRect
            let k = 2 * r / max(1, box.width)
            let scaled = path.applying(CGAffineTransform(scaleX: k, y: k))
            let b = scaled.boundingRect
            context.fill(scaled.offsetBy(dx: center.x - b.midX, dy: center.y - b.midY), with: .color(color))
        } else {
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
        }
    }

    /// The soft highlight on the note (or rest) that's sounding while the screen is
    /// played to him, so he can follow along left to right.
    private func drawFollow(_ context: inout GraphicsContext, at center: CGPoint, effect: StaffEffects.Effect) {
        let p = effect.progress(at: now)
        // in fast, then held, out at the end
        let alpha = min(1, p / 0.08) * min(1, (1 - p) / 0.15)
        let rect = CGRect(x: center.x - g * 1.25, y: center.y - g * 1.05, width: g * 2.5, height: g * 2.1)
        context.fill(Path(ellipseIn: rect), with: .color(StaffPainter.followColor.opacity(0.85 * alpha)))
    }

    /// Soft sky blue, unlike the yellow rhythm glow and the gold sparkle.
    static let followColor = Color(red: 0.66, green: 0.84, blue: 1.0)

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
