public enum SessionPhase: String, Codable, Hashable, Sendable {
    case notStarted
    /// An item is up and he's on the first rung of the hint ladder for the current note.
    case prompt
    /// One step up the ladder (a wrong key, or stuck): it wobbled, still waiting.
    case waiting
    /// Two steps: the app played the right pitch.
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
///
/// Praise is process praise only - it names what he did (mueller & dweck). Never
/// "smart", "genius", "good boy".
public enum Speech: Hashable, Codable, Sendable {
    /// Intro of a new rhythm item, before the app plays it to him: "here's a new one! listen"
    case newNote
    /// Intro of a new single note, with its pitch played and the key lit: "this is D"
    case meetNote(Letter)
    /// Intro of a new chord or group: "these are C, E and G"
    case meetNotes([Letter])
    /// After a right single note: "D!"
    case letter(Letter)
    /// After a right group or chord: "C, E, G!"
    case letters([Letter])
    /// Right letter, wrong octave in a lenient unit: "that's a C! this one is the middle C".
    /// Doesn't count against him.
    case almost(played: Pitch, expected: Pitch)
    /// Now and then after a first-try success: "you looked carefully!"
    case lookedCarefully
    /// Every success that needed a hint: "you kept trying and found it!"
    case keptTrying
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
    /// One step up the hint ladder (wrong key, or stuck): that note wobbles a little.
    case wobble(note: Int)
    /// Play these pitches out loud. A hint, or the demo of a new note or chord.
    case playPitches([Pitch])
    /// Right key(s) for that note: it hops off the staff and gets gobbled (chomp).
    case correct(note: Int)
    case say(Speech)
    /// Rhythm nudge: that note glows for its full written length.
    case rhythmGlow(note: Int)
    /// Play the whole item at `beat` seconds per quarter: the demo of a new group or
    /// rhythm item, before he plays it.
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

/// Why the current item was picked.
public enum PickReason: String, Codable, Hashable, Sendable {
    case normal
    /// Session opener: one of his strongest items.
    case warmUp
    /// He missed or needed hints on 3 of his last 5: one of his strongest items.
    case easing
    /// Time or count is up but the last one wasn't first try: an easy one to end on.
    case extra
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
    /// The limit that was reached. The session then ran until a first-try success.
    public var endedBy: EndReason?
    /// Easy items played after the limit so the session ends on a success (max `maxExtraItems`).
    public var extraItems = 0

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
/// (it closes chord windows, steps up the hint ladder when he's stuck, and stops
/// waiting for the last key-up of a rhythm line).
///
/// Shape of a session (learning principles in the plan):
/// - opens with up to `warmUpCount` of his strongest items, new items wait until after
/// - a new item is introduced i do / we do / you do: the app plays it and lights the
///   key (`.playPitches` + `.say(.meetNote)`), he plays it with the picture up, after
///   that the picture only comes back as a hint
/// - after 3 of his last 5 weren't right first try, the next 2 are his strongest
/// - when time or count is up it ends after his next first-try success (easy items,
///   at most `maxExtraItems` extra)
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
    /// Why the current item was picked.
    public private(set) var pickReason = PickReason.normal

    private var config: NoteCoreConfig { engine.config }
    private var rng: SeededRandom
    private var judge: AttemptJudge?

    // clock: active time = app time - start - paused total
    private var startTime = 0.0
    private var pausedTotal = 0.0
    private var pausedAt: Double?
    private var resumePhase: SessionPhase?

    // session shape
    private var warmUpLeft = 0
    private var easingLeft = 0
    /// Last few attempts: true when it wasn't right first try.
    private var struggles: [Bool] = []
    private var limitReached: SessionSummary.EndReason?

    // the current item
    private var promptTime = 0.0
    private var lastActivity = 0.0
    private var firstCorrectTime: Double?
    /// Steps up the hint ladder on the current note (wrong keys and stuck steps).
    private var ladder = 0
    private var totalWrongs = 0
    private var stuckSteps = 0
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
        warmUpLeft = min(config.warmUpCount, engine.playedPool.count)
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
            stuckSteps += 1
            lastActivity = t
            cues += climbLadder()
        }
        return cues
    }

    /// After the success animation: the next item, or the end of the session.
    public mutating func next(at time: Double) -> [Cue] {
        guard phase == .success else { return [] }
        let t = activeTime(at: time)
        summary.activeDuration = t
        if limitReached == nil {
            if summary.itemsPlayed >= config.sessionMaxItems {
                limitReached = .itemLimit
            } else if t >= config.sessionMaxDuration {
                limitReached = .timeLimit
            }
        }
        if let limit = limitReached {
            // end on a success: right after a first-try one, or once the extras run out
            if summary.attempts.last?.firstTry == true || summary.extraItems >= config.maxExtraItems {
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
        var reason = forced ?? .normal
        if forced == nil {
            if warmUpLeft > 0 {
                warmUpLeft -= 1
                reason = .warmUp
            } else if easingLeft > 0 {
                easingLeft -= 1
                reason = .easing
            }
        }
        let next = engine.pickNext(reason == .normal ? .normal : .strongest, using: &rng)
        item = next
        pickReason = reason
        isIntro = engine.needsIntro(next)
        noteIndex = 0
        promptTime = t
        lastActivity = t
        firstCorrectTime = nil
        ladder = 0
        totalWrongs = 0
        stuckSteps = 0
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
            // i do: the app shows him. then we do: he plays it with the picture up
            let letters = next.notes.flatMap { $0.pitches.map(\.naturalLetter) }
            switch next.kind {
            case .note:
                cues += [.playPitches(next.notes[0].pitches), .say(.meetNote(letters[0]))]
            case .chord:
                cues += [.playPitches(next.notes[0].pitches), .say(.meetNotes(letters))]
            case .group:
                cues += [.playPhrase(beat: config.demoBeat), .say(.meetNotes(letters))]
            case .rhythm:
                cues += [.say(.newNote), .playPhrase(beat: config.demoBeat)] // sound before symbol
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
            lastActivity = t
            if firstCorrectTime == nil {
                firstCorrectTime = t
            }
            if noteIndex < item.notes.count - 1 {
                noteIndex += 1
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
            cues += finish(at: t, rhythm: nil)
            return cues

        case .almost(let played):
            almosts += 1
            keyboardHint = expected
            return [.say(.almost(played: played[0], expected: expected[0]))]

        case .wrong:
            totalWrongs += 1
            return climbLadder()
        }
    }

    /// One step up the hint ladder for the current note: wobble, then the sound, then
    /// the keyboard picture. Past the top, a wrong key replays the sound.
    private mutating func climbLadder() -> [Cue] {
        guard let item else { return [] }
        let expected = item.notes[noteIndex].pitches
        ladder += 1
        rhythmJudgeable = false
        var cues: [Cue] = [.wobble(note: noteIndex)]
        switch ladder {
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
            itemID: item.id, unit: engine.unit.number, wasIntro: isIntro,
            firstTry: totalWrongs == 0 && stuckSteps == 0, wrongPresses: totalWrongs, almostPresses: almosts,
            stuckSteps: stuckSteps, hints: hints, responseTime: max(0, responseTime), rhythm: rhythm
        )
        let fluencyBefore = engine.stats(for: item.id).peakFluency
        let update = engine.record(attempt)
        noteSummary(attempt, update: update, fluencyBefore: fluencyBefore)
        noteStruggle(attempt)

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
        } else if hints > .none {
            cues.append(.say(.keptTrying))
        } else if unitInterval(&rng) < config.praiseChance {
            cues.append(.say(.lookedCarefully))
        }
        if !update.unlocked.isEmpty {
            cues.append(.unlocked(update.unlocked))
        }
        return cues
    }

    /// Easing: after `easingTrigger` of the last `easingWindow` weren't right first try,
    /// the next `easingItems` are his strongest.
    private mutating func noteStruggle(_ attempt: AttemptResult) {
        struggles = Array((struggles + [!attempt.firstTry]).suffix(config.easingWindow))
        if easingLeft == 0, struggles.filter({ $0 }).count >= config.easingTrigger {
            easingLeft = config.easingItems
            struggles = []
        }
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

// see LenientDecoding.swift. the app keeps every session as JSON
extension SessionSummary {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startUnit = try c.value(.startUnit, or: 1)
        endUnit = try c.value(.endUnit, or: startUnit)
        itemsPlayed = try c.value(.itemsPlayed, or: 0)
        firstTryCount = try c.value(.firstTryCount, or: 0)
        activeDuration = try c.value(.activeDuration, or: 0)
        attempts = try c.value(.attempts, or: [])
        unlocked = try c.value(.unlocked, or: [])
        completedUnits = try c.value(.completedUnits, or: [])
        practiced = try c.value(.practiced, or: [])
        endedBy = try c.decodeIfPresent(EndReason.self, forKey: .endedBy)
        extraItems = try c.value(.extraItems, or: 0)
    }
}
