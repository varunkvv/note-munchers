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
    /// He played a note as a different value: the app plays the screen back to him (with
    /// the keyboard), then calls `replayFinished(at:)` and he plays it again. Keys don't count.
    case replaying
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
/// No voice in a session (varun, 2026-10-17: "no talking in the middle of the session
/// ... he needs to be focused on the notes"). The one line is `.sessionDone`, when the
/// session is over. Praise is process praise only - it names what he did (mueller &
/// dweck), never "smart", "genius", "good boy".
///
/// NoteCore no longer says `.hello`, `.meetNote`, `.listen`, `.twoAtOnce`, `.almost`,
/// `.sharpHint`, `.hintListen`, `.hintShow`, `.hintLook`, `.oops`, `.keptTrying`,
/// `.lookedCarefully`, `.holdLonger`, `.longOne`, `.shortOne`, `.keepGoing` or
/// `.turnOnPiano` (the paused screen has words). The sound, wobble, glow and
/// keyboard picture that went with them stay. The cases (and their clips) are kept for
/// the parent side or later rounds.
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
    /// Earned, now and then: after a screen where a note needed the keyboard picture
    /// and he found it anyway: "you kept trying and found it!"
    case keptTrying
    /// Earned, now and then: after 6 screens in a row all right first try: "you looked carefully!"
    case lookedCarefully
    /// A long note played short, on the second go round: "hold this one a little longer"
    case holdLonger
    /// A long note played short (a half as a quarter), before the screen is played back
    /// to him: "listen to this one - it's a long one"
    case longOne
    /// A short note played long (an eighth as a quarter), before the play back: "listen
    /// to this one - it's a short one"
    case shortOne
    /// Still a wrong value after the last go: no more tries, on to the next screen. "let's keep going"
    case keepGoing
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
    /// Play the whole screen at `beat` seconds per quarter, the staff note sounding
    /// softly highlighted: sound before symbol, before he reads it (a rhythm lesson's
    /// first screen, a level's first rhythm screens). No keyboard: he still reads it.
    case playPhrase(beat: Double)
    /// Play the whole screen at `beat` with the staff highlight and the keyboard picture
    /// lighting each key as it sounds: the play button, and the play back after a wrong
    /// value (then call `replayFinished(at:)` when it's over).
    case showAndPlay(beat: Double)
    /// The same screen again from its first note: a rhythm retry. Draw every note fresh.
    case again
    /// He slipped past the first note and then paused: the screen goes back to its first
    /// note for another go (a screen counts when it's all played right in one go). The
    /// `played` notes he had played this go fade back onto the staff, the first note glows
    /// lightly. Silent. Draw from state (`noteIndex` is 0 again).
    case startOver(played: Int)
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
/// A screen of 2+ notes counts when he plays it all right in one go (varun, 2026-10-17:
/// "he has to play the whole sequence correctly ... gently start over"). A slip on the
/// first note works note by note: wobble, he tries again. A slip past it (a wrong key,
/// the wrong octave, a wrong two at once) wobbles softly and nothing else: keys after it
/// don't count, and once he pauses (`restartPause`, nothing held) the screen goes back to
/// its first note (`.startOver`). Every time, no cap (varun, 2026-10-20), a lesson's intro
/// and a rhythm retry too.
///
/// Each note keeps its own hint ladder across goes (a slip is a rung: the wobble, then
/// its pitch when he gets back to it, then the keyboard picture every time he gets back
/// to it, so he can always finish), and its result is from the first go that reached it:
/// first try, wrong keys, stuck steps, its response time from when it became the next
/// note until he played it right.
///
/// Shape of a session (learning principles in the plan):
/// - opens with one screen of his strongest notes, a run (start with success). Nothing is said
/// - a new note is introduced i do / we do / you do: the app plays it and lights the
///   key (`.playPitches`, the app shows its letter on the lit key), he plays it with the
///   picture up, after that the picture only comes back as a hint
/// - right after a new note's intro, its next few screens are mostly that note, then it
///   mixes in (blocked, then mixed)
/// - one burst of 3-4 drill screens (`Drill`) a session, inside one clef run, on notes
///   he has met in any lesson so far. A drill lesson is all drill screens
/// - about 1 normal screen in 4 (1 in 5 from level 3) is a pattern screen: two even bars,
///   bar 2 made from bar 1 (`PatternShape`), more of them right after a new note's intro
/// - now and then, after a screen all right first try, the same screen once more (a
///   second read, `PickReason.again`). Nothing on screen says so, nothing is counted
/// - after 3 of his last 5 notes weren't right first try, the next 2 screens are his strongest
/// - when time or the screen count is up it ends after his next screen all right first
///   try (easy screens, at most `maxExtraItems` extra)
/// - the voice: one line at the end, and at most one earned line in between (`finish`)
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
    /// What the rhythm judge listens to on this screen, nil when it isn't rhythm-judged
    /// (levels 1-2, one length only, intros).
    public private(set) var rhythmLine: RhythmLine?
    /// Rhythm retries used on this screen.
    public private(set) var retries = 0
    /// He slipped on this note (past the first): keys don't count until he pauses, then
    /// the screen starts over (at `nextDeadline`, call `tick`). nil the rest of the time.
    public private(set) var slippedNote: Int?
    /// Times this screen started over after a slip.
    public private(set) var restarts = 0
    /// The drill on this screen (a burst, a drill lesson, the warm-up's run), nil otherwise.
    public private(set) var drill: Drill?
    /// A pattern screen's shape (two bars, bar 2 made from bar 1), nil otherwise.
    public private(set) var pattern: PatternShape?
    /// The hand position each note of this screen is played in (finger numbers).
    public private(set) var positions: [HandPosition] = []
    /// The clef this part of the session is on, in one-clef lessons (nil on the grand
    /// staff). A session is two runs: the first clef for half of it (2/3 for a lesson's
    /// focus clef), then the other clef for the rest, extras included. One switch.
    public private(set) var runClef: Clef?
    /// Waiting for the last note's key-up (its hold counts).
    public var isAwaitingRelease: Bool { awaitingRelease }
    /// Notes of bar 2 he plays from memory: a twin, an answer or a new rhythm repeats bar
    /// 1's note at the same spot. A moved bar is read (by its shape), a frame's are new.
    public var recalledNotes: Set<Int> {
        guard let item, pattern?.repeatsNotes == true else { return [] }
        return Set(item.repeatedColumns)
    }
    /// Demos and screenshots: the session opens on a drill screen of this shape (no
    /// warm-up). Set before `start`.
    public var openWithDrill: Drill?
    /// Demos and screenshots: the session opens on a pattern screen of this shape (no
    /// warm-up). Set before `start`.
    public var openWithPattern: PatternShape?

    /// True while the current screen is an intro (a new note, or a new lesson texture).
    public var isIntro: Bool { introNote != nil || isLessonIntro }

    private var config: NoteCoreConfig { engine.config }
    private var rng: SeededRandom
    /// The day this session is on (habit wants two different days). nil: its own day.
    private let day: Int?
    private var judge: AttemptJudge?

    // clock: active time = app time - start - paused total
    private var startTime = 0.0
    private var pausedTotal = 0.0
    private var pausedAt: Double?
    private var resumePhase: SessionPhase?

    // session shape
    private var warmUpLeft = 0
    private var easingLeft = 0
    /// Last few notes: true when it wasn't right first try.
    private var struggles: [Bool] = []
    private var limitReached: SessionSummary.EndReason?
    /// The two runs, set up at the first one-clef screen.
    private var runs: (first: Clef, screens: Int, seconds: Double)?
    /// The session's one burst of drill screens: when it starts (screens played) and how
    /// many. Planned at the first screen, cleared once it starts.
    private var burst: (at: Int, length: Int)?
    private var burstPlanned = false
    private var burstLeft = 0
    /// The last screen shown, and whether it comes once more.
    private var lastPick: Pick?
    private var againNext = false
    private var agains = 0

    // the current screen, per column
    private var pickSize = 1
    private var lastActivity = 0.0
    private var startTimes: [Double] = []
    private var correctTimes: [Double] = []
    private var wrongs: [Int] = []
    private var stucks: [Int] = []
    private var almosts: [Int] = []
    private var hints: [HintLevel] = []
    /// Notes he hadn't played yet when he tapped play: he heard and saw them first.
    private var listened: [Bool] = []
    /// Steps up the hint ladder per note (wrong keys, stuck steps, slips). Kept across goes.
    private var rungs: [Int] = []
    /// Notes he has played right (in any go). Their result doesn't change after that.
    private var playedRight: [Bool] = []
    /// A slip took the note to the ladder's second rung: its pitch plays when he gets back to it.
    private var soundOnReach: [Bool] = []
    /// A slip on the wrong octave or the natural next to a sharp: the keyboard picture
    /// lights the key when he gets back to it (as it does straight away note by note).
    private var pictureOnReach: [Bool] = []
    /// Keys down now and when they went down (active time), for the pause after a slip.
    private var held: [Pitch: Double] = [:]
    private var lastKeyDown = 0.0
    /// Steps up the hint ladder on the current note.
    private var ladder: Int { rungs.indices.contains(noteIndex) ? rungs[noteIndex] : 0 }
    private var onsets: [Double] = []
    private var rhythmJudgeable = true
    private var awaitingRelease = false
    /// The first go at a screen that gets a rhythm retry: what's recorded (pitch from
    /// the first go counts as it was, and so does its rhythm).
    private var firstGo: (notes: [AttemptResult], rhythm: RhythmResult?)?
    private var isRhythmDemo = false

    /// `day`: the app's day number (days since some fixed date, in his time zone), so
    /// habit can tell two days apart. nil counts every session as a day of its own
    /// (tests, demos).
    public init(engine: MasteryEngine, seed: UInt64, pianoConnected: Bool = true, day: Int? = nil) {
        self.engine = engine
        self.day = day
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
        guard phase.isPlaying, item != nil else { return nil }
        var deadlines: [Double] = []
        if slippedNote != nil {
            deadlines.append(restartTime)
        } else if awaitingRelease, let line = rhythmLine {
            deadlines.append(RhythmJudge(config: config).settleTime(line, onsets: onsets))
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
        engine.beginSession(day: day)
        warmUpLeft = openWithDrill == nil && openWithPattern == nil && engine.lesson.clefs.contains { !engine.strongestNotes($0).isEmpty } ? config.warmUpScreens : 0
        guard isPianoConnected else {
            pausedAt = time
            resumePhase = nil
            phase = .paused
            return [.paused]
        }
        return showNext(at: 0)
    }

    public mutating func handle(_ event: NoteEvent) -> [Cue] {
        let t = activeTime(at: event.time)
        // the pause after a slip had already come (a late tick) before this key went down
        let pauseWasOver = slippedNote != nil && t >= restartTime
        switch event.kind {
        case .on: held[event.pitch] = t
        case .off: held[event.pitch] = nil
        }
        guard phase.isPlaying, let item else { return [] }
        var cues: [Cue] = []
        switch event.kind {
        case .off:
            if slippedNote != nil {
                // he let go: the screen starts over if he has paused long enough
                if t >= restartTime { cues += startOver(at: t) }
            } else if awaitingRelease, item.notes[item.notes.count - 1].pitches.contains(event.pitch) {
                cues += finishRhythm(release: t)
            }
        case .on:
            if slippedNote != nil {
                guard pauseWasOver else {
                    // after a slip keys don't count (no wobble), they only put the pause off
                    lastKeyDown = t
                    lastActivity = t
                    return []
                }
                // start over, then this key is his first note
                cues += startOver(at: t)
            }
            guard !awaitingRelease, var judge else { return cues }
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
        guard phase.isPlaying, item != nil else { return [] }
        let t = activeTime(at: time)
        if slippedNote != nil {
            // he slipped and has paused: back to the first note. no stuck steps meanwhile
            return t >= restartTime ? startOver(at: t) : []
        }
        if awaitingRelease, let line = rhythmLine {
            if t >= RhythmJudge(config: config).settleTime(line, onsets: onsets) {
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
            // stuck: one step up the ladder, same as a wrong try but not a wrong press. never
            // a start over
            if !playedRight[noteIndex] { stucks[noteIndex] += 1 }
            lastActivity = t
            cues += climbLadder()
        }
        return cues
    }

    /// The level-up splash is showing (`engine.pendingLevelUp`): it's had its celebration.
    public mutating func celebrateLevelUp() {
        engine.celebrateLevelUp()
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

    /// He tapped the play button: the whole screen is played to him at a gentle tempo,
    /// each key lighting up on the keyboard as it sounds. It's help, so the notes he
    /// hasn't played yet on this screen count as hinted (not first try, the box holds,
    /// "kept trying" can follow) - no other penalty. Tapped mid-screen, the rest of the
    /// line isn't rhythm-judged (he stopped to listen). The stuck clock and the current
    /// note's time start again once it's over.
    public mutating func listen(at time: Double) -> [Cue] {
        guard phase.isPlaying, let item, !awaitingRelease else { return [] }
        let t = activeTime(at: time)
        var cues: [Cue] = []
        if slippedNote != nil {
            // after a slip: he hears all of it, then plays it from its first note
            cues += startOver(at: t)
        }
        for i in noteIndex..<item.notes.count where !playedRight[i] {
            listened[i] = true
            hints[i] = .keyboard
        }
        if !onsets.isEmpty { rhythmJudgeable = false }
        let beat = config.demoBeat
        let over = t + item.totalBeats * beat
        if !playedRight[noteIndex] { startTimes[noteIndex] = over }
        lastActivity = over
        return cues + [.showAndPlay(beat: beat)]
    }

    /// The play back after a wrong value is over: he plays the screen again from its
    /// first note. A rhythm retry only: pitch from the first go counts as it was.
    public mutating func replayFinished(at time: Double) -> [Cue] {
        if phase == .paused, resumePhase == .replaying {
            // the piano went while it played. start the retry when it's back
            resumePhase = .prompt
            restartRun(at: activeTime(at: time))
            return []
        }
        guard phase == .replaying else { return [] }
        restartRun(at: activeTime(at: time))
        phase = .prompt
        return [.again]
    }

    /// No MIDI source. Shows the paused screen; nothing counts until it's back.
    public mutating func pianoDisconnected(at time: Double) -> [Cue] {
        isPianoConnected = false
        guard phase.isPlaying || phase == .success || phase == .replaying else { return [] }
        pausedAt = time
        resumePhase = phase
        phase = .paused
        judge?.reset()
        held = [:] // their key-ups won't come
        rhythmJudgeable = false // the timing of this line isn't his any more
        return [.paused]
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
        var reason = forced ?? .normal
        var style = PickStyle.strongest
        let clef = run(at: t)
        planBurst()
        if forced == nil {
            if warmUpLeft > 0 {
                warmUpLeft -= 1
                reason = .warmUp
                style = .warmUp
            } else if easingLeft > 0 {
                easingLeft -= 1
                reason = .easing
                burstLeft = 0 // easy screens instead, and the burst doesn't come back
            } else if againNext, let last = lastPick, clef == nil || last.item.clefs.first == clef {
                // a second read stays in its run: none across the switch to the other clef
                reason = .again
            } else if burstLeft > 0 || startsBurst(on: clef) {
                burstLeft -= 1
                reason = .drill
                style = .drill
            } else {
                style = .normal
            }
        }
        againNext = false
        var pick: Pick
        if reason == .again, let last = lastPick {
            agains += 1
            pick = engine.again(last)
        } else if let drill = openWithDrill, let opener = engine.pickDrill(drill, on: clef, using: &rng) {
            openWithDrill = nil
            reason = .drill
            pick = opener
        } else if let shape = openWithPattern, let opener = engine.pickPattern(shape, on: clef, using: &rng) {
            openWithPattern = nil
            reason = .normal
            pick = opener
        } else {
            pick = engine.pickScreen(style, clef: clef, using: &rng)
        }
        switch reason {
        case .again: break
        case .drill: if pick.drill == nil { reason = pick.isStretch ? .stretch : .normal }
        default: if !pick.usedStrongest { reason = pick.isStretch ? .stretch : .normal }
        }
        lastPick = pick
        drill = pick.drill
        pattern = pick.pattern
        positions = pick.positions
        let next = pick.item
        item = next
        pickReason = reason
        let lesson = engine.lesson
        rhythmLine = pick.intro == nil ? next.rhythmLine(lesson.texture.isRhythm ? .all : lesson.rhythmCheck) : nil
        if rhythmLine != nil, lesson.rhythmCheck == .halves, !lesson.texture.isRhythm, !next.hasSameRhythmBars,
           engine.wantsRhythmDemo || unitInterval(&rng) >= config.halvesMixedShare {
            // level 3's halves check prefers two bars in one rhythm: bar 1 sets his beat
            rhythmLine = nil
        }
        retries = 0
        restarts = 0
        slippedNote = nil
        firstGo = nil
        isRhythmDemo = false
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
        listened = Array(repeating: false, count: columns)
        rungs = Array(repeating: 0, count: columns)
        playedRight = Array(repeating: false, count: columns)
        soundOnReach = Array(repeating: false, count: columns)
        pictureOnReach = Array(repeating: false, count: columns)
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
        // nothing is said at the start of a screen: the sound and the picture do it
        if let intro = pick.intro {
            // i do: the app plays it and lights the key (with its letter). then we do:
            // he plays it with the picture up
            cues.append(.playPitches([intro.pitch]))
        } else if pick.isLessonIntro {
            // a new texture: play it to him first (sound before symbol)
            if engine.lesson.texture.isRhythm {
                cues.append(.playPhrase(beat: config.demoBeat))
            } else {
                cues.append(.playPitches(next.notes[0].pitches))
            }
        } else if rhythmLine != nil, engine.wantsRhythmDemo {
            // the first rhythm screens of level 3 (and 4): hear it first, then read it
            isRhythmDemo = true
            cues.append(.playPhrase(beat: config.demoBeat))
        }
        return cues
    }

    /// The clef for the next screen. The first run lasts half the session's screens or
    /// half its time, whichever comes first (2/3 when its clef is the lesson's focus),
    /// then the session switches once and stays. The first clef alternates from session
    /// to session (saved with his state); a focus lesson always starts on its focus clef.
    private mutating func run(at t: Double) -> Clef? {
        let lesson = engine.lesson
        guard lesson.layout == .alternating, lesson.clefs.count == 2 else {
            runClef = nil
            return nil
        }
        if runs == nil {
            let first = engine.firstRunClef
            engine.startedRun(on: first)
            let share = lesson.focus == .both ? 0.5 : 2.0 / 3
            runs = (first, Int((Double(config.sessionMaxItems) * share).rounded()), config.sessionMaxDuration * share)
        }
        let runs = runs!
        let second: Clef = runs.first == .treble ? .bass : .treble
        let switched = runClef == second || summary.screensPlayed >= runs.screens || t >= runs.seconds
        runClef = switched ? second : runs.first
        return runClef
    }

    /// Plans the session's burst at its first screen: 3 or 4 drill screens inside one of
    /// the two clef runs (the first or the second at random), clear of the warm-up and
    /// the last screens. None in a drill lesson (it's all drills) or a short session.
    private mutating func planBurst() {
        guard !burstPlanned else { return }
        burstPlanned = true
        let lesson = engine.lesson
        let total = config.sessionMaxItems
        guard !lesson.isDrillLesson, !lesson.drills.isEmpty, total >= config.burstMinSession else { return }
        let lengths = config.burstScreens
        let length = lengths.lowerBound + min(lengths.count - 1, Int(unitInterval(&rng) * Double(lengths.count)))
        let half = runs?.screens ?? total / 2
        // early in the second run: a session that ends on time (rhythm screens take
        // longer) can stop before its last screens
        let first = 2...max(2, half - length), second = (half + 1)...max(half + 1, min(half + 4, total - length - 1))
        let range = unitInterval(&rng) < 0.5 ? first : second
        let at = range.lowerBound + min(range.count - 1, Int(unitInterval(&rng) * Double(range.count)))
        burst = (at, length)
    }

    /// Whether the burst starts with this screen: its time has come, nothing is waiting
    /// for its intro on this clef and no new note's blocked screens are running. It waits
    /// a screen or two for those, and is dropped when there's no room left before the end.
    private mutating func startsBurst(on clef: Clef?) -> Bool {
        guard let burst, summary.screensPlayed >= burst.at, limitReached == nil else { return false }
        guard summary.screensPlayed + burst.length <= config.sessionMaxItems else {
            self.burst = nil
            return false
        }
        if let runs, summary.screensPlayed < runs.screens, summary.screensPlayed + burst.length > runs.screens {
            // waited too long to fit in the first run: early in the second one instead
            self.burst = (runs.screens + 1, burst.length)
            return false
        }
        let clefs = clef.map { [$0] } ?? engine.lesson.clefs
        guard clefs.allSatisfy({ engine.pendingIntros($0).isEmpty && engine.blockedNote($0) == nil }) else { return false }
        burstLeft = burst.length
        self.burst = nil
        return true
    }

    /// Back to the screen's first note for another go (a rhythm retry).
    private mutating func restartRun(at t: Double) {
        guard let item else { return }
        noteIndex = 0
        onsets = []
        rungs = rungs.map { _ in 0 }
        soundOnReach = soundOnReach.map { _ in false }
        pictureOnReach = pictureOnReach.map { _ in false }
        rhythmJudgeable = true
        awaitingRelease = false
        keyboardHint = []
        lastActivity = t
        judge?.expect(item.notes[0].pitches)
    }

    /// When the screen starts over after a slip, in active time: `restartPause` after his
    /// last key down, once nothing is held (a key holds it back for at most
    /// `restartHoldLimit` after it went down, so it always comes).
    private var restartTime: Double {
        let pause = lastKeyDown + config.restartPause
        guard let latest = held.values.max() else { return pause }
        return max(pause, latest + config.restartHoldLimit)
    }

    /// A slip here starts the screen over: past its first note and a start over left (no
    /// cap by default). Lesson intros and rhythm retries too.
    private var canStartOver: Bool {
        noteIndex > 0 && restarts < config.sequenceRestarts
    }

    /// A slip past the first note: that note wobbles softly and nothing else happens yet.
    /// It's a miss (an almost isn't), and a rung of that note's ladder, shown when he gets
    /// back to it. The screen starts over once he pauses.
    private mutating func slip(at t: Double, almost: Bool = false, sharpNatural: Bool = false) -> [Cue] {
        let i = noteIndex
        if !playedRight[i] {
            if almost { almosts[i] += 1 } else { wrongs[i] += 1 }
        }
        if !almost {
            rungs[i] += 1
            if !playedRight[i] { hints[i] = max(hints[i], Self.hint(rung: rungs[i])) }
            if rungs[i] == 2 { soundOnReach[i] = true }
            phase = Self.phase(rung: rungs[i])
        }
        if almost || sharpNatural { pictureOnReach[i] = true }
        slippedNote = i
        lastKeyDown = t
        lastActivity = t
        rhythmJudgeable = false
        return [.wobble(note: i)]
    }

    /// He slipped and paused: back to the first note for another go. Silent: the app fades
    /// the played notes back and lights the first one softly.
    private mutating func startOver(at t: Double) -> [Cue] {
        guard let slipped = slippedNote else { return [] }
        slippedNote = nil
        restarts += 1
        noteIndex = 0
        onsets = []
        rhythmJudgeable = true
        awaitingRelease = false
        lastActivity = t
        judge?.reset()
        return [.startOver(played: slipped)] + reach(at: t)
    }

    /// He's on `noteIndex` now: a note he hasn't played right yet starts its clock, and a
    /// note the ladder climbed on in an earlier go shows its help again (its pitch once,
    /// the keyboard picture every time).
    private mutating func reach(at t: Double) -> [Cue] {
        guard let item else { return [] }
        let i = noteIndex
        let pitches = item.notes[i].pitches
        if !playedRight[i] { startTimes[i] = t }
        phase = Self.phase(rung: rungs[i])
        judge?.expect(pitches)
        keyboardHint = isIntro || rungs[i] >= 3 || pictureOnReach[i] ? pitches : []
        guard soundOnReach[i] else { return [] }
        soundOnReach[i] = false
        return [.playPitches(pitches)]
    }

    private static func phase(rung: Int) -> SessionPhase {
        switch rung {
        case 0: .prompt
        case 1: .waiting
        case 2: .hint1
        default: .hint2
        }
    }

    private static func hint(rung: Int) -> HintLevel {
        switch rung {
        case 0: .none
        case 1: .wobble
        case 2: .playedPitch
        default: .keyboard
        }
    }

    private mutating func apply(_ verdict: PitchVerdict, at t: Double) -> [Cue] {
        guard let item else { return [] }
        let expected = item.notes[noteIndex].pitches
        switch verdict {
        case .correct:
            var cues: [Cue] = [.correct(note: noteIndex)]
            onsets.append(t)
            lastActivity = t
            if !playedRight[noteIndex] {
                playedRight[noteIndex] = true
                correctTimes[noteIndex] = t
            }
            if noteIndex < item.notes.count - 1 {
                noteIndex += 1
                cues += reach(at: t)
                return cues
            }
            if let line = rhythmLine, rhythmJudgeable {
                if line.judged[line.judged.count - 1] {
                    awaitingRelease = true // the last note's hold counts
                    return cues
                }
                return cues + finishRhythm(release: t)
            }
            return cues + finish(at: t, rhythm: nil)

        case .almost:
            if canStartOver { return slip(at: t, almost: true) }
            // right letter, wrong octave: the keyboard picture shows where. no words
            if !playedRight[noteIndex] { almosts[noteIndex] += 1 }
            keyboardHint = expected
            return []

        case .wrong(let played):
            // the natural next to a sharp (F on an F# note)
            let sharpNatural = expected.count == 1 && played.count == 1 && !expected[0].isWhiteKey
                && played[0].midi == expected[0].midi - 1
            if canStartOver { return slip(at: t, sharpNatural: sharpNatural) }
            if !playedRight[noteIndex] { wrongs[noteIndex] += 1 }
            // the natural next to a sharp: show the black key straight away
            if sharpNatural {
                let cues = climbLadder()
                keyboardHint = expected
                return cues
            }
            return climbLadder()
        }
    }

    /// One step up the hint ladder for the current note: wobble, then the sound, then
    /// the keyboard picture. Past the top, a wrong key replays the sound. No words.
    private mutating func climbLadder() -> [Cue] {
        guard let item else { return [] }
        let expected = item.notes[noteIndex].pitches
        rungs[noteIndex] += 1
        let rung = rungs[noteIndex]
        rhythmJudgeable = false
        var cues: [Cue] = [.wobble(note: noteIndex)]
        phase = Self.phase(rung: rung)
        if !playedRight[noteIndex] { hints[noteIndex] = max(hints[noteIndex], Self.hint(rung: rung)) }
        switch rung {
        case 1:
            break
        case 2:
            cues.append(.playPitches(expected))
        default:
            if keyboardHint == expected {
                cues.append(.playPitches(expected)) // picture already up: the sound again
            }
            keyboardHint = expected
        }
        return cues
    }

    /// Level 2: his rhythm on a screen whose bars share one, measured silently when this
    /// go was clean (no slip, hint or play button in it). Nothing is said or shown.
    private var silentMeasure: RhythmMeasure? {
        guard let item, engine.lesson.level == 2, engine.lesson.rhythmCheck == .off, rhythmLine == nil, rhythmJudgeable,
              !isIntro, pickReason != .again, onsets.count == item.notes.count else { return nil }
        return RhythmJudge(config: config).measure(item, onsets: onsets)
    }

    private mutating func finishRhythm(release: Double) -> [Cue] {
        guard let item, let line = rhythmLine, onsets.count == item.notes.count else {
            return finish(at: release, rhythm: nil)
        }
        let result = RhythmJudge(config: config).judge(line, onsets: onsets, release: release)
        return finish(at: release, rhythm: result)
    }

    private mutating func finish(at t: Double, rhythm: RhythmResult?) -> [Cue] {
        guard let item else { return [] }
        awaitingRelease = false
        let lesson = engine.lesson
        if firstGo == nil {
            // a rhythm line's gaps are the rhythm, not reading: every note gets the reading time
            let readingTime = correctTimes[0] - startTimes[0]
            let recalled = recalledNotes
            var notes: [AttemptResult] = []
            for (i, column) in item.notes.enumerated() {
                let time = lesson.texture.isRhythm ? readingTime : correctTimes[i] - startTimes[i]
                // habit's in-line time: reading from one note to the next, nothing else in it
                // (bar 2 of a twin or an answer is played from memory)
                let inLine = i > 0 && !isIntro && !lesson.texture.isRhythm && rhythmLine == nil && pickReason != .again
                    && column.pitches != item.notes[i - 1].pitches && !recalled.contains(i)
                for key in column.keys {
                    notes.append(AttemptResult(
                        itemID: key.id, lesson: lesson.id, level: lesson.level, wasIntro: introNote == key || isLessonIntro,
                        firstTry: wrongs[i] == 0 && stucks[i] == 0 && !listened[i], wrongPresses: wrongs[i], almostPresses: almosts[i],
                        stuckSteps: stucks[i], hints: hints[i], responseTime: max(0, time), inLine: inLine,
                        fromMemory: recalled.contains(i)
                    ))
                }
            }
            firstGo = (notes, rhythm)
        }
        // a note played as a different value: hear the screen, then another go. Not on
        // an intro, and at most `rhythmRetries` times, so there's no loop he can't leave
        if let rhythm, let wrong = rhythm.nudgeIndex, !isIntro, retries < config.rhythmRetries {
            retries += 1
            phase = .replaying
            keyboardHint = []
            let beat = rhythm.beat > 0 ? min(1.5, max(0.35, rhythm.beat)) : config.demoBeat
            return [.rhythmGlow(note: wrong), .showAndPlay(beat: beat)]
        }
        let go = firstGo!
        let screen = ScreenResult(
            screenID: item.id, lesson: lesson.id, reason: pickReason, wasIntro: introNote != nil,
            wasLessonIntro: isLessonIntro, notes: go.notes, rhythm: go.rhythm, size: pickSize,
            rhythmRetries: retries, wasRhythmDemo: isRhythmDemo, restarts: restarts, pattern: pattern,
            secondBar: item.bars.count == 2 ? item.notes[item.barRanges[0]].reduce(0) { $0 + $1.keys.count } : nil,
            rhythmMeasure: silentMeasure
        )
        let before = Dictionary(item.keys.map { ($0.id, engine.stats(for: $0).peakFluency) }, uniquingKeysWith: { a, _ in a })
        let update = engine.record(screen)
        noteSummary(screen, update: update, fluencyBefore: before)
        noteStruggles(screen)

        phase = .success
        keyboardHint = []
        var cues: [Cue] = []
        if let rhythm, let wrong = rhythm.nudgeIndex {
            // still a different value after the last go: that note glows, and on we go, kindly
            cues.append(.rhythmGlow(note: wrong))
        }
        // now and then a clean screen comes once more: a second read (not inside a burst,
        // so the burst stays in its run, and not a pattern screen: a twin twice is four
        // bars of the same)
        if screen.firstTry, retries == 0, !isIntro, burstLeft == 0, pattern == nil, [.normal, .stretch, .drill].contains(pickReason), update.unlocked.isEmpty,
           agains < config.againMax, unitInterval(&rng) < config.againChance {
            againNext = true
        }
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
                struggles = []
            }
        }
    }

    private mutating func noteSummary(_ screen: ScreenResult, update: MasteryUpdate, fluencyBefore: [ItemID: Double]) {
        summary.screensPlayed += 1
        summary.screens.append(screen)
        // a second read is kept as a screen (its time against the first read's), not as notes
        guard screen.reason != .again else { return }
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
