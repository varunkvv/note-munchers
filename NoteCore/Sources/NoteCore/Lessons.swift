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
    /// pool, the rest come one batch at a time through the gate, also at random. In a
    /// paced lesson (`Lesson.paced`: level 1, and level 3's middle C lessons) the listed
    /// order is the order.
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
    /// What the parent sees the lesson as. Every session has both clefs anyway: on one
    /// clef per screen the focus clef's run goes first and gets about 2/3 of the session
    /// (`PracticeSession`), on the grand staff it starts about 5 screens in 8.
    public enum Focus: String, Codable, Hashable, Sendable {
        case treble, bass, both
    }

    public enum Layout: String, Codable, Hashable, Sendable {
        /// One clef per screen. A session is two runs, one on each clef, with one switch
        /// half way (`PracticeSession`).
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
        /// Level 1 (a piano teacher's review): steps and repeats, with a third as the
        /// only skip. Nothing on a line moves further than a third.
        case gentle

        /// The widest move from one note to the next on a line, in letters (2 = a third).
        /// nil: no limit.
        public var widest: Int? { self == .gentle ? 2 : nil }
    }

    public enum Texture: Hashable, Sendable {
        /// One key at a time.
        case single
        /// Lines mixing single notes and two notes at once: about half the columns get
        /// a second note this many letters above (2 = a third, 3 = a fourth, 4 = a
        /// fifth), from notes he already has. Sizes count columns.
        case dyads(intervals: [Int])
        /// Rhythm lines in 3/4 or 4/4 from these lengths (eighths come as a beamed pair,
        /// at most one pair a bar; with halves, a whole note or dotted half now and then).
        /// Sizes count bars. `oneNote`: every note on a screen is the
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
    /// How much of the rhythm is listened to: off in levels 1-2, "half longer than
    /// quarter" in level 3, everything (rests counted) from level 4.
    public let rhythmCheck: RhythmCheck
    /// New notes are paced (round 3's level 1, and level 3's middle C lessons from a
    /// piano teacher's review): they come in the listed order (G first, middle C first),
    /// each one gets at least `lessonMinNewPlays` plays in the lesson before it can
    /// finish, the newest notes are about 1 in 3 (`pacedNewestShare`) of the notes on
    /// their clef, and 2 notes on a clef already make 2-note screens. (Round 3 called
    /// this `drill`. Drill screens are something else: `Drill`.)
    public let paced: Bool
    /// The drill screens this lesson can make (plans/2026-10-16-drills-and-habit.md): a
    /// burst of 3-4 of them a session, or every screen in a drill lesson.
    public let drills: [Drill]
    /// Notes on a drill screen (single notes, or columns of two at once). Drill screens
    /// in a rhythm lesson are reading screens, so this counts notes there too, except in
    /// a rhythm drill lesson (bars).
    public let drillSizes: ClosedRange<Int>
    /// A level's last lesson (a new stone on the path): every screen is a drill, no new
    /// notes, and it finishes once his notes are habit on two different days
    /// (`isHabit`), or after `drillLessonMaxSessions` good sessions so he never gets stuck.
    public let isDrillLesson: Bool
    /// Hand positions this lesson's drill screens use (nil: the standard ones,
    /// `HandPosition.standard`). Level 3's positions lesson adds D position.
    public let drillPositions: [HandPosition]?
    /// The home note of a home drill (every other note): nil for the G in the hand
    /// position, middle C in level 3's positions lesson.
    public let home: Pitch?

    public init(
        _ id: LessonID, level: Int, title: String, focus: Focus, layout: Layout = .alternating,
        treble: ClefNotes?, bass: ClefNotes?, sizes: ClosedRange<Int>, unlockBatch: Int = 1,
        octavePolicy: OctavePolicy, keySignature: KeySignature = .none, texture: Texture = .single,
        contour: Contour = .mixed, rhythmCheck: RhythmCheck? = nil, paced: Bool = false,
        drills: [Drill]? = nil, drillSizes: ClosedRange<Int>? = nil, isDrillLesson: Bool = false,
        drillPositions: [HandPosition]? = nil, home: Pitch? = nil
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
        self.rhythmCheck = rhythmCheck ?? (level <= 2 ? .off : level == 3 ? .halves : .all)
        self.paced = paced
        self.drills = drills ?? Self.defaultDrills(level: level, layout: layout)
        self.drillSizes = drillSizes ?? (level == 1 ? 3...4 : 4...6)
        self.isDrillLesson = isDrillLesson
        self.drillPositions = drillPositions
        self.home = home
    }

    /// Bursts in every lesson: runs, homes, repeats, motifs, now and then a bit of a
    /// tune, and echoes on the grand staff.
    static func defaultDrills(level: Int, layout: Layout) -> [Drill] {
        var drills: [Drill] = [.run, .motif, .home, .repeatNote]
        if layout == .grand { drills.append(.echo) }
        if level != 3 { drills.append(.tune) } // tunes are in G position
        return drills
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
    /// bass G2-D3. Level 1 from plans/2026-10-16-round-3-feedback.md: G and A on both
    /// clefs, then one more letter a lesson, each one drilled, reading steps and repeats.
    public static let standard = Curriculum(levels: [
        Level(number: 1, title: "G position", lessons: [
            // ids stay 1.1-1.4 (they're saved), the notes changed in round 3
            Lesson(
                "1.1", level: 1, title: "G and A, both clefs", focus: .both,
                treble: ClefNotes(new: [g4, a4], start: 2), bass: ClefNotes(new: [g2, a2], start: 2),
                sizes: 2...3, octavePolicy: .lenient, contour: .gentle, paced: true
            ),
            Lesson(
                "1.2", level: 1, title: "Add B", focus: .both,
                treble: ClefNotes(known: [g4, a4], new: [b4], start: 1), bass: ClefNotes(known: [g2, a2], new: [b2], start: 1),
                sizes: 2...3, octavePolicy: .lenient, contour: .gentle, paced: true
            ),
            Lesson(
                "1.3", level: 1, title: "Add C", focus: .both,
                treble: ClefNotes(known: [g4, a4, b4], new: [c5], start: 1), bass: ClefNotes(known: [g2, a2, b2], new: [c3], start: 1),
                sizes: 2...3, octavePolicy: .lenient, contour: .gentle, paced: true
            ),
            Lesson(
                "1.4", level: 1, title: "Add D: the whole G position", focus: .both,
                treble: ClefNotes(known: [g4, a4, b4, c5], new: [d5], start: 1), bass: ClefNotes(known: [g2, a2, b2, c3], new: [d3], start: 1),
                sizes: 2...3, octavePolicy: .lenient, contour: .gentle, paced: true
            ),
            // each level ends with a drill lesson (plans/2026-10-16-drills-and-habit.md)
            Lesson(
                "1.5", level: 1, title: "G position patterns", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...4, octavePolicy: .lenient, contour: .gentle,
                drills: [.run, .home, .repeatNote, .motif, .tune], isDrillLesson: true
            ),
        ]),
        // sessions run in clef blocks now, so level 2's four one-clef lessons became two
        // both-clef ones (steps, then skips) in the drills round
        Level(number: 2, title: "G position, steps and skips", lessons: [
            Lesson(
                "2.1", level: 2, title: "Steps, both clefs", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...4, octavePolicy: .lenient, contour: .steps
            ),
            Lesson(
                "2.2", level: 2, title: "Skips, both clefs", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...4, octavePolicy: .lenient, contour: .skips
            ),
            Lesson(
                "2.3", level: 2, title: "Grand staff: a treble bar and a bass bar", focus: .both, layout: .grand,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 4...6, octavePolicy: .lenient
            ),
            Lesson(
                "2.4", level: 2, title: "Patterns and echoes", focus: .both, layout: .grand,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 4...6, octavePolicy: .lenient, drills: [.motif, .echo], isDrillLesson: true
            ),
        ]),
        // G major from here on: the key signature's sharp is on every screen, and F is
        // read as F# from it (F#4 and F#5 in treble, F#3 in bass). 4-6 notes, 2 bars at
        // most: real bars of quarters wider than that don't fit the staff at the 30pt
        // line gap (round 2's plan said "4 notes per screen, 2 bars")
        Level(number: 3, title: "Around G position, in G major", lessons: [
            // each screen stays inside one hand position (HandPosition), so his hand stays
            // put. 3.3-3.5 bring their notes in the listed order, middle C first, a
            // landmark like Faber's guide notes (artifacts/reviews/2026-10-16-piano-teacher-review.md)
            Lesson(
                "3.1", level: 3, title: "Treble up to G5", focus: .treble,
                treble: ClefNotes(known: trebleG, new: [e5, fs5, g5], start: 1), bass: ClefNotes(known: bassG),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor
            ),
            Lesson(
                "3.2", level: 3, title: "Bass up to G3", focus: .bass,
                treble: ClefNotes(known: trebleUp), bass: ClefNotes(known: bassG, new: [e3, fs3, g3], start: 1),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor
            ),
            Lesson(
                "3.3", level: 3, title: "Middle C and D from the treble side", focus: .treble,
                treble: ClefNotes(known: trebleUp, new: [c4, d4], start: 1), bass: ClefNotes(known: bassUp),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor, paced: true
            ),
            Lesson(
                "3.4", level: 3, title: "E and F sharp under G", focus: .treble,
                treble: ClefNotes(known: [c4, d4] + trebleUp, new: [e4, fs4], start: 1), bass: ClefNotes(known: bassUp),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor, paced: true
            ),
            Lesson(
                "3.5", level: 3, title: "Middle C from the bass side", focus: .bass,
                treble: ClefNotes(known: trebleWide), bass: ClefNotes(known: bassUp, new: [c4, b3, a3], start: 1),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor, paced: true
            ),
            Lesson(
                "3.6", level: 3, title: "Grand staff, the whole range", focus: .both, layout: .grand,
                treble: ClefNotes(known: trebleWide), bass: ClefNotes(known: bassWide),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor
            ),
            // G and D position (F# under finger 3), home on middle C, and shift screens:
            // each bar in a different position. No new notes
            Lesson(
                "3.7", level: 3, title: "Hand positions", focus: .both,
                treble: ClefNotes(known: trebleWide), bass: ClefNotes(known: bassWide),
                sizes: 4...6, octavePolicy: .strict, keySignature: .gMajor,
                drills: [.motif, .home, .shift], isDrillLesson: true,
                drillPositions: [.g(.treble), .d(.treble), .g(.bass), .d(.bass)], home: .middleC
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
            // a two at once moved by step (G+B, A+C, B+D), and broken then together (G B, G+B)
            Lesson(
                "4.5", level: 4, title: "Same shape, moved", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 3...5, octavePolicy: .strict, keySignature: .gMajor, texture: .dyads(intervals: [2, 3, 4]),
                drills: [.movedTwo, .brokenTwo], isDrillLesson: true
            ),
        ]),
        // rhythm on notes he knows (G position). 2 bars at most: wider lines don't fit
        // the landscape staff at the fixed line gap. Every screen is 3/4 or 4/4
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
            // a one-bar rhythm repeated a step higher, or the same notes with a new rhythm
            Lesson(
                "5.6", level: 5, title: "Rhythm motifs", focus: .both,
                treble: ClefNotes(known: trebleG), bass: ClefNotes(known: bassG),
                sizes: 2...2, octavePolicy: .strict, keySignature: .gMajor,
                texture: .rhythm(values: [.eighth, .quarter, .half], oneNote: false),
                drills: [.rhythmMotif], isDrillLesson: true
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
