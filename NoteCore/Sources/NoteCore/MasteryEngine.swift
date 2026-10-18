public struct AttemptSample: Hashable, Codable, Sendable {
    public var firstTry: Bool
    public var responseTime: Double
    /// The session it was played in (`MasteryState.session`). 0 for samples saved before
    /// the drills round.
    public var session: Int

    public init(firstTry: Bool, responseTime: Double, session: Int = 0) {
        self.firstTry = firstTry
        self.responseTime = responseTime
        self.session = session
    }
}

/// A note's first showing in one session: was it right first try (with no wrong
/// octave). Habit needs this clean on two different days.
public struct SessionFirst: Hashable, Codable, Sendable {
    public var session: Int
    public var day: Int
    public var clean: Bool

    public init(session: Int, day: Int, clean: Bool) {
        self.session = session
        self.day = day
        self.clean = clean
    }
}

/// Rolling stats for one note (`NoteKey`). Value type, Codable - lives inside `MasteryState`.
public struct ItemStats: Hashable, Codable, Sendable {
    /// Leitner box, 1...boxCount. Right first try moves up one, a miss moves down one.
    public var box = 1
    /// Last `solidWindow` attempts, oldest first. Intros are not in here.
    public var recent: [AttemptSample] = []
    public var attempts = 0
    public var firstTryCount = 0
    /// Highest fluency ever reached (0...1). Never goes down, so his muncher for this
    /// note never shrinks.
    public var peakFluency = 0.0
    /// His last `habitWindow` in-line plays of it (not the first note of a screen, see
    /// `AttemptResult.inLine`), first try meaning no wrong key, no stuck step and no wrong
    /// octave. What habit is measured on.
    public var inLine: [AttemptSample] = []
    /// Its first showing in each of his last few sessions.
    public var sessionFirsts: [SessionFirst] = []
    /// "Come back to it": the band played it for him in a song, so practice shows it a bit
    /// more often (`comeBackBoost`) until he has played it right first try this many more
    /// times. Not a miss: the box doesn't move for it.
    public var comeBack = 0

    public init() {}

    public var medianResponse: Double? {
        recent.isEmpty ? nil : median(recent.map(\.responseTime))
    }

    public var recentFirstTryRate: Double? {
        recent.isEmpty ? nil : Double(recent.filter(\.firstTry).count) / Double(recent.count)
    }
}

/// One normal screen at his current size: how many notes, how many right first try.
public struct SizeSample: Hashable, Codable, Sendable {
    public var notes: Int
    public var firstTry: Int

    public init(notes: Int, firstTry: Int) {
        self.notes = notes
        self.firstTry = firstTry
    }
}

/// Everything the engine remembers. The app saves this (JSON in one SwiftData record)
/// after every screen and restores it with `MasteryEngine(state:)`.
public struct MasteryState: Hashable, Codable, Sendable {
    /// Current lesson.
    public var lesson: LessonID = "1.1"
    /// Note ids he can be shown. Notes never re-lock, across lessons.
    public var unlocked: Set<ItemID> = []
    public var completedLessons: Set<LessonID> = []
    /// Per note id (`"treble:G4"`).
    public var stats: [ItemID: ItemStats] = [:]
    /// Notes he has met (intro done, or played), plus `"lesson:<id>"` once a lesson's
    /// new texture (two at once, rhythm) has been shown to him.
    public var introduced: Set<ItemID> = []
    /// The most recent batch that unlocked in this lesson, per clef (`Clef.rawValue`).
    /// The gate waits for these to be solid.
    public var newest: [String: [ItemID]] = [:]
    /// Screens played in this lesson (no intros). Reset when the lesson changes.
    public var lessonScreens = 0
    /// His last notes in this lesson. Reset when the lesson changes.
    public var lessonRecent: [AttemptSample] = []
    /// Plays of each note in this lesson (not intros), by note id. Reset when the lesson
    /// changes. Drill lessons wait for their new notes to have `lessonMinNewPlays`.
    public var lessonPlays: [ItemID: Int] = [:]
    /// Whether each recent rhythm-judged screen in this lesson had no wrong value (the
    /// first go). Only rhythm lessons wait for it.
    public var rhythmRecent: [Bool] = []
    /// Per level number: how many of its first rhythm screens were played to him first.
    public var rhythmDemos: [String: Int] = [:]
    /// Notes per screen (bars on rhythm screens). Grows when he's doing well, drops
    /// back when he struggles, always inside the lesson's range.
    public var screenSize = 1
    /// Normal screens at the current size. Cleared when the size changes.
    public var sizeRecent: [SizeSample] = []
    /// Last screen ids, oldest first, so a screen doesn't come back too soon.
    public var recentScreens: [ItemID] = []
    /// Last few columns shown (`"treble:G4"`, `"treble:G4+B4"`), for the no-long-runs rule.
    public var recentColumns: [ItemID] = []
    /// Per clef (`Clef.rawValue`): screens on it since its last new-note intro. Missing
    /// means no intro lately. Intros on a clef wait for `introSpacing` screens.
    public var introGap: [String: Int] = [:]
    /// His last songs (song time), oldest first, so a new song is never one of them and
    /// level 1 songs take turns between the clefs. Not mastery: songs never touch stats.
    public var recentSongs: [PlayedSong] = []
    /// The most his current lesson's stone on the level path has shown (`lessonProgress`),
    /// so his path never goes backwards. Reset when the lesson changes.
    public var lessonPeak = 0.0
    /// The clef his last session started on (its first run), so the next one starts on
    /// the other. nil before his first session.
    public var lastFirstClef: Clef?
    /// The last drill screen's shape, so the next one is a different one.
    public var lastDrill: Drill?
    /// The last pattern screen's shape, so the next one is a different one.
    public var lastShape: PatternShape?
    /// The last pattern screens' shape and bar 1 (`patternMemo`), oldest first, so a
    /// pattern screen doesn't come back too soon.
    public var recentPatterns: [String] = []
    /// The bar rhythms of the last few pattern screens (`"4/4 q q h"`), oldest first, so
    /// the next one has another while there are others.
    public var recentCells: [String] = []
    /// Sessions started, counting from 1 (0 before the first). Samples carry it.
    public var session = 0
    /// The day the current session is on (the app's day number), for habit's "two
    /// different days".
    public var sessionDay = 0
    /// Days with a session in the current lesson. Reset when the lesson changes. A drill
    /// lesson finishes on habit, or after `drillLessonMaxDays` of these.
    public var lessonDays: Set<Int> = []
    /// Notes that have been habit right after a play in the current lesson (habit is a
    /// window, it can dip: once reached here, it counts for the lesson). Reset when the
    /// lesson changes.
    public var lessonHabit: Set<ItemID> = []
    /// Per clef (`Clef.rawValue`): the note of its last intro. With `introGap` it makes
    /// the blocked screens that follow an intro.
    public var lastIntro: [String: ItemID] = [:]
    /// Levels he reached by finishing the level before, waiting for their celebration
    /// (the level-up splash). A parent moving him never adds one.
    public var levelUps: [Int] = []
    /// Levels whose splash he has had. Once per level, ever.
    public var celebratedLevels: Set<Int> = []
    /// The engine's own dice for curriculum choices: which notes a lesson starts with
    /// and which come next. Seeded once per kid (the app seeds it at first launch),
    /// saved with everything else, so the same state always makes the same choice.
    public var dice: SeededRandom

    public init(seed: UInt64 = 0x5EED_F00D) {
        dice = SeededRandom(seed: seed)
    }
}

/// What changed after recording a screen.
public struct MasteryUpdate: Hashable, Codable, Sendable {
    /// Newly unlocked notes. Each one gets an intro (and a new muncher) when it comes up.
    public var unlocked: [ItemID] = []
    public var completedLesson: LessonID?
    /// Set when the engine moved to another lesson.
    public var enteredLesson: LessonID?
    /// Set when notes per screen changed.
    public var screenSize: Int?
    /// Set when finishing a level moved him into this one (and it hasn't been celebrated).
    public var levelUp: Int?
    public init() {}
}

/// How to pick the next screen.
public enum PickStyle: String, Codable, Hashable, Sendable {
    /// Intros when one is due, otherwise his current size, weighted toward weak notes,
    /// with the newest notes as about 1 in 4 of the notes on their clef.
    case normal
    /// Only his strongest notes (highest boxes among notes he has played). For easing
    /// after misses and the easy screens at the end. No intros. Falls back to `normal`
    /// when he hasn't played anything in this lesson's pool yet.
    case strongest
    /// The session's opener: a run of his strongest notes (falls back to `strongest`).
    case warmUp
    /// A drill screen (a burst): one of the lesson's drills on notes he has met, in
    /// any lesson up to this one. No intros.
    case drill
}

public enum LessonStatus: String, Codable, Hashable, Sendable {
    case completed, current, skipped, upcoming
}

/// Progress for one note, for the munchers view and the parent dashboard.
public struct NoteProgress: Identifiable, Hashable, Codable, Sendable {
    public let key: NoteKey
    public let box: Int
    public let isSolid: Bool
    public let attempts: Int
    /// Over the last `solidWindow` attempts.
    public let recentFirstTryRate: Double?
    public let medianResponse: Double?
    /// 0...1 from the leitner box and how fast he finds it. Can dip after misses.
    public let fluency: Double
    /// Highest `fluency` ever. Use this to size his muncher so it never shrinks.
    public let peakFluency: Double

    public var id: ItemID { key.id }
}

/// Per-note mastery, the unlock gate, lessons and levels, and the screen picker
/// (`pickScreen`, in ScreenGenerator.swift).
///
/// Pure value type. No clock, and no dice of its own: curriculum choices use
/// `state.dice`, screens use the generator the caller passes in.
public struct MasteryEngine: Sendable {
    public let curriculum: Curriculum
    public var config: NoteCoreConfig
    public internal(set) var state: MasteryState

    public init(curriculum: Curriculum = .standard, config: NoteCoreConfig = .default, state: MasteryState = MasteryState()) {
        self.curriculum = curriculum
        self.config = config
        self.state = state
        if curriculum.lesson(state.lesson) == nil {
            // a lesson id this curriculum doesn't have (lessons from level 2 up were
            // renumbered in the drills round): the first lesson of that level not done yet
            let number = Int(state.lesson.split(separator: ".").first ?? "")
            let level = number.flatMap(curriculum.level) ?? curriculum.levels[0]
            let target = level.lessons.first { !state.completedLessons.contains($0.id) } ?? level.lessons[0]
            enter(target.id)
        } else {
            prepareLesson()
        }
    }

    // MARK: reading

    public var lesson: Lesson { curriculum.lesson(state.lesson)! }

    public var level: Level { curriculum.level(lesson.level)! }

    public var screenSize: Int { state.screenSize }

    public func isUnlocked(_ key: NoteKey) -> Bool { state.unlocked.contains(key.id) }

    /// Unlocked notes of the current lesson on one clef, low to high.
    public func pool(_ clef: Clef) -> [NoteKey] {
        guard let notes = lesson.notes(clef) else { return [] }
        return notes.all.map { NoteKey(clef, $0) }.filter(isUnlocked).sorted()
    }

    /// Unlocked notes of the current lesson, treble first.
    public var pool: [NoteKey] { lesson.clefs.flatMap(pool) }

    /// Pool notes that can go on a normal screen: all but new notes still waiting for their intro.
    public func playable(_ clef: Clef) -> [NoteKey] {
        pool(clef).filter { !needsIntro($0) }
    }

    /// This lesson's new notes on a clef that haven't unlocked yet.
    public func lockedNew(_ clef: Clef) -> [NoteKey] {
        guard let notes = lesson.notes(clef) else { return [] }
        return notes.new.map { NoteKey(clef, $0) }.filter { !isUnlocked($0) }
    }

    /// The most recent batch to unlock on this clef in this lesson (or the start set; in
    /// a paced lesson its new notes). Empty when the lesson started with everything
    /// already unlocked. Only notes in this lesson's pool: an old save can hold notes the
    /// lesson doesn't use (round 3 shrank level 1).
    public func newestBatch(_ clef: Clef) -> [NoteKey] {
        let pool = pool(clef)
        return (state.newest[clef.rawValue] ?? []).compactMap { NoteKey(id: $0) }.filter(pool.contains)
    }

    /// Plays of this note in the current lesson (not intros).
    public func lessonPlays(_ key: NoteKey) -> Int { state.lessonPlays[key.id] ?? 0 }

    /// A paced lesson's new note that has had its `lessonMinNewPlays`.
    public func hasMinPlays(_ key: NoteKey) -> Bool {
        lesson.paced && lessonPlays(key) >= config.lessonMinNewPlays
    }

    /// The note just introduced on `clef` while its first `blockedScreens` screens on
    /// that clef are still to come: those are mostly that note, then it mixes in (blocked,
    /// then mixed: varun ok'd it, "this is for young kids").
    public func blockedNote(_ clef: Clef) -> NoteKey? {
        guard let id = state.lastIntro[clef.rawValue], let key = NoteKey(id: id), let gap = state.introGap[clef.rawValue],
              gap < config.blockedScreens, playable(clef).contains(key) else { return nil }
        return key
    }

    /// Does this note get its intro (keyboard picture up front, "this is D") next time?
    /// Only a lesson's new notes get intros. Known notes from earlier lessons don't,
    /// even if a parent skipped ahead past where he would have met them.
    public func needsIntro(_ key: NoteKey) -> Bool {
        isUnlocked(key) && !state.introduced.contains(key.id) && lesson.newKeys.contains(key)
    }

    /// Unlocked notes on a clef still waiting for their intro.
    public func pendingIntros(_ clef: Clef) -> [NoteKey] { pool(clef).filter(needsIntro) }

    public var pendingIntros: [NoteKey] { lesson.clefs.flatMap(pendingIntros) }

    public func stats(for id: ItemID) -> ItemStats { state.stats[id] ?? ItemStats() }

    public func stats(for key: NoteKey) -> ItemStats { stats(for: key.id) }

    /// 7 of the last 8 right first try with median response under 4s, or the fast
    /// track: the last 3 all right first try, each under 3s.
    public func isSolid(_ key: NoteKey) -> Bool { isSolid(stats(for: key).recent) }

    /// The unlock gate for one clef: the newest batch solid AND nothing on this clef
    /// below box 3. In levels 1-2 the fast track doesn't count here, only 7 of 8: a few
    /// quick ones aren't "really drilled in" (a piano teacher's review).
    public func isGateOpen(_ clef: Clef) -> Bool {
        let fastTrack = lesson.level > 2
        return newestBatch(clef).allSatisfy { isSolid(stats(for: $0).recent, fastTrack: fastTrack) }
            && pool(clef).allSatisfy { stats(for: $0).box >= config.gateMinBox }
    }

    /// His notes in this lesson are going well: the size can grow and stretch screens
    /// can come up.
    public var isDoingWell: Bool {
        let recent = state.lessonRecent.suffix(config.lessonWindow)
        guard recent.count >= config.sizeWindow * 2 else { return false }
        return Double(recent.filter(\.firstTry).count) / Double(recent.count) >= config.sizeUpRate
    }

    /// The next rhythm-judged screen gets played to him first: one of the first few of
    /// a level that listens to rhythm without drilling it (3 and 4). Level 5's rhythm
    /// lessons open with their own lesson intro.
    public var wantsRhythmDemo: Bool {
        lesson.rhythmCheck != .off && !lesson.texture.isRhythm
            && (state.rhythmDemos[String(lesson.level)] ?? 0) < config.rhythmDemoScreens
    }

    /// Rhythm track for the current lesson: 6 of the last 8 judged screens fully ok,
    /// or the last 3 all ok.
    public var isRhythmSolid: Bool {
        let recent = state.rhythmRecent.suffix(config.solidWindow)
        if recent.filter({ $0 }).count >= config.rhythmSolidRequired { return true }
        return recent.count >= config.fastTrackCount && recent.suffix(config.fastTrackCount).allSatisfy { $0 }
    }

    public func status(ofLesson id: LessonID) -> LessonStatus {
        if id == state.lesson { return .current }
        if state.completedLessons.contains(id) { return .completed }
        guard let index = curriculum.index(of: id), let current = curriculum.index(of: state.lesson) else { return .upcoming }
        return index < current ? .skipped : .upcoming
    }

    /// A level is current while he's in one of its lessons, completed when every lesson is.
    public func status(ofLevel number: Int) -> LessonStatus {
        guard let level = curriculum.level(number) else { return .upcoming }
        if lesson.level == number { return .current }
        if level.lessons.allSatisfy({ state.completedLessons.contains($0.id) }) { return .completed }
        return number < lesson.level ? .skipped : .upcoming
    }

    public var isCurriculumComplete: Bool {
        curriculum.lessons.allSatisfy { state.completedLessons.contains($0.id) }
    }

    /// The clef a session's first run is on (one-clef lessons): the lesson's focus clef,
    /// otherwise the clef his last session didn't start on (treble the very first time).
    public var firstRunClef: Clef {
        if let focus = Clef(rawValue: lesson.focus.rawValue) { return focus }
        return state.lastFirstClef == .treble ? .bass : .treble
    }

    /// A session started its first run on `clef`.
    mutating func startedRun(on clef: Clef) {
        state.lastFirstClef = clef
    }

    public func progress(for key: NoteKey) -> NoteProgress {
        let s = stats(for: key)
        return NoteProgress(
            key: key, box: s.box, isSolid: isSolid(key), attempts: s.attempts,
            recentFirstTryRate: s.recentFirstTryRate, medianResponse: s.medianResponse,
            fluency: fluency(s), peakFluency: s.peakFluency
        )
    }

    public func progress(for id: ItemID) -> NoteProgress? { NoteKey(id: id).map { progress(for: $0) } }

    /// Every note he has played at least once (not counting intros), treble first, low to high.
    public var allProgress: [NoteProgress] {
        state.stats.filter { $0.value.attempts > 0 }.keys.compactMap(NoteKey.init(id:)).sorted().map { progress(for: $0) }
    }

    /// Notes he has met (intro done, or played), treble first, low to high.
    public var metNotes: [NoteKey] {
        let ids = state.introduced.union(state.stats.filter { $0.value.attempts > 0 }.keys)
        return ids.compactMap(NoteKey.init(id:)).sorted()
    }

    /// 0...1. 60% from the leitner box, 40% from speed: full marks at half the
    /// fast-track time or quicker, none at the solid threshold or slower.
    public func fluency(_ s: ItemStats) -> Double {
        guard s.attempts > 0 else { return 0 }
        let boxPart = Double(s.box - 1) / Double(max(1, config.boxCount - 1))
        var speedPart = 0.0
        if let m = s.medianResponse {
            let fast = config.fastTrackResponse / 2
            let slow = config.solidMedianResponse
            speedPart = min(1, max(0, (slow - m) / (slow - fast)))
        }
        return 0.6 * boxPart + 0.4 * speedPart
    }

    // MARK: changing

    /// Records one finished screen, note by note, then opens gates and moves on if
    /// he's ready.
    @discardableResult
    public mutating func record(_ screen: ScreenResult) -> MasteryUpdate {
        var update = MasteryUpdate()
        // a second read of the screen he just played: nothing counts, it's measured silently
        guard screen.reason != .again else { return update }
        if screen.wasLessonIntro {
            state.introduced.insert(lessonIntroID)
        }
        for attempt in screen.notes {
            guard let key = NoteKey(id: attempt.itemID) else { continue }
            state.introduced.insert(key.id) // met, whichever screen it was on
            guard !attempt.wasIntro else { continue }
            var s = stats(for: key)
            let sample = AttemptSample(firstTry: attempt.firstTry, responseTime: max(0, attempt.responseTime), session: state.session)
            s.recent = Array((s.recent + [sample]).suffix(config.solidWindow))
            // habit: in-line times, and the first showing each session (a wrong octave isn't automatic)
            let automatic = attempt.firstTry && attempt.almostPresses == 0
            if attempt.inLine {
                let inLine = AttemptSample(firstTry: automatic, responseTime: max(0, attempt.responseTime), session: state.session)
                s.inLine = Array((s.inLine + [inLine]).suffix(config.habitWindow))
            }
            if s.sessionFirsts.last?.session != state.session {
                let first = SessionFirst(session: state.session, day: state.sessionDay, clean: automatic)
                s.sessionFirsts = Array((s.sessionFirsts + [first]).suffix(6))
            }
            // a note the band helped with in a song: back to normal after a couple right first try
            if attempt.firstTry, s.comeBack > 0 { s.comeBack -= 1 }
            // stuck isn't wrong: a hint from being stuck alone holds the box where it is
            if attempt.firstTry {
                s.box = min(config.boxCount, s.box + 1)
            } else if attempt.wrongPresses > 0 {
                s.box = max(1, s.box - 1)
            }
            s.attempts += 1
            s.firstTryCount += attempt.firstTry ? 1 : 0
            s.peakFluency = max(s.peakFluency, fluency(s))
            state.stats[key.id] = s
            state.lessonPlays[key.id, default: 0] += 1
            if isHabit(key) { state.lessonHabit.insert(key.id) }
            state.lessonRecent = Array((state.lessonRecent + [sample]).suffix(max(config.lessonWindow, config.solidWindow)))
        }
        if !screen.wasIntro, !screen.wasLessonIntro {
            state.lessonScreens += 1
        }
        if let rhythm = screen.rhythm, !screen.wasLessonIntro {
            // a wrong value on the first go is a miss on the rhythm track. it never holds back notes
            state.rhythmRecent = Array((state.rhythmRecent + [rhythm.isOK]).suffix(config.solidWindow))
        }
        if screen.wasRhythmDemo {
            state.rhythmDemos[String(lesson.level), default: 0] += 1
        }
        if screen.reason == .normal, !screen.wasIntro, !screen.wasLessonIntro, screen.size == state.screenSize {
            noteSize(screen, &update)
        }
        advance(&update)
        // after moving on: a new lesson starts its stone from empty
        state.lessonPeak = max(state.lessonPeak, liveLessonFraction)
        return update
    }

    /// The band played these notes for him in a song (he was stuck): practice shows them
    /// a bit more often until he has played each right first try `comeBackPlays` times.
    /// Nothing else changes: no box drop, no miss, no stats (songs touch no stats).
    public mutating func comeBack(to keys: [NoteKey]) {
        for key in Set(keys) {
            var s = stats(for: key)
            s.comeBack = max(s.comeBack, config.comeBackPlays)
            state.stats[key.id] = s
        }
    }

    /// How much more a note is picked on a practice screen: `comeBackBoost` while the band
    /// helped with it lately, else 1.
    func comeBackWeight(_ key: NoteKey) -> Double {
        stats(for: key).comeBack > 0 ? config.comeBackBoost : 1
    }

    /// Parent jump: to any lesson, in any level. Lessons in between are not marked done.
    /// He plays the lesson until it's solid (fresh screens), then moves on to the next
    /// lesson that isn't done. Returns the notes that unlocked.
    @discardableResult
    public mutating func moveToLesson(_ id: LessonID) -> [ItemID] {
        guard curriculum.lesson(id) != nil, id != state.lesson else { return [] }
        // a parent moving him isn't a level-up, and a splash for a level he isn't in would be odd
        state.levelUps = []
        let unlocked = enter(id)
        // between sessions: his last session's day isn't a day in this lesson
        state.lessonDays = []
        return unlocked
    }

    /// Parent reset inside a level (plans/2026-10-17-reset-and-repetition.md): he starts
    /// this lesson fresh, as if entering it for the first time (screens, recent window,
    /// plays, habit-in-lesson, days and the stone's peak from zero), and it and every
    /// later lesson of its level go back to not done. Works on the lesson he's in too.
    /// What he knows stays: stats, boxes, habit samples, unlocked and introduced notes.
    /// Never a level-up, and `celebratedLevels` stays. Returns the notes that unlocked.
    @discardableResult
    public mutating func restartLesson(_ id: LessonID) -> [ItemID] {
        guard let target = curriculum.lesson(id), let level = curriculum.level(target.level) else { return [] }
        state.completedLessons.subtract(level.lessons.drop(while: { $0.id != id }).map(\.id))
        // a pending splash for the level he stays in is still his (he finished the one
        // before). one for any other level would be odd, like a parent move
        state.levelUps.removeAll { $0 != target.level }
        let unlocked = enter(id)
        // between sessions: his last session's day isn't a day in this lesson
        state.lessonDays = []
        return unlocked
    }

    /// Parent reset of a whole level: `restartLesson` on its first lesson.
    @discardableResult
    public mutating func restartLevel(_ number: Int) -> [ItemID] {
        guard let first = curriculum.level(number)?.lessons.first else { return [] }
        return restartLesson(first.id)
    }

    /// A level he reached by finishing the one before, still to be celebrated.
    public var pendingLevelUp: Int? { state.levelUps.first }

    /// The level-up splash is up: it's had its celebration, it never comes back.
    public mutating func celebrateLevelUp() {
        guard !state.levelUps.isEmpty else { return }
        state.celebratedLevels.insert(state.levelUps.removeFirst())
    }

    /// Parent picks a level: its first lesson that isn't done (or its first lesson).
    @discardableResult
    public mutating func moveToLevel(_ number: Int) -> [ItemID] {
        guard let level = curriculum.level(number) else { return [] }
        let target = level.lessons.first { !state.completedLessons.contains($0.id) } ?? level.lessons[0]
        return moveToLesson(target.id)
    }

    // MARK: internals

    var lessonIntroID: ItemID { "lesson:\(lesson.id)" }

    private mutating func noteSize(_ screen: ScreenResult, _ update: inout MasteryUpdate) {
        let counted = screen.notes.filter { !$0.wasIntro }
        state.sizeRecent = Array((state.sizeRecent + [SizeSample(notes: counted.count, firstTry: counted.filter(\.firstTry).count)]).suffix(config.sizeWindow))
        let notes = state.sizeRecent.reduce(0) { $0 + $1.notes }
        guard notes > 0 else { return }
        let rate = Double(state.sizeRecent.reduce(0) { $0 + $1.firstTry }) / Double(notes)
        let sizes = lesson.sizes
        // a screen never needs every note he has on a clef, or it's only a reshuffle:
        // 3 notes on a clef allow 2 a screen, 5 allow 4. grand staff screens put half on
        // each. paced lessons (level 1) repeat on purpose: 2 notes make 2-note screens,
        // 3 notes allow 3
        let perClef = lesson.clefs.map { playable($0).count - (lesson.paced ? 0 : 1) }.min() ?? 1
        let room = lesson.texture.isRhythm ? Int.max : lesson.layout == .grand ? perClef * 2 : perClef
        if state.sizeRecent.count >= config.sizeWindow, rate >= config.sizeUpRate, state.screenSize < sizes.upperBound,
           state.screenSize < room {
            state.screenSize += 1
        } else if state.sizeRecent.count >= config.sizeWindow - 1, rate < config.sizeDownRate, state.screenSize > sizes.lowerBound {
            state.screenSize -= 1
        } else {
            return
        }
        state.sizeRecent = []
        update.screenSize = state.screenSize
    }

    private mutating func advance(_ update: inout MasteryUpdate) {
        let lesson = self.lesson
        for clef in lesson.clefs where isGateOpen(clef) {
            let locked = lockedNew(clef)
            guard !locked.isEmpty else { continue }
            let batch = chooseBatch(from: locked, count: lesson.unlockBatch, joining: pool(clef))
            unlock(batch, clef: clef)
            update.unlocked += batch.map(\.id)
        }
        guard isLessonDone else { return }
        state.completedLessons.insert(lesson.id)
        update.completedLesson = lesson.id
        // on to the next lesson not done yet (a parent may have moved him back). the
        // last lesson of a level leads into the next level
        guard let index = curriculum.index(of: lesson.id),
              let next = curriculum.lessons[(index + 1)...].first(where: { !state.completedLessons.contains($0.id) })
        else { return }
        update.enteredLesson = next.id
        if next.level > lesson.level, !state.celebratedLevels.contains(next.level), !state.levelUps.contains(next.level) {
            state.levelUps.append(next.level)
            update.levelUp = next.level
        }
        update.unlocked += enter(next.id)
    }

    /// Every note out and met, every note at box 3 or more, enough screens in this
    /// lesson, and his recent notes here right first try (and rhythm solid in rhythm
    /// lessons, and every new note played `lessonMinNewPlays` times in paced lessons, so
    /// the fast track can't end one early). The newest batch doesn't need its own 7 of 8
    /// here: that rule paces unlocks, and with nothing left to unlock the lesson window
    /// covers it.
    var isLessonDone: Bool {
        let lesson = self.lesson
        guard lesson.clefs.allSatisfy({ lockedNew($0).isEmpty && pendingIntros($0).isEmpty }),
              pool.allSatisfy({ stats(for: $0).box >= config.gateMinBox }),
              state.lessonScreens >= config.lessonMinScreens,
              !lesson.paced || lesson.newKeys.allSatisfy(hasMinPlays)
        else { return false }
        let window = state.lessonRecent.suffix(config.lessonWindow)
        // a drill lesson: his notes habit (on two days), or enough days in it and the usual rule
        if lesson.isDrillLesson {
            let ready = drillLessonReady
            if ready.habit { return !lesson.texture.isRhythm || isRhythmSolid }
            guard ready.enoughDays else { return false }
        }
        guard window.count >= config.lessonWindow,
              Double(window.filter(\.firstTry).count) / Double(window.count) >= config.lessonRate,
              median(window.map(\.responseTime)) < config.solidMedianResponse
        else { return false }
        // rhythm lessons: the rhythm track too (a rhythm slip never holds back notes,
        // but a rhythm lesson is about the rhythm)
        if lesson.texture.isRhythm, !isRhythmSolid { return false }
        return state.introduced.contains(lessonIntroID) || lesson.texture == .single || lesson.isDrillLesson
    }

    /// Starts a lesson: fresh windows, then its notes.
    @discardableResult
    private mutating func enter(_ id: LessonID) -> [ItemID] {
        state.lesson = id
        state.lessonScreens = 0
        state.lessonRecent = []
        state.lessonPlays = [:]
        state.rhythmRecent = []
        state.newest = [:]
        state.sizeRecent = []
        state.lessonPeak = 0
        state.lessonDays = state.session > 0 ? [state.sessionDay] : []
        state.lessonHabit = []
        return prepareLesson()
    }

    /// Unlocks the lesson's known notes and tops its new notes up to the start count.
    /// A paced lesson's new notes are its newest even when they were out already (an old
    /// save, a parent move), so they still get their share.
    /// Safe to call again: a lesson that's already set up doesn't change.
    @discardableResult
    private mutating func prepareLesson() -> [ItemID] {
        let lesson = self.lesson
        var unlocked: [ItemID] = []
        for clef in lesson.clefs {
            let notes = lesson.notes(clef)!
            for pitch in notes.known where !state.unlocked.contains(NoteKey(clef, pitch).id) {
                state.unlocked.insert(NoteKey(clef, pitch).id)
            }
            let out = notes.new.filter { state.unlocked.contains(NoteKey(clef, $0).id) }.count
            if out < notes.start {
                let batch = chooseBatch(from: lockedNew(clef), count: notes.start - out, joining: pool(clef))
                unlock(batch, clef: clef)
                unlocked += batch.map(\.id)
            }
            if lesson.paced, newestBatch(clef).isEmpty {
                state.newest[clef.rawValue] = notes.new.map { NoteKey(clef, $0).id }.filter(state.unlocked.contains)
            }
        }
        state.screenSize = min(max(state.screenSize, lesson.sizes.lowerBound), lesson.sizes.upperBound)
        return unlocked
    }

    private mutating func unlock(_ batch: [NoteKey], clef: Clef) {
        for key in batch { state.unlocked.insert(key.id) }
        state.newest[clef.rawValue] = batch.map(\.id)
    }

    /// `count` notes at random from `locked`, so that the pool they join has at least
    /// one line note and one space note when that's possible. In a paced lesson, the
    /// first `count` in the lesson's order (G first).
    private mutating func chooseBatch(from locked: [NoteKey], count: Int, joining pool: [NoteKey]) -> [NoteKey] {
        let n = min(count, locked.count)
        guard n > 0 else { return [] }
        if lesson.paced { return Array(locked.prefix(n)) }
        var first: [NoteKey]?
        for _ in 0..<40 {
            let pick = Array(shuffled(locked, using: &state.dice).prefix(n))
            let all = pool + pick
            if all.contains(where: \.isOnLine), all.contains(where: { !$0.isOnLine }) {
                return pick.sorted()
            }
            first = first ?? pick
        }
        return first!.sorted()
    }

    /// `fastTrack`: the last 3 quick and right count too.
    func isSolid(_ recent: [AttemptSample], fastTrack: Bool = true) -> Bool {
        let window = recent.suffix(config.solidWindow)
        let firstTries = window.filter(\.firstTry).count
        if firstTries >= config.solidRequired, median(window.map(\.responseTime)) < config.solidMedianResponse {
            return true
        }
        guard fastTrack else { return false }
        let streak = window.suffix(config.fastTrackCount)
        return streak.count == config.fastTrackCount
            && streak.allSatisfy { $0.firstTry && $0.responseTime < config.fastTrackResponse }
    }
}

/// [0, 1) from 53 random bits. Our own, so picks don't depend on stdlib internals.
func unitInterval(_ rng: inout some RandomNumberGenerator) -> Double {
    Double(rng.next() >> 11) * 0x1p-53
}

/// Fisher-Yates with `unitInterval`, so the order only depends on the generator.
func shuffled<T>(_ items: [T], using rng: inout some RandomNumberGenerator) -> [T] {
    var items = items
    for i in stride(from: items.count - 1, to: 0, by: -1) {
        let j = min(i, Int(unitInterval(&rng) * Double(i + 1)))
        items.swapAt(i, j)
    }
    return items
}

func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty)
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

// see LenientDecoding.swift. a round-1 state (per curated item, with units) decodes
// too: single-note stats carry over where clef and pitch match ("treble:G4"), group,
// chord and rhythm item ids are dropped, and he starts at lesson 1.1.
extension MasteryState {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MasteryState()
        lesson = try c.value(.lesson, or: d.lesson)
        unlocked = try c.value(.unlocked, or: d.unlocked).filter { NoteKey(id: $0) != nil }
        completedLessons = try c.value(.completedLessons, or: d.completedLessons)
        stats = try c.value(.stats, or: d.stats).filter { NoteKey(id: $0.key) != nil }
        introduced = try c.value(.introduced, or: d.introduced).filter { NoteKey(id: $0) != nil || $0.hasPrefix("lesson:") }
        newest = try c.value(.newest, or: d.newest)
        lessonScreens = try c.value(.lessonScreens, or: d.lessonScreens)
        lessonRecent = try c.value(.lessonRecent, or: d.lessonRecent)
        lessonPlays = try c.value(.lessonPlays, or: d.lessonPlays)
        rhythmRecent = try c.value(.rhythmRecent, or: d.rhythmRecent)
        rhythmDemos = try c.value(.rhythmDemos, or: d.rhythmDemos)
        screenSize = try c.value(.screenSize, or: d.screenSize)
        sizeRecent = try c.value(.sizeRecent, or: d.sizeRecent)
        recentScreens = try c.value(.recentScreens, or: d.recentScreens)
        recentColumns = try c.value(.recentColumns, or: d.recentColumns)
        introGap = try c.value(.introGap, or: d.introGap)
        recentSongs = try c.value(.recentSongs, or: d.recentSongs)
        lessonPeak = try c.value(.lessonPeak, or: d.lessonPeak)
        lastFirstClef = try c.decodeIfPresent(Clef.self, forKey: .lastFirstClef)
        lastDrill = try? c.decodeIfPresent(Drill.self, forKey: .lastDrill)
        lastShape = try? c.decodeIfPresent(PatternShape.self, forKey: .lastShape)
        recentPatterns = (try? c.value(.recentPatterns, or: d.recentPatterns)) ?? d.recentPatterns
        recentCells = (try? c.value(.recentCells, or: d.recentCells)) ?? d.recentCells
        lastIntro = try c.value(.lastIntro, or: d.lastIntro)
        session = try c.value(.session, or: d.session)
        sessionDay = try c.value(.sessionDay, or: d.sessionDay)
        lessonDays = try c.value(.lessonDays, or: d.lessonDays)
        lessonHabit = try c.value(.lessonHabit, or: d.lessonHabit)
        levelUps = try c.value(.levelUps, or: d.levelUps)
        celebratedLevels = try c.value(.celebratedLevels, or: d.celebratedLevels)
        dice = try c.value(.dice, or: d.dice)
    }
}

extension ItemStats {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ItemStats()
        box = try c.value(.box, or: d.box)
        recent = try c.value(.recent, or: d.recent)
        attempts = try c.value(.attempts, or: d.attempts)
        firstTryCount = try c.value(.firstTryCount, or: d.firstTryCount)
        peakFluency = try c.value(.peakFluency, or: d.peakFluency)
        inLine = try c.value(.inLine, or: d.inLine)
        sessionFirsts = try c.value(.sessionFirsts, or: d.sessionFirsts)
        comeBack = try c.value(.comeBack, or: d.comeBack)
    }
}

// every saved note's `recent` is a list of these, so a sample saved before a field was
// added must still decode (or his whole state wouldn't)
extension AttemptSample {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstTry = try c.value(.firstTry, or: false)
        responseTime = try c.value(.responseTime, or: 0)
        session = try c.value(.session, or: 0)
    }
}

extension SessionFirst {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = try c.value(.session, or: 0)
        day = try c.value(.day, or: 0)
        clean = try c.value(.clean, or: false)
    }
}
