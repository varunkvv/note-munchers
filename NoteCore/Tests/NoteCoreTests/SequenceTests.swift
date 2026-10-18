import Testing
@testable import NoteCore

/// A screen counts only when he plays the whole thing right in one go, and a slip gently
/// starts it over at his next pause (plans/2026-10-17-whole-sequence.md).
@Suite struct SequenceTests {
    /// A session on a screen of at least `notes` notes (2.1: 3-4 a screen, lenient
    /// octaves), nothing played on it yet.
    func bench(_ lesson: LessonID = "2.1", notes: Int = 3, config: NoteCoreConfig = .default, seed: UInt64 = 1) -> Bench {
        var bench = Bench(engine(in: lesson, config: config), seed: seed)
        _ = bench.start()
        for _ in 0..<60 {
            if !bench.session.isIntro, bench.session.item!.notes.count >= notes, bench.session.rhythmLine == nil { return bench }
            _ = bench.playScreen()
            _ = bench.next()
        }
        fatalError("no \(notes)-note screen in \(lesson)")
    }

    /// The hand off the keys it was on, then a key down and up again, like a tap.
    func tap(_ bench: inout Bench, _ pitch: Pitch, after dt: Double = 0.5) -> [Cue] {
        bench.releaseAll(after: dt) + bench.press(pitch, after: 0) + bench.release(pitch, after: 0.15)
    }

    /// Wrong for the current note in any octave policy, never the natural next to a sharp.
    func wrong(_ bench: Bench) -> Pitch { bench.wrongKey }

    func notes(_ bench: Bench) -> [AttemptResult] { bench.session.summary.screens.last!.notes }

    @Test func aCleanGoFinishes() {
        var b = bench()
        let cues = b.playScreen()
        #expect(b.session.phase == .success)
        #expect(!cues.contains { if case .startOver = $0 { true } else { false } })
        let screen = b.session.summary.screens.last!
        #expect(screen.restarts == 0 && screen.firstTry)
    }

    @Test func aSlipOnNoteTwoThenAPauseStartsOverAtNoteOne() throws {
        var b = bench()
        _ = b.playNote()
        let slip = tap(&b, wrong(b))
        #expect(slip == [.wobble(note: 1)], "a soft wobble, nothing else")
        #expect(b.session.slippedNote == 1)
        #expect(b.session.noteIndex == 1, "the played note stays played until the pause")
        let deadline = try #require(b.session.nextDeadline)
        #expect(abs(deadline - (b.now - 0.15 + 1.2)) < 1e-9, "1.2s after the key went down")
        #expect(b.tick(at: deadline - 0.01).isEmpty, "not before the pause")
        let over = b.tick(at: deadline)
        #expect(over == [.startOver(played: 1)], "silent: no voice, no sound of its own")
        #expect(b.session.noteIndex == 0 && b.session.slippedNote == nil)
        #expect(b.session.phase == .prompt)
        #expect(b.session.keyboardHint.isEmpty)
        _ = b.playScreen()
        #expect(b.session.phase == .success)
        #expect(b.session.summary.screens.last!.restarts == 1)
    }

    @Test func keysBetweenTheSlipAndThePauseDontCount() throws {
        var b = bench()
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        let first = try #require(b.session.nextDeadline)
        // more keys, right and wrong: no wobble, nothing counts, the pause moves back
        let right = b.expected
        #expect(tap(&b, right[0], after: 0.4).isEmpty)
        #expect(tap(&b, wrong(b), after: 0.4).isEmpty)
        #expect(b.session.noteIndex == 1)
        let later = try #require(b.session.nextDeadline)
        #expect(later > first)
        #expect(b.tick(at: later) == [.startOver(played: 1)])
        _ = b.playScreen()
        #expect(notes(b)[1].wrongPresses == 1, "only the slip counts")
    }

    @Test func aSelfCorrectionStraightAfterTheSlipStillStartsOver() throws {
        var b = bench()
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        #expect(tap(&b, b.expected[0], after: 0.2).isEmpty, "the right key a moment later doesn't count")
        #expect(b.session.noteIndex == 1)
        let deadline = try #require(b.session.nextDeadline)
        #expect(b.tick(at: deadline) == [.startOver(played: 1)])
    }

    @Test func aSlipOnTheFirstNoteDoesntStartOver() throws {
        var b = bench()
        #expect(tap(&b, wrong(b)) == [.wobble(note: 0)])
        #expect(b.session.slippedNote == nil)
        #expect(b.session.phase == .waiting, "the ladder, as before")
        let deadline = try #require(b.session.nextDeadline)
        #expect(abs(deadline - (b.now - 0.15 + 15)) < 1e-9, "only the stuck clock")
        _ = b.playScreen()
        #expect(b.session.summary.screens.last!.restarts == 0)
    }

    @Test func aHeldKeyHoldsTheStartOverBack() throws {
        var b = bench()
        _ = b.playNote()
        _ = b.releaseAll()
        let slipped = wrong(b)
        _ = b.press(slipped)
        let held = try #require(b.session.nextDeadline)
        #expect(abs(held - (b.now + 4)) < 1e-9, "held: at most restartHoldLimit after it went down")
        #expect(b.tick(at: b.now + 2).isEmpty, "still holding it 2s later")
        #expect(b.release(slipped) == [.startOver(played: 1)], "he lets go after his pause: it starts over then")
    }

    @Test func aKeyHeldForeverStillLetsItStartOver() throws {
        var b = bench()
        _ = b.playNote()
        _ = b.press(wrong(b))
        let deadline = try #require(b.session.nextDeadline)
        #expect(b.tick(at: deadline) == [.startOver(played: 1)], "a lost key-up can't keep him stuck")
    }

    @Test func aLateTickStartsOverOnHisNextKey() {
        var b = bench()
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        let first = b.session.item!.notes[0].pitches
        // no tick: his next key comes 3s later, after the pause
        let cues = b.press(first[0], after: 3)
        #expect(cues == [.startOver(played: 1), .correct(note: 0)])
        #expect(b.session.noteIndex == 1)
    }

    @Test func stuckIsNotASlip() throws {
        var b = bench()
        _ = b.playNote()
        let deadline = try #require(b.session.nextDeadline)
        #expect(b.tick(at: deadline) == [.wobble(note: 1)], "the ladder climbs on the note he's on")
        #expect(b.session.slippedNote == nil && b.session.noteIndex == 1)
        _ = b.playScreen()
        let screen = b.session.summary.screens.last!
        #expect(screen.restarts == 0)
        #expect(screen.notes[1].stuckSteps == 1 && !screen.notes[1].firstTry)
    }

    /// Each note's result is from the first go that reached it.
    @Test func resultsAreFromTheFirstGoThatReachedEachNote() throws {
        var b = bench(notes: 4)
        _ = b.playNote()
        _ = b.playNote()
        _ = tap(&b, wrong(b)) // a slip on the third note
        _ = b.startOver()
        // go 2: the first three right (the third for the first time), a slip on the fourth
        _ = b.playNote()
        _ = b.playNote()
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        _ = b.startOver()
        // go 3: a slip on the first note, which he had right in go 1, then clean
        _ = tap(&b, wrong(b))
        _ = b.playScreen()
        #expect(b.session.phase == .success)
        let screen = b.session.summary.screens.last!
        #expect(screen.notes.map(\.firstTry) == [true, true, false, false] + Array(repeating: true, count: screen.notes.count - 4))
        #expect(screen.notes.map(\.wrongPresses).prefix(4) == [0, 0, 1, 1])
        #expect(!screen.firstTry, "a screen is right first try only when the first go was clean")
        #expect(screen.restarts == 2)
    }

    @Test func theSlippedNoteIsTimedFromTheGoWherePlayedItRight() {
        var b = bench()
        _ = b.playNote(after: 1)
        _ = tap(&b, wrong(b), after: 3)
        _ = b.startOver()
        _ = b.playNote(after: 1)
        _ = b.playNote(after: 0.8)
        _ = b.playScreen(after: 1)
        let notes = notes(b)
        #expect(abs(notes[0].responseTime - 1) < 1e-9, "from go 1")
        #expect(abs(notes[1].responseTime - 0.8) < 1e-9, "from when it became next in go 2")
    }

    /// Each slip on a note is a rung of its ladder: the wobble, then its pitch when he gets
    /// back to it. At most 3 goes, then a slip works note by note and he finishes from there.
    @Test func theLadderCarriesOverAndTheCapHandsOverToNoteByNote() throws {
        var b = bench()
        let slipped = b.session.item!.notes[1].pitches
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        #expect(b.startOver() == [.startOver(played: 1)], "first slip: the wobble was it")
        _ = b.playNote()
        #expect(b.session.phase == .waiting, "back on it, one rung up")
        #expect(tap(&b, wrong(b)) == [.wobble(note: 1)])
        #expect(b.startOver() == [.startOver(played: 1)], "the reset itself is silent")
        let reach = b.playNote()
        #expect(reach == [.correct(note: 0), .playPitches(slipped)], "second slip: its pitch plays once he's back on it")
        #expect(b.session.phase == .hint1)
        // the third go is the last: a slip now stays on the note with the ladder
        #expect(tap(&b, wrong(b)) == [.wobble(note: 1)])
        #expect(b.session.slippedNote == nil && b.session.noteIndex == 1)
        #expect(b.session.keyboardHint == slipped, "third rung: the keyboard picture")
        _ = b.playScreen()
        #expect(b.session.phase == .success, "he can always finish")
        #expect(b.session.summary.screens.last!.restarts == 2)
    }

    @Test func aThirdSlipLightsTheKeyWhenHeGetsBackToIt() throws {
        var config = NoteCoreConfig()
        config.sequenceRestarts = 3
        var b = bench(config: config)
        let slipped = b.session.item!.notes[1].pitches
        for _ in 0..<3 {
            _ = b.playNote()
            _ = tap(&b, wrong(b))
            _ = b.startOver()
        }
        _ = b.playNote()
        #expect(b.session.noteIndex == 1)
        #expect(b.session.keyboardHint == slipped)
        #expect(b.session.phase == .hint2)
        #expect(b.session.nextDeadline == nil, "the top of the ladder: nothing more on a clock")
    }

    @Test func noStartOversAtAllWithZero() {
        var b = bench(config: .noteByNote)
        _ = b.playNote()
        #expect(tap(&b, wrong(b)) == [.wobble(note: 1)])
        #expect(b.session.slippedNote == nil && b.session.noteIndex == 1)
    }

    /// Level 1-2's "almost" (the right letter an octave off) is a slip, but not a miss.
    @Test func almostInLevelOneIsASlipButNotAMiss() {
        var b = bench("1.2", notes: 2)
        let second = b.session.item!.notes[1].pitches
        _ = b.playNote()
        #expect(tap(&b, Pitch(midi: second[0].midi + 12)) == [.wobble(note: 1)])
        #expect(b.session.slippedNote == 1)
        _ = b.startOver()
        _ = b.playNote()
        #expect(b.session.keyboardHint == second, "back on it, the picture shows which one")
        _ = b.playScreen()
        let notes = notes(b)
        #expect(notes[1].firstTry && notes[1].almostPresses == 1)
        #expect(b.session.summary.screens.last!.restarts == 1)
    }

    @Test func aWrongTwoAtOnceIsASlip() throws {
        var engine = engine(in: "4.1", config: noDemos)
        var rng = SeededRandom(seed: 1)
        engine.playPick(engine.pickScreen(using: &rng)) // the lesson intro
        var b = Bench(engine, seed: 4)
        _ = b.start()
        // to a screen with two at once past its first note, on that column
        var found = false
        for _ in 0..<60 where !found {
            let item = b.session.item!
            if let k = item.notes.indices.dropFirst().first(where: { item.notes[$0].pitches.count == 2 }) {
                while b.session.noteIndex < k, b.session.phase.isPlaying { _ = b.playNote() }
                found = b.session.noteIndex == k && b.session.phase.isPlaying
                if found { break }
            }
            while b.session.phase.isPlaying || b.session.isAwaitingRelease { _ = b.playNote() }
            _ = b.next()
        }
        try #require(found)
        let k = b.session.noteIndex
        let dyad = b.expected
        _ = b.press(dyad[0])
        _ = b.press(Pitch(midi: dyad[1].midi + 1), after: 0.01)
        let cues = b.tick(at: b.now + 0.2) // the chord window closes
        #expect(cues == [.wobble(note: k)])
        #expect(b.session.slippedNote == k)
        _ = b.releaseAll()
        #expect(b.startOver() == [.startOver(played: k)])
    }

    var noDemos: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.rhythmDemoScreens = 0
        return config
    }

    /// A rhythm line is judged on the go that got every note right.
    @Test func aRhythmLineIsJudgedOnTheCleanGo() {
        var b = Bench(engine(in: "3.1", config: noDemos), seed: 5)
        _ = b.start()
        for _ in 0..<200 where b.session.rhythmLine == nil || b.session.isIntro {
            _ = b.playScreen()
            _ = b.next()
        }
        let item = b.session.item!
        let line = b.session.rhythmLine!
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        _ = b.startOver()
        // the clean go, in time at 0.6s a beat
        var cues: [Cue] = []
        for i in item.notes.indices {
            if i > 0 { cues += b.release(item.notes[i - 1].pitches[0], after: line.gaps[i - 1] * 0.6) }
            cues += b.press(item.notes[i].pitches[0], after: i == 0 ? 1 : 0)
        }
        if b.session.isAwaitingRelease {
            cues += b.release(item.notes.last!.pitches[0], after: line.gaps.last! * 0.6)
        }
        #expect(b.session.phase == .success)
        let screen = b.session.summary.screens.last!
        #expect(screen.restarts == 1)
        let rhythm = screen.rhythm
        #expect(rhythm != nil, "judged")
        #expect(rhythm?.isOK == true, "\(String(describing: rhythm))")
    }

    @Test func thePlayButtonAfterASlipStartsOverAndPlaysIt() {
        var b = bench()
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        let cues = b.session.listen(at: b.now + 0.3)
        #expect(cues == [.startOver(played: 1), .showAndPlay(beat: NoteCoreConfig().demoBeat)])
        #expect(b.session.noteIndex == 0 && b.session.slippedNote == nil)
        b.now += 10
        _ = b.playScreen()
        let notes = notes(b)
        #expect(notes[0].firstTry, "played right before it")
        #expect(notes.dropFirst().allSatisfy { !$0.firstTry && $0.hints == .keyboard }, "heard and seen first")
    }

    @Test func thePianoGoingAwayAfterASlipKeepsItForWhenItsBack() throws {
        var b = bench()
        _ = b.playNote()
        _ = tap(&b, wrong(b))
        b.now += 0.3
        #expect(b.session.pianoDisconnected(at: b.now) == [.paused])
        b.now += 20
        #expect(b.session.pianoConnected(at: b.now) == [.resumed])
        #expect(b.session.slippedNote == 1)
        let deadline = try #require(b.session.nextDeadline)
        #expect(abs(deadline - (b.now + 0.75)) < 1e-9, "the rest of his pause, paused time doesn't count")
        // a hair past it, like the app's tick (the paused total rounds)
        #expect(b.tick(at: deadline + 0.0005) == [.startOver(played: 1)])
    }

    @Test func introsDontStartOver() {
        // a rhythm lesson's intro is a bar of notes with the picture up: guided
        var b = Bench(engine(in: "5.1"), seed: 1)
        _ = b.start()
        #expect(b.session.isLessonIntro)
        guard b.session.item!.notes.count > 1 else { return }
        _ = b.playNote()
        #expect(tap(&b, wrong(b)) == [.wobble(note: 1)])
        #expect(b.session.slippedNote == nil, "note by note on an intro")
    }

    // MARK: the seeded level 1 sim

    struct SimLog {
        var screens = 0
        var restarts = 0
        var screensStartedOver = 0
        var lines: [Speech] = []
        var midSession: [Speech] = []
        var minutes = 0.0
        var firstTry = 0.0
        var done = false
        var maxRestarts = 0
    }

    /// One session of QuietVoiceTests' scripted kid (65% right first try, a wrong key now and
    /// then, the wrong octave, stuck now and then). After a slip he stops, the screen starts
    /// over at his pause and he plays it again from the start (Bench).
    static func session(_ kid: QuietVoiceTests.Kid, _ engine: MasteryEngine, seed: UInt64) -> (SimLog, MasteryEngine) {
        var bench = Bench(engine, seed: seed)
        var dice = SeededRandom(seed: seed &+ 0xD1CE)
        var log = SimLog()
        func hear(_ cues: [Cue]) {
            for cue in cues {
                if case .startOver = cue { log.restarts += 1 }
                if case .say(let s) = cue {
                    log.lines.append(s)
                    if !cues.contains(.done) { log.midSession.append(s) }
                }
            }
        }
        hear(bench.start())
        var guardRail = 0
        while bench.session.phase != .done, guardRail < 300 {
            guardRail += 1
            if bench.session.isIntro {
                hear(bench.playScreen(after: 2))
            } else {
                var presses = 0
                while bench.session.phase.isPlaying, presses < 200 {
                    presses += 1
                    let roll = unitInterval(&dice)
                    if roll < kid.right {
                        // right first try
                    } else if roll < kid.right + kid.wrong {
                        hear(bench.press(bench.wrongKey, after: 1.5))
                    } else if roll < kid.right + kid.wrong + kid.octave {
                        hear(bench.press(Pitch(midi: bench.expected[0].midi + 12), after: 1.5))
                    } else {
                        let rungs = 1 + Int(unitInterval(&dice) * 3)
                        for _ in 0..<rungs {
                            if let deadline = bench.session.nextDeadline { hear(bench.tick(at: deadline)) }
                        }
                    }
                    hear(bench.playNote(after: 1.5))
                }
                #expect(presses < 200, "a screen he couldn't finish")
            }
            hear(bench.next(after: 1.2))
        }
        let summary = bench.session.summary
        log.done = bench.session.phase == .done
        log.screens = summary.screensPlayed
        log.screensStartedOver = summary.screens.filter { $0.restarts > 0 }.count
        log.maxRestarts = summary.screens.map(\.restarts).max() ?? 0
        log.minutes = summary.activeDuration / 60
        log.firstTry = Double(summary.firstTryNotes) / Double(max(1, summary.notesPlayed))
        return (log, bench.session.engine)
    }

    static func sessions(_ kid: QuietVoiceTests.Kid, _ count: Int, kidSeed: UInt64, config: NoteCoreConfig = .default) -> [SimLog] {
        var engine = MasteryEngine(config: config, state: MasteryState(seed: kidSeed))
        var logs: [SimLog] = []
        for s in 0..<count {
            let (log, after) = session(kid, engine, seed: kidSeed &* 1000 &+ UInt64(s))
            logs.append(log)
            engine = after
        }
        return logs
    }

    /// The 65% kid in level 1: how often a screen starts over, every screen finished,
    /// nothing said until the end. Before (note by note) next to after, same seeds.
    @Test func theSeededLevelOneKid() {
        var report: [String] = []
        for (name, config) in [("note by note", NoteCoreConfig.noteByNote), ("whole screen", NoteCoreConfig())] {
            var all: [SimLog] = []
            for kidSeed: UInt64 in 1...10 {
                let logs = Self.sessions(QuietVoiceTests.scripted, 3, kidSeed: kidSeed, config: config)
                for (i, log) in logs.enumerated() {
                    #expect(log.done, "kid \(kidSeed) session \(i + 1) ended")
                    #expect(log.midSession.isEmpty, "kid \(kidSeed) session \(i + 1): \(log.midSession)")
                    #expect(log.lines.count <= 1)
                    #expect(log.maxRestarts <= config.sequenceRestarts)
                    if kidSeed == 1 {
                        report.append("\(name), kid 1 session \(i + 1): \(log.screens) screens, \(log.restarts) start overs on \(log.screensStartedOver) screens, "
                            + "\(String(format: "%.1f", log.minutes)) min, \(Int((log.firstTry * 100).rounded()))% notes first try, lines \(log.lines)")
                    }
                }
                all += logs
            }
            let n = Double(all.count)
            let restarts = Double(all.map(\.restarts).reduce(0, +)) / n
            let screens = Double(all.map(\.screens).reduce(0, +)) / n
            let over = Double(all.map(\.screensStartedOver).reduce(0, +)) / n
            let minutes = all.map(\.minutes).reduce(0, +) / n
            let firstTry = all.map(\.firstTry).reduce(0, +) / n
            report.append("\(name), 10 kids x 3 sessions: \(String(format: "%.1f", restarts)) start overs a session on \(String(format: "%.1f", over)) screens, "
                + "\(String(format: "%.1f", screens)) screens, \(String(format: "%.1f", minutes)) min, \(Int((firstTry * 100).rounded()))% notes first try, "
                + "max \(all.map(\.maxRestarts).max() ?? 0) on one screen")
        }
        print(report.joined(separator: "\n"))
    }
}
