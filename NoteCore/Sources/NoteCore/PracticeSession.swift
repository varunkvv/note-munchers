public enum SessionPhase: String, Codable, Hashable, Sendable {
    case notStarted
    /// An item is up and he hasn't pressed a wrong key on the current note yet.
    case prompt
    /// One wrong key on the current note: it wobbled, still waiting.
    case waiting
    /// Two wrong keys: the app played the right pitch.
    case hint1
    /// Three or more: the keyboard picture lights up the key (picture only, not tappable).
    case hint2
    /// Item done. Celebrate, then call `next(at:)` when the animation ends.
    case success
    /// Piano disconnected: the "turn on the piano" screen. Picks up where it was.
    case paused
    /// Session over: the summary screen.
    case done

    /// Phases where key presses are judged.
    public var isPlaying: Bool { [.prompt, .waiting, .hint1, .hint2].contains(self) }
}

/// What the voice should say. The app turns these into words (or a recorded parent
/// voice later). The kid never sees text.
public enum Speech: Hashable, Codable, Sendable {
    /// First time he sees this item: "here's a new one!"
    case newNote
    /// After a right single note: "D!"
    case letter(Letter)
    /// After a right group or chord: "C, E, G!"
    case letters([Letter])
    /// Right letter, wrong octave in a lenient unit: "that's a C! this one is the middle C".
    /// Doesn't count against him.
    case almost(played: Pitch, expected: Pitch)
    /// Occasional praise. The app picks a varied phrase. Not every time.
    case praise
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
    /// A new item is up. Draw `item` on `staffLayout`, starting at note 0.
    case showItem
    /// Wrong key: that note wobbles a little.
    case wobble(note: Int)
    /// Hint: play these pitches out loud.
    case playPitches([Pitch])
    /// Right key(s) for that note: it hops off the staff and gets gobbled (chomp).
    case correct(note: Int)
    case say(Speech)
    /// Rhythm nudge: that note glows for its full written length.
    case rhythmGlow(note: Int)
    /// Play the whole item at `beat` seconds per quarter (a new rhythm item, before he plays it).
    case playPhrase(beat: Double)
    /// New items unlocked: an egg hatches for each.
    case unlocked([ItemID])
    /// Show the "turn on the piano" screen.
    case paused
    /// Piano is back. Hide the paused screen and redraw the current state.
    case resumed
    /// Show the session end screen from `summary`.
    case done
}

/// One item's share of a session, for the end screen.
public struct PracticedItem: Hashable, Codable, Sendable {
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

    public var startUnit: Int
    public var endUnit: Int
    public var itemsPlayed = 0
    public var firstTryCount = 0
    /// Seconds, not counting time paused.
    public var activeDuration = 0.0
    public var attempts: [AttemptResult] = []
    /// Items unlocked this session (eggs hatched).
    public var unlocked: [ItemID] = []
    public var completedUnits: [Int] = []
    /// Every item played this session, in the order first played.
    public var practiced: [PracticedItem] = []
    public var endedBy: EndReason?

    public init(startUnit: Int) {
        self.startUnit = startUnit
        endUnit = startUnit
    }
}

/// One practice session: prompt -> waiting -> hint1 -> hint2 -> success -> next ... -> done.
///
/// Feed it note events and the app clock. Every call returns the cues to play; what
/// to draw is in the state. All times are seconds on the app's one monotonic clock.
/// After every call, if `nextDeadline` is set, call `tick(at:)` at that time
/// (it closes chord windows and stops waiting for the last key-up of a rhythm line).
public struct PracticeSession: Sendable {
    public private(set) var engine: MasteryEngine
    public private(set) var phase: SessionPhase = .notStarted
    public private(set) var summary: SessionSummary
    public private(set) var isPianoConnected: Bool

    /// The item on screen.
    public private(set) var item: PracticeItem?
    /// Which note of `item` he's on (groups and rhythm lines go left to right).
    public private(set) var noteIndex = 0
    /// Keys lit in the keyboard picture. Empty means the picture is hidden.
    public private(set) var keyboardHint: [Pitch] = []
    /// True while the current item is having its intro.
    public private(set) var isIntro = false

    private var config: NoteCoreConfig { engine.config }
    private var rng: SeededRandom
    private var judge: AttemptJudge?

    // clock: active time = app time - start - paused total
    private var startTime = 0.0
    private var pausedTotal = 0.0
    private var pausedAt: Double?
    private var resumePhase: SessionPhase?

    // the current item
    private var promptTime = 0.0
    private var firstCorrectTime: Double?
    private var wrongsOnNote = 0
    private var totalWrongs = 0
    private var almosts = 0
    private var hints = HintLevel.none
    private var onsets: [Double] = []
    private var rhythmJudgeable = true
    private var awaitingRelease = false

    public init(engine: MasteryEngine, seed: UInt64, pianoConnected: Bool = true) {
        self.engine = engine
        rng = SeededRandom(seed: seed)
        isPianoConnected = pianoConnected
        summary = SessionSummary(startUnit: engine.unit.number)
    }

    /// Staves to show for the current unit.
    public var staffLayout: StaffLayout { engine.unit.staff }

    /// Seconds into the session, not counting pauses.
    public func activeTime(at time: Double) -> Double {
        let pausedNow = pausedAt.map { time - $0 } ?? 0
        return max(0, time - startTime - pausedTotal - pausedNow)
    }

    /// When the app should call `tick(at:)` next, on the app clock. nil when nothing is pending.
    public var nextDeadline: Double? {
        guard phase.isPlaying, let item else { return nil }
        var deadlines: [Double] = []
        if let window = judge?.windowDeadline {
            deadlines.append(window)
        }
        if awaitingRelease, let values = item.values {
            deadlines.append(RhythmJudge(config: config).settleTime(values, onsets: onsets))
        }
        return deadlines.min().map { $0 + startTime + pausedTotal }
    }

    // MARK: calls from the app

    public mutating func start(at time: Double) -> [Cue] {
        guard phase == .notStarted else { return [] }
        startTime = time
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
            if awaitingRelease, event.pitch == item.notes[item.notes.count - 1].pitches[0] {
                cues += finishRhythm(release: t)
            }
        case .on:
            guard !awaitingRelease, var judge else { return [] }
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
        guard var judge, let verdict = judge.closeWindow(at: t) else { return [] }
        self.judge = judge
        return apply(verdict, at: t)
    }

    /// After the success animation: the next item, or the end of the session.
    public mutating func next(at time: Double) -> [Cue] {
        guard phase == .success else { return [] }
        let t = activeTime(at: time)
        summary.activeDuration = t
        if summary.itemsPlayed >= config.sessionMaxItems {
            return end(.itemLimit)
        }
        if t >= config.sessionMaxDuration {
            return end(.timeLimit)
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

    private mutating func showNext(at t: Double) -> [Cue] {
        let next = engine.pickNext(using: &rng)
        item = next
        isIntro = engine.needsIntro(next)
        noteIndex = 0
        promptTime = t
        firstCorrectTime = nil
        wrongsOnNote = 0
        totalWrongs = 0
        almosts = 0
        hints = .none
        onsets = []
        rhythmJudgeable = true
        awaitingRelease = false
        if judge == nil {
            judge = AttemptJudge(expected: next.notes[0].pitches, octavePolicy: engine.unit.octavePolicy, config: config)
        } else {
            judge!.expect(next.notes[0].pitches)
            judge!.octavePolicy = engine.unit.octavePolicy
        }
        keyboardHint = isIntro ? next.notes[0].pitches : []
        phase = .prompt
        var cues: [Cue] = [.showItem]
        if isIntro {
            cues.append(.say(.newNote))
            if next.isRhythm {
                cues.append(.playPhrase(beat: config.demoBeat))
            }
        }
        return cues
    }

    private mutating func apply(_ verdict: PitchVerdict, at t: Double) -> [Cue] {
        guard let item else { return [] }
        let expected = item.notes[noteIndex].pitches
        switch verdict {
        case .correct:
            var cues: [Cue] = [.correct(note: noteIndex)]
            onsets.append(t)
            if firstCorrectTime == nil {
                firstCorrectTime = t
            }
            if noteIndex < item.notes.count - 1 {
                noteIndex += 1
                wrongsOnNote = 0
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
            cues += finish(at: t, rhythm: nil)
            return cues

        case .almost(let played):
            almosts += 1
            keyboardHint = expected
            return [.say(.almost(played: played[0], expected: expected[0]))]

        case .wrong:
            wrongsOnNote += 1
            totalWrongs += 1
            rhythmJudgeable = false
            var cues: [Cue] = [.wobble(note: noteIndex)]
            switch wrongsOnNote {
            case 1:
                phase = .waiting
                hints = max(hints, .wobble)
            case 2:
                phase = .hint1
                hints = max(hints, .playedPitch)
                cues.append(.playPitches(expected))
            default:
                phase = .hint2
                hints = .keyboard
                if keyboardHint == expected {
                    cues.append(.playPitches(expected)) // picture already up: say it with sound again
                }
                keyboardHint = expected
            }
            return cues
        }
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
        let lastCorrect = onsets.last ?? t
        let responseTime: Double
        switch item.kind {
        case .note, .chord:
            responseTime = lastCorrect - promptTime
        case .group:
            responseTime = (lastCorrect - promptTime) / Double(item.notes.count)
        case .rhythm:
            responseTime = (firstCorrectTime ?? lastCorrect) - promptTime
        }
        let attempt = AttemptResult(
            itemID: item.id, unit: engine.unit.number, wasIntro: isIntro, firstTry: totalWrongs == 0,
            wrongPresses: totalWrongs, almostPresses: almosts, hints: hints,
            responseTime: max(0, responseTime), rhythm: rhythm
        )
        let fluencyBefore = engine.stats(for: item.id).peakFluency
        let update = engine.record(attempt)
        noteSummary(attempt, update: update, fluencyBefore: fluencyBefore)

        phase = .success
        keyboardHint = []
        var cues: [Cue] = []
        switch item.kind {
        case .note:
            cues.append(.say(.letter(item.notes[0].pitches[0].naturalLetter)))
        case .chord:
            cues.append(.say(.letters(item.notes[0].pitches.map(\.naturalLetter))))
        case .group:
            cues.append(.say(.letters(item.notes.map { $0.pitches[0].naturalLetter })))
        case .rhythm:
            break
        }
        if let rhythm, let nudge = rhythm.nudgeIndex {
            cues.append(.rhythmGlow(note: nudge))
            if rhythm.verdicts[nudge] == .tooShort {
                cues.append(.say(.holdLonger))
            }
        } else if unitInterval(&rng) < config.praiseChance {
            cues.append(.say(.praise))
        }
        if !update.unlocked.isEmpty {
            cues.append(.unlocked(update.unlocked))
        }
        return cues
    }

    private mutating func noteSummary(_ attempt: AttemptResult, update: MasteryUpdate, fluencyBefore: Double) {
        summary.itemsPlayed += 1
        summary.firstTryCount += attempt.firstTry ? 1 : 0
        summary.attempts.append(attempt)
        summary.unlocked += update.unlocked
        if let unit = update.completedUnit {
            summary.completedUnits.append(unit)
        }
        summary.endUnit = engine.unit.number
        let after = engine.stats(for: attempt.itemID).peakFluency
        if let i = summary.practiced.firstIndex(where: { $0.id == attempt.itemID }) {
            summary.practiced[i].plays += 1
            summary.practiced[i].firstTries += attempt.firstTry ? 1 : 0
            summary.practiced[i].fluencyAfter = after
        } else {
            summary.practiced.append(PracticedItem(
                id: attempt.itemID, plays: 1, firstTries: attempt.firstTry ? 1 : 0,
                fluencyBefore: fluencyBefore, fluencyAfter: after
            ))
        }
    }

    private mutating func end(_ reason: SessionSummary.EndReason) -> [Cue] {
        phase = .done
        item = nil
        summary.endedBy = reason
        return [.done, .say(.sessionDone)]
    }
}
