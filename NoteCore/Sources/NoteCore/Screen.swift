/// A stable identifier string. Note ids (`NoteKey.id`, e.g. `"treble:G4"`) are what
/// stats and munchers are stored under. Screen ids (`PracticeItem.id`) only keep the
/// generator from showing the same screen again too soon.
public typealias ItemID = String

/// Written length of a note (or of a rest). No ties, no dotted quarters (out of scope).
public enum NoteValue: String, CaseIterable, Codable, Hashable, Sendable {
    case eighth = "e"
    case quarter = "q"
    case half = "h"
    /// 3 beats. Fills a 3/4 bar.
    case dottedHalf = "h."
    /// 4 beats. Fills a 4/4 bar.
    case whole = "w"

    public var beats: Double {
        switch self {
        case .eighth: 0.5
        case .quarter: 1
        case .half: 2
        case .dottedHalf: 3
        case .whole: 4
        }
    }

    /// Halves, dotted halves and wholes are drawn as open heads (thick outline), the rest are filled.
    public var hasOpenHead: Bool { self == .half || self == .dottedHalf || self == .whole }

    /// Every value but the whole note has a stem.
    public var hasStem: Bool { self != .whole }

    public var isDotted: Bool { self == .dottedHalf }
}

/// The time signature. Every generated screen is whole bars in one of these.
public enum Meter: String, CaseIterable, Codable, Hashable, Sendable {
    case threeFour = "3/4"
    case fourFour = "4/4"

    /// Quarter beats in a bar (the top number). The bottom number is always 4.
    public var beats: Int { self == .threeFour ? 3 : 4 }
}

/// One column of a screen: the keys he plays together, on one staff, how long, and
/// the rests that follow it before the next key. Rests only come at the end of a bar
/// (q q q + a quarter rest), so they hang off the bar's last note.
public struct WrittenNote: Hashable, Codable, Sendable {
    public let clef: Clef
    /// Lowest first. One pitch for a single note, two for a dyad.
    public let pitches: [Pitch]
    /// Written length. Drawn only on screens with a meter; the munchers' tiny staffs
    /// on home show a plain head.
    public let value: NoteValue
    /// Rests after this note, in order, that fill out its bar.
    public let restsAfter: [NoteValue]

    public init(_ clef: Clef, _ pitches: [Pitch], _ value: NoteValue = .quarter, rests: [NoteValue] = []) {
        precondition(!pitches.isEmpty)
        self.clef = clef
        self.pitches = pitches.sorted()
        self.value = value
        restsAfter = rests
    }

    public init(_ key: NoteKey, _ value: NoteValue = .quarter, rests: [NoteValue] = []) {
        self.init(key.clef, [key.pitch], value, rests: rests)
    }

    /// One note key per pitch, lowest first.
    public var keys: [NoteKey] { pitches.map { NoteKey(clef, $0) } }

    public var isChord: Bool { pitches.count > 1 }

    /// Beats from this note to the next key: its value plus the rests after it.
    public var span: Double { value.beats + restsAfter.reduce(0) { $0 + $1.beats } }

    /// The same note with other values (the generator writes pitches first, then rhythm).
    func with(_ value: NoteValue, rests: [NoteValue] = []) -> WrittenNote {
        WrittenNote(clef, pitches, value, rests: rests)
    }
}

/// One screen he reads left to right: single notes, dyads or a rhythm line, on one
/// staff or on the grand staff. The mastery engine generates these from the lesson's
/// notes. Each note on it is judged and recorded on its own.
///
/// Generated screens are whole bars in 3/4 or 4/4 (`meter`), every note with its
/// value, rests filling out bars the notes don't fill. On the grand staff each bar's
/// notes are on one staff; the other staff rests for that bar (drawn, not modelled).
public struct PracticeItem: Identifiable, Hashable, Codable, Sendable {
    public let notes: [WrittenNote]
    /// Which staves the screen shows.
    public let layout: StaffLayout
    public let keySignature: KeySignature
    /// Columns per bar, left to right.
    public let bars: [Int]
    /// The time signature. nil for a plain note with no bars or values drawn (the
    /// munchers' tiny staffs, the parent's preview).
    public let meter: Meter?

    /// - layout: defaults to the one staff every note is on, or the grand staff
    /// - bars: defaults to one bar
    /// - meter: when set, every bar must add up to it exactly
    public init(_ notes: [WrittenNote], layout: StaffLayout? = nil, keySignature: KeySignature = .none, bars: [Int]? = nil,
                meter: Meter? = nil) {
        precondition(!notes.isEmpty)
        let clefs = Set(notes.map(\.clef))
        let layout = layout ?? (clefs.count == 1 ? (clefs.first! == .treble ? .treble : .bass) : .grand)
        precondition(clefs.allSatisfy(layout.contains), "a note is on a staff the layout doesn't show")
        let bars = bars ?? [notes.count]
        precondition(bars.reduce(0, +) == notes.count && bars.allSatisfy { $0 > 0 }, "bars must cover every column")
        if let meter {
            var start = 0
            for size in bars {
                let beats = notes[start..<(start + size)].reduce(0) { $0 + $1.span }
                precondition(beats == Double(meter.beats), "a \(meter.rawValue) bar holds \(beats) beats")
                start += size
            }
        }
        self.notes = notes
        self.layout = layout
        self.keySignature = keySignature
        self.bars = bars
        self.meter = meter
    }

    /// A one-note screen with nothing but the note (the munchers' tiny staffs).
    public init(_ key: NoteKey, layout: StaffLayout? = nil, keySignature: KeySignature = .none) {
        self.init([WrittenNote(key)], layout: layout, keySignature: keySignature)
    }

    /// e.g. `treble:G4`, `treble:G4-A4-B4`, `treble:G4+B4-A4` (no meter),
    /// `treble:G4/q-A4/q-B4/h 3/4`, `treble:G4/h-A4/q/rq 3/4` (a quarter rest after A4),
    /// `treble:G4/w bass:G2/w 4/4` (grand staff, a treble bar then a bass bar).
    /// A one-note screen with no meter has the same id as its note.
    public var id: ItemID {
        var segments: [String] = []
        var current: Clef?
        var body: [String] = []
        for note in notes {
            if note.clef != current {
                if let current { segments.append("\(current.rawValue):" + body.joined(separator: "-")) }
                current = note.clef
                body = []
            }
            var column = note.pitches.map(\.name).joined(separator: "+")
            if meter != nil {
                column += "/\(note.value.rawValue)" + note.restsAfter.map { "/r\($0.rawValue)" }.joined()
            }
            body.append(column)
        }
        if let current { segments.append("\(current.rawValue):" + body.joined(separator: "-")) }
        return segments.joined(separator: " ") + (meter.map { " \($0.rawValue)" } ?? "")
    }

    public var hasChords: Bool { notes.contains(where: \.isChord) }

    /// Clefs on the screen, in the order they first appear.
    public var clefs: [Clef] {
        var seen: [Clef] = []
        for note in notes where !seen.contains(note.clef) { seen.append(note.clef) }
        return seen
    }

    /// Every note key on the screen, in the order first played, no repeats.
    public var keys: [NoteKey] {
        var seen: [NoteKey] = []
        for key in notes.flatMap(\.keys) where !seen.contains(key) { seen.append(key) }
        return seen
    }

    public func clef(ofNote index: Int) -> Clef { notes[index].clef }

    /// The written length of each note.
    public var values: [NoteValue] { notes.map(\.value) }

    /// Beats on the screen, rests included.
    public var totalBeats: Double { notes.reduce(0) { $0 + $1.span } }

    /// Beat offset where each note starts, rests before it included.
    public var startBeats: [Double] {
        var beat = 0.0
        return notes.map { note in
            defer { beat += note.span }
            return beat
        }
    }

    /// Beats from each note to the next key: its value plus any rests after it. The
    /// last note's is its own value (only how long he holds it counts).
    public var gapBeats: [Double] {
        notes.indices.map { i in i == notes.count - 1 ? notes[i].value.beats : notes[i].span }
    }

    /// Indexes of the first note of each beamed eighth pair: an eighth that starts on
    /// a beat and is followed by another eighth.
    public var beamedPairStarts: [Int] {
        let starts = startBeats
        return notes.indices.dropLast().filter { i in
            notes[i].value == .eighth && notes[i + 1].value == .eighth && notes[i].restsAfter.isEmpty
                && starts[i].rounded() == starts[i]
        }
    }

    /// Columns after which a bar line goes (not after the last one).
    public var barLinesAfter: [Int] {
        var result: [Int] = []
        var end = -1
        for size in bars.dropLast() {
            end += size
            result.append(end)
        }
        return result
    }

    /// The columns of each bar, left to right.
    public var barRanges: [Range<Int>] {
        var start = 0
        return bars.map { size in
            defer { start += size }
            return start..<(start + size)
        }
    }

    /// Staff position of every key in note `index`, lowest first, on that note's staff.
    public func positions(ofNote index: Int) -> [StaffPosition] {
        notes[index].pitches.map { notes[index].clef.position(of: $0) }
    }

    /// When to sound each note to play the screen back at `beat` seconds per quarter.
    /// Rests are the silence between.
    public func playback(beat: Double) -> [ScheduledNote] {
        zip(notes, startBeats).map { note, start in
            ScheduledNote(pitches: note.pitches, start: start * beat, duration: note.value.beats * beat)
        }
    }
}

public struct ScheduledNote: Hashable, Sendable {
    public let pitches: [Pitch]
    /// Seconds from the start of playback.
    public let start: Double
    public let duration: Double
}
