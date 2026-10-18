/// How far the hints went on a note.
public enum HintLevel: Int, Comparable, Codable, Hashable, Sendable {
    case none
    /// one step up the ladder: the note wobbled
    case wobble
    /// two steps: the app played the right pitch
    case playedPitch
    /// three or more: the keyboard picture lit up the key
    case keyboard

    public static func < (lhs: HintLevel, rhs: HintLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One note he played on a screen: what the mastery engine records for that note, and
/// what the app stores (with its own date) for the parent dashboard. A dyad column
/// gives one result per key.
public struct AttemptResult: Hashable, Codable, Sendable {
    /// The note's id, `NoteKey.id` (`"treble:G4"`).
    public var itemID: ItemID
    /// The lesson he was in when he played it.
    public var lesson: LessonID
    public var level: Int
    /// The note's intro (the app showed it first, keyboard picture up). Not counted in stats.
    public var wasIntro: Bool
    /// Right on the first press. An "almost" (right letter, wrong octave in a lenient
    /// lesson) doesn't count against him.
    public var firstTry: Bool
    public var wrongPresses: Int
    public var almostPresses: Int
    /// Steps up the hint ladder from being stuck (no key for `stuckAfter` seconds).
    /// Not a wrong press, but it means it wasn't right first try.
    public var stuckSteps: Int
    public var hints: HintLevel
    /// Seconds from when this became the next note to play until he found it, not
    /// counting time the piano was disconnected. On a rhythm screen every note gets
    /// the screen's reading time (prompt to first key), since the gaps after that are
    /// the rhythm, not reading.
    public var responseTime: Double
    /// The time is a pure in-line reading time, what habit is measured on: not the
    /// screen's first note (that time includes taking in a new screen), not the same key
    /// as the note before it, not on a rhythm-judged screen or a rhythm line (the gaps
    /// are the rhythm), not an intro or a second read.
    public var inLine: Bool
    /// Bar 2 of a pattern screen played bar 1's note again at the same spot (a twin, an
    /// answer, a new rhythm): from memory, not read. Not in-line for habit, and not one of a
    /// paced lesson's plays of a new note.
    public var fromMemory: Bool

    public init(
        itemID: ItemID, lesson: LessonID, level: Int, wasIntro: Bool = false, firstTry: Bool,
        wrongPresses: Int = 0, almostPresses: Int = 0, stuckSteps: Int = 0, hints: HintLevel = .none,
        responseTime: Double, inLine: Bool = false, fromMemory: Bool = false
    ) {
        self.itemID = itemID
        self.lesson = lesson
        self.level = level
        self.wasIntro = wasIntro
        self.firstTry = firstTry
        self.wrongPresses = wrongPresses
        self.almostPresses = almostPresses
        self.stuckSteps = stuckSteps
        self.hints = hints
        self.responseTime = responseTime
        self.inLine = inLine
        self.fromMemory = fromMemory
    }
}

/// Why a screen was shown.
public enum PickReason: String, Codable, Hashable, Sendable {
    case normal
    /// Session opener: his strongest notes.
    case warmUp
    /// He missed or needed hints on 3 of his last 5 notes: his strongest notes.
    case easing
    /// Time or count is up but the last screen wasn't all right first try: an easy one to end on.
    case extra
    /// Doing well: one note more than his current size, now and then.
    case stretch
    /// One of the session's burst of drill screens.
    case drill
    /// The screen he just played clean, once more: a second read. Not counted in his stats.
    case again
}

/// One finished screen.
public struct ScreenResult: Hashable, Codable, Sendable {
    /// `PracticeItem.id`
    public var screenID: ItemID
    public var lesson: LessonID
    public var reason: PickReason
    /// A new note's intro (one note, keyboard picture up from the start).
    public var wasIntro: Bool
    /// The first screen of a lesson with a new texture (two at once, rhythm), played
    /// to him first.
    public var wasLessonIntro: Bool
    /// Notes on the screen, one per key, left to right.
    public var notes: [AttemptResult]
    /// Rhythm screens, when every key was right first try. nil otherwise.
    public var rhythm: RhythmResult?
    /// The screen's size in the lesson's unit: columns, or bars on rhythm screens.
    public var size: Int
    /// Wrong values got the screen played back and another go this many times (at most
    /// `rhythmRetries`). `rhythm` is the first go, the one that counts.
    public var rhythmRetries: Int
    /// One of a level's first rhythm screens, played to him before he read it.
    public var wasRhythmDemo: Bool
    /// Times the screen went back to its first note after a slip (at most
    /// `sequenceRestarts`). Each note's result is from the first go that reached it.
    public var restarts: Int
    /// A pattern screen's shape (two bars, bar 2 made from bar 1), nil otherwise.
    public var pattern: PatternShape?

    public init(
        screenID: ItemID, lesson: LessonID, reason: PickReason = .normal, wasIntro: Bool = false,
        wasLessonIntro: Bool = false, notes: [AttemptResult], rhythm: RhythmResult? = nil, size: Int? = nil,
        rhythmRetries: Int = 0, wasRhythmDemo: Bool = false, restarts: Int = 0, pattern: PatternShape? = nil
    ) {
        self.screenID = screenID
        self.lesson = lesson
        self.reason = reason
        self.wasIntro = wasIntro
        self.wasLessonIntro = wasLessonIntro
        self.notes = notes
        self.rhythm = rhythm
        self.size = size ?? notes.count
        self.rhythmRetries = rhythmRetries
        self.wasRhythmDemo = wasRhythmDemo
        self.restarts = restarts
        self.pattern = pattern
    }

    /// Every note right first try.
    public var firstTry: Bool { notes.allSatisfy(\.firstTry) }

    public var usedHints: Bool { notes.contains { $0.hints > .none } }
}

// see LenientDecoding.swift. the app keeps every attempt as JSON
extension AttemptResult {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try c.decode(ItemID.self, forKey: .itemID)
        lesson = try c.value(.lesson, or: "")
        level = try c.value(.level, or: 0)
        wasIntro = try c.value(.wasIntro, or: false)
        firstTry = try c.value(.firstTry, or: false)
        wrongPresses = try c.value(.wrongPresses, or: 0)
        almostPresses = try c.value(.almostPresses, or: 0)
        stuckSteps = try c.value(.stuckSteps, or: 0)
        hints = try c.value(.hints, or: .none)
        responseTime = try c.value(.responseTime, or: 0)
        inLine = try c.value(.inLine, or: false)
        fromMemory = try c.value(.fromMemory, or: false)
    }
}

extension ScreenResult {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screenID = try c.value(.screenID, or: "")
        lesson = try c.value(.lesson, or: "")
        reason = try c.value(.reason, or: .normal)
        wasIntro = try c.value(.wasIntro, or: false)
        wasLessonIntro = try c.value(.wasLessonIntro, or: false)
        notes = try c.value(.notes, or: [])
        rhythm = try c.decodeIfPresent(RhythmResult.self, forKey: .rhythm)
        size = try c.value(.size, or: notes.count)
        rhythmRetries = try c.value(.rhythmRetries, or: 0)
        wasRhythmDemo = try c.value(.wasRhythmDemo, or: false)
        restarts = try c.value(.restarts, or: 0)
        // a shape a later build drops reads as no pattern
        pattern = try? c.decodeIfPresent(PatternShape.self, forKey: .pattern)
    }
}
