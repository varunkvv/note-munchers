import Testing
@testable import NoteCore

/// Drives a session with a moving clock.
struct Bench {
    var session: PracticeSession
    var now = 0.0

    init(_ engine: MasteryEngine, seed: UInt64 = 1, connected: Bool = true) {
        session = PracticeSession(engine: engine, seed: seed, pianoConnected: connected)
    }

    var expected: [Pitch] { session.item!.notes[session.noteIndex].pitches }
    /// A key that's wrong for the current note in any octave policy.
    var wrongKey: Pitch { Pitch(midi: expected[0].midi + 2) }

    mutating func start() -> [Cue] { session.start(at: now) }

    mutating func press(_ pitch: Pitch, after dt: Double = 0.5) -> [Cue] {
        now += dt
        return session.handle(.on(pitch, at: now))
    }

    mutating func release(_ pitch: Pitch, after dt: Double = 0) -> [Cue] {
        now += dt
        return session.handle(.off(pitch, at: now))
    }

    /// Presses every key of the current note at once (well, 10ms apart).
    mutating func playCurrent(after dt: Double = 0.5) -> [Cue] {
        var cues: [Cue] = []
        for (i, pitch) in expected.enumerated() {
            cues += press(pitch, after: i == 0 ? dt : 0.01)
        }
        return cues
    }

    mutating func next(after dt: Double = 1) -> [Cue] {
        now += dt
        return session.next(at: now)
    }

    mutating func tick(at time: Double) -> [Cue] {
        now = time
        return session.tick(at: time)
    }
}

/// An engine sitting in `unit` with its starting items already introduced, so prompts are normal ones.
func engine(inUnit unit: Int, config: NoteCoreConfig = .default) -> MasteryEngine {
    var engine = MasteryEngine(config: config)
    engine.moveToUnit(unit)
    for item in engine.pool { engine.intro(item.id) }
    return engine
}

@Suite struct PracticeSessionTests {
    @Test func hintsEscalateAndNeverMoveOnWithoutHim() {
        var bench = Bench(engine(inUnit: 1))
        #expect(bench.start() == [.showItem])
        #expect(bench.session.phase == .prompt)
        let expected = bench.expected
        let wrong = bench.wrongKey

        #expect(bench.press(wrong) == [.wobble(note: 0)])
        #expect(bench.session.phase == .waiting)
        #expect(bench.session.keyboardHint.isEmpty)

        #expect(bench.press(wrong) == [.wobble(note: 0), .playPitches(expected)])
        #expect(bench.session.phase == .hint1)

        #expect(bench.press(wrong) == [.wobble(note: 0)])
        #expect(bench.session.phase == .hint2)
        #expect(bench.session.keyboardHint == expected)

        #expect(bench.press(wrong) == [.wobble(note: 0), .playPitches(expected)], "still waiting, plays it again")
        #expect(bench.session.phase == .hint2)
        #expect(bench.tick(at: bench.now + 60).isEmpty, "no timers: nothing happens if he waits")

        let cues = bench.press(expected[0])
        #expect(cues.prefix(2) == [.correct(note: 0), .say(.letter(expected[0].letter!))])
        #expect(bench.session.phase == .success)
        #expect(bench.session.keyboardHint.isEmpty)
        let attempt = bench.session.summary.attempts.last!
        #expect(!attempt.firstTry)
        #expect(attempt.wrongPresses == 4)
        #expect(attempt.hints == .keyboard)

        #expect(bench.next() == [.showItem])
        #expect(bench.session.phase == .prompt)
    }

    @Test func newItemGetsAnIntroAndDoesNotCount() {
        var bench = Bench(MasteryEngine())
        // i do: the app plays it, lights the key, says its name
        #expect(bench.start() == [.showItem, .playPitches([.middleC]), .say(.meetNote(.c))])
        #expect(bench.session.isIntro)
        #expect(bench.session.item!.id == "treble:C4")
        #expect(bench.session.keyboardHint == [.middleC], "keyboard picture is up from the start")
        _ = bench.press(.middleC, after: 6)
        #expect(bench.session.phase == .success)
        #expect(bench.session.summary.attempts[0].wasIntro)
        #expect(bench.session.engine.stats(for: "treble:C4").attempts == 0)
        #expect(bench.next() == [.showItem, .playPitches([Pitch(.g, 4)]), .say(.meetNote(.g))], "G4 is next, also new")
        #expect(bench.session.item!.id == "treble:G4")
    }

    @Test func wrongOctaveIsAlmostInUnitOneAndWrongInUnitFour() {
        var early = Bench(engine(inUnit: 1))
        _ = early.start()
        let expected = early.expected[0]
        let octaveUp = Pitch(midi: expected.midi + 12)
        #expect(early.press(octaveUp) == [.say(.almost(played: octaveUp, expected: expected))])
        #expect(early.session.phase == .prompt, "doesn't count as a wrong try")
        #expect(early.session.keyboardHint == [expected], "shows which one")
        _ = early.press(expected)
        #expect(early.session.summary.attempts[0].firstTry, "doesn't count against him")
        #expect(early.session.summary.attempts[0].almostPresses == 1)

        var later = Bench(engine(inUnit: 4))
        _ = later.start()
        let written = later.expected[0]
        let shifted = Pitch(midi: written.midi + (written.midi >= 72 ? -12 : 12))
        #expect(later.press(shifted) == [.wobble(note: 0)])
        #expect(later.session.phase == .waiting)
    }

    @Test func accidentalTwoKeyPressCountsOnce() {
        var bench = Bench(engine(inUnit: 1))
        _ = bench.start()
        let expected = bench.expected[0]
        // wrong key with the right one 60ms behind it: the first key is judged, the second ignored
        #expect(bench.press(bench.wrongKey) == [.wobble(note: 0)])
        #expect(bench.press(expected, after: 0.06).isEmpty)
        #expect(bench.session.phase == .waiting)
        // a deliberate press after the window counts
        _ = bench.press(expected, after: 0.3)
        #expect(bench.session.phase == .success)
        #expect(bench.session.summary.attempts[0].wrongPresses == 1)
    }

    @Test func chordWindowThroughTheSession() throws {
        var bench = Bench(engine(inUnit: 8))
        _ = bench.start()
        let chord = bench.expected
        #expect(chord.count == 2)

        // one key down, the other never comes: judged when the window closes
        #expect(bench.press(chord[0]).isEmpty)
        let deadline = try #require(bench.session.nextDeadline)
        #expect(abs(deadline - (bench.now + 0.15)) < 1e-9)
        #expect(bench.tick(at: deadline - 0.01).isEmpty)
        #expect(bench.tick(at: deadline) == [.wobble(note: 0)])
        #expect(bench.session.nextDeadline! > bench.now + 10, "only the stuck timer is left")

        // both keys inside the window: right away
        let cues = bench.playCurrent()
        #expect(cues.first == .correct(note: 0))
        #expect(cues.contains(.say(.letters(chord.map(\.naturalLetter)))))
        #expect(bench.session.phase == .success)
    }

    @Test func groupsGoLeftToRight() {
        var bench = Bench(engine(inUnit: 7))
        _ = bench.start()
        let item = bench.session.item!
        #expect(item.kind == .group)
        var cues: [Cue] = []
        for i in item.notes.indices {
            #expect(bench.session.noteIndex == i)
            if i == 1 {
                #expect(bench.press(bench.wrongKey) == [.wobble(note: 1)], "the wobble is on the note he's at")
            }
            cues += bench.playCurrent()
        }
        #expect(bench.session.phase == .success)
        #expect(cues.contains(.correct(note: item.notes.count - 1)))
        #expect(cues.contains(.say(.letters(item.notes.map { $0.pitches[0].naturalLetter }))))
        #expect(!bench.session.summary.attempts[0].firstTry)
    }

    /// Plays the current rhythm item with the right keys at these lengths (seconds per
    /// note, key-down to next key-down). He lifts every key but the last one early.
    func playLine(_ bench: inout Bench, lengths: [Double]) -> [Cue] {
        let notes = bench.session.item!.notes
        var cues: [Cue] = []
        var t = bench.now + 0.8
        for (i, note) in notes.enumerated() {
            let pitch = note.pitches[0]
            cues += bench.session.handle(.on(pitch, at: t))
            let isLast = i == notes.count - 1
            cues += bench.session.handle(.off(pitch, at: t + lengths[i] * (isLast ? 1 : 0.5)))
            t += lengths[i]
        }
        bench.now = t
        return cues
    }

    @Test func wrongRhythmNeverFlipsARightPitchToWrong() {
        var bench = Bench(engine(inUnit: 10))
        _ = bench.start()
        let item = bench.session.item!
        let boxBefore = bench.session.engine.stats(for: item.id).box
        // every note the same length: rhythm is off
        let cues = playLine(&bench, lengths: item.notes.map { _ in 0.6 })
        #expect(bench.session.phase == .success, "pitch was right, so it's a success")
        let attempt = bench.session.summary.attempts[0]
        #expect(attempt.firstTry)
        #expect(attempt.rhythm != nil && !attempt.rhythm!.isOK)
        #expect(bench.session.engine.stats(for: item.id).box == boxBefore + 1, "pitch box still goes up")
        #expect(bench.session.engine.stats(for: item.id).rhythmBox == 1)
        let nudge = attempt.rhythm!.nudgeIndex!
        #expect(cues.contains(.rhythmGlow(note: nudge)))
        #expect(cues.contains(.say(.holdLonger)) == (attempt.rhythm!.verdicts[nudge] == .tooShort))
        #expect(!cues.contains { if case .wobble = $0 { true } else { false } }, "never a miss")
    }

    @Test func goodRhythmAtHisOwnTempo() {
        var bench = Bench(engine(inUnit: 10))
        _ = bench.start()
        let item = bench.session.item!
        let cues = playLine(&bench, lengths: item.values!.map { $0.beats * 1.1 }) // slow and steady
        let attempt = bench.session.summary.attempts[0]
        #expect(attempt.rhythm!.isOK)
        #expect(!cues.contains { if case .rhythmGlow = $0 { true } else { false } })
        #expect(abs(attempt.rhythm!.beat - 1.1) < 1e-6)
        #expect(abs(attempt.responseTime - 0.8) < 1e-9, "rhythm response time is how fast he started")
    }

    @Test func lastKeyUpNeverComesSoTickSettlesIt() throws {
        var bench = Bench(engine(inUnit: 10))
        _ = bench.start()
        let notes = bench.session.item!.notes
        for (i, note) in notes.enumerated() {
            _ = bench.press(note.pitches[0], after: i == 0 ? 0.5 : notes[i - 1].value!.beats * 0.6)
        }
        #expect(bench.session.phase != .success, "waiting for the last key-up")
        let deadline = try #require(bench.session.nextDeadline)
        _ = bench.tick(at: deadline)
        #expect(bench.session.phase == .success)
        #expect(bench.session.summary.attempts[0].rhythm!.isOK)
    }

    @Test func wrongKeyMidLineSkipsRhythm() {
        var bench = Bench(engine(inUnit: 12))
        _ = bench.start()
        let notes = bench.session.item!.notes
        for (i, _) in notes.enumerated() {
            if i == 1 { _ = bench.press(bench.wrongKey) }
            _ = bench.playCurrent(after: 0.6)
        }
        #expect(bench.session.phase == .success, "no waiting for a key-up when rhythm isn't judged")
        #expect(bench.session.summary.attempts[0].rhythm == nil)
        #expect(bench.session.engine.stats(for: bench.session.summary.attempts[0].itemID).rhythmAttempts == 0)
    }

    @Test func newRhythmItemIsPlayedToHimFirst() {
        var engine = MasteryEngine()
        engine.moveToUnit(10)
        var bench = Bench(engine)
        #expect(bench.start() == [.showItem, .say(.newNote), .playPhrase(beat: 0.75)])
    }

    @Test func endsAfterTheItemLimit() {
        var config = NoteCoreConfig()
        config.sessionMaxItems = 3
        var bench = Bench(engine(inUnit: 1, config: config))
        _ = bench.start()
        for _ in 0..<2 {
            _ = bench.playCurrent()
            #expect(bench.next() == [.showItem])
        }
        _ = bench.playCurrent()
        #expect(bench.next() == [.done, .say(.sessionDone)])
        #expect(bench.session.phase == .done)
        #expect(bench.session.summary.endedBy == .itemLimit)
        #expect(bench.session.summary.itemsPlayed == 3)
    }

    @Test func endsOnTimeButNeverMidItem() {
        var config = NoteCoreConfig()
        config.sessionMaxDuration = 10
        var bench = Bench(engine(inUnit: 1, config: config))
        _ = bench.start()
        // time is up while he's on this one. the session waits for him
        #expect(bench.tick(at: 11).isEmpty)
        #expect(bench.session.phase == .prompt)
        _ = bench.playCurrent(after: 1)
        #expect(bench.session.phase == .success)
        #expect(bench.next() == [.done, .say(.sessionDone)])
        #expect(bench.session.summary.endedBy == .timeLimit)
    }

    @Test func pianoDropsMidItemAndPicksUpWhereItWas() {
        var bench = Bench(engine(inUnit: 1))
        _ = bench.start()
        let item = bench.session.item!
        _ = bench.press(bench.wrongKey, after: 2) // now waiting, t = 2
        bench.now = 5
        #expect(bench.session.pianoDisconnected(at: 5) == [.paused, .say(.turnOnPiano)])
        #expect(bench.session.phase == .paused)
        #expect(bench.session.nextDeadline == nil)
        #expect(bench.press(bench.expected[0]).isEmpty, "keys don't count while paused")
        #expect(bench.next().isEmpty && bench.tick(at: 20).isEmpty)

        #expect(bench.session.pianoConnected(at: 65) == [.resumed])
        #expect(bench.session.phase == .waiting, "same item, same hint level")
        #expect(bench.session.item == item)
        #expect(bench.session.activeTime(at: 65) == 5)
        bench.now = 66
        _ = bench.press(bench.expected[0], after: 0)
        #expect(bench.session.phase == .success)
        let attempt = bench.session.summary.attempts[0]
        #expect(abs(attempt.responseTime - 6) < 1e-9, "paused minute doesn't count")
        #expect(attempt.wrongPresses == 1)
    }

    @Test func startsPausedWhenThePianoIsOff() {
        var bench = Bench(engine(inUnit: 1), connected: false)
        #expect(bench.start() == [.paused, .say(.turnOnPiano)])
        #expect(bench.session.phase == .paused)
        #expect(bench.session.item == nil)
        #expect(bench.session.pianoConnected(at: 30) == [.resumed, .showItem])
        #expect(bench.session.phase == .prompt)
        #expect(bench.session.activeTime(at: 31) == 1)
    }

    @Test func pianoDropsDuringTheCelebration() {
        var bench = Bench(engine(inUnit: 1))
        _ = bench.start()
        _ = bench.playCurrent()
        _ = bench.session.pianoDisconnected(at: bench.now + 0.2)
        #expect(bench.next().isEmpty)
        _ = bench.session.pianoConnected(at: bench.now + 10)
        #expect(bench.session.phase == .success)
        #expect(bench.next() == [.showItem])
    }

    @Test func pianoDropsWhileHoldingTheLastNote() {
        var bench = Bench(engine(inUnit: 10))
        _ = bench.start()
        let notes = bench.session.item!.notes
        for (i, note) in notes.enumerated() {
            _ = bench.press(note.pitches[0], after: i == 0 ? 0.5 : notes[i - 1].value!.beats * 0.6)
        }
        _ = bench.session.pianoDisconnected(at: bench.now + 0.1)
        let cues = bench.session.pianoConnected(at: bench.now + 5)
        #expect(cues.first == .resumed)
        #expect(bench.session.phase == .success)
        #expect(bench.session.summary.attempts[0].firstTry)
        #expect(bench.session.summary.attempts[0].rhythm == nil, "the key-up got lost, rhythm isn't judged")
    }

    @Test func nothingHappensAfterDone() {
        var config = NoteCoreConfig()
        config.sessionMaxItems = 1
        var bench = Bench(engine(inUnit: 1, config: config))
        _ = bench.start()
        _ = bench.playCurrent()
        _ = bench.next()
        #expect(bench.session.phase == .done)
        #expect(bench.press(.middleC).isEmpty)
        #expect(bench.next().isEmpty)
        #expect(bench.tick(at: 100).isEmpty)
        #expect(bench.session.pianoDisconnected(at: 101).isEmpty)
        #expect(bench.session.phase == .done)
        #expect(bench.start().isEmpty)
    }

    @Test func aFullDefaultSessionFromScratch() {
        var bench = Bench(MasteryEngine(), seed: 2024)
        var cues = bench.start()
        var hatched: [ItemID] = []
        while bench.session.phase != .done {
            cues = bench.playCurrent(after: 1.2)
            if bench.session.phase == .success {
                for case .unlocked(let ids) in cues { hatched += ids }
                cues = bench.next()
            }
        }
        let summary = bench.session.summary
        #expect(summary.itemsPlayed == 20)
        #expect(summary.endedBy == .itemLimit)
        #expect(summary.firstTryCount == 20)
        #expect(summary.unlocked == hatched)
        #expect(!summary.unlocked.isEmpty, "a quick kid unlocks something in his first session")
        #expect(summary.practiced.contains { $0.fluencyAfter > $0.fluencyBefore })
        #expect(maxRun(summary.attempts.map(\.itemID)) <= 2)
        #expect(cues == [.done, .say(.sessionDone)])
    }

    @Test func sameSeedSameSession() {
        func run() -> [ItemID] {
            var bench = Bench(MasteryEngine(), seed: 77)
            _ = bench.start()
            while bench.session.phase != .done {
                _ = bench.playCurrent(after: 1.5)
                _ = bench.next()
            }
            return bench.session.summary.attempts.map(\.itemID)
        }
        #expect(run() == run())
    }
}
