import NoteCore
import SwiftUI

/// How one item's muncher looks. Picked from a stable hash of the item id, so his
/// C muncher looks the same every day. Every item gets one: single notes, groups,
/// chords and rhythm lines alike.
struct MuncherLook: Hashable {
    enum Topper: CaseIterable { case antennae, horns, tuft }

    let body: Color
    let belly: Color
    let dark: Color
    let eyes: Int
    let topper: Topper
    /// eyes poke out above the head, frog style
    let eyesOnTop: Bool

    static let palette: [(Double, Double, Double)] = [
        (0.30, 0.75, 0.70), // teal
        (1.00, 0.62, 0.30), // orange
        (0.62, 0.50, 0.90), // purple
        (0.45, 0.78, 0.40), // green
        (0.98, 0.52, 0.66), // pink
        (0.38, 0.62, 0.95), // blue
        (0.98, 0.78, 0.28), // yellow
        (0.95, 0.47, 0.42), // coral
    ]

    /// Colours offered as big swatches when a muncher hatches (he picks one).
    static let pickable = [1, 2, 3, 4, 5, 6]

    /// `colorIndex`: the colour he picked at hatch. nil = the hashed one (munchers
    /// from before colour picking, and eggs).
    init(id: ItemID, colorIndex: Int? = nil) {
        // fnv1a alone barely changes its high bits between "treble:C4" and "treble:G4",
        // so it only seeds SplitMix64, which mixes well
        var rng = SeededRandom(seed: Self.fnv1a(id))
        func next(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        let hashed = next(Self.palette.count)
        let rgb = Self.palette[colorIndex.map { min(max(0, $0), Self.palette.count - 1) } ?? hashed]
        self.init(rgb: rgb, eyes: [2, 2, 2, 1, 3][next(5)], topper: Topper.allCases[next(Topper.allCases.count)], eyesOnTop: next(3) == 0)
    }

    /// A just-hatched muncher before he picks its colour: pale and waiting.
    static func uncolored(id: ItemID) -> MuncherLook {
        let look = MuncherLook(id: id)
        return MuncherLook(rgb: (0.86, 0.84, 0.8), eyes: look.eyes, topper: look.topper, eyesOnTop: look.eyesOnTop)
    }

    private init(rgb: (Double, Double, Double), eyes: Int, topper: Topper, eyesOnTop: Bool) {
        let (r, g, b) = rgb
        body = Color(red: r, green: g, blue: b)
        belly = Color(red: r + (1 - r) * 0.55, green: g + (1 - g) * 0.55, blue: b + (1 - b) * 0.55)
        dark = Color(red: r * 0.55, green: g * 0.55, blue: b * 0.55)
        self.eyes = eyes
        self.topper = topper
        self.eyesOnTop = eyesOnTop
    }

    static func swatch(_ index: Int) -> Color {
        let (r, g, b) = palette[index]
        return Color(red: r, green: g, blue: b)
    }

    /// FNV-1a. `String.hashValue` changes every launch, this doesn't.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// One frame of a muncher.
struct MuncherPose {
    /// 0...1 peak fluency: bigger, rounder and sillier as it grows. Never shrinks.
    /// Only its own body changes (size, spots, tongue). No hats or gear: those would
    /// read as prizes, and munchers inform, they never pay.
    var fluency = 0.0
    /// 0 closed (smiling) ... 1 wide open
    var mouthOpen = 0.0
    /// 0...1 chomp squash
    var squash = 0.0
    /// full and happy: closed smiling eyes (end screen)
    var full = false
    /// a note on its way into the mouth: 0 at the left edge ... 1 in the mouth. nil = none
    var noteFlight: Double?
    /// small up-down idle bob, in points
    var bob = 0.0
}

/// Draws a muncher with paths. Friendly on purpose: always smiling, big round eyes,
/// rounded teeth, no claws. No muncher is ever drawn hungry or sad.
struct MuncherPainter {
    let look: MuncherLook
    let pose: MuncherPose

    func draw(in context: inout GraphicsContext, rect: CGRect) {
        let f = min(1, max(0, pose.fluency))
        let s = min(rect.width, rect.height) * CGFloat(0.58 + 0.42 * f)
        let cx = rect.midX
        let bottom = rect.maxY - s * 0.03 - CGFloat(pose.bob)
        let squash = CGFloat(pose.squash)
        let bodyW = s * CGFloat(0.8 + 0.14 * f) * (1 + 0.1 * squash)
        let bodyH = s * 0.72 * (1 - 0.1 * squash)
        let bodyCY = bottom - s * 0.07 - bodyH / 2
        let top = bodyCY - bodyH / 2

        // feet
        for side in [-1.0, 1.0] {
            let foot = CGRect(x: cx + CGFloat(side) * s * 0.2 - s * 0.11, y: bottom - s * 0.11, width: s * 0.22, height: s * 0.11)
            context.fill(Path(ellipseIn: foot), with: .color(look.dark))
        }

        // topper (horns, antennae, tuft) once it's grown a little
        if f >= 0.2 { drawTopper(&context, cx: cx, top: top, bodyW: bodyW, s: s) }

        // body and belly
        let bodyRect = CGRect(x: cx - bodyW / 2, y: top, width: bodyW, height: bodyH)
        context.fill(Path(ellipseIn: bodyRect), with: .color(look.body))
        let bellyRect = CGRect(x: cx - bodyW * 0.3, y: bodyCY - bodyH * 0.02, width: bodyW * 0.6, height: bodyH * 0.48)
        context.fill(Path(ellipseIn: bellyRect), with: .color(look.belly))

        if f >= 0.45 {
            for (dx, dy, r) in [(-0.4, -0.08, 0.05), (0.41, 0.0, 0.045), (-0.33, 0.2, 0.035), (0.34, -0.22, 0.035)] {
                let p = CGPoint(x: cx + bodyW * CGFloat(dx), y: bodyCY + bodyH * CGFloat(dy))
                let rr = s * CGFloat(r)
                context.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(look.dark.opacity(0.35)))
            }
        }

        let mouthY = bodyCY + bodyH * 0.1
        if f >= 0.3 {
            for side in [-1.0, 1.0] {
                let cheek = CGRect(x: cx + CGFloat(side) * bodyW * 0.31 - s * 0.06, y: mouthY - s * 0.07, width: s * 0.12, height: s * 0.07)
                context.fill(Path(ellipseIn: cheek), with: .color(Color(red: 1, green: 0.45, blue: 0.5).opacity(0.45)))
            }
        }

        drawEyes(&context, cx: cx, top: top, bodyW: bodyW, bodyH: bodyH, s: s)
        drawMouth(&context, cx: cx, y: mouthY, width: bodyW * 0.52, s: s, f: f)

        if let flight = pose.noteFlight, flight < 1 {
            drawFlyingNote(&context, rect: rect, to: CGPoint(x: cx, y: mouthY + s * 0.05), progress: flight, s: s)
        }
    }

    private func drawEyes(_ context: inout GraphicsContext, cx: CGFloat, top: CGFloat, bodyW: CGFloat, bodyH: CGFloat, s: CGFloat) {
        let y = look.eyesOnTop ? top + bodyH * 0.06 : top + bodyH * 0.3
        let eyes: [(CGFloat, CGFloat, CGFloat)] = switch look.eyes {
        case 1: [(0, 0, 0.19)]
        case 3: [(-0.24, 0.02, 0.1), (0, -0.06, 0.11), (0.24, 0.02, 0.1)]
        default: [(-0.17, 0, 0.135), (0.17, 0, 0.135)]
        }
        let ink = Color(red: 0.12, green: 0.1, blue: 0.12)
        for (dx, dy, r) in eyes {
            let c = CGPoint(x: cx + bodyW * dx, y: y + s * dy)
            let rr = s * r
            let eye = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            if pose.full {
                // happy closed eyes: an upside-down U
                var arc = Path()
                arc.addArc(center: CGPoint(x: c.x, y: c.y + rr * 0.35), radius: rr * 0.7, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
                continue
            }
            context.fill(eye, with: .color(.white))
            context.stroke(eye, with: .color(ink.opacity(0.8)), lineWidth: max(1, s * 0.014))
            // pupils look left, toward the staff where the notes come from
            let pr = rr * 0.5
            let pc = CGPoint(x: c.x - rr * 0.22, y: c.y + rr * 0.08)
            context.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)), with: .color(ink))
            let hr = pr * 0.38
            context.fill(Path(ellipseIn: CGRect(x: pc.x - pr * 0.35 - hr, y: pc.y - pr * 0.4 - hr, width: hr * 2, height: hr * 2)), with: .color(.white))
        }
    }

    private func drawMouth(_ context: inout GraphicsContext, cx: CGFloat, y: CGFloat, width: CGFloat, s: CGFloat, f: Double) {
        let open = CGFloat(min(1, max(0, pose.mouthOpen)))
        let left = CGPoint(x: cx - width / 2, y: y)
        let right = CGPoint(x: cx + width / 2, y: y)
        if open > 0.05 {
            var mouth = Path()
            mouth.move(to: left)
            mouth.addQuadCurve(to: right, control: CGPoint(x: cx, y: y - s * 0.06 * open))
            mouth.addQuadCurve(to: left, control: CGPoint(x: cx, y: y + s * 0.5 * open))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(Color(red: 0.4, green: 0.12, blue: 0.16)))
            context.drawLayer { layer in
                layer.clip(to: mouth)
                let tongue = CGRect(x: cx - width * 0.28, y: y + s * 0.2 * open, width: width * 0.56, height: s * 0.2 * open)
                layer.fill(Path(ellipseIn: tongue), with: .color(Color(red: 1, green: 0.5, blue: 0.58)))
                // two rounded teeth under the top lip
                for side in [-1.0, 1.0] {
                    let tooth = CGRect(x: cx + CGFloat(side) * width * 0.16 - s * 0.035, y: y - s * 0.03 * open, width: s * 0.07, height: s * 0.075 * open + s * 0.02)
                    layer.fill(Path(roundedRect: tooth, cornerRadius: s * 0.02), with: .color(.white))
                }
            }
        } else {
            var smile = Path()
            smile.move(to: left)
            smile.addQuadCurve(to: right, control: CGPoint(x: cx, y: y + s * (pose.full ? 0.2 : 0.15)))
            context.stroke(smile, with: .color(Color(red: 0.25, green: 0.1, blue: 0.12)), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
            if f >= 0.7 {
                // silly: tongue poking out
                let tongue = CGRect(x: cx + width * 0.08, y: y + s * 0.08, width: s * 0.1, height: s * 0.09)
                context.fill(Path(ellipseIn: tongue), with: .color(Color(red: 1, green: 0.5, blue: 0.58)))
            }
        }
    }

    private func drawTopper(_ context: inout GraphicsContext, cx: CGFloat, top: CGFloat, bodyW: CGFloat, s: CGFloat) {
        switch look.topper {
        case .antennae:
            for side in [-1.0, 1.0] {
                let base = CGPoint(x: cx + CGFloat(side) * bodyW * 0.14, y: top + s * 0.06)
                let tip = CGPoint(x: cx + CGFloat(side) * bodyW * 0.26, y: top - s * 0.2)
                var stalk = Path()
                stalk.move(to: base)
                stalk.addQuadCurve(to: tip, control: CGPoint(x: base.x, y: tip.y))
                context.stroke(stalk, with: .color(look.dark), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                let r = s * 0.05
                context.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)), with: .color(look.dark))
            }
        case .horns:
            for side in [-1.0, 1.0] {
                let x = cx + CGFloat(side) * bodyW * 0.24
                var horn = Path()
                horn.move(to: CGPoint(x: x - s * 0.07, y: top + s * 0.08))
                horn.addQuadCurve(to: CGPoint(x: x + CGFloat(side) * s * 0.04, y: top - s * 0.12), control: CGPoint(x: x - s * 0.05, y: top - s * 0.04))
                horn.addQuadCurve(to: CGPoint(x: x + s * 0.07, y: top + s * 0.08), control: CGPoint(x: x + s * 0.06, y: top - s * 0.02))
                horn.closeSubpath()
                context.fill(horn, with: .color(Color(red: 1, green: 0.95, blue: 0.82)))
            }
        case .tuft:
            for (dx, r) in [(-0.07, 0.045), (0.0, 0.055), (0.07, 0.045)] {
                let c = CGPoint(x: cx + s * CGFloat(dx), y: top + s * 0.005)
                let rr = s * CGFloat(r)
                context.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr * 1.4, width: rr * 2, height: rr * 2.4)), with: .color(look.dark))
            }
        }
    }

    private func drawFlyingNote(_ context: inout GraphicsContext, rect: CGRect, to target: CGPoint, progress p: Double, s: CGFloat) {
        // comes in from the left (the staff side) at mouth height, with a small hop
        let start = CGPoint(x: rect.minX - s * 0.05, y: target.y - s * 0.05)
        let t = CGFloat(p)
        let x = start.x + (target.x - start.x) * t
        let y = start.y + (target.y - start.y) * t - s * 0.1 * sin(.pi * t)
        let w = s * 0.2 * (1 - 0.3 * t)
        let head = Path(ellipseIn: CGRect(x: -w / 2, y: -w * 0.36, width: w, height: w * 0.72))
            .applying(CGAffineTransform(translationX: x, y: y).rotated(by: -0.38))
        context.fill(head, with: .color(Theme.ink))
    }
}

/// A still muncher (collection, end screen). The practice lane animates its own.
struct MuncherView: View {
    let id: ItemID
    var pose = MuncherPose()
    @Environment(MuncherColors.self) private var colors

    var body: some View {
        let look = colors.look(id)
        Canvas { context, size in
            MuncherPainter(look: look, pose: pose).draw(in: &context, rect: CGRect(origin: .zero, size: size))
        }
    }
}

/// The colours he picked, by item. Read by every view that draws a muncher.
@MainActor @Observable
final class MuncherColors {
    private(set) var picked: [ItemID: Int]

    init(picked: [ItemID: Int] = [:]) {
        self.picked = picked
    }

    func look(_ id: ItemID) -> MuncherLook {
        MuncherLook(id: id, colorIndex: picked[id])
    }

    func hasColor(_ id: ItemID) -> Bool { picked[id] != nil }

    func set(_ index: Int, for id: ItemID) {
        picked[id] = index
    }
}

/// An egg that wobbles, cracks and hatches its muncher. `progress` 0...1.
struct EggPainter {
    let look: MuncherLook
    let progress: Double

    func draw(in context: inout GraphicsContext, rect: CGRect, id: ItemID) {
        let p = progress
        let s = min(rect.width, rect.height)
        let cx = rect.midX
        let bottom = rect.maxY - s * 0.04
        let eggW = s * 0.56
        let eggH = s * 0.72
        let center = CGPoint(x: cx, y: bottom - eggH / 2)
        let wobble = p < 0.5 ? sin(p * .pi * 10) * 0.14 * (p / 0.5) : 0
        let shell = Color(red: 1, green: 0.97, blue: 0.9)

        // the baby muncher pops out of the bottom half
        if p > 0.55 {
            let grow = min(1, (p - 0.55) / 0.3)
            let size = s * CGFloat(0.4 + 0.55 * grow)
            let babyRect = CGRect(x: cx - size / 2, y: bottom - size - s * 0.12 * CGFloat(grow), width: size, height: size)
            MuncherPainter(look: look, pose: MuncherPose(fluency: 0, mouthOpen: grow > 0.8 ? 0.6 : 0)).draw(in: &context, rect: babyRect)
        }

        var egg = context
        egg.translateBy(x: center.x, y: bottom)
        egg.rotate(by: .radians(wobble))
        egg.translateBy(x: -center.x, y: -bottom)
        let eggPath = Self.eggPath(center: center, width: eggW, height: eggH)
        let crackY = center.y - eggH * 0.02

        if p <= 0.55 {
            egg.fill(eggPath, with: .color(shell))
            egg.drawLayer { layer in
                layer.clip(to: eggPath)
                for (dx, dy, r) in [(-0.18, -0.2, 0.07), (0.15, -0.05, 0.09), (-0.1, 0.18, 0.06), (0.2, 0.22, 0.05)] {
                    let c = CGPoint(x: center.x + s * CGFloat(dx), y: center.y + s * CGFloat(dy))
                    let rr = s * CGFloat(r)
                    layer.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(look.body.opacity(0.75)))
                }
            }
            egg.stroke(eggPath, with: .color(Theme.keyEdge.opacity(0.5)), lineWidth: max(1, s * 0.012))
            if p > 0.35 {
                egg.stroke(Self.crack(center: center, y: crackY, width: eggW), with: .color(Theme.keyEdge), style: StrokeStyle(lineWidth: s * 0.02, lineJoin: .round))
            }
        } else {
            // bottom half stays, top half flies up and fades
            let fade = max(0, 1 - (p - 0.55) / 0.45)
            var bottomHalf = egg
            bottomHalf.clip(to: Path(CGRect(x: rect.minX, y: crackY, width: rect.width, height: rect.maxY - crackY)))
            bottomHalf.fill(eggPath, with: .color(shell.opacity(fade)))
            var topHalf = egg
            let lift = s * 0.5 * CGFloat(p - 0.55)
            topHalf.translateBy(x: s * 0.2 * CGFloat(p - 0.55), y: -lift)
            topHalf.clip(to: Path(CGRect(x: rect.minX - s, y: rect.minY - s, width: rect.width + 2 * s, height: crackY - rect.minY + s)))
            topHalf.fill(eggPath, with: .color(shell.opacity(fade)))
        }
    }

    static func eggPath(center: CGPoint, width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let x = cos(t) * Double(width) / 2
            // narrower and taller on top
            let y = sin(t) * Double(height) / 2 * (sin(t) < 0 ? 1.08 : 0.92)
            let narrow = sin(t) < 0 ? 1 - 0.18 * -sin(t) : 1
            let point = CGPoint(x: center.x + CGFloat(x * narrow), y: center.y + CGFloat(y))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func crack(center: CGPoint, y: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        let left = center.x - width * 0.42
        path.move(to: CGPoint(x: left, y: y))
        for i in 1...6 {
            let x = left + width * 0.84 * CGFloat(i) / 6
            path.addLine(to: CGPoint(x: x, y: y + (i.isMultiple(of: 2) ? 0 : -width * 0.08)))
        }
        return path
    }
}
