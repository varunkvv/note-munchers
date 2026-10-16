/// A lesson's id, `"<level>.<lesson>"`, e.g. `"1.1"`. Persisted, so keep ids stable.
public typealias LessonID = String

/// Whether the right letter in the wrong octave counts.
public enum OctavePolicy: String, Codable, Hashable, Sendable {
    /// Right letter, wrong octave is "almost": the voice says which way to go, the
    /// keyboard picture shows the right key, and it doesn't count against him.
    case lenient
    /// Only the written key counts.
    case strict
}

/// The notes a lesson uses on one clef.
public struct ClefNotes: Hashable, Sendable {
    /// Unlocked as soon as the lesson starts, no intro. Notes from earlier lessons.
    public let known: [Pitch]
    /// Notes this lesson brings in. A set, not an order: `start` of them unlock when the
    /// lesson starts, picked at random with at least one line and one space in the
    /// pool, the rest come one batch at a time through the gate, also at random.
    public let new: [Pitch]
    public let start: Int

    public init(known: [Pitch] = [], new: [Pitch] = [], start: Int = 0) {
        self.known = known
        self.new = new
        self.start = min(start, new.count)
    }

    public var all: [Pitch] { known + new }
}

/// One lesson: which notes, how many per screen, which staves. Lessons are data; the
/// mastery engine generates every screen from them.
public struct Lesson: Identifiable, Hashable, Sendable {
    /// What the parent sees the lesson as. Every session mixes both clefs anyway; the
    /// focus clef gets about 5 screens in 8 (the other clef never comes twice in a row).
    public enum Focus: String, Codable, Hashable, Sendable {
        case treble, bass, both
    }

    public enum Layout: String, Codable, Hashable, Sendable {
        /// One clef per screen. A session alternates treble and bass screens, weighted
        /// toward the weaker clef.
        case alternating
        /// Grand staff screens: a bar on one staff, then a bar on the other.
        case grand
    }

    /// How notes on a screen move from one to the next.
    public enum Contour: String, Codable, Hashable, Sendable {
        /// Steps, skips and repeats mixed.
        case mixed
        /// Mostly next-door notes (line to space).
        case steps
        /// Mostly skips (line to line, space to space, or wider).
        case skips
    }

    public enum Texture: Hashable, Sendable {
        /// One key at a time.
        case single
    }

    public let id: LessonID
    public let level: Int
    /// Parent-facing. The kid never sees text.
    public let title: String
    public let focus: Focus
    public let layout: Layout
    public let treble: ClefNotes?
    public let bass: ClefNotes?
    /// Notes per screen. Where he sits inside this range depends on how he's doing.
    public let sizes: ClosedRange<Int>
    /// How many new notes unlock together when the gate opens.
    public let unlockBatch: Int
    public let octavePolicy: OctavePolicy
    public let keySignature: KeySignature
    public let texture: Texture
    public let contour: Contour

    public init(
        _ id: LessonID, level: Int, title: String, focus: Focus, layout: Layout = .alternating,
        treble: ClefNotes?, bass: ClefNotes?, sizes: ClosedRange<Int>, unlockBatch: Int = 1,
        octavePolicy: OctavePolicy, keySignature: KeySignature = .none, texture: Texture = .single,
        contour: Contour = .mixed
    ) {
        self.id = id
        self.level = level
        self.title = title
        self.focus = focus
        self.layout = layout
        self.treble = treble
        self.bass = bass
        self.sizes = sizes
        self.unlockBatch = max(1, unlockBatch)
        self.octavePolicy = octavePolicy
        self.keySignature = keySignature
        self.texture = texture
        self.contour = contour
    }

    public func notes(_ clef: Clef) -> ClefNotes? { clef == .treble ? treble : bass }

    /// Clefs with notes in this lesson, treble first.
    public var clefs: [Clef] { Clef.allCases.filter { notes($0) != nil } }

    /// Every note the lesson can show.
    public var keys: [NoteKey] {
        clefs.flatMap { clef in notes(clef)!.all.map { NoteKey(clef, $0) } }
    }

    /// Notes the lesson brings in (the ones that get intros).
    public var newKeys: [NoteKey] {
        clefs.flatMap { clef in notes(clef)!.new.map { NoteKey(clef, $0) } }
    }

    /// The staff a screen on `clef` uses.
    public func staff(for clef: Clef) -> StaffLayout {
        layout == .grand ? .grand : (clef == .treble ? .treble : .bass)
    }

    /// The lesson number inside its level ("1.3" -> 3).
    public var number: Int { Int(id.split(separator: ".").last ?? "") ?? 0 }
}

public struct Level: Identifiable, Hashable, Sendable {
    public let number: Int
    /// Parent-facing.
    public let title: String
    public let lessons: [Lesson]

    public var id: Int { number }
}

/// Levels of lessons, in order. The parent picks the level (and can jump to a lesson in
/// it); inside a level, lessons follow each other as he masters them.
public struct Curriculum: Sendable {
    public let levels: [Level]
    /// Every lesson, in order.
    public let lessons: [Lesson]
    private let byID: [LessonID: Lesson]

    public init(levels: [Level]) {
        precondition(!levels.isEmpty && levels.allSatisfy { !$0.lessons.isEmpty })
        self.levels = levels
        lessons = levels.flatMap(\.lessons)
        byID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }

    public func lesson(_ id: LessonID) -> Lesson? { byID[id] }

    public func level(_ number: Int) -> Level? { levels.first { $0.number == number } }

    public var firstLesson: Lesson { lessons[0] }

    /// Position of a lesson in the whole curriculum, for "is this before that".
    public func index(of id: LessonID) -> Int? { lessons.firstIndex { $0.id == id } }

    /// Every note any lesson uses, treble first, low to high.
    public var allKeys: [NoteKey] { Array(Set(lessons.flatMap(\.keys))).sorted() }
}

// MARK: - the standard curriculum

extension Curriculum {
    /// Levels from plans/2026-10-15-round-2-feedback.md. G position = treble G4-D5,
    /// bass G2-D3.
    public static let standard = Curriculum(levels: [
        Level(number: 1, title: "G position", lessons: [
            Lesson(
                "1.1", level: 1, title: "First notes, both clefs", focus: .both,
                treble: ClefNotes(new: trebleG, start: 3), bass: ClefNotes(new: bassG, start: 3),
                sizes: 1...3, unlockBatch: 2, octavePolicy: .lenient
            ),
            Lesson(
                "1.2", level: 1, title: "Treble G position", focus: .treble,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 2...3, octavePolicy: .lenient
            ),
            Lesson(
                "1.3", level: 1, title: "Bass G position", focus: .bass,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 2...3, octavePolicy: .lenient
            ),
            Lesson(
                "1.4", level: 1, title: "Both clefs", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 2...3, octavePolicy: .lenient
            ),
        ]),
    ])

    // typed pitch constants, so a typo is a compile error rather than a crash
    static let g2 = Pitch(.g, 2), a2 = Pitch(.a, 2), b2 = Pitch(.b, 2)
    static let c3 = Pitch(.c, 3), d3 = Pitch(.d, 3), e3 = Pitch(.e, 3), g3 = Pitch(.g, 3)
    static let a3 = Pitch(.a, 3), b3 = Pitch(.b, 3)
    static let c4 = Pitch(.c, 4), d4 = Pitch(.d, 4), e4 = Pitch(.e, 4)
    static let g4 = Pitch(.g, 4), a4 = Pitch(.a, 4), b4 = Pitch(.b, 4)
    static let c5 = Pitch(.c, 5), d5 = Pitch(.d, 5), e5 = Pitch(.e, 5), g5 = Pitch(.g, 5)

    /// G position.
    static let trebleG = [g4, a4, b4, c5, d5]
    static let bassG = [g2, a2, b2, c3, d3]
}
