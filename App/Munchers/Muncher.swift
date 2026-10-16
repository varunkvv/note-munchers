import NoteCore
import SwiftUI

/// How one note's muncher looks. Picked from a stable hash of the id, so his G muncher
/// looks the same every day. Colour is separate from everything else (`traits`): he picks
/// the colour at hatch, and both munchers he picks between are the same muncher.
struct MuncherLook: Hashable {
    enum Topper: CaseIterable { case antennae, horns, tuft, curl, sprout, none }
    enum BodyShape: CaseIterable { case round, tall, wide, pear, boxy, gumdrop, bean, fluffy }
    enum EyeStyle: CaseIterable { case plain, oval, lashes, lid, sparkle }
    /// on the face, frog bumps on top, on little stalks, or far apart at the sides
    enum EyePlacement: CaseIterable { case face, top, stalks, wide }
    enum Mouth: CaseIterable { case grin, small, cat, open, lopsided, wide }
    enum Teeth: CaseIterable { case none, buck, one, row, under }
    enum Pattern: CaseIterable { case plain, spots, stripes, freckles, patch, twoTone }
    enum Ears: CaseIterable { case none, round, cat, floppy, bunny, fins }
    enum Tail: CaseIterable { case none, curl, puff, swoosh }
    enum Arms: CaseIterable { case none, nubs, noodle }
    enum Feet: CaseIterable { case round, wide, paws, tiny }

    /// Everything except colour.
    struct Traits: Hashable {
        var shape: BodyShape
        var eyes: Int
        var eyePlacement: EyePlacement
        var eyeStyle: EyeStyle
        var eyeSize: Double
        var mouth: Mouth
        var teeth: Teeth
        var pattern: Pattern
        var belly: Bool
        var ears: Ears
        var topper: Topper
        var tail: Tail
        var arms: Arms
        var feet: Feet
        /// tail, eye patch and waving arm on the left instead of the right
        var flip: Bool
        /// where the spots go
        var patternSeed: UInt64

        /// The draw order is what keeps a note's muncher the same every day. Add new
        /// traits at the end, never in the middle.
        init(using rng: inout SeededRandom) {
            func pick<T>(_ options: [T]) -> T { options[Int(rng.next() % UInt64(options.count))] }
            shape = pick(BodyShape.allCases)
            eyes = pick([2, 2, 2, 1, 3])
            eyePlacement = pick([.face, .face, .face, .top, .stalks, .wide])
            eyeStyle = pick(EyeStyle.allCases)
            eyeSize = pick([0.88, 1.0, 1.14])
            mouth = pick(Mouth.allCases)
            teeth = pick([.none, .buck, .buck, .one, .row, .under])
            pattern = pick(Pattern.allCases)
            belly = rng.next() % 3 != 0
            // eyes on top of the head leave no room for big ears or antennae
            ears = switch eyePlacement {
            case .top: pick([.none, .floppy, .fins])
            case .stalks: pick([.none, .round, .floppy, .fins])
            default: pick(Ears.allCases)
            }
            topper = switch (eyePlacement, ears) {
            case (.stalks, _): .none
            case (.top, _): pick([.tuft, .curl, .sprout])
            case (_, .bunny): pick([.none, .tuft, .curl])
            case (_, .cat), (_, .round): pick([.tuft, .curl, .sprout])
            default: pick([.antennae, .horns, .tuft, .curl, .sprout])
            }
            tail = pick(Tail.allCases)
            arms = pick(Arms.allCases)
            feet = pick(Feet.allCases)
            flip = rng.next() % 2 == 0
            patternSeed = rng.next()
        }
    }

    let body: Color
    let belly: Color
    let dark: Color
    /// a little darker than the body: ears, arms, fins, tails
    let shade: Color
    let traits: Traits

    var eyes: Int { traits.eyes }
    var topper: Topper { traits.topper }
    /// eyes poke out above the head, frog style
    var eyesOnTop: Bool { traits.eyePlacement == .top }

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

    /// Colours a hatching muncher can be offered in (two of them at a time). Coral is
    /// left out because it's too close to orange and pink to be a real choice.
    static let pickable = [0, 1, 2, 3, 4, 5, 6]

    /// `colorIndex`: the colour he picked at hatch. nil = the hashed one (munchers
    /// from before colour picking, and eggs).
    init(id: ItemID, colorIndex: Int? = nil) {
        // fnv1a alone barely changes its high bits between "treble:C4" and "treble:G4",
        // so it only seeds SplitMix64, which mixes well
        var rng = SeededRandom(seed: Self.fnv1a(id))
        let hashed = Int(rng.next() % UInt64(Self.palette.count))
        let rgb = Self.palette[colorIndex.map { min(max(0, $0), Self.palette.count - 1) } ?? hashed]
        self.init(rgb: rgb, traits: Self.traits(id: id))
    }

    /// Mixed into the trait hash. Picked with artifacts/muncher-sheet (`salt` mode) so no
    /// two of the 27 note munchers in levels 1-5 share most of their looks. Changing it
    /// changes every muncher's shape, so only do it on purpose.
    static let traitSalt: UInt64 = 11859

    /// Everything but colour, from the id alone, so a picked colour never changes the
    /// rest of the muncher.
    static func traits(id: ItemID, salt: UInt64 = traitSalt) -> Traits {
        var rng = SeededRandom(seed: fnv1a(id) &+ salt &* 0x9E37_79B9_7F4A_7C15)
        _ = rng.next()
        return Traits(using: &rng)
    }

    /// A just-hatched muncher before he picks its colour: pale and waiting, but dark
    /// enough to stand out from the paper while it comes out of the egg.
    static func uncolored(id: ItemID) -> MuncherLook {
        MuncherLook(rgb: (0.78, 0.76, 0.72), traits: traits(id: id))
    }

    private init(rgb: (Double, Double, Double), traits: Traits) {
        let (r, g, b) = rgb
        body = Color(red: r, green: g, blue: b)
        belly = Color(red: r + (1 - r) * 0.55, green: g + (1 - g) * 0.55, blue: b + (1 - b) * 0.55)
        dark = Color(red: r * 0.55, green: g * 0.55, blue: b * 0.55)
        shade = Color(red: r * 0.84, green: g * 0.84, blue: b * 0.84)
        self.traits = traits
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
    /// 0 eyes open ... 1 shut (an idle blink on home)
    var blink = 0.0
    /// where the pupils look: 0 the usual (a little left, toward the staff), 1 to the
    /// right, -1 further left. Home's idle look around
    var glance = 0.0
}

/// Draws a muncher with paths. Friendly on purpose: always smiling, big round eyes,
/// rounded teeth, no claws. No muncher is ever drawn hungry or sad.
///
/// Who he is (shape, face, ears, pattern, tail, arms, feet) shows from the first day.
/// Fluency adds the silly extras on top: topper at 0.2, cheeks 0.3, more pattern 0.45,
/// tongue out 0.7, bigger topper and a waving arm 0.85. He also gets bigger and rounder.
struct MuncherPainter {
    let look: MuncherLook
    let pose: MuncherPose
    /// Size at fluency 0 and at 1, as a share of the rect's short side. The practice
    /// lane starts bigger so a new muncher is easy to see from the piano bench.
    var growth: ClosedRange<Double> = 0.58...1.0

    static let topperAt = 0.2
    static let cheeksAt = 0.3
    static let morePatternAt = 0.45
    static let tongueAt = 0.7
    static let waveAt = 0.85

    private var t: MuncherLook.Traits { look.traits }
    private static let ink = Color(red: 0.12, green: 0.1, blue: 0.12)
    private static let mouthInk = Color(red: 0.25, green: 0.1, blue: 0.12)
    private static let mouthInside = Color(red: 0.4, green: 0.12, blue: 0.16)
    private static let tongue = Color(red: 1, green: 0.5, blue: 0.58)
    private static let blush = Color(red: 1, green: 0.45, blue: 0.5)

    func draw(in context: inout GraphicsContext, rect: CGRect) {
        let f = min(1, max(0, pose.fluency))
        let spec = ShapeSpec(t.shape)
        let squash = CGFloat(min(1, max(0, pose.squash)))
        // grows with fluency, but always fits the rect with its ears, topper and tail.
        // the fit is taken at full growth (the most room it ever needs), so a muncher
        // never gets smaller as it grows. it ignores the squash, so a chomp never changes the size
        let grownW = spec.width * (1 + 0.17 * f)
        let side = min(rect.width, rect.height)
        let s = min(side * CGFloat(growth.lowerBound + (growth.upperBound - growth.lowerBound) * f),
                    rect.height / CGFloat(0.1 + spec.height + headroom(1)),
                    rect.width / CGFloat(spec.width * 1.17 + 2 * sideRoom(1)))
        let ground = rect.maxY - s * 0.03 - CGFloat(pose.bob)
        let bodyW = s * CGFloat(grownW) * (1 + 0.1 * squash)
        let bodyH = s * CGFloat(spec.height) * (1 - 0.1 * squash)
        let body = BodyOutline(spec: spec, center: CGPoint(x: rect.midX, y: ground - s * 0.07 - bodyH / 2), width: bodyW, height: bodyH)
        let m = Metrics(body: body, s: s, f: f, spec: spec)
        let eyes = eyeLayout(m)

        drawTail(&context, m)
        drawFeet(&context, m, ground: ground)
        drawEars(&context, m)
        if f >= Self.topperAt { drawTopper(&context, m) }
        drawArms(&context, m)
        drawEyeMounts(&context, m, eyes: eyes)

        let mouthY = mouthLine(m, eyes: eyes)
        context.fill(body.path, with: .color(look.body))
        context.drawLayer { layer in
            layer.clip(to: body.path)
            drawPattern(&layer, m, eyes: eyes, mouthY: mouthY)
        }
        drawFloppyEars(&context, m)

        if f >= Self.cheeksAt {
            let dx = min(body.halfWidth(at: mouthY) * 0.66, bodyW * 0.33)
            for side in [-1.0, 1.0] {
                let cheek = CGRect(x: m.cx + CGFloat(side) * dx - s * 0.06, y: mouthY - s * 0.075, width: s * 0.12, height: s * 0.07)
                context.fill(Path(ellipseIn: cheek), with: .color(Self.blush.opacity(0.45)))
            }
        }
        drawEyes(&context, m, eyes: eyes)
        drawMouth(&context, m, y: mouthY)

        if let flight = pose.noteFlight, flight < 1 {
            drawFlyingNote(&context, rect: rect, to: CGPoint(x: m.cx, y: mouthY + s * 0.05), progress: flight, s: s)
        }
    }

    // MARK: layout

    /// How far ears, toppers and eyes stick up above the body, in units of `s`.
    private func headroom(_ f: Double) -> Double {
        let ears: Double = switch t.ears {
        case .none, .floppy, .fins: 0
        case .round: 0.11
        case .cat: 0.15
        case .bunny: 0.3
        }
        let grow = f >= Self.waveAt ? 1.3 : 1
        let topperHeight: Double = switch t.topper {
        case .antennae: 0.26 * grow
        case .horns: 0.13 * grow
        case .tuft: 0.08 * grow
        case .curl: 0.15 * grow
        case .sprout: 0.17 * grow
        case .none: 0
        }
        let topper = f < Self.topperAt ? 0 : topperHeight
        let r = eyeRadius()
        let eyes: Double = switch t.eyePlacement {
        case .top: r * 1.1
        case .stalks: 2 * r + Self.stalkLength(f) + (t.eyes == 3 ? 0.03 : 0)
        case .face, .wide: 0
        }
        return max(ears, topper, eyes) + 0.02
    }

    /// How far tails, arms, floppy ears and fins stick out on one side, in units of `s`.
    private func sideRoom(_ f: Double) -> Double {
        let tail: Double = switch t.tail {
        case .none: 0
        case .curl: 0.14
        case .puff: 0.1
        case .swoosh: 0.2
        }
        let arms: Double = switch t.arms {
        case .none: 0
        case .nubs: 0.1
        case .noodle: 0.15
        }
        let ears: Double = switch t.ears {
        case .floppy: 0.13
        case .fins: 0.12
        default: 0
        }
        return max(tail, arms, ears, 0.02)
    }

    private struct Metrics {
        let body: BodyOutline
        let s: CGFloat
        let f: Double
        let spec: ShapeSpec
        var cx: CGFloat { body.center.x }
        var cy: CGFloat { body.center.y }
        var top: CGFloat { body.center.y - body.height / 2 }
        var w: CGFloat { body.width }
        var h: CGFloat { body.height }
    }

    private struct Eye {
        let center: CGPoint
        let radius: CGFloat
    }

    /// Eye radius before it's fitted to the face, in units of `s`.
    private func eyeRadius() -> Double {
        let r: Double = switch t.eyes {
        case 1: 0.19
        case 3: 0.1
        default: 0.135
        }
        return r * t.eyeSize * (t.eyePlacement == .top ? 0.92 : t.eyePlacement == .stalks ? 0.72 : 1)
    }

    /// How far stalk eyes stand above the head (stalk only), in units of `s`.
    private static func stalkLength(_ f: Double) -> Double { 0.07 + 0.03 * f }

    private func eyeLayout(_ m: Metrics) -> [Eye] {
        let s = m.s
        var r = s * CGFloat(eyeRadius())
        switch t.eyePlacement {
        case .face, .wide:
            let y = m.top + m.h * CGFloat(m.spec.eyeY)
            let room = m.body.halfWidth(at: y)
            if t.eyes == 1 {
                r = min(r, room * 0.62)
                return [Eye(center: CGPoint(x: m.cx, y: y), radius: r)]
            }
            if t.eyePlacement == .wide {
                r *= 1.06
                r = min(r, room * 0.42)
                let dx = room * 0.8
                if t.eyes == 3 {
                    return [Eye(center: CGPoint(x: m.cx - dx, y: y), radius: r * 0.85),
                            Eye(center: CGPoint(x: m.cx, y: y - s * 0.05), radius: r * 0.85),
                            Eye(center: CGPoint(x: m.cx + dx, y: y), radius: r * 0.85)]
                }
                return [Eye(center: CGPoint(x: m.cx - dx, y: y), radius: r), Eye(center: CGPoint(x: m.cx + dx, y: y), radius: r)]
            }
            if t.eyes == 3 {
                r = min(r, room * 0.3)
                let dx = min(max(m.w * 0.24, r * 2.15), room - r)
                return [Eye(center: CGPoint(x: m.cx - dx, y: y + s * 0.02), radius: r),
                        Eye(center: CGPoint(x: m.cx, y: y - s * 0.05), radius: r * 1.1),
                        Eye(center: CGPoint(x: m.cx + dx, y: y + s * 0.02), radius: r)]
            }
            r = min(r, room * 0.46)
            let dx = min(max(m.w * 0.17, r * 1.12), room - r * 0.95)
            return [Eye(center: CGPoint(x: m.cx - dx, y: y), radius: r), Eye(center: CGPoint(x: m.cx + dx, y: y), radius: r)]
        case .top:
            // frog bumps: each eye sits on the top edge of the head
            let xs: [CGFloat] = switch t.eyes {
            case 1: [0]
            case 3: [-max(m.w * 0.26, r * 2.1), 0, max(m.w * 0.26, r * 2.1)]
            default: [-max(m.w * 0.2, r * 1.2), max(m.w * 0.2, r * 1.2)]
            }
            return xs.map { dx in
                let x = m.cx + dx
                return Eye(center: CGPoint(x: x, y: m.body.topY(at: x) + r * 0.15), radius: r)
            }
        case .stalks:
            // the stalks lean out a little, the eyes sit on their tips
            let xs: [CGFloat] = switch t.eyes {
            case 1: [0]
            case 3: [-max(m.w * 0.2, r * 1.9), 0, max(m.w * 0.2, r * 1.9)]
            default: [-max(m.w * 0.14, r * 1.1), max(m.w * 0.14, r * 1.1)]
            }
            let lift = r + s * CGFloat(Self.stalkLength(m.f))
            return xs.map { dx in
                let extra = dx == 0 && xs.count == 3 ? s * 0.03 : 0
                return Eye(center: CGPoint(x: m.cx + dx * 1.25, y: m.body.topY(at: m.cx + dx) - lift - extra), radius: r)
            }
        }
    }

    /// The mouth sits below the eyes, whatever the shape.
    private func mouthLine(_ m: Metrics, eyes: [Eye]) -> CGFloat {
        var y = m.top + m.h * CGFloat(m.spec.mouthY)
        if t.eyePlacement == .face || t.eyePlacement == .wide {
            let eyeBottom = eyes.map { $0.center.y + $0.radius * (t.eyeStyle == .oval ? 1.12 : 1) }.max() ?? y
            y = max(y, eyeBottom + m.s * 0.06)
        }
        return min(y, m.top + m.h - m.s * 0.16)
    }

    // MARK: behind the body

    private func drawTail(_ context: inout GraphicsContext, _ m: Metrics) {
        let s = m.s
        let side: CGFloat = t.flip ? -1 : 1
        let y = m.cy + m.h * 0.22
        let base = CGPoint(x: m.cx + side * m.body.halfWidth(at: y) * 0.8, y: y)
        switch t.tail {
        case .none:
            break
        case .curl:
            var tail = Path()
            tail.move(to: base)
            let out = CGPoint(x: base.x + side * s * 0.17, y: base.y - s * 0.02)
            tail.addQuadCurve(to: out, control: CGPoint(x: base.x + side * s * 0.1, y: base.y + s * 0.06))
            tail.addArc(center: CGPoint(x: out.x - side * s * 0.035, y: out.y), radius: s * 0.035, startAngle: .degrees(side > 0 ? 0 : 180), endAngle: .degrees(side > 0 ? 270 : -90), clockwise: side > 0)
            context.stroke(tail, with: .color(look.shade), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round, lineJoin: .round))
        case .puff:
            let c = CGPoint(x: base.x + side * s * 0.07, y: base.y + s * 0.03)
            for (dx, dy, r) in [(0.0, 0.0, 0.075), (0.045, -0.035, 0.045), (0.05, 0.03, 0.045), (-0.01, 0.055, 0.045)] {
                context.fill(circle(CGPoint(x: c.x + side * s * dx, y: c.y + s * dy), s * r), with: .color(look.belly))
            }
        case .swoosh:
            var tail = Path()
            tail.move(to: base)
            let tip = CGPoint(x: base.x + side * s * 0.2, y: base.y - s * 0.15)
            tail.addQuadCurve(to: tip, control: CGPoint(x: base.x + side * s * 0.22, y: base.y + s * 0.07))
            context.stroke(tail, with: .color(look.shade), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
            context.fill(circle(tip, s * 0.045), with: .color(look.dark))
        }
    }

    private func drawFeet(_ context: inout GraphicsContext, _ m: Metrics, ground: CGFloat) {
        let s = m.s
        let (dx, w, h): (CGFloat, CGFloat, CGFloat) = switch t.feet {
        case .round: (m.w * 0.25, s * 0.22, s * 0.11)
        case .wide: (m.w * 0.27, s * 0.29, s * 0.09)
        case .paws: (m.w * 0.24, s * 0.21, s * 0.12)
        case .tiny: (m.w * 0.16, s * 0.14, s * 0.085)
        }
        for side in [-1.0, 1.0] {
            let x = m.cx + CGFloat(side) * dx
            let foot = CGRect(x: x - w / 2, y: ground - h, width: w, height: h)
            context.fill(Path(ellipseIn: foot), with: .color(look.dark))
            if t.feet == .paws {
                // toe beans
                for i in -1...1 {
                    let r = s * 0.02
                    context.fill(circle(CGPoint(x: x + CGFloat(i) * w * 0.24, y: ground - h * 0.32), r), with: .color(look.belly.opacity(0.85)))
                }
            }
        }
    }

    private func drawEars(_ context: inout GraphicsContext, _ m: Metrics) {
        let s = m.s
        for sideD in [-1.0, 1.0] {
            let side = CGFloat(sideD)
            switch t.ears {
            case .none:
                break
            case .round:
                let x = m.cx + side * m.w * 0.3
                let c = CGPoint(x: x, y: m.body.topY(at: x) + s * 0.01)
                context.fill(circle(c, s * 0.11), with: .color(look.body))
                context.fill(circle(CGPoint(x: c.x, y: c.y - s * 0.005), s * 0.06), with: .color(look.belly))
            case .cat:
                let x = m.cx + side * m.w * 0.27
                let y = m.body.topY(at: x) + s * 0.05
                context.fill(catEar(base: CGPoint(x: x, y: y), side: side, size: s * 0.2), with: .color(look.body))
                context.fill(catEar(base: CGPoint(x: x + side * s * 0.008, y: y - s * 0.02), side: side, size: s * 0.12), with: .color(look.belly))
            case .bunny:
                let x = m.cx + side * m.w * 0.16
                let base = CGPoint(x: x, y: m.body.topY(at: x) + s * 0.04)
                var ear = context
                ear.translateBy(x: base.x, y: base.y)
                ear.rotate(by: .degrees(Double(side) * 12))
                ear.fill(Path(ellipseIn: CGRect(x: -s * 0.065, y: -s * 0.33, width: s * 0.13, height: s * 0.36)), with: .color(look.body))
                ear.fill(Path(ellipseIn: CGRect(x: -s * 0.032, y: -s * 0.28, width: s * 0.064, height: s * 0.24)), with: .color(look.belly))
            case .floppy:
                // drawn in front of the head, see drawFloppyEars
                break
            case .fins:
                let y = m.top + m.h * 0.32
                let base = CGPoint(x: m.cx + side * m.body.halfWidth(at: y) * 0.92, y: y)
                for angle in [-28.0, 0, 28] {
                    var fin = context
                    fin.translateBy(x: base.x, y: base.y)
                    fin.rotate(by: .degrees(Double(side) * angle))
                    let rect = side > 0
                        ? CGRect(x: -s * 0.02, y: -s * 0.028, width: s * 0.15, height: s * 0.056)
                        : CGRect(x: -s * 0.13, y: -s * 0.028, width: s * 0.15, height: s * 0.056)
                    fin.fill(Path(roundedRect: rect, cornerRadius: s * 0.028), with: .color(look.shade))
                }
            }
        }
    }

    /// Puppy ears hanging down the sides of the head, in front of it.
    private func drawFloppyEars(_ context: inout GraphicsContext, _ m: Metrics) {
        guard t.ears == .floppy else { return }
        let s = m.s
        let y = m.top + m.h * 0.1
        for sideD in [-1.0, 1.0] {
            let side = CGFloat(sideD)
            let base = CGPoint(x: m.cx + side * m.body.halfWidth(at: y) * 0.97, y: y)
            var ear = context
            ear.translateBy(x: base.x, y: base.y)
            ear.rotate(by: .degrees(sideD * -28))
            ear.fill(Path(ellipseIn: CGRect(x: -s * 0.07, y: -s * 0.05, width: s * 0.14, height: s * 0.27)), with: .color(look.shade))
        }
    }

    private func catEar(base: CGPoint, side: CGFloat, size: CGFloat) -> Path {
        // a soft triangle with a rounded tip, leaning a little outward
        var path = Path()
        let left = CGPoint(x: base.x - size * 0.48, y: base.y)
        let right = CGPoint(x: base.x + size * 0.48, y: base.y)
        let tip = CGPoint(x: base.x + side * size * 0.18, y: base.y - size * 0.82)
        path.move(to: left)
        path.addQuadCurve(to: CGPoint(x: tip.x - size * 0.1, y: tip.y + size * 0.12), control: CGPoint(x: left.x + size * 0.12, y: base.y - size * 0.45))
        path.addQuadCurve(to: CGPoint(x: tip.x + size * 0.1, y: tip.y + size * 0.12), control: tip)
        path.addQuadCurve(to: right, control: CGPoint(x: right.x - size * 0.08, y: base.y - size * 0.45))
        path.closeSubpath()
        return path
    }

    private func drawTopper(_ context: inout GraphicsContext, _ m: Metrics) {
        let s = m.s
        let k: CGFloat = m.f >= Self.waveAt ? 1.3 : 1
        let top = m.body.topY(at: m.cx)
        switch t.topper {
        case .none:
            break
        case .antennae:
            for side in [-1.0, 1.0] {
                let x = m.cx + CGFloat(side) * m.w * 0.14
                let base = CGPoint(x: x, y: m.body.topY(at: x) + s * 0.06)
                let tip = CGPoint(x: m.cx + CGFloat(side) * m.w * 0.26, y: top - s * 0.2 * k)
                var stalk = Path()
                stalk.move(to: base)
                stalk.addQuadCurve(to: tip, control: CGPoint(x: base.x, y: tip.y))
                context.stroke(stalk, with: .color(look.dark), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                context.fill(circle(tip, s * 0.05 * k), with: .color(look.dark))
            }
        case .horns:
            for side in [-1.0, 1.0] {
                let x = m.cx + CGFloat(side) * m.w * 0.24
                let y = m.body.topY(at: x)
                var horn = Path()
                horn.move(to: CGPoint(x: x - s * 0.07, y: y + s * 0.08))
                horn.addQuadCurve(to: CGPoint(x: x + CGFloat(side) * s * 0.04 * k, y: y - s * 0.12 * k), control: CGPoint(x: x - s * 0.05, y: y - s * 0.04))
                horn.addQuadCurve(to: CGPoint(x: x + s * 0.07, y: y + s * 0.08), control: CGPoint(x: x + s * 0.06, y: y - s * 0.02))
                horn.closeSubpath()
                // ivory with a soft edge, so it still shows on the paper background
                context.fill(horn, with: .color(Color(red: 0.99, green: 0.9, blue: 0.72)))
                context.stroke(horn, with: .color(look.dark.opacity(0.35)), lineWidth: max(0.75, s * 0.01))
            }
        case .tuft:
            for (dx, r) in [(-0.07, 0.045), (0.0, 0.055), (0.07, 0.045)] {
                let c = CGPoint(x: m.cx + s * CGFloat(dx) * k, y: top + s * 0.005)
                let rr = s * CGFloat(r) * k
                context.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr * 1.4, width: rr * 2, height: rr * 2.4)), with: .color(look.dark))
            }
        case .curl:
            var curl = Path()
            let r = s * 0.045 * k
            curl.move(to: CGPoint(x: m.cx, y: top + s * 0.04))
            curl.addQuadCurve(to: CGPoint(x: m.cx, y: top - s * 0.08 * k), control: CGPoint(x: m.cx - s * 0.03, y: top - s * 0.02))
            curl.addArc(center: CGPoint(x: m.cx + r, y: top - s * 0.08 * k), radius: r, startAngle: .degrees(180), endAngle: .degrees(100), clockwise: false)
            context.stroke(curl, with: .color(look.dark), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round, lineJoin: .round))
        case .sprout:
            var stem = Path()
            let tip = CGPoint(x: m.cx, y: top - s * 0.08 * k)
            stem.move(to: CGPoint(x: m.cx, y: top + s * 0.04))
            stem.addLine(to: tip)
            context.stroke(stem, with: .color(look.dark), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
            for side in [-1.0, 1.0] {
                var leaf = context
                leaf.translateBy(x: tip.x, y: tip.y)
                leaf.rotate(by: .degrees(side * -35))
                let lw = s * 0.11 * k
                let rect = side > 0 ? CGRect(x: 0, y: -lw * 0.22, width: lw, height: lw * 0.44) : CGRect(x: -lw, y: -lw * 0.22, width: lw, height: lw * 0.44)
                leaf.fill(Path(ellipseIn: rect), with: .color(look.shade))
            }
        }
    }

    private func drawArms(_ context: inout GraphicsContext, _ m: Metrics) {
        guard t.arms != .none else { return }
        let s = m.s
        let y = m.cy + m.h * 0.1
        for sideD in [-1.0, 1.0] {
            let side = CGFloat(sideD)
            let shoulder = CGPoint(x: m.cx + side * m.body.halfWidth(at: y) * 0.9, y: y)
            // the arm away from the staff waves once he's quick at this note
            let waving = m.f >= Self.waveAt && (side > 0) != t.flip
            switch t.arms {
            case .none:
                break
            case .nubs:
                var arm = context
                arm.translateBy(x: shoulder.x, y: shoulder.y)
                arm.rotate(by: .degrees(Double(side) * (waving ? -50 : 35)))
                let rect = side > 0 ? CGRect(x: -s * 0.03, y: -s * 0.045, width: s * 0.15, height: s * 0.09) : CGRect(x: -s * 0.12, y: -s * 0.045, width: s * 0.15, height: s * 0.09)
                arm.fill(Path(roundedRect: rect, cornerRadius: s * 0.045), with: .color(look.shade))
            case .noodle:
                var arm = Path()
                arm.move(to: shoulder)
                let hand = waving
                    ? CGPoint(x: shoulder.x + side * s * 0.13, y: shoulder.y - s * 0.17)
                    : CGPoint(x: shoulder.x + side * s * 0.12, y: shoulder.y + s * 0.1)
                arm.addQuadCurve(to: hand, control: CGPoint(x: shoulder.x + side * s * 0.13, y: shoulder.y - (waving ? 0 : s * 0.01)))
                context.stroke(arm, with: .color(look.shade), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
                context.fill(circle(hand, s * 0.04), with: .color(look.shade))
            }
        }
    }

    /// Frog bumps and eye stalks, behind the body so they grow out of it.
    private func drawEyeMounts(_ context: inout GraphicsContext, _ m: Metrics, eyes: [Eye]) {
        switch t.eyePlacement {
        case .top:
            for eye in eyes {
                context.fill(circle(CGPoint(x: eye.center.x, y: eye.center.y + eye.radius * 0.1), eye.radius * 1.28), with: .color(look.body))
            }
        case .stalks:
            for eye in eyes {
                let x = m.cx + (eye.center.x - m.cx) / 1.25
                var stalk = Path()
                stalk.move(to: CGPoint(x: x, y: m.body.topY(at: x) + m.s * 0.06))
                stalk.addLine(to: eye.center)
                context.stroke(stalk, with: .color(look.body), style: StrokeStyle(lineWidth: eye.radius * 0.6, lineCap: .round))
            }
        case .face, .wide:
            break
        }
    }

    // MARK: on the body

    private func drawPattern(_ layer: inout GraphicsContext, _ m: Metrics, eyes: [Eye], mouthY: CGFloat) {
        let s = m.s
        let more = m.f >= Self.morePatternAt
        let spotInk = look.dark.opacity(0.3)

        if t.pattern == .twoTone {
            // a light underside, frog style: a smooth arc from side to side, below the smile
            let edge = min(mouthY + s * 0.12, m.top + m.h * 0.78)
            let depth = m.top + m.h + s * 0.2 - edge
            let under = CGRect(x: m.cx - m.w * 0.75, y: edge, width: m.w * 1.5, height: depth * 2)
            layer.fill(Path(ellipseIn: under), with: .color(look.belly))
        } else if t.belly {
            let belly = CGRect(x: m.cx - m.w * 0.3, y: m.cy - m.h * 0.02, width: m.w * 0.6, height: m.h * 0.5)
            layer.fill(Path(ellipseIn: belly), with: .color(look.belly))
        }

        var rng = SeededRandom(seed: t.patternSeed)
        func unit() -> CGFloat { CGFloat(Double(rng.next() % 10_000) / 10_000) }

        switch t.pattern {
        case .plain, .twoTone:
            break
        case .spots:
            // around the sides and top, never across the face
            for i in 0..<(more ? 7 : 4) {
                let side: CGFloat = i.isMultiple(of: 2) ? -1 : 1
                let v = 0.12 + 0.76 * unit()
                let y = m.top + m.h * v
                let x = m.cx + side * m.body.halfWidth(at: y) * (0.62 + 0.38 * unit())
                layer.fill(circle(CGPoint(x: x, y: y), s * (0.04 + 0.035 * unit())), with: .color(spotInk))
            }
        case .stripes:
            for i in 0..<(more ? 4 : 3) {
                let y = m.top + m.h * (0.22 + 0.17 * CGFloat(i))
                let room = m.body.halfWidth(at: y)
                for side in [-1.0, 1.0] {
                    var band = Path()
                    let outer = CGPoint(x: m.cx + CGFloat(side) * (room + s * 0.02), y: y - s * 0.02)
                    let inner = CGPoint(x: m.cx + CGFloat(side) * (room - m.w * 0.17), y: y + s * 0.015)
                    band.move(to: outer)
                    band.addLine(to: inner)
                    layer.stroke(band, with: .color(spotInk), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
                }
            }
        case .freckles:
            // a little cluster on each cheek, beside the smile
            let y = mouthY - s * 0.075
            let dx = min(m.body.halfWidth(at: y) * 0.66, m.w * 0.33)
            for side in [-1.0, 1.0] {
                let c = CGPoint(x: m.cx + CGFloat(side) * dx, y: y)
                var dots = [(-0.032, -0.01), (0.032, -0.01), (0.0, 0.022)]
                if more { dots.append((0.0, -0.04)) }
                for (ox, oy) in dots {
                    layer.fill(circle(CGPoint(x: c.x + s * CGFloat(ox), y: c.y + s * CGFloat(oy)), s * 0.017), with: .color(look.dark.opacity(0.5)))
                }
            }
        case .patch:
            let eye = t.flip ? eyes.first : eyes.last
            if let eye, t.eyePlacement == .face || t.eyePlacement == .wide {
                layer.fill(circle(eye.center, eye.radius * 1.5), with: .color(look.belly))
            } else {
                // eyes are up top: a patch on the body instead
                let y = m.top + m.h * 0.38
                let x = m.cx + (t.flip ? -1 : 1) * m.body.halfWidth(at: y) * 0.55
                layer.fill(circle(CGPoint(x: x, y: y), s * 0.13), with: .color(look.belly))
            }
            if more {
                for i in 0..<2 {
                    let y = m.top + m.h * (0.55 + 0.15 * CGFloat(i))
                    let x = m.cx + (t.flip ? 1 : -1) * m.body.halfWidth(at: y) * 0.75
                    layer.fill(circle(CGPoint(x: x, y: y), s * 0.04), with: .color(spotInk))
                }
            }
        }
    }

    private func drawEyes(_ context: inout GraphicsContext, _ m: Metrics, eyes: [Eye]) {
        let s = m.s
        let ink = Self.ink
        for eye in eyes {
            let c = eye.center
            let rr = eye.radius
            let (rx, ry) = t.eyeStyle == .oval ? (rr * 0.84, rr * 1.12) : (rr, rr)
            if pose.full {
                // happy closed eyes: an upside-down U
                if t.eyePlacement == .stalks {
                    context.fill(circle(c, rr), with: .color(look.body))
                }
                var arc = Path()
                arc.addArc(center: CGPoint(x: c.x, y: c.y + rr * 0.35), radius: rr * 0.7, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, s * 0.035), lineCap: .round))
                continue
            }
            if pose.blink > 0.8 {
                // shut for a moment in a blink: a soft downward curve, like sleeping
                if t.eyePlacement == .stalks {
                    context.fill(circle(c, rr), with: .color(look.body))
                }
                var arc = Path()
                arc.addArc(center: CGPoint(x: c.x, y: c.y - rr * 0.45), radius: rr * 0.75, startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
                context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: max(1.5, s * 0.03), lineCap: .round))
                continue
            }
            let white = Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
            context.fill(white, with: .color(.white))
            // pupils look left, toward the staff where the notes come from
            let pr = rr * (t.eyeStyle == .sparkle ? 0.6 : 0.5)
            let g = min(1, max(-1, pose.glance))
            let pc = CGPoint(x: c.x + rx * (g < 0 ? -0.22 + 0.2 * g : -0.22 + 0.44 * g), y: c.y + ry * 0.08)
            context.fill(circle(pc, pr), with: .color(ink))
            context.fill(circle(CGPoint(x: pc.x - pr * 0.35, y: pc.y - pr * 0.4), pr * 0.38), with: .color(.white))
            if t.eyeStyle == .sparkle {
                context.fill(circle(CGPoint(x: pc.x + pr * 0.4, y: pc.y + pr * 0.38), pr * 0.18), with: .color(.white))
            }
            if t.eyeStyle == .lid {
                // smiling eyes: a lower lid arching up, the way cheeks push up in a
                // big smile. a top lid read as sleepy or side-eye with the pupils left
                context.drawLayer { lid in
                    lid.clip(to: white)
                    var cover = Path()
                    cover.move(to: CGPoint(x: c.x - rx * 1.1, y: c.y + ry * 1.2))
                    cover.addLine(to: CGPoint(x: c.x - rx * 1.1, y: c.y + ry * 0.8))
                    cover.addQuadCurve(to: CGPoint(x: c.x + rx * 1.1, y: c.y + ry * 0.8), control: CGPoint(x: c.x, y: c.y + ry * 0.12))
                    cover.addLine(to: CGPoint(x: c.x + rx * 1.1, y: c.y + ry * 1.2))
                    cover.closeSubpath()
                    lid.fill(cover, with: .color(look.body))
                }
            }
            if pose.blink > 0.02 {
                // an upper lid in the body colour comes down over the eye
                let b = CGFloat(min(1, pose.blink))
                let edge = c.y - ry + 2 * ry * b
                context.drawLayer { lid in
                    lid.clip(to: white)
                    lid.fill(Path(CGRect(x: c.x - rx * 1.2, y: c.y - ry * 1.2, width: rx * 2.4, height: edge - (c.y - ry * 1.2))), with: .color(look.body))
                    var line = Path()
                    line.move(to: CGPoint(x: c.x - rx * 1.2, y: edge))
                    line.addLine(to: CGPoint(x: c.x + rx * 1.2, y: edge))
                    lid.stroke(line, with: .color(ink.opacity(0.8)), lineWidth: max(1, s * 0.02))
                }
            }
            context.stroke(white, with: .color(ink.opacity(0.8)), lineWidth: max(1, s * 0.014))
            if t.eyeStyle == .lashes {
                for (a, len) in [(-130.0, 0.32), (-90.0, 0.36), (-50.0, 0.32)] {
                    let rad = a * .pi / 180
                    let from = CGPoint(x: c.x + rx * cos(rad), y: c.y + ry * sin(rad))
                    let to = CGPoint(x: c.x + (rx + rr * len) * cos(rad), y: c.y + (ry + rr * len) * sin(rad))
                    var lash = Path()
                    lash.move(to: from)
                    lash.addLine(to: to)
                    context.stroke(lash, with: .color(ink), style: StrokeStyle(lineWidth: max(1, s * 0.018), lineCap: .round))
                }
            }
        }
    }

    private func drawMouth(_ context: inout GraphicsContext, _ m: Metrics, y: CGFloat) {
        let s = m.s
        let cx = m.cx
        let room = m.body.halfWidth(at: y) * 2 * 0.8
        let styleWidth: CGFloat = switch t.mouth {
        case .grin: 0.52
        case .small: 0.3
        case .cat: 0.34
        case .open: 0.46
        case .lopsided: 0.44
        case .wide: 0.7
        }
        let width = min(m.w * styleWidth, room)
        var open = CGFloat(min(1, max(0, pose.mouthOpen)))
        if t.mouth == .open { open = max(open, 0.3) }
        let tilt: CGFloat = t.mouth == .lopsided ? s * 0.025 : 0

        if open > 0.05 {
            let w = min(width + (max(width, m.w * 0.44) - width) * open, room)
            let left = CGPoint(x: cx - w / 2, y: y + tilt)
            let right = CGPoint(x: cx + w / 2, y: y - tilt)
            let depth = s * 0.5 * open * min(1.15, max(0.75, w / (m.w * 0.52)))
            var mouth = Path()
            mouth.move(to: left)
            mouth.addQuadCurve(to: right, control: CGPoint(x: cx, y: y - s * 0.06 * open))
            mouth.addQuadCurve(to: left, control: CGPoint(x: cx, y: y + depth))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(Self.mouthInside))
            context.drawLayer { layer in
                layer.clip(to: mouth)
                let tongue = CGRect(x: cx - w * 0.28, y: y + depth * 0.4, width: w * 0.56, height: depth * 0.4)
                layer.fill(Path(ellipseIn: tongue), with: .color(Self.tongue))
                let lip = y - s * 0.03 * open
                func tooth(_ x: CGFloat, _ tw: CGFloat) {
                    let rect = CGRect(x: x - tw / 2, y: lip, width: tw, height: s * 0.075 * open + s * 0.02)
                    layer.fill(Path(roundedRect: rect, cornerRadius: tw * 0.3), with: .color(.white))
                }
                switch t.teeth {
                case .none:
                    break
                case .buck:
                    tooth(cx - w * 0.16, s * 0.07)
                    tooth(cx + w * 0.16, s * 0.07)
                case .one:
                    tooth(cx, s * 0.085)
                case .row:
                    for k in [-0.3, -0.1, 0.1, 0.3] {
                        let x = cx + w * CGFloat(k)
                        let rect = CGRect(x: x - s * 0.024, y: lip, width: s * 0.048, height: s * 0.04 * open + s * 0.018)
                        layer.fill(Path(roundedRect: rect, cornerRadius: s * 0.02), with: .color(.white))
                    }
                case .under:
                    for side in [-1.0, 1.0] {
                        let x = cx + CGFloat(side) * w * 0.22
                        let rect = CGRect(x: x - s * 0.032, y: y + depth * 0.42 - s * 0.07, width: s * 0.064, height: s * 0.1)
                        layer.fill(Path(roundedRect: rect, cornerRadius: s * 0.025), with: .color(.white))
                    }
                }
            }
            return
        }

        let lineWidth = s * 0.035
        let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let left = CGPoint(x: cx - width / 2, y: y + tilt * 0.6)
        let right = CGPoint(x: cx + width / 2, y: y - tilt)
        let depth: CGFloat = switch t.mouth {
        case .small: s * 0.09
        case .wide: s * 0.1
        case .cat: s * 0.06
        default: s * (pose.full ? 0.2 : 0.15)
        }
        var smile = Path()
        smile.move(to: left)
        if t.mouth == .cat {
            // :3
            smile.addQuadCurve(to: CGPoint(x: cx, y: y), control: CGPoint(x: cx - width / 4, y: y + depth * 2))
            smile.addQuadCurve(to: right, control: CGPoint(x: cx + width / 4, y: y + depth * 2))
        } else {
            smile.addQuadCurve(to: right, control: CGPoint(x: cx + (t.mouth == .lopsided ? width * 0.1 : 0), y: y + depth))
        }
        if t.mouth == .wide {
            // little upturned ends
            for (end, side) in [(left, -1.0), (right, 1.0)] {
                var flick = Path()
                flick.move(to: end)
                flick.addLine(to: CGPoint(x: end.x + CGFloat(side) * s * 0.02, y: end.y - s * 0.035))
                context.stroke(flick, with: .color(Self.mouthInk), style: stroke)
            }
        }
        // the lowest point of the smile, where teeth hang
        let low = t.mouth == .cat ? y + depth * 0.95 : y + depth / 2
        let lowX = t.mouth == .cat ? cx : cx + (t.mouth == .lopsided ? width * 0.05 : 0)

        // teeth peeking out of a closed smile
        let toothInk = Self.ink.opacity(0.5)
        func peek(_ x: CGFloat, _ top: CGFloat, _ tw: CGFloat, _ th: CGFloat) {
            let rect = CGRect(x: x - tw / 2, y: top, width: tw, height: th)
            let path = Path(roundedRect: rect, cornerRadius: tw * 0.32)
            context.fill(path, with: .color(.white))
            context.stroke(path, with: .color(toothInk), lineWidth: max(0.75, s * 0.008))
        }
        switch t.teeth {
        case .buck:
            peek(lowX - s * 0.026, low - lineWidth * 0.3, s * 0.05, s * 0.06)
            peek(lowX + s * 0.026, low - lineWidth * 0.3, s * 0.05, s * 0.06)
        case .one:
            peek(lowX, low - lineWidth * 0.3, s * 0.06, s * 0.065)
        case .under:
            if t.mouth != .cat {
                for side in [-1.0, 1.0] {
                    // on the curve, a third of the way in from each end
                    let x = cx + CGFloat(side) * width * 0.3
                    let yOnCurve = y + depth * 0.42 + (side < 0 ? tilt * 0.4 : -tilt * 0.6)
                    peek(x, yOnCurve - s * 0.05, s * 0.045, s * 0.05)
                }
            }
        case .none, .row:
            break
        }
        context.stroke(smile, with: .color(Self.mouthInk), style: stroke)

        if m.f >= Self.tongueAt {
            // silly: tongue poking out
            let x = t.teeth == .buck || t.teeth == .one ? lowX + width * 0.2 : cx + width * 0.08
            let tongue = CGRect(x: x - s * 0.02, y: low - s * 0.005, width: s * 0.1, height: s * 0.09)
            context.fill(Path(ellipseIn: tongue), with: .color(Self.tongue))
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

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// Body proportions per shape, in units of the muncher's size.
private struct ShapeSpec {
    var width: Double
    var height: Double
    /// superellipse exponents: 2 is an ellipse, higher is boxier
    var nTop: Double
    var nBottom: Double
    /// > 0 wider at the bottom (pear), < 0 wider at the top (bean)
    var taper = 0.0
    /// soft scallops all round (fluffy)
    var bumps = 0
    /// eye line and mouth line, from the top of the body
    var eyeY = 0.3
    var mouthY = 0.6

    init(_ shape: MuncherLook.BodyShape) {
        switch shape {
        case .round: (width, height, nTop, nBottom) = (0.8, 0.72, 2, 2)
        case .tall: (width, height, nTop, nBottom, eyeY, mouthY) = (0.62, 0.86, 2.2, 2.4, 0.27, 0.55)
        case .wide: (width, height, nTop, nBottom, eyeY, mouthY) = (0.96, 0.6, 2.4, 2.6, 0.33, 0.63)
        case .pear: (width, height, nTop, nBottom, taper, eyeY) = (0.8, 0.78, 2, 2.5, 0.34, 0.31)
        case .boxy: (width, height, nTop, nBottom) = (0.76, 0.72, 3.4, 3.4)
        case .gumdrop: (width, height, nTop, nBottom, eyeY, mouthY) = (0.8, 0.76, 2, 5, 0.32, 0.6)
        case .bean: (width, height, nTop, nBottom, taper, mouthY) = (0.84, 0.74, 2.3, 2.3, -0.17, 0.58)
        case .fluffy: (width, height, nTop, nBottom, bumps) = (0.8, 0.74, 2, 2, 16)
        }
    }

    /// Half-width at normalized height `uy` (-1 top ... 1 bottom), before normalizing.
    func rawHalfWidth(_ uy: Double) -> Double {
        let n = uy < 0 ? nTop : nBottom
        let a = abs(uy)
        guard a < 1 else { return 0 }
        return pow(1 - pow(a, n), 1 / n) * (1 + taper * uy)
    }
}

/// A smooth closed body outline: a superellipse, maybe tapered, maybe scalloped.
private struct BodyOutline {
    let center: CGPoint
    let width: CGFloat
    let height: CGFloat
    let path: Path
    private let spec: ShapeSpec
    private let norm: Double
    /// the top half, left to right
    private let topHalf: [CGPoint]

    init(spec: ShapeSpec, center: CGPoint, width: CGFloat, height: CGFloat) {
        self.spec = spec
        self.center = center
        self.width = width
        self.height = height
        // the widest point of a tapered body is the real width
        var widest = 0.0
        for i in 0...60 { widest = max(widest, spec.rawHalfWidth(-1 + 2 * Double(i) / 60)) }
        norm = widest
        let count = 144
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            let c = cos(a), sn = sin(a)
            let e = 2 / (sn < 0 ? spec.nTop : spec.nBottom)
            let uy = copysign(pow(abs(sn), e), sn)
            var ux = copysign(pow(abs(c), e), c) * (1 + spec.taper * uy) / widest
            var vy = uy
            if spec.bumps > 0 {
                let k = 1 + 0.035 * cos(Double(spec.bumps) * a)
                ux *= k
                vy *= k
            }
            points.append(CGPoint(x: center.x + width / 2 * CGFloat(ux), y: center.y + height / 2 * CGFloat(vy)))
        }
        // angles from pi to 2pi are the top half, left to right
        topHalf = Array(points[(count / 2)...]) + [points[0]]
        path = Self.smooth(points)
    }

    /// Catmull-Rom through the points, as cubic curves.
    private static func smooth(_ p: [CGPoint]) -> Path {
        var path = Path()
        let n = p.count
        path.move(to: p[0])
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    /// Half the body's width at height `y` (smooth shape, ignores scallops).
    func halfWidth(at y: CGFloat) -> CGFloat {
        let uy = Double((y - center.y) / (height / 2))
        return width / 2 * CGFloat(spec.rawHalfWidth(min(1, max(-1, uy))) / norm)
    }

    /// The top edge of the body above `x`.
    func topY(at x: CGFloat) -> CGFloat {
        var best = topHalf[0]
        for p in topHalf where abs(p.x - x) < abs(best.x - x) { best = p }
        return best.y
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
    /// shell spot colours, taken in turn. Empty = the muncher's own colour.
    var spotColors: [Color] = []
    /// Where the baby stands once it's out, in the same coordinates as the egg's rect.
    /// The hatch screen passes the spot its colour pick starts from, so nothing jumps.
    /// nil = just above the bottom shell.
    var babyRect: CGRect?
    var babyFluency = 0.0
    /// The egg's tilt in radians, about its bottom. nil = the built-in wobble before the
    /// crack. Home's idle wobble and the hatch's growing rocks set their own.
    var rock: Double?

    private let shell = Color(red: 1, green: 0.97, blue: 0.9)

    func draw(in context: inout GraphicsContext, rect: CGRect, id: ItemID) {
        let p = progress
        let s = min(rect.width, rect.height)
        let cx = rect.midX
        let bottom = rect.maxY - s * 0.04
        let eggW = s * 0.56
        let eggH = s * 0.72
        let center = CGPoint(x: cx, y: bottom - eggH / 2)
        let wobble = rock ?? (p < 0.5 ? sin(p * .pi * 10) * 0.14 * (p / 0.5) : 0)

        // the baby pops out of the bottom half: drawn first, so the shell is in front of it
        if p > 0.55 {
            let t = min(1, (p - 0.55) / 0.35)
            let grow = 1 - pow(1 - t, 3)
            let from = CGRect(x: cx - s * 0.2, y: bottom - s * 0.4, width: s * 0.4, height: s * 0.4)
            let to = babyRect ?? CGRect(x: cx - s * 0.475, y: bottom - s * 1.07, width: s * 0.95, height: s * 0.95)
            let baby = CGRect(
                x: from.minX + (to.minX - from.minX) * grow, y: from.minY + (to.minY - from.minY) * grow,
                width: from.width + (to.width - from.width) * grow, height: from.height + (to.height - from.height) * grow
            )
            let pose = MuncherPose(fluency: babyFluency, mouthOpen: grow > 0.8 ? 0.6 : 0)
            MuncherPainter(look: look, pose: pose).draw(in: &context, rect: baby)
        }

        var egg = context
        egg.translateBy(x: center.x, y: bottom)
        egg.rotate(by: .radians(wobble))
        egg.translateBy(x: -center.x, y: -bottom)
        let eggPath = Self.eggPath(center: center, width: eggW, height: eggH)
        let crackY = center.y - eggH * 0.02
        let crack = Self.crack(center: center, y: crackY, width: eggW)
        let crackStyle = StrokeStyle(lineWidth: s * 0.02, lineJoin: .round)

        if p <= 0.55 {
            drawShell(&egg, eggPath, center: center, s: s)
            if p > 0.35 {
                egg.stroke(crack, with: .color(Theme.keyEdge), style: crackStyle)
            }
            return
        }
        // the two halves keep their outline and spots while they fall away, so the
        // screen is never empty while the baby comes out. top half: up and over.
        // bottom half: stays a moment, then sinks. both fade at the end
        let q = (p - 0.55) / 0.45
        func ease(_ a: Double, _ b: Double) -> Double {
            let x = min(1, max(0, (q - a) / (b - a)))
            return x * x * (3 - 2 * x)
        }
        let far = s * 2
        var below = Self.crackLine(center: center, y: crackY, width: eggW, reach: far)
        below.addLine(to: CGPoint(x: cx + far, y: rect.maxY + far))
        below.addLine(to: CGPoint(x: cx - far, y: rect.maxY + far))
        below.closeSubpath()
        var above = Self.crackLine(center: center, y: crackY, width: eggW, reach: far)
        above.addLine(to: CGPoint(x: cx + far, y: rect.minY - far))
        above.addLine(to: CGPoint(x: cx - far, y: rect.minY - far))
        above.closeSubpath()

        var bottomHalf = egg
        bottomHalf.opacity = 1 - ease(0.45, 1)
        bottomHalf.translateBy(x: 0, y: s * 0.18 * CGFloat(ease(0.35, 1)))
        bottomHalf.clip(to: below)
        drawShell(&bottomHalf, eggPath, center: center, s: s)
        bottomHalf.stroke(crack, with: .color(Theme.keyEdge), style: crackStyle)

        var topHalf = egg
        let lift = ease(0, 0.8)
        topHalf.opacity = 1 - ease(0.4, 1)
        topHalf.translateBy(x: center.x + s * 0.32 * CGFloat(lift), y: crackY - s * 0.42 * CGFloat(lift))
        topHalf.rotate(by: .radians(0.9 * lift))
        topHalf.translateBy(x: -center.x, y: -crackY)
        topHalf.clip(to: above)
        drawShell(&topHalf, eggPath, center: center, s: s)
        topHalf.stroke(crack, with: .color(Theme.keyEdge), style: crackStyle)
    }

    /// Shell, its spots and its outline.
    private func drawShell(_ context: inout GraphicsContext, _ eggPath: Path, center: CGPoint, s: CGFloat) {
        context.fill(eggPath, with: .color(shell))
        context.drawLayer { layer in
            layer.clip(to: eggPath)
            for (i, (dx, dy, r)) in [(-0.18, -0.2, 0.07), (0.15, -0.05, 0.09), (-0.1, 0.18, 0.06), (0.2, 0.22, 0.05)].enumerated() {
                let c = CGPoint(x: center.x + s * CGFloat(dx), y: center.y + s * CGFloat(dy))
                let rr = s * CGFloat(r)
                let color = spotColors.isEmpty ? look.body : spotColors[i % spotColors.count]
                layer.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(color.opacity(0.75)))
            }
        }
        context.stroke(eggPath, with: .color(Theme.keyEdge.opacity(0.5)), lineWidth: max(1, s * 0.012))
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
        path.addLines(crackPoints(center: center, y: y, width: width))
        return path
    }

    private static func crackPoints(center: CGPoint, y: CGFloat, width: CGFloat) -> [CGPoint] {
        let left = center.x - width * 0.42
        return (0...6).map { i in
            CGPoint(x: left + width * 0.84 * CGFloat(i) / 6, y: y + (i.isMultiple(of: 2) ? 0 : -width * 0.08))
        }
    }

    /// The crack, carried on flat out to `reach` on both sides, left to right. Closed
    /// above or below, it splits the shell into its two halves.
    static func crackLine(center: CGPoint, y: CGFloat, width: CGFloat, reach: CGFloat) -> Path {
        var path = Path()
        path.addLines([CGPoint(x: center.x - reach, y: y)] + crackPoints(center: center, y: y, width: width) + [CGPoint(x: center.x + reach, y: y)])
        return path
    }
}
