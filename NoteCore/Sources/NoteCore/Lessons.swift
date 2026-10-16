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
        /// Lines mixing single notes and two notes at once: about half the columns get
        /// a second note this many letters above (2 = a third, 3 = a fourth, 4 = a
        /// fifth), from notes he already has. Sizes count columns.
        case dyads(intervals: [Int])
        /// Rhythm lines in 4/4 from these lengths (eighths come as a beamed pair, at most
        /// one pair a bar). Sizes count bars. `oneNote`: every note on a screen is the
        /// same key, so only the rhythm is new.
        case rhythm(values: [NoteValue], oneNote: Bool)

        public var isRhythm: Bool { if case .rhythm = self { true } else { false } }
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
        Level(number: 2, title: "G position, steps and skips", lessons: [
            Lesson(
                "2.1", level: 2, title: "Treble steps", focus: .treble,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...4, octavePolicy: .lenient, contour: .steps
            ),
            Lesson(
                "2.2", level: 2, title: "Bass steps", focus: .bass,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...4, octavePolicy: .lenient, contour: .steps
            ),
            Lesson(
                "2.3", level: 2, title: "Treble skips", focus: .treble,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...4, octavePolicy: .lenient, contour: .skips
            ),
            Lesson(
                "2.4", level: 2, title: "Bass skips", focus: .bass,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...4, octavePolicy: .lenient, contour: .skips
            ),
            Lesson(
                "2.5", level: 2, title: "Grand staff: a treble bar and a bass bar", focus: .both, layout: .grand,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 4...6, octavePolicy: .lenient
            ),
        ]),
        // G major from here on: the key signature's sharp is on every screen, and F is
        // read as F# from it (F#4 and F#5 in treble, F#3 in bass)
        Level(number: 3, title: "Around G position, in G major", lessons: [
            Lesson(
                "3.1", level: 3, title: "Treble up to G5", focus: .treble,
                treble: ClefNotes(known: trebleG, new: [e5, fs5, g5], start: 1), bass: ClefNotes(known: bassG),
                sizes: 4...8, octavePolicy: .strict, keySignature: .gMajor
            ),
            Lesson(
                "3.2", level: 3, title: "Bass up to G3", focus: .bass,
                treble: ClefNotes(known: trebleUp), bass: ClefNotes(known: bassG, new: [e3, fs3, g3], start: 1),
                sizes: 4...8, octavePolicy: .strict, keySignature: .gMajor
            ),
            Lesson(
                "3.3", level: 3, title: "Middle C from the treble side", focus: .treble,
                treble: ClefNotes(known: trebleUp, new: [c4, d4, e4, fs4], start: 1), bass: ClefNotes(known: bassUp),
                sizes: 4...8, octavePolicy: .strict, keySignature: .gMajor
            ),
            Lesson(
                "3.4", level: 3, title: "Middle C from the bass side", focus: .bass,
                treble: ClefNotes(known: trebleWide), bass: ClefNotes(known: bassUp, new: [a3, b3, c4], start: 1),
                sizes: 4...8, octavePolicy: .strict, keySignature: .gMajor
            ),
            Lesson(
                "3.5", level: 3, title: "Grand staff, the whole range", focus: .both, layout: .grand,
                treble: ClefNotes(known: trebleWide), bass: ClefNotes(known: bassWide),
                sizes: 6...8, octavePolicy: .strict, keySignature: .gMajor
            ),
        ]),
        Level(number: 4, title: "Two notes at once", lessons: [
            Lesson(
                "4.1", level: 4, title: "Treble: thirds and fifths", focus: .treble,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...5, octavePolicy: .strict, keySignature: .gMajor, texture: .dyads(intervals: [2, 4])
            ),
            Lesson(
                "4.2", level: 4, title: "Bass: thirds and fifths", focus: .bass,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...5, octavePolicy: .strict, keySignature: .gMajor, texture: .dyads(intervals: [2, 4])
            ),
            Lesson(
                "4.3", level: 4, title: "Thirds, fourths and fifths", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...6, octavePolicy: .strict, keySignature: .gMajor, texture: .dyads(intervals: [2, 3, 4])
            ),
            Lesson(
                "4.4", level: 4, title: "Grand staff, two at once", focus: .both, layout: .grand,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor, texture: .dyads(intervals: [2, 3, 4])
            ),
        ]),
        // rhythm on notes he knows (G position). 2 bars at most: wider lines don't fit
        // the landscape staff at the fixed line gap
        Level(number: 5, title: "Rhythm", lessons: [
            Lesson(
                "5.1", level: 5, title: "Quarters and halves on one note", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 1...2, octavePolicy: .strict, keySignature: .gMajor,
                texture: .rhythm(values: [.quarter, .half], oneNote: true)
            ),
            Lesson(
                "5.2", level: 5, title: "Eighths on one note", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 1...2, octavePolicy: .strict, keySignature: .gMajor,
                texture: .rhythm(values: [.eighth, .quarter, .half], oneNote: true)
            ),
            Lesson(
                "5.3", level: 5, title: "Treble lines", focus: .treble,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 1...2, octavePolicy: .strict, keySignature: .gMajor,
                texture: .rhythm(values: [.quarter, .half], oneNote: false)
            ),
            Lesson(
                "5.4", level: 5, title: "Bass lines with eighths", focus: .bass,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 1...2, octavePolicy: .strict, keySignature: .gMajor,
                texture: .rhythm(values: [.eighth, .quarter, .half], oneNote: false)
            ),
            Lesson(
                "5.5", level: 5, title: "Grand staff lines", focus: .both, layout: .grand,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 2...2, octavePolicy: .strict, keySignature: .gMajor,
                texture: .rhythm(values: [.eighth, .quarter, .half], oneNote: false)
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
    static let fs3 = Pitch("F#3")!, fs4 = Pitch("F#4")!, fs5 = Pitch("F#5")!

    /// G position.
    static let trebleG = [g4, a4, b4, c5, d5]
    static let bassG = [g2, a2, b2, c3, d3]
    /// Level 3: up to G5 / G3, then down / up to middle C.
    static let trebleUp = trebleG + [e5, fs5, g5]
    static let bassUp = bassG + [e3, fs3, g3]
    static let trebleWide = [c4, d4, e4, fs4] + trebleUp
    static let bassWide = bassUp + [a3, b3, c4]
}
