import CoreGraphics
import NoteCore

/// What the staff has to make room for: which staves, the key signature, whether
/// there's a time signature, and the widest screen it will show. The vertical room on
/// each staff is fixed, so the staff sits in the same place on every screen and in
/// every lesson.
struct StaffSpec: Hashable {
    var layout: StaffLayout
    var keySignature: KeySignature
    /// Room for a time signature after the key signature (every practice screen).
    var hasMeter: Bool
    /// Widest screen it has to fit, in line gaps, left margin to right margin.
    var width: Double

    init(layout: StaffLayout, keySignature: KeySignature = .none, hasMeter: Bool = false, noteWidth: Double) {
        self.layout = layout
        self.keySignature = keySignature
        self.hasMeter = hasMeter
        width = Metrics.systemLeft(layout) + Metrics.notesStart(keySignature, meter: hasMeter) + noteWidth + Metrics.rightPad
    }

    /// Room for the biggest screen a lesson can show, in either meter: its largest size
    /// plus a stretch note in the widest way the bars can be written, or its most bars
    /// of the busiest rhythm.
    init(lesson: Lesson, layout: StaffLayout) {
        var widest = 0.0
        for meter in Meter.allCases {
            if case .rhythm(let values, _) = lesson.texture {
                let bars = layout == .grand ? 2 : lesson.sizes.upperBound
                widest = max(widest, Double(bars) * Metrics.busiestBar(meter, values: values) + Metrics.barsExtra(bars))
            } else {
                let n = min(lesson.sizes.upperBound + 1, MasteryEngine.maxNotes(meter))
                var splits: [[Int]] = n <= meter.beats ? [[n]] : []
                for first in 1..<max(1, n) where first <= meter.beats && n - first <= meter.beats && n - first >= 1 {
                    splits.append([first, n - first])
                }
                for split in splits {
                    let width = split.reduce(0) { $0 + Metrics.widestBar(notes: $1, meter: meter) } + Metrics.barsExtra(split.count)
                    widest = max(widest, width)
                }
            }
        }
        self.init(layout: layout, keySignature: lesson.keySignature, hasMeter: true, noteWidth: widest)
    }

    /// Exactly one screen (galleries, the collection's tiny staffs, parent previews).
    init(item: PracticeItem) {
        self.init(layout: item.layout, keySignature: item.keySignature, hasMeter: item.meter != nil, noteWidth: Metrics.notesWidth(item))
    }

    /// Staves top to bottom (grand staff: treble over bass).
    var clefs: [Clef] {
        switch layout {
        case .treble: [.treble]
        case .bass: [.bass]
        case .grand: [.treble, .bass]
        }
    }

    /// Steps of the whole drawing, top of the highest staff's room to the bottom of
    /// the lowest's.
    var heightInSteps: Double {
        switch layout {
        case .treble: Metrics.room(.treble).upperBound - Metrics.room(.treble).lowerBound
        case .bass: Metrics.room(.bass).upperBound - Metrics.room(.bass).lowerBound
        case .grand: Metrics.room(.treble).upperBound + Metrics.grandSpace + 8 - Metrics.room(.bass).lowerBound
        }
    }
}

/// Sizes in line gaps (or steps where it says so). One place to tune the look.
enum Metrics {
    /// Line gap on the iPad, in points, at the parent's staff size 1.0. Sized so 2-4
    /// bars fit on an 11 inch iPad in landscape. The same for every lesson; it only
    /// shrinks when a screen wouldn't fit (a small window on the mac).
    static let gap: CGFloat = 30

    // notehead: filled ellipse a little heavier than engraving, tilted like engraved heads
    static let headRX = 0.64
    static let headRY = 0.50
    static let headTilt = -20.0 // degrees
    /// half width of the tilted head, for ledger lines and stems
    static let headHalfWidth = 0.61
    /// a whole note's head is wider and rounder, like engraved ones
    static let wholeRX = 0.8
    static let wholeRY = 0.54
    static func headHalfWidth(_ value: NoteValue?) -> Double { value == .whole ? wholeRX : headHalfWidth }
    /// ledger lines stick out this far past the head on each side
    static let ledgerOverhang = 0.42
    /// the augmentation dot: its centre this far right of the head's edge, and its radius
    static let dotOffset = 0.42
    static let dotRadius = 0.21

    static let leftPad = 0.5
    /// room for the grand staff's brace in front of the system line. Everything else
    /// on the grand staff moves right by this much
    static let braceRoom = 1.2
    static func systemLeft(_ layout: StaffLayout) -> Double { layout == .grand ? braceRoom : 0 }
    static let clefX = leftPad + 0.4
    static let clefWidth = 2.8
    /// one sharp in the key signature
    static let sharpWidth = 1.1
    /// the time signature's digits (Bravura's are about 1.8 spaces wide)
    static let meterWidth = 1.8
    static let rightPad = 0.8
    /// room on each side of a bar line, and before the final one
    static let barGap = 1.1
    static let endGap = 0.7

    /// Left edge of the time signature: past the key signature's sharps (which start
    /// half a gap after the clef), or that half gap after the clef.
    static func meterX(_ key: KeySignature) -> Double {
        let sharps = Double(key.sharpSteps(.treble).count)
        return clefX + clefWidth + 0.5 + sharps * sharpWidth + (sharps > 0 ? 0.35 : 0)
    }

    static func notesStart(_ key: KeySignature, meter: Bool) -> Double {
        meter ? meterX(key) + meterWidth + 1.1 : clefX + clefWidth + Double(key.sharpSteps(.treble).count) * sharpWidth + 1.3
    }

    /// Space between the treble staff's bottom line and the bass staff's top line, in
    /// steps. Middle C's ledger line from both sides fits with room between.
    static let grandSpace = 10.0

    /// Steps of room on each staff, fixed so the staff never moves between screens:
    /// the lowest and highest notes the levels use, their stems, and the clef glyph.
    static func room(_ clef: Clef) -> ClosedRange<Double> {
        switch clef {
        case .treble: -4.5...11.5 // middle C and a stem down from B4, G5 and the G clef's top
        case .bass: -3.5...12.0 // a stem down from D3, middle C from above
        }
    }

    // stems, flags and beams, in line gaps
    static let stemLength = 3.5
    static let stemWidth = 0.16
    static let beamThickness = 0.5

    /// Stem direction per column, from the note farthest from the middle line (below it:
    /// stems up). A beamed pair shares one direction, set the same way over both notes.
    static func stemsUp(_ item: PracticeItem) -> [Bool] {
        func up(_ steps: [Int]) -> Bool {
            let farthest = steps.max { abs($0 - StaffPosition.middleLineStep) < abs($1 - StaffPosition.middleLineStep) }
            return (farthest ?? 0) < StaffPosition.middleLineStep
        }
        var ups = item.notes.indices.map { up(item.positions(ofNote: $0).map(\.step)) }
        for start in item.beamedPairStarts {
            let pairUp = up((item.positions(ofNote: start) + item.positions(ofNote: start + 1)).map(\.step))
            ups[start] = pairUp
            ups[start + 1] = pairUp
        }
        return ups
    }

    /// Width of a note's column in line gaps, before stretching to fill the staff:
    /// roughly by length so a half takes more room than a quarter, but roomy, not
    /// engraving-tight. nil: a plain head with no rhythm (tiny staffs).
    static func columnWidth(_ value: NoteValue?) -> Double {
        switch value {
        case nil: 3
        case .eighth: 1.7
        case .quarter: 2.3
        case .half: 3.0
        case .dottedHalf: 3.5
        case .whole: 3.7
        }
    }

    /// A rest's column. Rests are drawn smaller than the room their length would get as
    /// a note, so a bar with a rest isn't wider than the same bar full of notes.
    static func restWidth(_ value: NoteValue) -> Double {
        value == .quarter ? 2.0 : 2.4
    }

    /// A bar with one long note still gets some room, so the note doesn't sit on the bar line.
    static let minBar = 5.4

    /// Width of one bar's notes and rests.
    static func barWidth(_ notes: some Collection<WrittenNote>) -> Double {
        max(minBar, notes.reduce(0) { $0 + columnWidth($1.value) + $1.restsAfter.reduce(0) { $0 + restWidth($1) } })
    }

    static func barWidth(_ rhythm: BarRhythm) -> Double {
        max(minBar, rhythm.values.reduce(0) { $0 + columnWidth($1) } + rhythm.rests.reduce(0) { $0 + restWidth($1) })
    }

    /// The widest way a reading screen can write `notes` notes in one bar.
    static func widestBar(notes: Int, meter: Meter) -> Double {
        MasteryEngine.readingBars(notes: notes, meter: meter).map { barWidth($0.rhythm) }.max() ?? 0
    }

    /// The busiest bar a rhythm lesson can write: an eighth pair and quarters.
    static func busiestBar(_ meter: Meter, values: [NoteValue]) -> Double {
        let pair = values.contains(.eighth) ? 2 * columnWidth(.eighth) - columnWidth(.quarter) : 0
        return Double(meter.beats) * columnWidth(.quarter) + pair
    }

    /// Bar lines between `bars` bars and the gap before the final bar line.
    static func barsExtra(_ bars: Int) -> Double {
        Double(max(0, bars - 1)) * barGap + endGap
    }

    /// Notes, rests and the room around bar lines.
    static func notesWidth(_ item: PracticeItem) -> Double {
        guard item.meter != nil else {
            return Double(item.notes.count) * columnWidth(nil) + Double(item.barLinesAfter.count) * barGap
        }
        return item.barRanges.reduce(0) { $0 + barWidth(item.notes[$1]) } + barsExtra(item.bars.count)
    }
}

/// Where everything on a screen goes, left to right.
struct ScreenLayout {
    struct Rest {
        var value: NoteValue
        var clef: Clef
        var x: CGFloat
        /// the note it follows, and which of that note's rests it is
        var note: Int
        var index: Int
    }

    /// Centre x of each note's column.
    var notes: [CGFloat] = []
    var rests: [Rest] = []
    /// Bar lines between bars.
    var barLines: [CGFloat] = []
    /// Each bar's span, bar line to bar line (for a whole-bar rest on an idle staff).
    var bars: [ClosedRange<CGFloat>] = []
    /// The final bar line, where the staff ends. nil without a meter (the staff runs on).
    var end: CGFloat?
}

/// Concrete positions for one staff area size.
struct StaffGeometry {
    let spec: StaffSpec
    let size: CGSize
    /// line gap in points
    let g: CGFloat
    let lineWidth: CGFloat
    private let bottomLine: [Clef: CGFloat]
    /// where the staff starts, past the brace on the grand staff. Clef, key signature
    /// and notes are placed from here
    let systemLeft: CGFloat
    let staffLeft: CGFloat
    let staffRight: CGFloat

    /// - gap: the line gap wanted (the practice screen passes `Metrics.gap` times the
    ///   parent's size). nil = the biggest that fits (small previews)
    init(spec: StaffSpec, size: CGSize, style: StaffStyle, gap: CGFloat? = nil) {
        self.spec = spec
        self.size = size
        let byHeight = size.height / CGFloat(spec.heightInSteps / 2)
        let byWidth = size.width / CGFloat(spec.width)
        let fits = min(byHeight, byWidth)
        let g = max(4, gap.map { min($0, fits) } ?? fits)
        self.g = g
        lineWidth = max(1.5, g * CGFloat(style.lineThickness) * (style.highContrast ? 1.15 : 1))

        // center the staves vertically
        let contentHeight = CGFloat(spec.heightInSteps) * g / 2
        let top = (size.height - contentHeight) / 2
        let treble = Metrics.room(.treble), bass = Metrics.room(.bass)
        var lines: [Clef: CGFloat] = [:]
        switch spec.layout {
        case .treble:
            lines[.treble] = top + CGFloat(treble.upperBound) * g / 2
        case .bass:
            lines[.bass] = top + CGFloat(bass.upperBound) * g / 2
        case .grand:
            let trebleBottom = top + CGFloat(treble.upperBound) * g / 2
            lines[.treble] = trebleBottom
            lines[.bass] = trebleBottom + CGFloat(Metrics.grandSpace + 8) * g / 2
        }
        bottomLine = lines
        // the staff always spans the full width (after the brace)
        systemLeft = CGFloat(Metrics.systemLeft(spec.layout)) * g
        staffLeft = systemLeft + CGFloat(Metrics.leftPad) * g
        staffRight = size.width - CGFloat(Metrics.leftPad) * g
    }

    func y(_ step: Int, on clef: Clef) -> CGFloat {
        y(Double(step), on: clef)
    }

    func y(_ step: Double, on clef: Clef) -> CGFloat {
        (bottomLine[clef] ?? 0) - CGFloat(step) * g / 2
    }

    var clefX: CGFloat { systemLeft + CGFloat(Metrics.clefX) * g }
    var keySignatureX: CGFloat { systemLeft + CGFloat(Metrics.clefX + Metrics.clefWidth + 0.5) * g }
    /// Left edge of the time signature's digits.
    var meterX: CGFloat { systemLeft + CGFloat(Metrics.meterX(spec.keySignature)) * g }
    var notesLeft: CGFloat { systemLeft + CGFloat(Metrics.notesStart(spec.keySignature, meter: spec.hasMeter)) * g }
    var notesRight: CGFloat { size.width - CGFloat(Metrics.rightPad) * g }

    /// Top line of the highest staff to the bottom line of the lowest, for bar lines.
    var systemTop: CGFloat { y(8, on: spec.clefs[0]) }
    var systemBottom: CGFloat { y(0, on: spec.clefs[spec.clefs.count - 1]) }

    /// Where each column, rest and bar line goes. Screens with a meter start right after
    /// the time signature and stretch up to 1.4x their natural width to use the room;
    /// the staff ends at the final bar line. Screens without one (tiny staffs) are
    /// centred in the room and the staff runs on.
    func layout(_ item: PracticeItem) -> ScreenLayout {
        var result = ScreenLayout()
        let room = notesRight - notesLeft
        guard item.meter != nil else {
            let widths = item.notes.map { _ in CGFloat(Metrics.columnWidth(nil)) * g }
            let bars = Set(item.barLinesAfter)
            let barRoom = CGFloat(Metrics.barGap) * g
            let natural = widths.reduce(0, +) + CGFloat(bars.count) * barRoom
            let stretch = min(1.4, max(natural, room) / natural)
            var x = notesLeft + (max(natural, room) - natural * stretch) / 2
            for (i, w) in widths.enumerated() {
                result.notes.append(x + w * stretch / 2)
                x += w * stretch
                if bars.contains(i) {
                    result.barLines.append(x + barRoom * stretch / 2)
                    x += barRoom * stretch
                }
            }
            return result
        }
        let natural = CGFloat(Metrics.notesWidth(item)) * g
        let k = min(1.4, max(1, room / natural))
        var x = notesLeft
        var barStart = notesLeft - CGFloat(Metrics.barGap) * g * k / 2
        for (b, range) in item.barRanges.enumerated() {
            if b > 0 {
                let line = x + CGFloat(Metrics.barGap) * g * k / 2
                result.bars.append(barStart...line)
                result.barLines.append(line)
                barStart = line
                x += CGFloat(Metrics.barGap) * g * k
            }
            let start = x
            for i in range {
                let note = item.notes[i]
                let w = CGFloat(Metrics.columnWidth(note.value)) * g * k
                result.notes.append(x + w / 2)
                x += w
                for (j, rest) in note.restsAfter.enumerated() {
                    let rw = CGFloat(Metrics.restWidth(rest)) * g * k
                    result.rests.append(.init(value: rest, clef: note.clef, x: x + rw / 2, note: i, index: j))
                    x += rw
                }
            }
            // a short bar (one whole note) takes the bar's minimum room after its notes
            x = max(x, start + CGFloat(Metrics.barWidth(item.notes[range])) * g * k)
        }
        let end = x + CGFloat(Metrics.endGap) * g * k
        result.bars.append(barStart...end)
        result.end = end
        return result
    }
}
