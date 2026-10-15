/// Stable item identifier, derived from the item's content (see `PracticeItem.id`).
/// This is what the app persists stats under.
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

/// One column of an item: the keys he plays together, and how long (rhythm items only).
public struct WrittenNote: Hashable, Codable, Sendable {
    /// Lowest first. One pitch for a single note, two or three for a dyad / triad.
    public let pitches: [Pitch]
    /// nil for items without rhythm (drawn as a plain filled head, no stem).
    public let value: NoteValue?

    public init(_ pitches: [Pitch], _ value: NoteValue? = nil) {
        precondition(!pitches.isEmpty)
        self.pitches = pitches.sorted()
        self.value = value
    }
}

/// One prompt he can be shown: a single note, a group read left to right, a chord,
/// or a rhythm line. All notes of an item are on one clef.
public struct PracticeItem: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        /// One key.
        case note
        /// 2-4 single keys, left to right, no rhythm.
        case group
        /// Two or three keys at once.
        case chord
        /// Notes with written lengths. Pitch and rhythm are judged separately.
        case rhythm
    }

    public let clef: Clef
    public let notes: [WrittenNote]

    public init(_ clef: Clef, _ notes: [WrittenNote]) {
        precondition(!notes.isEmpty)
        self.clef = clef
        self.notes = notes
    }

    /// e.g. `treble:C4`, `bass:C4`, `treble:C4-D4-E4`, `treble:C4+E4+G4`, `treble:G4/q-G4/q-G4/h`.
    public var id: ItemID {
        let body = notes.map { note in
            note.pitches.map(\.name).joined(separator: "+") + (note.value.map { "/\($0.rawValue)" } ?? "")
        }
        return "\(clef.rawValue):" + body.joined(separator: "-")
    }

    public var kind: Kind {
        if notes.contains(where: { $0.value != nil }) { return .rhythm }
        if notes.count > 1 { return .group }
        return notes[0].pitches.count > 1 ? .chord : .note
    }

    public var isRhythm: Bool { kind == .rhythm }

    /// The written lengths of a rhythm item, nil otherwise.
    public var values: [NoteValue]? {
        let values = notes.compactMap(\.value)
        return values.count == notes.count ? values : nil
    }

    public var totalBeats: Double { notes.reduce(0) { $0 + ($1.value?.beats ?? 1) } }

    /// Beat offset where each note starts (quarter = 1 for items without rhythm).
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

    /// Staff position of every key in note `index`, lowest first.
    public func positions(ofNote index: Int) -> [StaffPosition] {
        notes[index].pitches.map { clef.position(of: $0) }
    }

    /// When to sound each note to play the item back at `beat` seconds per quarter.
    /// Items without rhythm play as quarters.
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

/// Whether the right letter in the wrong octave counts.
public enum OctavePolicy: String, Codable, Hashable, Sendable {
    /// Right letter, wrong octave is "almost": the voice says which C it was, the
    /// keyboard picture shows the right one, and it doesn't count against him.
    case lenient
    /// Only the written key counts.
    case strict
}

public struct Unit: Identifiable, Hashable, Sendable {
    /// 1-based, matches the plan's list.
    public let number: Int
    /// Parent-facing name. The kid never sees text.
    public let title: String
    public let staff: StaffLayout
    public let octavePolicy: OctavePolicy
    /// New items in the order they unlock.
    public let newItems: [PracticeItem]
    /// How many of `newItems` unlock together when the unit starts. 2 when the unit
    /// has no review pool, so the no-repeat rule holds from the first prompt.
    public let startCount: Int
    /// Earlier units whose items join this unit's practice pool.
    public let reviews: [Int]

    public var id: Int { number }

    public init(
        number: Int, title: String, staff: StaffLayout, octavePolicy: OctavePolicy,
        newItems: [PracticeItem], startCount: Int, reviews: [Int] = []
    ) {
        self.number = number
        self.title = title
        self.staff = staff
        self.octavePolicy = octavePolicy
        self.newItems = newItems
        self.startCount = min(startCount, newItems.count)
        self.reviews = reviews
    }
}

public struct Curriculum: Sendable {
    /// In order, numbered 1...count.
    public let units: [Unit]
    private let itemsByID: [ItemID: PracticeItem]
    private let unitByItem: [ItemID: Int]

    public init(units: [Unit]) {
        self.units = units
        var items: [ItemID: PracticeItem] = [:]
        var owners: [ItemID: Int] = [:]
        for unit in units {
            for item in unit.newItems {
                items[item.id] = item
                owners[item.id] = unit.number
            }
        }
        itemsByID = items
        unitByItem = owners
    }

    public var unitNumbers: ClosedRange<Int> { 1...units.count }

    public func unit(_ number: Int) -> Unit? {
        unitNumbers.contains(number) ? units[number - 1] : nil
    }

    public func item(_ id: ItemID) -> PracticeItem? { itemsByID[id] }

    /// The unit that introduces this item.
    public func unitNumber(of id: ItemID) -> Int? { unitByItem[id] }

    public var allItems: [PracticeItem] { units.flatMap(\.newItems) }
}

// MARK: - the standard curriculum

extension Curriculum {
    /// Units 1-12 from the plan. Notes are listed in intro order.
    public static let standard = Curriculum(units: [
        Unit(
            number: 1, title: "Treble near middle C", staff: .treble, octavePolicy: .lenient,
            newItems: notes(.treble, [c4, g4, e4, d4, f4]), startCount: 2
        ),
        Unit(
            number: 2, title: "Bass near middle C", staff: .bass, octavePolicy: .lenient,
            newItems: notes(.bass, [c4, b3, a3, g3, f3]), startCount: 2
        ),
        Unit(
            number: 3, title: "Grand staff", staff: .grand, octavePolicy: .lenient,
            newItems: [], startCount: 0, reviews: [1, 2]
        ),
        Unit(
            number: 4, title: "Treble up", staff: .treble, octavePolicy: .strict,
            newItems: notes(.treble, [a4, b4, c5, d5, e5, f5, g5]), startCount: 1, reviews: [1]
        ),
        Unit(
            number: 5, title: "Bass down", staff: .bass, octavePolicy: .strict,
            newItems: notes(.bass, [e3, d3, c3, b2, a2, g2]), startCount: 1, reviews: [2]
        ),
        Unit(
            number: 6, title: "Ledger lines", staff: .grand, octavePolicy: .strict,
            newItems: notes(.treble, [a5, b5, c6]) + notes(.bass, [f2, e2, d2, c2]),
            startCount: 1, reviews: [1, 2, 4, 5]
        ),
        Unit(
            number: 7, title: "Note groups", staff: .grand, octavePolicy: .strict,
            newItems: [
                group(.treble, c4, d4),
                group(.treble, c4, e4),
                group(.treble, e4, f4, g4),
                group(.treble, g4, e4, c4),
                group(.bass, c4, b3, a3),
                group(.treble, d4, f4, e4),
                group(.bass, f3, a3, c4),
                group(.treble, g4, f4, e4, d4),
                group(.treble, c4, e4, d4, f4),
            ],
            startCount: 2
        ),
        Unit(
            number: 8, title: "Two notes at once", staff: .treble, octavePolicy: .strict,
            newItems: [
                chord(.treble, c4, e4),
                chord(.treble, c4, g4),
                chord(.treble, e4, g4),
                chord(.treble, d4, f4),
                chord(.treble, d4, a4),
                chord(.treble, f4, a4),
                chord(.treble, g4, b4),
                chord(.treble, g4, d5),
            ],
            startCount: 2
        ),
        Unit(
            number: 9, title: "Triads", staff: .treble, octavePolicy: .strict,
            newItems: [
                chord(.treble, c4, e4, g4),
                chord(.treble, g4, b4, d5),
                chord(.treble, f4, a4, c5),
            ],
            startCount: 2
        ),
        Unit(
            number: 10, title: "Rhythm: quarters and halves", staff: .treble, octavePolicy: .strict,
            newItems: [
                rhythm(g4, [q, q, h]),
                rhythm(g4, [h, q, q]),
                rhythm(g4, [q, h, q]),
                rhythm(g4, [q, q, h, q, q, h]),
                rhythm(g4, [h, h, q, q, h]),
                rhythm(g4, [q, q, q, q, h, h]),
            ],
            startCount: 2
        ),
        Unit(
            number: 11, title: "Rhythm: eighths", staff: .treble, octavePolicy: .strict,
            newItems: [
                rhythm(g4, [e, e, q, h]),
                rhythm(g4, [q, e, e, q, q]),
                rhythm(g4, [e, e, e, e, h]),
                rhythm(g4, [h, e, e, q]),
                rhythm(g4, [q, q, e, e, q]),
                rhythm(g4, [e, e, q, e, e, q]),
            ],
            startCount: 1, reviews: [10]
        ),
        Unit(
            number: 12, title: "Short lines", staff: .treble, octavePolicy: .strict,
            newItems: [
                line([(c4, q), (d4, q), (e4, h), (e4, q), (d4, q), (c4, h)]),
                line([(c4, q), (c4, q), (g4, q), (g4, q), (a4, q), (a4, q), (g4, h)]),
                line([(g4, h), (f4, q), (e4, q), (d4, q), (e4, q), (c4, h)]),
                line([(e4, q), (e4, q), (f4, q), (g4, q), (g4, q), (f4, q), (e4, h)]),
                line([(g4, e), (f4, e), (e4, e), (d4, e), (c4, h)]),
                line([(c4, e), (d4, e), (e4, q), (f4, q), (g4, q), (g4, h), (c4, h)]),
                line([(c4, q), (e4, e), (e4, e), (g4, h)]),
            ],
            startCount: 2
        ),
    ])

    // typed pitch constants, so a typo is a compile error rather than a crash
    private static let c2 = Pitch(.c, 2), d2 = Pitch(.d, 2), e2 = Pitch(.e, 2), f2 = Pitch(.f, 2)
    private static let g2 = Pitch(.g, 2), a2 = Pitch(.a, 2), b2 = Pitch(.b, 2)
    private static let c3 = Pitch(.c, 3), d3 = Pitch(.d, 3), e3 = Pitch(.e, 3), f3 = Pitch(.f, 3)
    private static let g3 = Pitch(.g, 3), a3 = Pitch(.a, 3), b3 = Pitch(.b, 3)
    private static let c4 = Pitch(.c, 4), d4 = Pitch(.d, 4), e4 = Pitch(.e, 4), f4 = Pitch(.f, 4)
    private static let g4 = Pitch(.g, 4), a4 = Pitch(.a, 4), b4 = Pitch(.b, 4)
    private static let c5 = Pitch(.c, 5), d5 = Pitch(.d, 5), e5 = Pitch(.e, 5), f5 = Pitch(.f, 5)
    private static let g5 = Pitch(.g, 5), a5 = Pitch(.a, 5), b5 = Pitch(.b, 5)
    private static let c6 = Pitch(.c, 6)

    private static let e = NoteValue.eighth, q = NoteValue.quarter, h = NoteValue.half

    private static func notes(_ clef: Clef, _ pitches: [Pitch]) -> [PracticeItem] {
        pitches.map { PracticeItem(clef, [WrittenNote([$0])]) }
    }

    private static func group(_ clef: Clef, _ pitches: Pitch...) -> PracticeItem {
        PracticeItem(clef, pitches.map { WrittenNote([$0]) })
    }

    private static func chord(_ clef: Clef, _ pitches: Pitch...) -> PracticeItem {
        PracticeItem(clef, [WrittenNote(pitches)])
    }

    /// One repeated note with a rhythm (units 10-11).
    private static func rhythm(_ pitch: Pitch, _ values: [NoteValue]) -> PracticeItem {
        PracticeItem(.treble, values.map { WrittenNote([pitch], $0) })
    }

    /// Pitch and rhythm together (unit 12).
    private static func line(_ notes: [(Pitch, NoteValue)]) -> PracticeItem {
        PracticeItem(.treble, notes.map { WrittenNote([$0.0], $0.1) })
    }
}
