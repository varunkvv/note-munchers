public enum SessionPhase: String, Codable, Hashable, Sendable {
    case notStarted
    /// A screen is up and he's on the first rung of the hint ladder for the current note.
    case prompt
    /// One step up the ladder (a wrong key, or stuck): it wobbled, still waiting.
    case waiting
    /// Two steps: the app played the right pitch.
    case hint1
    /// Three or more: the keyboard picture lights up the key (picture only, not tappable).
    case hint2
    /// Screen done. Celebrate, then call `next(at:)` when the animation ends.
    case success
    /// Piano disconnected: the "turn on the piano" screen. Picks up where it was.
    case paused
    /// Session over: the summary screen.
    case done

    /// Phases where key presses are judged.
    public var isPlaying: Bool { [.prompt, .waiting, .hint1, .hint2].contains(self) }
}

/// Which way the right key is, after the right letter in the wrong octave.
public enum AlmostHint: String, CaseIterable, Codable, Hashable, Sendable {
    /// "this one is higher up"
    case higher
    /// "this one is lower down"
    case lower
    /// "this one is the middle C" (only when the note is middle C)
    case middleC
}

/// What the voice says. A finite set of situations: the app turns each into words (and
/// later into one of several recorded clips). Where a line names a note it's an
/// associated value, so a clip bank needs one take per note name (A-G and F sharp).
///
/// Voice is rare: no letter after right keys (the piano already makes the sound).
/// NoteCore decides when to talk. Praise is process praise only - it names what he
/// did (mueller & dweck), never "smart", "genius", "good boy".
public enum Speech: Hashable, Codable, Sendable {
    /// Session start: "hi! let's play"
    case hello
    /// A new note's intro, right after its pitch plays and the key lights up: "this is D"
    case meetNote(NoteName)
    /// First screen of a rhythm lesson, before the app plays it to him: "here's a new one! listen"
    case listen
    /// First screen of a two-at-once lesson, before the app plays it: "two at once! listen"
    case twoAtOnce
    /// Right letter, wrong octave in a lenient lesson: "that's a C! this one is the
    /// middle C" / "...higher up" / "...lower down". Doesn't count against him.
    case almost(NoteName, AlmostHint)
    /// The natural next to a sharp note (F on an F# note): "that's F - this one is F
    /// sharp, the black key". The value is the sharp note.
    case sharpHint(NoteName)
    /// Hint ladder, second step, just before the app plays the right pitch: "listen"
    case hintListen
    /// Hint ladder, third step, as the keyboard picture lights up: "this one is D -
    /// here it is"
    case hintShow(NoteName)
    /// Hint ladder, third step, on two notes at once: "here they are"
    case hintLook
    /// A wrong key when he's been doing well: "oops, silly goose! let's look again" (his
    /// teacher's phrase, said with a smile). Rare: the first miss on a screen, only when
    /// 4 of his last 5 screens this session were right first try, at most once a
    /// session, never once easing has kicked in. Goes with the wobble, the hint ladder
    /// carries on as usual
    case oops
    /// Now and then after a screen that needed a hint: "you kept trying and found it!"
    case keptTrying
    /// Now and then after a screen he read right first try: "you looked carefully!"
    case lookedCarefully
    /// Rhythm: a note was too short. "hold this one longer"
    case holdLonger
    /// Shown with the paused screen.
    case turnOnPiano
    /// Session end: "look who ate well today"
    case sessionDone
}

/// One-shot things to do after a call: sounds, voice, animations. What to draw is
/// read from the session's state (`item`, `noteIndex`, `keyboardHint`, `phase`).
public enum Cue: Hashable, Sendable {
    /// A new screen is up. Draw `item`, starting at note 0.
    case showItem
    /// One step up the hint ladder (wrong key, or stuck): that note wobbles a little.
    case wobble(note: Int)
    /// Play these pitches out loud. A hint, or the demo of a new note.
    case playPitches([Pitch])
    /// Right key(s) for that note: it hops off the staff and its muncher gobbles it.
    case correct(note: Int)
    case say(Speech)
    /// Rhythm nudge: that note glows for its full written length.
    case rhythmGlow(note: Int)
    /// Play the whole screen at `beat` seconds per quarter: the demo of a new rhythm
    /// lesson, before he plays it.
    case playPhrase(beat: Double)
    /// New notes unlocked. Each gets an intro (and a new muncher) when it comes up.
    case unlocked([ItemID])
    /// Show the "turn on the piano" screen.
    case paused
    /// Piano is back. Hide the paused screen and redraw the current state.
    case resumed
    /// Show the session end screen from `summary`.
    case done
}

/// One note's share of a session, for the end screen.
public struct PracticedItem: Hashable, Codable, Sendable {
    /// The note's id (`"treble:G4"`).
    public let id: ItemID
    public var plays: Int
    public var firstTries: Int
    /// `peakFluency` before and after this session. His muncher for this note grew if after > before.
    public var fluencyBefore: Double
    public var fluencyAfter: Double
}

public struct SessionSummary: Hashable, Codable, Sendable {
    public enum EndReason: String, Codable, Hashable, Sendable {
        case itemLimit, timeLimit
    }

    public var startLesson: LessonID
    public var endLesson: LessonID
    public var screensPlayed = 0
    /// Notes played (no intros), one per key.
    public var notesPlayed = 0
    public var firstTryNotes = 0
    /// Seconds, not counting time paused.
    public var activeDuration = 0.0
    public var screens: [ScreenResult] = []
    /// Notes unlocked this session.
    public var unlocked: [ItemID] = []
    public var completedLessons: [LessonID] = []
    /// Every note played this session, in the order first played.
    public var practiced: [PracticedItem] = []
    /// The limit that was reached. The session then ran until a screen all right first try.
    public var endedBy: EndReason?
    /// Easy screens played after the limit so the session ends on a success (max `maxExtraItems`).
    public var extraItems = 0

    public init(startLesson: LessonID) {
        self.startLesson = startLesson
        endLesson = startLesson
    }

    /// Every note, screen by screen.
    public var attempts: [AttemptResult] { screens.flatMap(\.notes) }
}

/// One practice session: prompt -> waiting -> hint1 -> hint2 -> success -> next ... -> done.
///
/// Feed it note events and the app clock. Every call returns the cues to play; what
/// to draw is in the state. All times are seconds on the app's one monotonic clock.
/// After every call, if `nextDeadline` is set, call `tick(at:)` at that time
/// (it closes chord windows, steps up the hint ladder when he's stuck, and stops
/// waiting for the last key-up of a rhythm line).
///
/// Each note on a screen is judged on its own: its own hint ladder, its own first try,
/// its own response time from when it became the next note.
///
/// Shape of a session (learning principles in the plan):
/// - says hello, then opens with screens of his strongest notes (about 3 notes)
/// - a new note is introduced i do / we do / you do: the app plays it and lights the
///   key (`.playPitches` + `.say(.meetNote)`), he plays it with the picture up, after
///   that the picture only comes back as a hint
/// - after 3 of his last 5 notes weren't right first try, the next 2 screens are his strongest
/// - when time or the screen count is up it ends after his next screen all right first
///   try (easy screens, at most `maxExtraItems` extra)
public struct PracticeSession: Sendable {
    public private(set) var engine: MasteryEngine
    public private(set) var phase: SessionPhase = .notStarted
    public private(set) var summary: SessionSummary
    public private(set) var isPianoConnected: Bool

    /// The screen that's up.
    public private(set) var item: PracticeItem?
    /// Which note of `item` he's on (left to right).
    public private(set) var noteIndex = 0
    /// Keys lit in the keyboard picture. Empty means the picture is hidden.
    public private(set) var keyboardHint: [Pitch] = []
    /// The note this screen introduces, if it's an intro.
    public private(set) var introNote: NoteKey?
    /// The first screen of a lesson with a new texture.
    public private(set) var isLessonIntro = false
    /// Why the current screen was picked.
    public private(set) var pickReason = PickReason.normal

    /// True while the current screen is an intro (a new note, or a new lesson texture).
    public var isIntro: Bool { introNote != nil || isLessonIntro }

    private var config: NoteCoreConfig { engine.config }
    private var rng: SeededRandom
    private var judge: AttemptJudge?

    // clock: active time = app time - start - paused total
    private var startTime = 0.0
    private var pausedTotal = 0.0
    private var pausedAt: Double?
    private var resumePhase: SessionPhase?

    // session shape
    private var greeted = false
    private var warmUpLeft = 0
    private var easingLeft = 0
    /// Last few notes: true when it wasn't right first try.
    private var struggles: [Bool] = []
    private var limitReached: SessionSummary.EndReason?
    private var praisedLast = false
    private var saidOops = false
    private var eased = false

    // the current screen, per column
    private var pickSize = 1
    private var lastActivity = 0.0
    private var startTimes: [Double] = []
    private var correctTimes: [Double] = []
    private var wrongs: [Int] = []
    private var stucks: [Int] = []
    private var almosts: [Int] = []
    private var hints: [HintLevel] = []
    /// Steps up the hint ladder on the current note (wrong keys and stuck steps).
    private var ladder = 0
    private var onsets: [Double] = []
    private var rhythmJudgeable = true
    private var awaitingRelease = false

    public init(engine: MasteryEngine, seed: UInt64, pianoConnected: Bool = true) {
        self.engine = engine
        rng = SeededRandom(seed: seed)
        isPianoConnected = pianoConnected
        summary = SessionSummary(startLesson: engine.lesson.id)
    }

    /// Staves to show for the current screen.
    public var staffLayout: StaffLayout { item?.layout ?? (engine.lesson.layout == .grand ? .grand : .treble) }

    /// Seconds into the session, not counting pauses.
    public func activeTime(at time: Double) -> Double {
        let pausedNow = pausedAt.map { time - $0 } ?? 0
        return max(0, time - startTime - pausedTotal - pausedNow)
    }

    /// When the app should call `tick(at:)` next, on the app clock. nil when nothing is pending.
    public var nextDeadline: Double? {
        guard phase.isPlaying, let item else { return nil }
        var deadlines: [Double] = []
        if awaitingRelease, let values = item.values {
            deadlines.append(RhythmJudge(config: config).settleTime(values, onsets: onsets))
        } else {
            if let window = judge?.windowDeadline {
                deadlines.append(window)
            }
            if ladder < 3 {
                deadlines.append(lastActivity + config.stuckAfter)
            }
        }
        return deadlines.min().map { $0 + startTime + pausedTotal }
    }

    // MARK: calls from the app

    public mutating func start(at time: Double) -> [Cue] {
        guard phase == .notStarted else { return [] }
        startTime = time
        warmUpLeft = engine.lesson.clefs.contains { !engine.strongestNotes($0).isEmpty } ? config.warmUpCount : 0
        guard isPianoConnected else {
            pausedAt = time
            resumePhase = nil
            phase = .paused
            return [.paused, .say(.turnOnPiano)]
        }
        return showNext(at: 0)
    }

    public mutating func handle(_ event: NoteEvent) -> [Cue] {
        guard phase.isPlaying, let item else { return [] }
        let t = activeTime(at: event.time)
        var cues: [Cue] = []
        switch event.kind {
        case .off:
            if awaitingRelease, item.notes[item.notes.count - 1].pitches.contains(event.pitch) {
                cues += finishRhythm(release: t)
            }
        case .on:
            guard !awaitingRelease, var judge else { return [] }
            lastActivity = t // any key down means he's not stuck
            let verdict = judge.noteOn(event.pitch, at: t)
            self.judge = judge
            if let verdict {
                cues += apply(verdict, at: t)
            }
        }
        return cues
    }

    /// Call at `nextDeadline`. Safe to call any time.
    public mutating func tick(at time: Double) -> [Cue] {
        guard phase.isPlaying, let item else { return [] }
        let t = activeTime(at: time)
        if awaitingRelease, let values = item.values {
            if t >= RhythmJudge(config: config).settleTime(values, onsets: onsets) {
                return finishRhythm(release: t)
            }
            return []
        }
        var cues: [Cue] = []
        if var judge, let verdict = judge.closeWindow(at: t) {
            self.judge = judge
            cues += apply(verdict, at: t)
        }
        if phase.isPlaying, !awaitingRelease, ladder < 3, t >= lastActivity + config.stuckAfter {
            // stuck: one step up the ladder, same as a wrong try but not a wrong press
            stucks[noteIndex] += 1
            lastActivity = t
            cues += climbLadder(speak: true)
        }
        return cues
    }

    /// The app put something over the screen before he could play (a new muncher
    /// hatching before its intro). Starts the response clock and the stuck timer for
    /// the current note again, so the hatch doesn't count as time to find it. Only
    /// before he has played anything on this screen.
    public mutating func restartPromptClock(at time: Double) {
        guard phase.isPlaying, noteIndex == 0, onsets.isEmpty, !startTimes.isEmpty else { return }
        let t = activeTime(at: time)
        startTimes[0] = t
        lastActivity = t
    }

    /// After the success animation: the next screen, or the end of the session.
    public mutating func next(at time: Double) -> [Cue] {
        guard phase == .success else { return [] }
        let t = activeTime(at: time)
        summary.activeDuration = t
        if limitReached == nil {
            if summary.screensPlayed >= config.sessionMaxItems {
                limitReached = .itemLimit
            } else if t >= config.sessionMaxDuration {
                limitReached = .timeLimit
            }
        }
        if let limit = limitReached {
            // end on a success: right after a screen all right first try, or once the extras run out
            if summary.screens.last?.firstTry == true || summary.extraItems >= config.maxExtraItems {
                return end(limit)
            }
            summary.extraItems += 1
            return showNext(at: t, reason: .extra)
        }
        return showNext(at: t)
    }

    /// No MIDI source. Shows the paused screen; nothing counts until it's back.
    public mutating func pianoDisconnected(at time: Double) -> [Cue] {
        isPianoConnected = false
        guard phase.isPlaying || phase == .success else { return [] }
        pausedAt = time
        resumePhase = phase
        phase = .paused
        judge?.reset()
        rhythmJudgeable = false // the timing of this line isn't his any more
        return [.paused, .say(.turnOnPiano)]
    }

    /// A MIDI source showed up. Picks up where it was.
    public mutating func pianoConnected(at time: Double) -> [Cue] {
        isPianoConnected = true
        guard phase == .paused, let pausedAt else { return [] }
        pausedTotal += time - pausedAt
        self.pausedAt = nil
        guard let resumePhase else {
            // never got going: start for real
            return [.resumed] + showNext(at: activeTime(at: time))
        }
        phase = resumePhase
        self.resumePhase = nil
        if awaitingRelease {
            // the key-up got lost while unplugged. pitch was right, skip the rhythm
            return [.resumed] + finish(at: activeTime(at: time), rhythm: nil)
        }
        return [.resumed]
    }

    // MARK: internals

    private mutating func showNext(at t: Double, reason forced: PickReason? = nil) -> [Cue] {
        var cues: [Cue] = []
        if !greeted {
            greeted = true
            cues.append(.say(.hello))
        }
        var reason = forced ?? .normal
        if forced == nil {
            if warmUpLeft > 0 {
                reason = .warmUp
            } else if easingLeft > 0 {
                easingLeft -= 1
                reason = .easing
            }
        }
        let pick = engine.pickScreen(reason == .normal ? .normal : .strongest, using: &rng)
        if reason == .warmUp {
            warmUpLeft -= pick.item.notes.count
        }
        if !pick.usedStrongest {
            reason = pick.isStretch ? .stretch : .normal
        }
        let next = pick.item
        item = next
        pickReason = reason
        pickSize = pick.size
        introNote = pick.intro
        isLessonIntro = pick.isLessonIntro
        noteIndex = 0
        lastActivity = t
        let columns = next.notes.count
        startTimes = Array(repeating: t, count: columns)
        correctTimes = Array(repeating: t, count: columns)
        wrongs = Array(repeating: 0, count: columns)
        stucks = Array(repeating: 0, count: columns)
        almosts = Array(repeating: 0, count: columns)
        hints = Array(repeating: .none, count: columns)
        ladder = 0
        onsets = []
        rhythmJudgeable = true
        awaitingRelease = false
        let policy = engine.lesson.octavePolicy
        if judge == nil {
            judge = AttemptJudge(expected: next.notes[0].pitches, octavePolicy: policy, config: config)
        } else {
            judge!.expect(next.notes[0].pitches)
            judge!.octavePolicy = policy
        }
        keyboardHint = isIntro ? next.notes[0].pitches : []
        phase = .prompt
        cues.append(.showItem)
        if let intro = pick.intro {
            // i do: the app shows him. then we do: he plays it with the picture up
            cues.append(.playPitches([intro.pitch]))
            if let name = intro.name {
                cues.append(.say(.meetNote(name)))
            }
        }
        return cues
    }

    private mutating func apply(_ verdict: PitchVerdict, at t: Double) -> [Cue] {
        guard let item else { return [] }
        let expected = item.notes[noteIndex].pitches
        switch verdict {
        case .correct:
            let cues: [Cue] = [.correct(note: noteIndex)]
            onsets.append(t)
            lastActivity = t
            correctTimes[noteIndex] = t
            if noteIndex < item.notes.count - 1 {
                noteIndex += 1
                startTimes[noteIndex] = t
                ladder = 0
                phase = .prompt
                let nextPitches = item.notes[noteIndex].pitches
                judge?.expect(nextPitches)
                keyboardHint = isIntro ? nextPitches : []
                return cues
            }
            if item.isRhythm, rhythmJudgeable {
                awaitingRelease = true // the last note's hold counts
                return cues
            }
            return cues + finish(at: t, rhythm: nil)

        case .almost(let played):
            almosts[noteIndex] += 1
            keyboardHint = expected
            guard let name = NoteName(played[0]) else { return [] }
            let hint: AlmostHint = expected[0] == .middleC ? .middleC : expected[0] > played[0] ? .higher : .lower
            return [.say(.almost(name, hint))]

        case .wrong(let played):
            wrongs[noteIndex] += 1
            // the natural next to a sharp (F on an F# note): say what it is, show the black key
            if expected.count == 1, played.count == 1, !expected[0].isWhiteKey,
               played[0].midi == expected[0].midi - 1, let sharp = NoteName(expected[0]) {
                let cues = climbLadder(speak: false)
                keyboardHint = expected
                return cues + [.say(.sharpHint(sharp))]
            }
            let firstMiss = wrongs.reduce(0, +) == 1 && stucks.reduce(0, +) == 0
            let cues = climbLadder(speak: true)
            if firstMiss, oopsFits {
                saidOops = true
                return cues + [.say(.oops)]
            }
            return cues
        }
    }

    /// "oops, silly goose" only while he's on a roll: 4 of his last 5 screens this
    /// session right first try, once a session, never after easing or on an intro.
    private var oopsFits: Bool {
        guard !saidOops, !eased, !isIntro, pickReason != .easing else { return false }
        let recent = summary.screens.filter { !$0.wasIntro && !$0.wasLessonIntro }.suffix(5)
        return recent.count == 5 && recent.filter(\.firstTry).count >= 4
    }

    /// One step up the hint ladder for the current note: wobble, then the sound, then
    /// the keyboard picture. Past the top, a wrong key replays the sound.
    private mutating func climbLadder(speak: Bool) -> [Cue] {
        guard let item else { return [] }
        let expected = item.notes[noteIndex].pitches
        ladder += 1
        rhythmJudgeable = false
        var cues: [Cue] = [.wobble(note: noteIndex)]
        switch ladder {
        case 1:
            phase = .waiting
            hints[noteIndex] = max(hints[noteIndex], .wobble)
        case 2:
            phase = .hint1
            hints[noteIndex] = max(hints[noteIndex], .playedPitch)
            if speak { cues.append(.say(.hintListen)) }
            cues.append(.playPitches(expected))
        default:
            phase = .hint2
            hints[noteIndex] = .keyboard
            if keyboardHint == expected {
                cues.append(.playPitches(expected)) // picture already up: say it with sound again
            } else if speak {
                if expected.count == 1, let name = NoteName(expected[0]) {
                    cues.append(.say(.hintShow(name)))
                } else {
                    cues.append(.say(.hintLook))
                }
            }
            keyboardHint = expected
        }
        return cues
    }

    private mutating func finishRhythm(release: Double) -> [Cue] {
        guard let item, let values = item.values, onsets.count == values.count else {
            return finish(at: release, rhythm: nil)
        }
        let result = RhythmJudge(config: config).judge(values, onsets: onsets, release: release)
        return finish(at: release, rhythm: result)
    }

    private mutating func finish(at t: Double, rhythm: RhythmResult?) -> [Cue] {
        guard let item else { return [] }
        awaitingRelease = false
        let lesson = engine.lesson
        // a rhythm line's gaps are the rhythm, not reading: every note gets the reading time
        let readingTime = correctTimes[0] - startTimes[0]
        var notes: [AttemptResult] = []
        for (i, column) in item.notes.enumerated() {
            let time = item.isRhythm ? readingTime : correctTimes[i] - startTimes[i]
            for key in column.keys {
                notes.append(AttemptResult(
                    itemID: key.id, lesson: lesson.id, level: lesson.level, wasIntro: introNote == key,
                    firstTry: wrongs[i] == 0 && stucks[i] == 0, wrongPresses: wrongs[i], almostPresses: almosts[i],
                    stuckSteps: stucks[i], hints: hints[i], responseTime: max(0, time)
                ))
            }
        }
        let screen = ScreenResult(
            screenID: item.id, lesson: lesson.id, reason: pickReason, wasIntro: introNote != nil,
            wasLessonIntro: isLessonIntro, notes: notes, rhythm: rhythm, size: pickSize
        )
        let before = Dictionary(item.keys.map { ($0.id, engine.stats(for: $0).peakFluency) }, uniquingKeysWith: { a, _ in a })
        let update = engine.record(screen)
        noteSummary(screen, update: update, fluencyBefore: before)
        noteStruggles(screen)

        phase = .success
        keyboardHint = []
        var cues: [Cue] = []
        var praised = false
        let roll = unitInterval(&rng)
        if let rhythm, let nudge = rhythm.nudgeIndex {
            cues.append(.rhythmGlow(note: nudge))
            if rhythm.verdicts[nudge] == .tooShort {
                cues.append(.say(.holdLonger))
            }
        } else if !isIntro, !praisedLast {
            // process praise, now and then. never two screens in a row
            let hinted = screen.usedHints
            if roll < (hinted ? config.keptTryingChance : config.praiseChance) {
                cues.append(.say(hinted ? .keptTrying : .lookedCarefully))
                praised = true
            }
        }
        praisedLast = praised
        if !update.unlocked.isEmpty {
            cues.append(.unlocked(update.unlocked))
        }
        return cues
    }

    /// Easing: after `easingTrigger` of the last `easingWindow` notes weren't right first
    /// try, the next `easingItems` screens are his strongest.
    private mutating func noteStruggles(_ screen: ScreenResult) {
        for note in screen.notes {
            struggles = Array((struggles + [!note.firstTry]).suffix(config.easingWindow))
            if easingLeft == 0, struggles.filter({ $0 }).count >= config.easingTrigger {
                easingLeft = config.easingItems
                eased = true
                struggles = []
            }
        }
    }

    private mutating func noteSummary(_ screen: ScreenResult, update: MasteryUpdate, fluencyBefore: [ItemID: Double]) {
        summary.screensPlayed += 1
        summary.screens.append(screen)
        for note in screen.notes where !note.wasIntro {
            summary.notesPlayed += 1
            summary.firstTryNotes += note.firstTry ? 1 : 0
        }
        summary.unlocked += update.unlocked
        if let lesson = update.completedLesson {
            summary.completedLessons.append(lesson)
        }
        summary.endLesson = engine.lesson.id
        for note in screen.notes {
            let after = engine.stats(for: note.itemID).peakFluency
            if let i = summary.practiced.firstIndex(where: { $0.id == note.itemID }) {
                summary.practiced[i].plays += 1
                summary.practiced[i].firstTries += note.firstTry ? 1 : 0
                summary.practiced[i].fluencyAfter = after
            } else {
                summary.practiced.append(PracticedItem(
                    id: note.itemID, plays: 1, firstTries: note.firstTry ? 1 : 0,
                    fluencyBefore: fluencyBefore[note.itemID] ?? 0, fluencyAfter: after
                ))
            }
        }
    }

    private mutating func end(_ reason: SessionSummary.EndReason) -> [Cue] {
        phase = .done
        item = nil
        summary.endedBy = reason
        return [.done, .say(.sessionDone)]
    }
}

// see LenientDecoding.swift. the app keeps every session as JSON. a round-1 summary
// decodes with zeros for what it didn't have
extension SessionSummary {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startLesson = try c.value(.startLesson, or: "")
        endLesson = try c.value(.endLesson, or: startLesson)
        screensPlayed = try c.value(.screensPlayed, or: 0)
        notesPlayed = try c.value(.notesPlayed, or: 0)
        firstTryNotes = try c.value(.firstTryNotes, or: 0)
        activeDuration = try c.value(.activeDuration, or: 0)
        screens = try c.value(.screens, or: [])
        unlocked = try c.value(.unlocked, or: [])
        completedLessons = try c.value(.completedLessons, or: [])
        practiced = try c.value(.practiced, or: [])
        endedBy = try c.decodeIfPresent(EndReason.self, forKey: .endedBy)
        extraItems = try c.value(.extraItems, or: 0)
    }
}
