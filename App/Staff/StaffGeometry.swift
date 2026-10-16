import CoreGraphics
import NoteCore

/// What the staff has to make room for: which staves, the key signature, and the
/// widest screen it will show. The vertical room on each staff is fixed, so the staff
/// sits in the same place on every screen and in every lesson.
struct StaffSpec: Hashable {
    var layout: StaffLayout
    var keySignature: KeySignature
    /// Widest screen it has to fit, in line gaps, left margin to right margin.
    var width: Double

    init(layout: StaffLayout, keySignature: KeySignature = .none, noteWidth: Double) {
        self.layout = layout
        self.keySignature = keySignature
        width = Metrics.notesStart(keySignature) + noteWidth + Metrics.rightPad
    }

    /// Room for the biggest screen a lesson can show (its largest size plus a stretch note).
    init(lesson: Lesson, layout: StaffLayout) {
        let columns = lesson.sizes.upperBound + 1
        let bars = MasteryEngine.bars(columns).count
        let noteWidth = Double(columns) * Metrics.columnWidth(nil) + Double(bars - 1) * Metrics.barGap
        self.init(layout: layout, keySignature: lesson.keySignature, noteWidth: noteWidth)
    }

    /// Exactly one screen (galleries, the collection's tiny staffs, parent previews).
    init(item: PracticeItem) {
        self.init(layout: item.layout, keySignature: item.keySignature, noteWidth: Metrics.notesWidth(item))
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
    /// ledger lines stick out this far past the head on each side
    static let ledgerOverhang = 0.42

    static let leftPad = 0.5
    static let clefX = leftPad + 0.4
    static let clefWidth = 2.8
    /// one sharp in the key signature
    static let sharpWidth = 1.1
    static let rightPad = 1.0
    /// extra room on each side of a bar line
    static let barGap = 1.2

    static func notesStart(_ key: KeySignature) -> Double {
        clefX + clefWidth + Double(key.sharpSteps(.treble).count) * sharpWidth + 1.3
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

    // stems, flags and beams (rhythm screens), in line gaps
    static let stemLength = 3.5
    static let stemWidth = 0.16
    static let beamThickness = 0.5

    /// Stem direction per column. Single notes: below the middle line stems go up.
    /// A beamed pair shares one direction, set by the note farther from the middle line.
    static func stemsUp(_ item: PracticeItem) -> [Bool] {
        var up = item.notes.indices.map { item.positions(ofNote: $0).first.map(\.stemUp) ?? true }
        for start in item.beamedPairStarts {
            let steps = [start, start + 1].map { item.positions(ofNote: $0)[0].step }
            let farthest = steps.max { abs($0 - StaffPosition.middleLineStep) < abs($1 - StaffPosition.middleLineStep) }!
            let pairUp = farthest < StaffPosition.middleLineStep
            up[start] = pairUp
            up[start + 1] = pairUp
        }
        return up
    }

    /// Width of one column in line gaps, before stretching to fill the staff.
    static func columnWidth(_ value: NoteValue?) -> Double {
        switch value {
        case nil: 3
        case .eighth: 2.3
        case .quarter: 2.9
        case .half: 3.9
        }
    }

    static func columnWidths(_ item: PracticeItem) -> [Double] {
        item.notes.map { columnWidth($0.value) }
    }

    /// Notes plus the room around bar lines.
    static func notesWidth(_ item: PracticeItem) -> Double {
        columnWidths(item).reduce(0, +) + Double(item.barLinesAfter.count) * barGap
    }
}

/// Concrete positions for one staff area size.
struct StaffGeometry {
    let spec: StaffSpec
    let size: CGSize
    /// line gap in points
    let g: CGFloat
    let lineWidth: CGFloat
    private let bottomLine: [Clef: CGFloat]
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
        // the staff always spans the full width
        staffLeft = CGFloat(Metrics.leftPad) * g
        staffRight = size.width - CGFloat(Metrics.leftPad) * g
    }

    func y(_ step: Int, on clef: Clef) -> CGFloat {
        y(Double(step), on: clef)
    }

    func y(_ step: Double, on clef: Clef) -> CGFloat {
        (bottomLine[clef] ?? 0) - CGFloat(step) * g / 2
    }

    var clefX: CGFloat { CGFloat(Metrics.clefX) * g }
    var keySignatureX: CGFloat { CGFloat(Metrics.clefX + Metrics.clefWidth + 0.5) * g }
    var notesLeft: CGFloat { CGFloat(Metrics.notesStart(spec.keySignature)) * g }
    var notesRight: CGFloat { size.width - CGFloat(Metrics.rightPad) * g }

    /// Top line of the highest staff to the bottom line of the lowest, for bar lines.
    var systemTop: CGFloat { y(8, on: spec.clefs[0]) }
    var systemBottom: CGFloat { y(0, on: spec.clefs[spec.clefs.count - 1]) }

    /// Center x of each column. Columns stretch up to 1.4x their natural width to use
    /// the room, then the screen is centered in what's left. Bar lines get room on both sides.
    func columnCenters(_ item: PracticeItem) -> [CGFloat] {
        let widths = Metrics.columnWidths(item).map { CGFloat($0) * g }
        let bars = Set(item.barLinesAfter)
        let barRoom = CGFloat(Metrics.barGap) * g
        let natural = widths.reduce(0, +) + CGFloat(bars.count) * barRoom
        let room = max(natural, notesRight - notesLeft)
        let stretch = min(1.4, room / natural)
        let used = natural * stretch
        var x = notesLeft + (room - used) / 2
        return widths.enumerated().map { i, w in
            defer { x += (w + (bars.contains(i) ? barRoom : 0)) * stretch }
            return x + w * stretch / 2
        }
    }
}
