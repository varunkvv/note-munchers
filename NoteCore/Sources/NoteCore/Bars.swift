/// The rhythm of one bar: the notes' values, then the rests that fill out the bar.
/// Rests only come at the end of a bar (q q q + a quarter rest), the way a beginner's
/// book writes a bar the notes don't fill.
public struct BarRhythm: Hashable, Sendable {
    public let values: [NoteValue]
    public let rests: [NoteValue]

    public init(_ values: [NoteValue], rests: [NoteValue] = []) {
        self.values = values
        self.rests = rests
    }

    public var count: Int { values.count }
    public var beats: Double { (values + rests).reduce(0) { $0 + $1.beats } }
}

/// How screens become real, countable bars (plans/2026-10-15-real-bars.md).
///
/// - every screen is whole bars in 3/4 or 4/4, picked per screen, so both meters show
///   up in every lesson and he gets used to checking the time signature
/// - at most 2 bars a screen: two full bars of quarters with clef, key signature and
///   time signature is about what fits the landscape staff at the 30pt line gap
/// - reading screens (levels 1-4) count notes: a bar holds up to one note a beat, as
///   quarters, halves, a whole note (4/4) or a dotted half (3/4). Rests fill a bar the
///   notes don't fill. Rhythm screens (level 5) count bars and fill them from cells
extension MasteryEngine {
    /// Every way to write `notes` notes in one bar of `meter` on a reading screen, with
    /// how likely each one is. Full bars are the usual thing, rests now and then.
    public static func readingBars(notes: Int, meter: Meter) -> [(rhythm: BarRhythm, weight: Double)] {
        let q = NoteValue.quarter, h = NoteValue.half
        switch (meter, notes) {
        case (.fourFour, 1):
            return [(BarRhythm([.whole]), 1), (BarRhythm([h], rests: [h]), 0.35), (BarRhythm([q], rests: [q, h]), 0.2)]
        case (.fourFour, 2):
            return [(BarRhythm([h, h]), 1), (BarRhythm([h, q], rests: [q]), 0.4), (BarRhythm([q, h], rests: [q]), 0.3),
                    (BarRhythm([q, q], rests: [h]), 0.4)]
        case (.fourFour, 3):
            return [(BarRhythm([q, q, h]), 1), (BarRhythm([h, q, q]), 1), (BarRhythm([q, h, q]), 0.6),
                    (BarRhythm([q, q, q], rests: [q]), 0.5)]
        case (.fourFour, 4):
            return [(BarRhythm([q, q, q, q]), 1)]
        case (.threeFour, 1):
            return [(BarRhythm([.dottedHalf]), 1), (BarRhythm([h], rests: [q]), 0.35), (BarRhythm([q], rests: [q, q]), 0.2)]
        case (.threeFour, 2):
            return [(BarRhythm([h, q]), 1), (BarRhythm([q, h]), 0.8), (BarRhythm([q, q], rests: [q]), 0.45)]
        case (.threeFour, 3):
            return [(BarRhythm([q, q, q]), 1)]
        default:
            preconditionFailure("\(notes) notes don't fit a \(meter.rawValue) bar")
        }
    }

    /// The most notes a reading screen in `meter` can hold (2 bars of one a beat).
    public static func maxNotes(_ meter: Meter) -> Int { 2 * meter.beats }

    /// Notes per bar for `count` notes in `meter`: one bar while they fit, else two.
    /// A screen that could be one bar is sometimes two with longer notes (h h | w), so
    /// screens of the same size don't all look alike. `twoBars` forces two (a bar on
    /// each staff of the grand staff).
    static func barSizes(_ count: Int, meter: Meter, twoBars: Bool, using rng: inout some RandomNumberGenerator) -> [Int] {
        let n = min(count, maxNotes(meter))
        precondition(n >= 1)
        if twoBars, n >= 2 {
            let first = (n + 1) / 2
            return [first, n - first]
        }
        let one = n <= meter.beats
        if one, n < 2 || unitInterval(&rng) >= 0.3 { return [n] }
        // two bars: a random split with each bar holding 1...beats
        let low = max(1, n - meter.beats), high = min(meter.beats, n - 1)
        let first = low + min(high - low, Int(unitInterval(&rng) * Double(high - low + 1)))
        return [first, n - first]
    }

    /// A rhythm for each bar of a reading screen.
    static func readingRhythms(_ sizes: [Int], meter: Meter, using rng: inout some RandomNumberGenerator) -> [BarRhythm] {
        sizes.map { size in
            let options = readingBars(notes: size, meter: meter)
            return options[weightedIndex(options.map(\.weight), using: &rng)].rhythm
        }
    }

    /// `bars` bars of `meter` from quarters, halves, beamed eighth pairs (at most one
    /// pair a bar, on a beat) and, when halves are allowed, a whole note (4/4) or a
    /// dotted half (3/4) now and then. A bar can end on a quarter rest. Always 3+ notes, at least two different lengths,
    /// and never a line the judge would pass played all one length, or it can't tell
    /// anything at his tempo (context/notecore-design.md). A meter that can't do that (one bar of quarters
    /// and halves in 3/4) gives way to the other one.
    public static func rhythm(bars: Int, from allowed: [NoteValue], meter: Meter,
                              using rng: inout some RandomNumberGenerator) -> (meter: Meter, bars: [BarRhythm]) {
        for candidate in [meter, meter == .fourFour ? .threeFour : .fourFour] {
            for _ in 0..<40 {
                let line = (0..<max(1, bars)).map { _ in rhythmBar(allowed, meter: candidate, using: &rng) }
                let values = line.flatMap(\.values)
                if values.count >= 3, Set(values).count >= 2, RhythmJudge.telling(rhythmLine(line)) { return (candidate, line) }
            }
        }
        let fallback = BarRhythm([.quarter, .quarter, .half])
        return (.fourFour, Array(repeating: fallback, count: max(1, bars)))
    }

    /// The judge's view of these bars, every note judged: each gap is the note's value
    /// plus the rests after it, the last note's is its value.
    public static func rhythmLine(_ bars: [BarRhythm]) -> RhythmLine {
        var values: [NoteValue] = [], gaps: [Double] = []
        for bar in bars {
            for (i, value) in bar.values.enumerated() {
                values.append(value)
                gaps.append(value.beats + (i == bar.values.count - 1 ? bar.rests.reduce(0) { $0 + $1.beats } : 0))
            }
        }
        gaps[gaps.count - 1] = values[values.count - 1].beats
        return RhythmLine(values: values, gaps: gaps)
    }

    private static func rhythmBar(_ allowed: [NoteValue], meter: Meter, using rng: inout some RandomNumberGenerator) -> BarRhythm {
        let total = Double(meter.beats)
        var beats = 0.0
        var out: [NoteValue] = []
        var pair = false
        while beats < total {
            var cells: [[NoteValue]] = []
            var weights: [Double] = []
            if allowed.contains(.quarter) { cells.append([.quarter]); weights.append(0.45) }
            if allowed.contains(.half), beats + 2 <= total { cells.append([.half]); weights.append(0.3) }
            if allowed.contains(.eighth), !pair { cells.append([.eighth, .eighth]); weights.append(0.25) }
            if allowed.contains(.half), beats == 0 {
                cells.append([meter == .fourFour ? .whole : .dottedHalf])
                weights.append(0.12)
            }
            if cells.isEmpty { cells = [[.quarter]]; weights = [1] }
            let cell = cells[weightedIndex(weights, using: &rng)]
            pair = pair || cell.first == .eighth
            out += cell
            beats += cell.reduce(0) { $0 + $1.beats }
        }
        // now and then the bar's last beat is a rest, which counts into the gap before
        // the next key (levels 4-5)
        if out.count >= 2, out.last == .quarter, unitInterval(&rng) < 0.2 {
            return BarRhythm(Array(out.dropLast()), rests: [.quarter])
        }
        return BarRhythm(out)
    }

    /// Writes `rhythms` onto untimed columns, bar by bar: values in order, each bar's
    /// rests on its last note.
    static func apply(_ rhythms: [BarRhythm], to columns: [WrittenNote]) -> [WrittenNote] {
        precondition(rhythms.reduce(0) { $0 + $1.count } == columns.count)
        var out: [WrittenNote] = []
        var i = 0
        for bar in rhythms {
            for (j, value) in bar.values.enumerated() {
                out.append(columns[i].with(value, rests: j == bar.values.count - 1 ? bar.rests : []))
                i += 1
            }
        }
        return out
    }
}
