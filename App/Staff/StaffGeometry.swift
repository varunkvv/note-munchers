import CoreGraphics
import NoteCore

/// What a unit needs room for: which staves, the step range on each, and the widest
/// item. Computed from every item the unit can show, so the staff keeps one size
/// for the whole unit instead of jumping between items.
struct StaffSpec: Hashable {
    var layout: StaffLayout
    /// Steps (half line gaps) to fit on each staff, padding included.
    var treble: ClosedRange<Double>
    var bass: ClosedRange<Double>
    /// Widest item plus clef and margins, in line gaps.
    var width: Double

    init(unit: NoteCore.Unit, curriculum: Curriculum = .standard) {
        let reviewed = unit.reviews.flatMap { curriculum.unit($0)?.newItems ?? [] }
        self.init(items: unit.newItems + reviewed, layout: unit.staff)
    }

    init(items: [PracticeItem], layout: StaffLayout) {
        self.layout = layout
        var treble = Metrics.clefSteps(.treble)
        var bass = Metrics.clefSteps(.bass)
        var widest = 3.0
        for item in items {
            let (low, high) = Metrics.stepExtent(of: item)
            switch item.clef {
            case .treble: treble = min(treble.lowerBound, low)...max(treble.upperBound, high)
            case .bass: bass = min(bass.lowerBound, low)...max(bass.upperBound, high)
            }
            widest = max(widest, Metrics.columnWidths(item).reduce(0, +))
        }
        self.treble = treble
        self.bass = bass
        width = Metrics.notesStart + widest + Metrics.rightPad
    }

    /// Steps of staff stacked top to bottom (grand staff: treble over bass).
    var clefs: [Clef] {
        switch layout {
        case .treble: [.treble]
        case .bass: [.bass]
        case .grand: [.treble, .bass]
        }
    }

    func range(_ clef: Clef) -> ClosedRange<Double> { clef == .treble ? treble : bass }

    var heightInSteps: Double {
        clefs.map { range($0).upperBound - range($0).lowerBound }.reduce(0, +)
            + Double(clefs.count - 1) * Metrics.grandGap
    }
}

/// Sizes in line gaps (or steps where it says so). One place to tune the look.
enum Metrics {
    // notehead: filled ellipse, slightly bigger than the gap, tilted like engraved heads
    static let headRX = 0.70
    static let headRY = 0.50
    static let headTilt = -22.0 // degrees
    /// half width of the tilted head, for ledger lines and stems
    static let headHalfWidth = 0.66
    /// ledger lines stick out this far past the head on each side
    static let ledgerOverhang = 0.5

    static let leftPad = 0.5
    static let clefX = leftPad + 0.4
    static let clefWidth = 2.8
    static let notesStart = clefX + clefWidth + 1.5
    static let rightPad = 1.2

    /// space between treble and bass on the grand staff, in steps
    static let grandGap = 1.0
    /// room around the highest / lowest notehead, in steps
    static let notePad = 2.0

    /// SMuFL clef extents in steps (from Bravura's bounding boxes), plus the staff itself
    static func clefSteps(_ clef: Clef) -> ClosedRange<Double> {
        switch clef {
        case .treble: -3.7...11.2 // G clef origin on step 2, -2.63...4.39 spaces
        case .bass: -0.5...8.5 // F clef origin on step 6, -2.55...1.0 spaces
        }
    }

    // stems, flags and beams (rhythm items), in line gaps
    static let stemLength = 3.5
    static let stemWidth = 0.16
    static let beamThickness = 0.5

    /// Lowest and highest step the item draws on, padding included. Stems count.
    static func stepExtent(of item: PracticeItem) -> (Double, Double) {
        var low = Double.infinity
        var high = -Double.infinity
        let up = stemsUp(item)
        for i in item.notes.indices {
            for position in item.positions(ofNote: i) {
                low = min(low, Double(position.step) - notePad)
                high = max(high, Double(position.step) + notePad)
                guard item.notes[i].value != nil else { continue }
                let reach = stemLength * 2 + 1 // steps, plus a little for a sloped beam
                if up[i] {
                    high = max(high, Double(position.step) + reach)
                } else {
                    low = min(low, Double(position.step) - reach)
                }
            }
        }
        return (low, high)
    }

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

    /// Columns after which a bar line goes (every 4 beats, not after the last note).
    static func barLinesAfter(_ item: PracticeItem) -> [Int] {
        guard item.isRhythm else { return [] }
        var beats = 0.0
        var result: [Int] = []
        for (i, note) in item.notes.enumerated() {
            beats += note.value?.beats ?? 1
            if i < item.notes.count - 1, beats.truncatingRemainder(dividingBy: 4) == 0 {
                result.append(i)
            }
        }
        return result
    }

    /// Width of each column in line gaps, before stretching to fill the staff.
    static func columnWidths(_ item: PracticeItem) -> [Double] {
        item.notes.map { note in
            switch note.value {
            case nil: item.notes.count == 1 ? 3 : 3.4
            case .eighth: 2.3
            case .quarter: 2.9
            case .half: 3.9
            }
        }
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

    init(spec: StaffSpec, size: CGSize, style: StaffStyle, maxGap: CGFloat = 120) {
        self.spec = spec
        self.size = size
        let byHeight = size.height / CGFloat(spec.heightInSteps / 2)
        let byWidth = size.width / CGFloat(spec.width)
        let g = max(4, min(byHeight, byWidth, maxGap) * CGFloat(style.size))
        self.g = g
        lineWidth = max(1.5, g * CGFloat(style.lineThickness) * (style.highContrast ? 1.15 : 1))

        // center the staves vertically
        let contentHeight = CGFloat(spec.heightInSteps) * g / 2
        var y = (size.height - contentHeight) / 2
        var lines: [Clef: CGFloat] = [:]
        for clef in spec.clefs {
            let range = spec.range(clef)
            // bottom line (step 0) sits range.upperBound steps below the top of this band
            lines[clef] = y + CGFloat(range.upperBound) * g / 2
            y += CGFloat(range.upperBound - range.lowerBound + Metrics.grandGap) * g / 2
        }
        bottomLine = lines
        // the staff always spans the full width. g already fits the widest item
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
    var notesLeft: CGFloat { CGFloat(Metrics.notesStart) * g }
    var notesRight: CGFloat { size.width - CGFloat(Metrics.rightPad) * g }

    /// Center x of each column. Columns stretch up to 1.5x their natural width to use
    /// the room, then the item is centered in what's left.
    func columnCenters(_ item: PracticeItem) -> [CGFloat] {
        let widths = Metrics.columnWidths(item).map { CGFloat($0) * g }
        let natural = widths.reduce(0, +)
        let room = max(natural, notesRight - notesLeft)
        let stretch = min(1.5, room / natural)
        let used = natural * stretch
        var x = notesLeft + (room - used) / 2
        return widths.map { w in
            defer { x += w * stretch }
            return x + w * stretch / 2
        }
    }
}
