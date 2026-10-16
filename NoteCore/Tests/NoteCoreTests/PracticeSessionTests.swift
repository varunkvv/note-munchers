import Testing
@testable import NoteCore

@Suite struct PracticeSessionTests {
    /// A session in 1.2 (2 notes a screen) with nothing played yet, so no warm-up.
    func twoNoteBench(seed: UInt64 = 1, config: NoteCoreConfig = .default) -> Bench {
        Bench(engine(in: "1.2", config: config), seed: seed)
    }

    @Test func startsWithHelloThenAScreen() {
        var bench = twoNoteBench()
        let cues = bench.start()
        #expect(cues.first == .say(.hello))
        #expect(cues.contains(.showItem))
        #expect(bench.session.phase == .prompt)
        #expect(bench.session.item!.notes.count == 2)
        #expect(bench.next().isEmpty, "next does nothing until he plays")
    }

    @Test func hintLadderIsPerNote() {
        var bench = twoNoteBench()
        _ = bench.start()
        let first = bench.expected
        #expect(bench.press(bench.wrongKey) == [.wobble(note: 0)])
        #expect(bench.session.phase == .waiting)
        let second = bench.press(bench.wrongKey)
        #expect(second == [.wobble(note: 0), .say(.hintListen), .playPitches(first)])
        #expect(bench.session.phase == .hint1)
        let third = bench.press(bench.wrongKey)
        #expect(third == [.wobble(note: 0), .say(.hintShow(NoteName(first[0])!))])
        #expect(bench.session.keyboardHint == first)
        #expect(bench.press(bench.wrongKey) == [.wobble(note: 0), .playPitches(first)], "past the top: the sound again, no more talk")
        // right key: on to note 1 with a fresh ladder and the picture gone
        #expect(bench.playCurrent() == [.correct(note: 0)])
        #expect(bench.session.noteIndex == 1)
        #expect(bench.session.phase == .prompt)
        #expect(bench.session.keyboardHint.isEmpty)
        #expect(bench.press(bench.wrongKey) == [.wobble(note: 1)], "note 1 starts at the bottom of the ladder")
        _ = bench.playCurrent()
        #expect(bench.session.phase == .success)
        let notes = bench.session.summary.screens[0].notes
        #expect(notes.map(\.firstTry) == [false, false])
        #expect(notes.map(\.wrongPresses) == [4, 1])
        #expect(notes.map(\.hints) == [.keyboard, .wobble])
    }

    @Test func eachNoteIsTimedFromWhenItBecameNext() {
        var bench = twoNoteBench()
        _ = bench.start()
        _ = bench.playCurrent(after: 2.0)
        _ = bench.playCurrent(after: 0.7)
        let notes = bench.session.summary.screens[0].notes
        #expect(abs(notes[0].responseTime - 2.0) < 1e-9)
        #expect(abs(notes[1].responseTime - 0.7) < 1e-9)
        #expect(notes.allSatisfy { $0.firstTry })
        #expect(notes.map(\.itemID) == bench.session.item!.notes.flatMap(\.keys).map(\.id))
    }

    @Test func noLetterAfterRightKeys() {
        var bench = twoNoteBench(seed: 3)
        _ = bench.start()
        for _ in 0..<30 {
            let cues = bench.playScreen()
            for speech in speeches(cues) {
                #expect(speech == .lookedCarefully || speech == .keptTrying, "\(speech)")
            }
            _ = bench.next()
        }
    }

    @Test func praiseIsRareAndNeverTwoScreensInARow() {
        var praised: [Bool] = []
        for seed: UInt64 in 1...10 {
            var run = 0
            var config = NoteCoreConfig()
            config.sessionMaxItems = 100
            config.sessionMaxDuration = 10_000
            var bench = twoNoteBench(seed: seed, config: config)
            _ = bench.start()
            for _ in 0..<40 {
                let said = speeches(bench.playScreen())
                let p = said.contains(.lookedCarefully)
                praised.append(p)
                run = p ? run + 1 : 0
                #expect(run < 2, "never two screens in a row")
                _ = bench.next()
            }
        }
        let rate = Double(praised.filter { $0 }.count) / Double(praised.count)
        print("praise rate over \(praised.count) first-try screens: \(rate)")
        #expect(rate > 0.1 && rate < 0.25, "about 1 in 5 or a bit less: \(rate)")
    }

    @Test func aHintedScreenSometimesGetsKeptTrying() {
        var kept = 0
        for seed: UInt64 in 1...40 {
            var bench = twoNoteBench(seed: seed)
            _ = bench.start()
            _ = bench.press(bench.wrongKey)
            let said = speeches(bench.playScreen())
            if said.contains(.keptTrying) { kept += 1 }
            #expect(!said.contains(.lookedCarefully))
        }
        #expect(kept > 10 && kept < 30, "about half: \(kept) of 40")
    }

    @Test func newNoteGetsAnIntroThatDoesNotCount() {
        var bench = Bench(MasteryEngine(state: MasteryState(seed: 2)))
        let cues = bench.start()
        let intro = bench.session.introNote!
        #expect(cues == [.say(.hello), .showItem, .playPitches([intro.pitch]), .say(.meetNote(intro.name!))])
        #expect(bench.session.isIntro)
        #expect(bench.session.keyboardHint == [intro.pitch], "we do: the picture is up from the start")
        #expect(bench.session.item!.notes.count == 1)
        let done = bench.playCurrent()
        #expect(speeches(done).isEmpty, "no praise for an intro")
        #expect(bench.session.engine.stats(for: intro).attempts == 0)
        #expect(!bench.session.engine.needsIntro(intro))
        #expect(bench.session.summary.notesPlayed == 0)
    }

    @Test func wrongOctaveIsAlmostInLevelOne() {
        var bench = Bench(engine(in: "1.1"))
        _ = bench.start()
        let expected = bench.expected[0]
        let cues = bench.press(Pitch(midi: expected.midi + 12))
        #expect(cues == [.say(.almost(NoteName(expected)!, .lower))], "played an octave up: this one is lower down")
        #expect(bench.session.keyboardHint == [expected])
        #expect(bench.session.phase == .prompt, "almost isn't a step up the ladder")
        _ = bench.playCurrent()
        #expect(bench.session.summary.screens[0].notes[0].firstTry, "doesn't count against him")
    }

    @Test func almostSaysWhichWay() {
        var bench = Bench(engine(in: "1.1"))
        _ = bench.start()
        let expected = bench.expected[0]
        #expect(bench.press(Pitch(midi: expected.midi - 12)) == [.say(.almost(NoteName(expected)!, .higher))])
    }

    @Test func accidentalTwoKeyPressCountsOnce() {
        var bench = twoNoteBench()
        _ = bench.start()
        let right = bench.expected[0]
        let cues = bench.press(right) + bench.press(Pitch(midi: right.midi + 1), after: 0.03)
        #expect(cues == [.correct(note: 0)])
        #expect(bench.session.noteIndex == 1)
    }

    @Test func pianoDropsMidScreenAndPicksUpWhereItWas() {
        var bench = twoNoteBench()
        _ = bench.start()
        _ = bench.playCurrent()
        _ = bench.press(bench.wrongKey)
        bench.now += 1
        #expect(bench.session.pianoDisconnected(at: bench.now) == [.paused, .say(.turnOnPiano)])
        #expect(bench.press(bench.expected[0]).isEmpty, "nothing counts while paused")
        bench.now += 30
        #expect(bench.session.pianoConnected(at: bench.now) == [.resumed])
        #expect(bench.session.noteIndex == 1)
        #expect(bench.session.phase == .waiting)
        _ = bench.playCurrent(after: 1)
        let notes = bench.session.summary.screens[0].notes
        #expect(notes[1].responseTime < 3, "paused time doesn't count: \(notes[1].responseTime)")
    }

    @Test func startsPausedWhenThePianoIsOff() {
        var bench = Bench(engine(in: "1.2"), connected: false)
        #expect(bench.start() == [.paused, .say(.turnOnPiano)])
        bench.now += 5
        let cues = bench.session.pianoConnected(at: bench.now)
        #expect(cues.prefix(3) == [.resumed, .say(.hello), .showItem])
    }

    @Test func endsAfterTheScreenLimitOnASuccess() {
        var config = NoteCoreConfig()
        config.sessionMaxItems = 5
        var bench = twoNoteBench(config: config)
        _ = bench.start()
        for _ in 0..<5 {
            _ = bench.playScreen()
            if bench.session.summary.screensPlayed < 5 { _ = bench.next() }
        }
        #expect(bench.next() == [.done, .say(.sessionDone)])
        #expect(bench.session.summary.endedBy == .itemLimit)
        #expect(bench.session.summary.extraItems == 0)
    }

    @Test func aMissOnTheLastScreenMeansOneMoreEasyScreen() {
        var config = NoteCoreConfig()
        config.sessionMaxItems = 2
        var bench = twoNoteBench(config: config)
        _ = bench.start()
        _ = bench.playScreen()
        _ = bench.next()
        _ = bench.press(bench.wrongKey)
        _ = bench.playScreen()
        let cues = bench.next()
        #expect(cues.contains(.showItem))
        #expect(bench.session.pickReason == .extra)
        _ = bench.playScreen()
        #expect(bench.next() == [.done, .say(.sessionDone)])
        #expect(bench.session.summary.extraItems == 1)
    }

    @Test func atMostThreeExtraThenEndsAnyway() {
        var config = NoteCoreConfig()
        config.sessionMaxItems = 1
        var bench = twoNoteBench(config: config)
        _ = bench.start()
        for _ in 0..<4 {
            _ = bench.press(bench.wrongKey)
            _ = bench.playScreen()
            if bench.session.summary.extraItems < 3 { _ = bench.next() }
        }
        #expect(bench.next() == [.done, .say(.sessionDone)])
        #expect(bench.session.summary.extraItems == 3)
    }

    @Test func sessionOpensWithHisStrongestNotes() {
        var engine = engine(in: "1.4")
        let strong = [key("treble:B4"), key("treble:C5"), key("bass:A2"), key("bass:B2")]
        for k in engine.pool { engine.play(k, time: 1) }
        for k in strong { for _ in 0..<4 { engine.play(k, time: 1) } }
        var bench = Bench(engine, seed: 4)
        _ = bench.start()
        var warmUpNotes = 0
        while bench.session.pickReason == .warmUp {
            #expect(bench.session.item!.keys.allSatisfy(strong.contains), "\(bench.session.item!.id)")
            warmUpNotes += bench.session.item!.notes.count
            _ = bench.playScreen()
            _ = bench.next()
        }
        #expect(warmUpNotes >= 3 && warmUpNotes <= 5, "2-3 strongest notes, a screen's worth: \(warmUpNotes)")
    }

    @Test func threeMissedNotesInFiveBringTwoStrongScreens() {
        var engine = engine(in: "1.4")
        for k in engine.pool { for _ in 0..<2 { engine.play(k, time: 1) } }
        var bench = Bench(engine, seed: 6)
        _ = bench.start()
        while bench.session.pickReason == .warmUp { _ = bench.playScreen(); _ = bench.next() }
        // miss three notes in a row
        var missed = 0
        while missed < 3 {
            _ = bench.press(bench.wrongKey)
            _ = bench.playCurrent()
            missed += 1
            if bench.session.phase == .success, missed < 3 { _ = bench.next() }
        }
        // finish the screen with the third miss, then the easy ones come
        if bench.session.phase.isPlaying { _ = bench.playScreen() }
        _ = bench.next()
        #expect(bench.session.pickReason == .easing)
        _ = bench.playScreen()
        _ = bench.next()
        #expect(bench.session.pickReason == .easing)
        _ = bench.playScreen()
        _ = bench.next()
        #expect(bench.session.pickReason != .easing)
    }

    /// Plays `count` screens right first try.
    func cruise(_ bench: inout Bench, _ count: Int) {
        for _ in 0..<count {
            _ = bench.playScreen()
            _ = bench.next()
        }
    }

    func roomy() -> NoteCoreConfig {
        var config = NoteCoreConfig()
        config.sessionMaxItems = 100
        config.sessionMaxDuration = 10_000
        return config
    }

    @Test func oopsOnAWrongKeyAfterAGoodRun() {
        var bench = twoNoteBench(config: roomy())
        _ = bench.start()
        cruise(&bench, 5)
        let cues = bench.press(bench.wrongKey)
        #expect(cues == [.wobble(note: bench.session.noteIndex), .say(.oops)], "goes with the wobble")
        #expect(bench.session.phase == .waiting, "the ladder carries on as usual")
        #expect(!speeches(bench.press(bench.wrongKey)).contains(.oops), "never after another miss on the same screen")
    }

    @Test func oopsAtMostOncePerSession() {
        var bench = twoNoteBench(config: roomy())
        _ = bench.start()
        var oops = 0
        for _ in 0..<6 {
            cruise(&bench, 6)
            oops += speeches(bench.press(bench.wrongKey)).filter { $0 == .oops }.count
            _ = bench.playScreen()
            _ = bench.next()
        }
        #expect(oops == 1)
    }

    @Test func noOopsAfterARunOfMisses() {
        var bench = twoNoteBench(config: roomy())
        _ = bench.start()
        var said: [Speech] = []
        for _ in 0..<12 {
            said += speeches(bench.press(bench.wrongKey))
            said += speeches(bench.playScreen())
            _ = bench.next()
        }
        #expect(!said.contains(.oops))
    }

    @Test func noOopsOnceEasingHasKickedIn() {
        var bench = twoNoteBench(config: roomy())
        _ = bench.start()
        // three missed notes in a row bring easing, then a long good run
        for _ in 0..<3 {
            _ = bench.press(bench.wrongKey)
            _ = bench.playCurrent()
            if bench.session.phase == .success { _ = bench.next() }
        }
        if bench.session.phase.isPlaying { _ = bench.playScreen() }
        _ = bench.next()
        #expect(bench.session.pickReason == .easing)
        cruise(&bench, 10)
        #expect(!speeches(bench.press(bench.wrongKey)).contains(.oops))
    }

    @Test func noOopsWhenStuckOrAlmost() {
        var bench = Bench(engine(in: "1.4", config: roomy()))
        _ = bench.start()
        cruise(&bench, 5)
        let expected = bench.expected[0]
        #expect(!speeches(bench.press(Pitch(midi: expected.midi + 12))).contains(.oops), "an almost isn't a wrong key")
        let deadline = bench.session.nextDeadline!
        #expect(!speeches(bench.tick(at: deadline)).contains(.oops), "being stuck isn't a wrong key")
    }

    @Test func stuckClimbsTheLadderAndStops() throws {
        var bench = twoNoteBench()
        _ = bench.start()
        let first = try #require(bench.session.nextDeadline)
        #expect(first == 15)
        #expect(bench.tick(at: first) == [.wobble(note: 0)])
        let second = try #require(bench.session.nextDeadline)
        #expect(bench.tick(at: second).contains(.say(.hintListen)))
        let third = try #require(bench.session.nextDeadline)
        #expect(bench.tick(at: third).contains(.say(.hintShow(NoteName(bench.expected[0])!))))
        #expect(bench.session.nextDeadline == nil, "nothing more on a clock")
        _ = bench.playCurrent()
        let note = bench.session.summary.screens.isEmpty ? nil : bench.session.summary.screens[0].notes[0]
        #expect(note == nil, "screen isn't done yet")
        _ = bench.playCurrent()
        #expect(bench.session.summary.screens[0].notes[0].stuckSteps == 3)
        #expect(!bench.session.summary.screens[0].notes[0].firstTry)
        #expect(bench.session.summary.screens[0].notes[0].wrongPresses == 0)
    }

    @Test func restartingThePromptClockAfterAHatch() {
        var bench = Bench(MasteryEngine(state: MasteryState(seed: 2)))
        _ = bench.start()
        bench.now = 8 // hatching
        bench.session.restartPromptClock(at: bench.now)
        #expect(bench.session.nextDeadline == 23)
        _ = bench.playCurrent(after: 1)
        #expect(abs(bench.session.summary.screens[0].notes[0].responseTime - 1) < 1e-9)
    }

    @Test func sameSeedSameSession() {
        func run(_ seed: UInt64) -> [ItemID] {
            var bench = Bench(MasteryEngine(state: MasteryState(seed: 5)), seed: seed)
            _ = bench.start()
            var ids: [ItemID] = []
            while bench.session.phase != .done {
                ids.append(bench.session.item!.id)
                _ = bench.playScreen()
                _ = bench.next()
            }
            return ids
        }
        #expect(run(3) == run(3))
        #expect(run(3) != run(4))
    }
}
