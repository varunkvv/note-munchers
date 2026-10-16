import Testing
@testable import NoteCore

/// Rhythm by level and the three outcomes (plans/2026-10-15-real-bars.md): display only
/// in levels 1-2, "half clearly longer than quarter" in level 3, every value and rests
/// from level 4. Sloppy is fine, a wrong value gets a replay and another go (at most 2),
/// a long pause is him reading.
@Suite struct RhythmPacingTests {
    let judge = RhythmJudge()
    let q = NoteValue.quarter, h = NoteValue.half, e = NoteValue.eighth

    func item(_ bars: [[WrittenNote]], _ meter: Meter) -> PracticeItem {
        PracticeItem(bars.flatMap { $0 }, bars: bars.map(\.count), meter: meter)
    }

    func n(_ value: NoteValue, _ rests: [NoteValue] = [], _ pitch: String = "G4") -> WrittenNote {
        WrittenNote(key("treble:\(pitch)"), value, rests: rests)
    }

    /// Plays `line` at `beat` seconds a quarter, each note's length times `stretch`.
    func run(_ line: RhythmLine, beat: Double, stretch: [Double]? = nil) -> RhythmResult {
        let lengths = line.gaps.enumerated().map { i, gap in gap * beat * (stretch?[i] ?? 1) }
        let p = performance(lengths)
        return judge.judge(line, onsets: p.onsets, release: p.release)
    }

    // MARK: what each level listens to

    @Test func levelsOneAndTwoAreDisplayOnly() {
        for id in ["1.1", "1.4", "2.1", "2.5"] {
            #expect(Curriculum.standard.lesson(id)!.rhythmCheck == .off)
            var bench = Bench(engine(in: id, config: long), seed: 3)
            _ = bench.start()
            for _ in 0..<15 {
                #expect(bench.session.rhythmLine == nil, "\(id): \(bench.session.item!.id)")
                // every note the same length, nothing to say about it
                for _ in 0..<20 where bench.session.phase.isPlaying { _ = bench.playCurrent(after: 0.7) }
                #expect(bench.session.phase == .success)
                #expect(bench.session.summary.screens.last!.rhythm == nil)
                _ = bench.next()
            }
        }
    }

    @Test func levelThreeListensToHalvesAgainstQuarters() {
        #expect(Curriculum.standard.levels[2].lessons.allSatisfy { $0.rhythmCheck == .halves })
        // q q h | w : the whole note is drawn, not judged
        let screen = item([[n(q), n(q), n(h)], [n(.whole)]], .fourFour)
        let line = screen.rhythmLine(.halves)!
        #expect(line.judged == [true, true, true, false])
        for beat in [1.2, 0.7, 0.35] { // slow, medium, fast
            #expect(run(line, beat: beat).isOK, "exact at \(beat)")
            let short = run(line, beat: beat, stretch: [1, 1, 0.5, 1])
            #expect(short.verdicts[2] == .tooShort, "the half played as a quarter at \(beat)")
            #expect(short.verdicts[3] == .unjudged)
            // only "was the half longer": a quarter held long is fine here
            #expect(run(line, beat: beat, stretch: [1, 2, 1, 1]).isOK)
        }
    }

    @Test func levelThreeSkipsWholesDottedHalvesAndNotesBeforeRests() {
        // q h + q rest | q q h. the half before the rest isn't judged
        let screen = item([[n(q), n(h, [q])], [n(q), n(q), n(h)]], .fourFour)
        let line = screen.rhythmLine(.halves)!
        #expect(line.judged == [true, false, true, true, true])
        #expect(run(line, beat: 0.6, stretch: [1, 0.5, 1, 1, 1]).isOK, "the half before the rest isn't judged in level 3")
        // dotted halves aren't judged in level 3: h. | q q q has nothing to compare
        #expect(item([[n(.dottedHalf)], [n(q), n(q), n(q)]], .threeFour).rhythmLine(.halves) == nil)
        // all quarters: nothing to compare, not judged
        #expect(item([[n(q), n(q), n(q), n(q)]], .fourFour).rhythmLine(.halves) == nil)
        #expect(item([[n(q), n(q), n(q), n(q)]], .fourFour).rhythmLine(.all) == nil)
    }

    @Test func levelFourJudgesWholesDottedHalvesAndCountsRests() {
        #expect(Curriculum.standard.level(4)!.lessons.allSatisfy { $0.rhythmCheck == .all })
        #expect(Curriculum.standard.level(5)!.lessons.allSatisfy { $0.rhythmCheck == .all })
        // w | q q h
        let wholes = item([[n(.whole)], [n(q), n(q), n(h)]], .fourFour).rhythmLine(.all)!
        #expect(wholes.gaps == [4, 1, 1, 2])
        // q h + q rest | q q h, at three tempos
        let rests = item([[n(q), n(h, [q])], [n(q), n(q), n(h)]], .fourFour).rhythmLine(.all)!
        #expect(rests.gaps == [1, 3, 1, 1, 2])
        for beat in [1.0, 0.6, 0.35] {
            #expect(run(wholes, beat: beat).isOK)
            #expect(run(wholes, beat: beat, stretch: [0.5, 1, 1, 1]).verdicts[0] == .tooShort, "a whole held as a half")
            #expect(run(rests, beat: beat).isOK, "rests count into the gap at \(beat)")
        }
        // skipping the rest after a quarter: played as an eighth's worth of its gap
        let restAfterQuarter = item([[n(q), n(q), n(q, [q])], [n(h), n(h)]], .fourFour).rhythmLine(.all)!
        #expect(run(restAfterQuarter, beat: 0.6, stretch: [1, 1, 0.5, 1, 1]).verdicts[2] == .tooShort)
        // h. | q q q: a dotted half held for one beat
        let dotted = item([[n(.dottedHalf)], [n(q), n(q), n(q)]], .threeFour).rhythmLine(.all)!
        #expect(run(dotted, beat: 0.6, stretch: [1.0 / 3, 1, 1, 1]).verdicts[0] == .tooShort)
    }

    @Test func eighthAsQuarterAndQuarterAsEighthInLevelFive() {
        let line = item([[n(e), n(e), n(q), n(h)]], .fourFour).rhythmLine(.all)!
        let asQuarters = run(line, beat: 0.6, stretch: [2, 2, 1, 1])
        #expect(asQuarters.verdicts[0] == .tooLong && asQuarters.verdicts[1] == .tooLong)
        let line2 = item([[n(q), n(q), n(e), n(e), n(q)], [n(.whole)]], .fourFour).rhythmLine(.all)!
        let asEighth = run(line2, beat: 0.6, stretch: [0.5, 1, 1, 1, 1, 1])
        #expect(asEighth.verdicts[0] == .tooShort)
    }

    @Test func aLongReadingPauseIsNotAWrongValue() {
        let line = item([[n(q), n(q), n(h)], [n(q), n(q), n(h)]], .fourFour).rhythmLine(.all)!
        for pause in [3.0, 4.5, 8.0] {
            let result = run(line, beat: 0.6, stretch: [1, pause, 1, 1, 1, 1])
            #expect(result.isOK, "a \(pause)-beat gap after a quarter")
            #expect(result.verdicts[1] == .pause)
        }
        // a quarter held near double is a wrong value
        #expect(run(line, beat: 0.6, stretch: [1, 2, 1, 1, 1, 1]).verdicts[1] == .tooLong)
        // after a half (before the next bar) a long gap is him reading, whatever its length
        for gap in [3.0, 4.0, 5.0] {
            #expect(run(line, beat: 0.6, stretch: [1, 1, gap / 2, 1, 1, 1]).isOK, "\(gap) beats after the half")
        }
        let halves = item([[n(q), n(q), n(h)], [n(q), n(q), n(h)]], .fourFour).rhythmLine(.halves)!
        #expect(run(halves, beat: 0.6, stretch: [4, 1, 1, 1, 1, 1]).isOK, "level 3 too")
    }

    @Test func aBitOffIsStillFine() {
        let line = item([[n(q), n(q), n(h)]], .fourFour).rhythmLine(.all)!
        let result = run(line, beat: 0.6, stretch: [1.35, 0.85, 0.7])
        #expect(result.isOK)
        #expect(result.verdicts.contains(.bitOff))
    }

    /// Every rhythm-judged screen the levels generate, played roughly right at a random
    /// tempo with +-20% jitter, passes.
    @Test func jitteryButRoughlyRightAlwaysPasses() {
        var rng = SeededRandom(seed: 21)
        var judged = 0
        for id in ["3.1", "3.5", "4.1", "4.4", "5.1", "5.2", "5.3", "5.5"] {
            var engine = engine(in: id)
            let check = engine.lesson.texture.isRhythm ? RhythmCheck.all : engine.lesson.rhythmCheck
            var picks = SeededRandom(seed: 4)
            for _ in 0..<150 {
                let pick = engine.pickScreen(using: &picks)
                engine.playPick(pick, time: 1)
                guard let line = pick.item.rhythmLine(check) else { continue }
                judged += 1
                let beat = 0.4 + Double(rng.next() % 1000) / 1000
                let stretch = line.values.map { _ in 1 + (Double(rng.next() % 1000) / 1000 - 0.5) * 0.4 }
                #expect(run(line, beat: beat, stretch: stretch).isOK, "\(id) \(pick.item.id) at \(beat)")
            }
        }
        #expect(judged > 500, "\(judged) judged screens")
    }

    @Test func levelThreeScreensGetJudgedOften() {
        var engine = engine(in: "3.1")
        var rng = SeededRandom(seed: 9)
        var judged = 0, total = 0
        for _ in 0..<300 {
            let pick = engine.pickScreen(using: &rng)
            engine.playPick(pick, time: 1)
            guard pick.intro == nil else { continue }
            total += 1
            if pick.item.rhythmLine(.halves) != nil { judged += 1 }
        }
        #expect(Double(judged) / Double(total) > 0.3, "\(judged) of \(total) level 3 screens rhythm-judged")
    }

    // MARK: the session

    /// Long sessions in one lesson, no demo screens in the way.
    var noDemos: NoteCoreConfig {
        var config = long
        config.rhythmDemoScreens = 0
        return config
    }

    var long: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        config.sessionMaxItems = 10_000
        config.sessionMaxDuration = 1e9
        return config
    }

    /// A session in `lesson` on a rhythm-judged screen that `fits`.
    func onJudged(_ lesson: LessonID, config: NoteCoreConfig? = nil, fits: (PracticeItem, RhythmLine) -> Bool = { _, _ in true }) -> Bench {
        var bench = Bench(engine(in: lesson, config: config ?? noDemos), seed: 5)
        _ = bench.start()
        for _ in 0..<200 {
            if let line = bench.session.rhythmLine, !bench.session.isIntro, fits(bench.session.item!, line) { return bench }
            _ = bench.playScreen()
            _ = bench.next()
        }
        fatalError("no such screen in \(lesson)")
    }

    /// Plays the screen through at `beat`, each note's length times `stretch`, holding the last.
    func play(_ bench: inout Bench, beat: Double = 0.6, stretch: (Int) -> Double = { _ in 1 }) -> [Cue] {
        let item = bench.session.item!, line = bench.session.rhythmLine!
        var cues: [Cue] = []
        for i in item.notes.indices {
            let after = i == 0 ? 1 : line.gaps[i - 1] * beat * stretch(i - 1)
            cues += bench.press(item.notes[i].pitches[0], after: after)
            for pitch in item.notes[i].pitches.dropFirst() { cues += bench.press(pitch, after: 0.01) }
        }
        if bench.session.isAwaitingRelease {
            cues += bench.release(item.notes.last!.pitches[0], after: line.gaps.last! * beat * stretch(item.notes.count - 1))
        }
        return cues
    }

    func firstHalf(_ item: PracticeItem, _ line: RhythmLine) -> Int? {
        item.notes.indices.first { line.judged[$0] && item.notes[$0].value == .half && $0 < item.notes.count - 1 }
    }

    @Test func aWrongValueGetsAReplayThenAnotherGo() {
        var bench = onJudged("3.1") { firstHalf($0, $1) != nil }
        let half = firstHalf(bench.session.item!, bench.session.rhythmLine!)!
        let recorded = bench.session.summary.screens.count
        let cues = play(&bench) { $0 == half ? 0.5 : 1 }
        #expect(bench.session.phase == .replaying)
        #expect(cues.contains(.rhythmGlow(note: half)))
        #expect(speeches(cues).isEmpty, "the glow and the play back, no words")
        let replay = cues.compactMap { if case .showAndPlay(let beat) = $0 { beat } else { nil } }
        #expect(replay.count == 1 && abs(replay[0] - 0.6) < 0.01, "at his own tempo: \(replay)")
        #expect(bench.session.summary.screens.count == recorded, "nothing recorded until the screen is done")
        #expect(bench.press(bench.expected[0]).isEmpty, "keys don't count during the play back")

        #expect(bench.next() == [.again])
        #expect(bench.session.phase == .prompt && bench.session.noteIndex == 0)
        _ = play(&bench)
        #expect(bench.session.phase == .success)
        let screen = bench.session.summary.screens.last!
        #expect(screen.rhythmRetries == 1)
        #expect(screen.rhythm?.isOK == false, "the first go is what counts")
        #expect(screen.notes.allSatisfy { $0.firstTry }, "pitch from the first go counts as it was")
        #expect(bench.session.engine.state.rhythmRecent.last == false, "a wrong value is a miss on the rhythm track")
    }

    @Test func retriesCapAtTwoThenItMovesOnKindly() {
        var bench = onJudged("3.1") { firstHalf($0, $1) != nil }
        let half = firstHalf(bench.session.item!, bench.session.rhythmLine!)!
        var said: [Speech] = []
        var last: [Cue] = []
        for go in 1...3 {
            last = play(&bench) { $0 == half ? 0.5 : 1 }
            said += speeches(last)
            if go < 3 {
                #expect(bench.session.phase == .replaying, "go \(go)")
                _ = bench.next()
            }
        }
        #expect(said.isEmpty)
        #expect(last.contains(.rhythmGlow(note: half)), "the note glows, and on we go")
        #expect(bench.session.phase == .success)
        #expect(bench.session.summary.screens.last!.rhythmRetries == 2)
        _ = bench.next()
        #expect(bench.session.retries == 0, "a fresh screen")
    }

    @Test func aShortNotePlayedLongInLevelFive() {
        var bench = onJudged("5.4") { item, line in
            item.notes.indices.dropLast().contains { item.notes[$0].value == .eighth && line.gaps[$0] == 0.5 }
        }
        let item = bench.session.item!
        let eighth = item.notes.indices.first { item.notes[$0].value == .eighth }!
        let cues = play(&bench) { $0 == eighth ? 2 : 1 }
        #expect(cues.contains(.rhythmGlow(note: eighth)) && speeches(cues).isEmpty, "\(item.id)")
        #expect(bench.session.phase == .replaying)
    }

    @Test func aWrongKeyOnTheRetryLeavesThePitchAsItWas() {
        var bench = onJudged("3.1") { firstHalf($0, $1) != nil }
        let half = firstHalf(bench.session.item!, bench.session.rhythmLine!)!
        _ = play(&bench) { $0 == half ? 0.5 : 1 }
        _ = bench.next()
        _ = bench.press(bench.wrongKey)
        let cues = bench.playScreen()
        #expect(bench.session.phase == .success)
        #expect(!cues.contains { if case .rhythmGlow = $0 { true } else { false } }, "no rhythm verdict after a wrong key")
        let screen = bench.session.summary.screens.last!
        #expect(screen.notes.allSatisfy { $0.firstTry } && screen.notes.allSatisfy { $0.wrongPresses == 0 })
        #expect(screen.rhythmRetries == 1)
    }

    @Test func roughlyRightInTheSessionIsQuiet() {
        var bench = onJudged("4.1")
        var rng = SeededRandom(seed: 3)
        var screens = 0
        for _ in 0..<200 where screens < 20 {
            if bench.session.rhythmLine != nil, !bench.session.isIntro {
                let cues = play(&bench, beat: 0.5) { _ in 1 + (Double(rng.next() % 1000) / 1000 - 0.5) * 0.4 }
                #expect(bench.session.phase == .success, "\(bench.session.item!.id)")
                #expect(!speeches(cues).contains { [.longOne, .shortOne, .holdLonger, .keepGoing].contains($0) })
                screens += 1
            } else {
                _ = bench.playScreen()
            }
            _ = bench.next()
        }
    }

    @Test func pianoGoneDuringThePlayBack() {
        var bench = onJudged("3.1") { firstHalf($0, $1) != nil }
        let half = firstHalf(bench.session.item!, bench.session.rhythmLine!)!
        _ = play(&bench) { $0 == half ? 0.5 : 1 }
        bench.now += 0.5
        #expect(bench.session.pianoDisconnected(at: bench.now) == [.paused, .say(.turnOnPiano)])
        bench.now += 2
        #expect(bench.session.replayFinished(at: bench.now).isEmpty, "the play back ended while paused")
        bench.now += 1
        _ = bench.session.pianoConnected(at: bench.now)
        #expect(bench.session.phase == .prompt && bench.session.noteIndex == 0, "back to the retry")
        _ = play(&bench)
        #expect(bench.session.phase == .success)
    }

    @Test func theFirstRhythmScreensOfLevelThreeArePlayedFirst() {
        let config = long
        var bench = Bench(engine(in: "3.1", config: config), seed: 8)
        var cues = bench.start()
        var demos: [Bool] = []
        for _ in 0..<80 where demos.count < 4 {
            if bench.session.rhythmLine != nil, !bench.session.isIntro {
                demos.append(cues.contains(.playPhrase(beat: config.demoBeat)))
                #expect(speeches(cues).isEmpty)
            } else {
                #expect(!cues.contains(.playPhrase(beat: config.demoBeat)), "only rhythm screens are played first")
            }
            _ = bench.playScreen()
            cues = bench.next()
        }
        #expect(demos == [true, true, false, false])
        #expect(bench.session.engine.state.rhythmDemos["3"] == 2)
        #expect(bench.session.summary.screens.filter { $0.wasRhythmDemo }.count == 2)
        // level 4 gets its own two
        var engine4 = bench.session.engine
        engine4.moveToLesson("4.1")
        #expect(engine4.wantsRhythmDemo)
        engine4.moveToLesson("5.1")
        #expect(!engine4.wantsRhythmDemo, "level 5's rhythm lessons open with their own lesson intro")
    }

    @Test func rhythmNeverHoldsBackNotes() {
        // level 3 notes unlock on pitch alone, however the rhythm goes
        var engine = engine(in: "3.1", config: long)
        var rng = SeededRandom(seed: 2)
        let start = engine.pool(.treble).count
        for _ in 0..<80 {
            let pick = engine.pickScreen(using: &rng)
            if let key = pick.intro { engine.intro(key); continue }
            engine.play(pick.item.notes.flatMap(\.keys), time: 1, rhythmOK: false, size: pick.size)
        }
        #expect(engine.pool(.treble).count == start + 2, "E5, F#5 and G5 all out, every rhythm a miss")
        #expect(!engine.isRhythmSolid)
    }
}
