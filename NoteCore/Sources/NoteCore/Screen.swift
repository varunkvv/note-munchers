/// A stable identifier string. Note ids (`NoteKey.id`, e.g. `"treble:G4"`) are what
/// stats and munchers are stored under. Screen ids (`PracticeItem.id`) only keep the
/// generator from showing the same screen again too soon.
public typealias ItemID = String

/// Written length of a note. 4/4 only, no dots, no rests (out of scope for now).
public enum NoteValue: String, CaseIterable, Codable, Hashable, Sendable {
    case eighth = "e"
    case quarter = "q"
    case half = "h"

    public var beats: Double {
        switch self {
        case .eighth: 0.5
        case .quarter: 1
        case .half: 2
        }
    }

    /// Half notes are drawn as open heads (thick outline), the rest are filled.
    public var hasOpenHead: Bool { self == .half }
}

/// One column of a screen: the keys he plays together, on one staff, and how long
/// (rhythm screens only).
public struct WrittenNote: Hashable, Codable, Sendable {
    public let clef: Clef
    /// Lowest first. One pitch for a single note, two for a dyad.
    public let pitches: [Pitch]
    /// nil for screens without rhythm (drawn as a plain filled head, no stem).
    public let value: NoteValue?

    public init(_ clef: Clef, _ pitches: [Pitch], _ value: NoteValue? = nil) {
        precondition(!pitches.isEmpty)
        self.clef = clef
        self.pitches = pitches.sorted()
        self.value = value
    }

    public init(_ key: NoteKey, _ value: NoteValue? = nil) {
        self.init(key.clef, [key.pitch], value)
    }

    /// One note key per pitch, lowest first.
    public var keys: [NoteKey] { pitches.map { NoteKey(clef, $0) } }

    public var isChord: Bool { pitches.count > 1 }
}

/// One screen he reads left to right: single notes, dyads or a rhythm line, on one
/// staff or on the grand staff. The mastery engine generates these from the lesson's
/// notes. Each note on it is judged and recorded on its own.
public struct PracticeItem: Identifiable, Hashable, Codable, Sendable {
    public let notes: [WrittenNote]
    /// Which staves the screen shows.
    public let layout: StaffLayout
    public let keySignature: KeySignature
    /// Columns per bar, left to right. Rhythm screens ignore this and bar every 4 beats.
    public let bars: [Int]

    /// - layout: defaults to the one staff every note is on, or the grand staff
    /// - bars: defaults to one bar
    public init(_ notes: [WrittenNote], layout: StaffLayout? = nil, keySignature: KeySignature = .none, bars: [Int]? = nil) {
        precondition(!notes.isEmpty)
        let clefs = Set(notes.map(\.clef))
        let layout = layout ?? (clefs.count == 1 ? (clefs.first! == .treble ? .treble : .bass) : .grand)
        precondition(clefs.allSatisfy(layout.contains), "a note is on a staff the layout doesn't show")
        let bars = bars ?? [notes.count]
        precondition(bars.reduce(0, +) == notes.count && bars.allSatisfy { $0 > 0 }, "bars must cover every column")
        self.notes = notes
        self.layout = layout
        self.keySignature = keySignature
        self.bars = bars
    }

    /// A one-note screen (intros).
    public init(_ key: NoteKey, layout: StaffLayout? = nil, keySignature: KeySignature = .none) {
        self.init([WrittenNote(key)], layout: layout, keySignature: keySignature)
    }

    /// e.g. `treble:G4`, `treble:G4-A4-B4`, `treble:G4+B4-A4`, `bass:G2/q-G2/q-G2/h`,
    /// `treble:G4-A4 bass:G2-B2` (grand staff, a treble bar then a bass bar).
    /// A one-note screen has the same id as its note.
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
            body.append(note.pitches.map(\.name).joined(separator: "+") + (note.value.map { "/\($0.rawValue)" } ?? ""))
        }
        if let current { segments.append("\(current.rawValue):" + body.joined(separator: "-")) }
        return segments.joined(separator: " ")
    }

    public var isRhythm: Bool { notes.contains { $0.value != nil } }

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

    /// The written lengths of a rhythm screen, nil otherwise.
    public var values: [NoteValue]? {
        let values = notes.compactMap(\.value)
        return values.count == notes.count ? values : nil
    }

    public var totalBeats: Double { notes.reduce(0) { $0 + ($1.value?.beats ?? 1) } }

    /// Beat offset where each note starts (quarter = 1 for screens without rhythm).
    public var startBeats: [Double] {
        var beat = 0.0
        return notes.map { note in
            defer { beat += note.value?.beats ?? 1 }
            return beat
        }
    }

    /// Indexes of the first note of each beamed eighth pair: an eighth that starts on
    /// a beat and is followed by another eighth.
    public var beamedPairStarts: [Int] {
        let starts = startBeats
        return notes.indices.dropLast().filter { i in
            notes[i].value == .eighth && notes[i + 1].value == .eighth
                && starts[i].rounded() == starts[i]
        }
    }

    /// Columns after which a bar line goes (not after the last one). Rhythm screens:
    /// every 4 beats. Others: between `bars`.
    public var barLinesAfter: [Int] {
        if isRhythm {
            var beats = 0.0
            var result: [Int] = []
            for (i, note) in notes.enumerated() {
                beats += note.value?.beats ?? 1
                if i < notes.count - 1, beats.truncatingRemainder(dividingBy: 4) == 0 {
                    result.append(i)
                }
            }
            return result
        }
        var result: [Int] = []
        var end = -1
        for size in bars.dropLast() {
            end += size
            result.append(end)
        }
        return result
    }

    /// Staff position of every key in note `index`, lowest first, on that note's staff.
    public func positions(ofNote index: Int) -> [StaffPosition] {
        notes[index].pitches.map { notes[index].clef.position(of: $0) }
    }

    /// When to sound each note to play the screen back at `beat` seconds per quarter.
    /// Screens without rhythm play as quarters.
    public func playback(beat: Double) -> [ScheduledNote] {
        zip(notes, startBeats).map { note, start in
            ScheduledNote(pitches: note.pitches, start: start * beat, duration: (note.value?.beats ?? 1) * beat)
        }
    }
}

public struct ScheduledNote: Hashable, Sendable {
    public let pitches: [Pitch]
    /// Seconds from the start of playback.
    public let start: Double
    public let duration: Double
}
