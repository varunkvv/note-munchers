public struct AttemptSample: Hashable, Codable, Sendable {
    public var firstTry: Bool
    public var responseTime: Double

    public init(firstTry: Bool, responseTime: Double) {
        self.firstTry = firstTry
        self.responseTime = responseTime
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
    public var lastScreenWasIntro = false
    /// His last songs (song time), oldest first, so a new song is never one of them and
    /// level 1 songs take turns between the clefs. Not mastery: songs never touch stats.
    public var recentSongs: [PlayedSong] = []
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
    public init() {}
}

/// How to pick the next screen.
public enum PickStyle: String, Codable, Hashable, Sendable {
    /// Intros when one is due, otherwise his current size, weighted toward weak notes,
    /// with the newest notes as about 1 in 4 of the notes on their clef.
    case normal
    /// Only his strongest notes (highest boxes among notes he has played). For the
    /// warm-up, easing after misses, and the easy screens at the end. No intros. Falls
    /// back to `normal` when he hasn't played anything in this lesson's pool yet.
    case strongest
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
            enter(curriculum.firstLesson.id)
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

    /// The most recent batch to unlock on this clef in this lesson (or the start set).
    /// Empty when the lesson started with everything already unlocked.
    public func newestBatch(_ clef: Clef) -> [NoteKey] {
        (state.newest[clef.rawValue] ?? []).compactMap { NoteKey(id: $0) }.filter(isUnlocked)
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
    /// below box 3.
    public func isGateOpen(_ clef: Clef) -> Bool {
        newestBatch(clef).allSatisfy(isSolid) && pool(clef).allSatisfy { stats(for: $0).box >= config.gateMinBox }
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
        if screen.wasLessonIntro {
            state.introduced.insert(lessonIntroID)
        }
        for attempt in screen.notes {
            guard let key = NoteKey(id: attempt.itemID) else { continue }
            state.introduced.insert(key.id) // met, whichever screen it was on
            guard !attempt.wasIntro else { continue }
            var s = stats(for: key)
            let sample = AttemptSample(firstTry: attempt.firstTry, responseTime: max(0, attempt.responseTime))
            s.recent = Array((s.recent + [sample]).suffix(config.solidWindow))
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
        return update
    }

    /// Parent jump: to any lesson, in any level. Lessons in between are not marked done.
    /// He plays the lesson until it's solid (fresh screens), then moves on to the next
    /// lesson that isn't done. Returns the notes that unlocked.
    @discardableResult
    public mutating func moveToLesson(_ id: LessonID) -> [ItemID] {
        guard curriculum.lesson(id) != nil, id != state.lesson else { return [] }
        return enter(id)
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
        // 3 notes on a clef allow 2 a screen, 5 allow 4. grand staff screens put half on each
        let perClef = lesson.clefs.map { playable($0).count - 1 }.min() ?? 1
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
        update.unlocked += enter(next.id)
    }

    /// Every note out and met, every note at box 3 or more, enough screens in this
    /// lesson, and his recent notes here right first try (and rhythm solid in rhythm
    /// lessons). The newest batch doesn't need its own 7 of 8 here: that rule paces
    /// unlocks, and with nothing left to unlock the lesson window covers it.
    var isLessonDone: Bool {
        let lesson = self.lesson
        guard lesson.clefs.allSatisfy({ lockedNew($0).isEmpty && pendingIntros($0).isEmpty }),
              pool.allSatisfy({ stats(for: $0).box >= config.gateMinBox }),
              state.lessonScreens >= config.lessonMinScreens
        else { return false }
        let window = state.lessonRecent.suffix(config.lessonWindow)
        guard window.count >= config.lessonWindow,
              Double(window.filter(\.firstTry).count) / Double(window.count) >= config.lessonRate,
              median(window.map(\.responseTime)) < config.solidMedianResponse
        else { return false }
        // rhythm lessons: the rhythm track too (a rhythm slip never holds back notes,
        // but a rhythm lesson is about the rhythm)
        if lesson.texture.isRhythm, !isRhythmSolid { return false }
        return state.introduced.contains(lessonIntroID) || lesson.texture == .single
    }

    /// Starts a lesson: fresh windows, then its notes.
    @discardableResult
    private mutating func enter(_ id: LessonID) -> [ItemID] {
        state.lesson = id
        state.lessonScreens = 0
        state.lessonRecent = []
        state.rhythmRecent = []
        state.newest = [:]
        state.sizeRecent = []
        return prepareLesson()
    }

    /// Unlocks the lesson's known notes and tops its new notes up to the start count.
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
        }
        state.screenSize = min(max(state.screenSize, lesson.sizes.lowerBound), lesson.sizes.upperBound)
        return unlocked
    }

    private mutating func unlock(_ batch: [NoteKey], clef: Clef) {
        for key in batch { state.unlocked.insert(key.id) }
        state.newest[clef.rawValue] = batch.map(\.id)
    }

    /// `count` notes at random from `locked`, so that the pool they join has at least
    /// one line note and one space note when that's possible.
    private mutating func chooseBatch(from locked: [NoteKey], count: Int, joining pool: [NoteKey]) -> [NoteKey] {
        let n = min(count, locked.count)
        guard n > 0 else { return [] }
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

    func isSolid(_ recent: [AttemptSample]) -> Bool {
        let window = recent.suffix(config.solidWindow)
        let firstTries = window.filter(\.firstTry).count
        if firstTries >= config.solidRequired, median(window.map(\.responseTime)) < config.solidMedianResponse {
            return true
        }
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
        rhythmRecent = try c.value(.rhythmRecent, or: d.rhythmRecent)
        rhythmDemos = try c.value(.rhythmDemos, or: d.rhythmDemos)
        screenSize = try c.value(.screenSize, or: d.screenSize)
        sizeRecent = try c.value(.sizeRecent, or: d.sizeRecent)
        recentScreens = try c.value(.recentScreens, or: d.recentScreens)
        recentColumns = try c.value(.recentColumns, or: d.recentColumns)
        lastScreenWasIntro = try c.value(.lastScreenWasIntro, or: d.lastScreenWasIntro)
        recentSongs = try c.value(.recentSongs, or: d.recentSongs)
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
    }
}
