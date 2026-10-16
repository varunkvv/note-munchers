import Testing
@testable import NoteCore

/// Generated rhythm must keep the rhythm judge's invariant: whole bars, 3+ notes, at
/// least two lengths (in a 2-note line any timing passes - context/notecore-design.md).
/// Round 1 checked this on a fixed curriculum; now it's a property of the generator.
@Suite struct RhythmGeneratorTests {
    let judge = RhythmJudge()
    static let sets: [[NoteValue]] = [[.quarter, .half], [.eighth, .quarter, .half]]

    /// Generated level 5 lines as the judge sees them (rests count into the gap).
    func generated(_ count: Int = 600) -> [RhythmLine] {
        var rng = SeededRandom(seed: 77)
        return (0..<count).map { i in
            let meter: Meter = i % 3 == 0 ? .threeFour : .fourFour
            return MasteryEngine.rhythmLine(MasteryEngine.rhythm(bars: 1 + i % 2, from: Self.sets[i % 2], meter: meter, using: &rng).bars)
        }
    }

    func run(_ line: RhythmLine, _ lengths: [Double]) -> RhythmResult {
        let p = performance(lengths)
        return judge.judge(line, onsets: p.onsets, release: p.release)
    }

    func name(_ line: RhythmLine) -> String {
        zip(line.values, line.gaps).map { $0.rawValue + ($1 > $0.beats ? "+r" : "") }.joined(separator: " ")
    }

    @Test func wholeBarsThreePlusNotesMixedLengths() {
        var rng = SeededRandom(seed: 1)
        var meters = Set<Meter>()
        var rests = 0
        for set in Self.sets {
            for bars in 1...2 {
                for meter in Meter.allCases {
                    for _ in 0..<300 {
                        let line = MasteryEngine.rhythm(bars: bars, from: set, meter: meter, using: &rng)
                        meters.insert(line.meter)
                        let values = line.bars.flatMap(\.values)
                        rests += line.bars.filter { !$0.rests.isEmpty }.count
                        let notes = MasteryEngine.apply(line.bars, to: values.map { _ in WrittenNote(.treble, [Pitch(.g, 4)]) })
                        // the item checks every bar adds up to the meter
                        let item = PracticeItem(notes, bars: line.bars.map(\.count), meter: line.meter)
                        #expect(item.totalBeats == Double(line.meter.beats * bars), "\(RhythmFixtures.name(values))")
                        #expect(values.count >= 3, "\(RhythmFixtures.name(values))")
                        #expect(Set(values).count >= 2, "\(RhythmFixtures.name(values))")
                        #expect(Set(values).isSubset(of: Set(set + [.whole, .dottedHalf])))
                        #expect(!values.contains(.whole) || line.meter == .fourFour)
                        #expect(!values.contains(.dottedHalf) || line.meter == .threeFour)
                        #expect(line.bars.allSatisfy { $0.rests.allSatisfy { $0 == .quarter } })
                        let eighths = values.filter { $0 == .eighth }.count
                        #expect(item.beamedPairStarts.count * 2 == eighths, "eighths come as beamed pairs on a beat")
                        #expect(item.beamedPairStarts.count <= bars, "at most one pair a bar")
                        #expect(item.barLinesAfter.count == bars - 1)
                        #expect(item.rhythmLine(.all) != nil, "every level 5 line can be judged: \(item.id)")
                    }
                }
            }
        }
        #expect(meters == Set(Meter.allCases))
        #expect(rests > 100, "a bar ends on a quarter rest now and then: \(rests)")
    }

    @Test func oneBarOfQuartersAndHalvesIn34GivesWayTo44() {
        // q q q is all one length and h q is two notes: neither can be judged
        var rng = SeededRandom(seed: 2)
        for _ in 0..<50 {
            #expect(MasteryEngine.rhythm(bars: 1, from: [.quarter, .half], meter: .threeFour, using: &rng).meter == .fourFour)
        }
    }

    @Test func everyGeneratedLinePassesAtAnyTempo() {
        for line in generated() {
            for beat in [0.3, 0.6, 1.2] {
                #expect(run(line, line.gaps.map { $0 * beat }).isOK, "\(name(line)) at \(beat)")
            }
        }
    }

    @Test func everyNoteTheSameLengthNeverPasses() {
        for line in generated() {
            for length in [0.3, 0.6, 1.0] {
                #expect(!run(line, line.values.map { _ in length }).isOK, "\(name(line)) at \(length)s each")
            }
        }
    }

    @Test func everyShortenedHalfIsTooShort() {
        for line in generated() {
            for (i, value) in line.values.enumerated() where value == .half && line.gaps[i] == 2 {
                var lengths = line.gaps.map { $0 * 0.6 }
                lengths[i] = NoteValue.quarter.beats * 0.6
                #expect(run(line, lengths).verdicts[i] == .tooShort, "\(name(line)) note \(i)")
            }
        }
    }

    @Test func roughlyRightTimingPasses() {
        var rng = SeededRandom(seed: 5)
        for (n, line) in generated(300).enumerated() {
            let beat = 0.4 + Double(rng.next() % 1000) / 1000
            let lengths = line.gaps.map { $0 * beat * (1 + (Double(rng.next() % 1000) / 1000 - 0.5) * 0.4) }
            #expect(run(line, lengths).isOK, "\(name(line)) trial \(n)")
        }
    }
}

@Suite struct TextureTests {
    var stay: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return config
    }

    /// An engine in `lesson` that has had the lesson's intro screen.
    func ready(_ id: LessonID) -> MasteryEngine {
        var engine = engine(in: id, config: stay)
        var rng = SeededRandom(seed: 1)
        let pick = engine.pickScreen(using: &rng)
        #expect(pick.isLessonIntro, "\(id) opens with its intro")
        engine.playPick(pick)
        return engine
    }

    @Test func dyadLinesMixSinglesAndTwoAtOnce() {
        var engine = ready("4.3")
        var rng = SeededRandom(seed: 2)
        var dyads = 0, singles = 0
        var intervals = Set<Int>()
        for _ in 0..<100 {
            let pick = engine.pickScreen(using: &rng)
            #expect(pick.item.notes.contains { $0.isChord }, "\(pick.item.id)")
            for column in pick.item.notes {
                if column.isChord {
                    dyads += 1
                    #expect(column.pitches.count == 2)
                    let d = column.pitches[1].diatonicIndex - column.pitches[0].diatonicIndex
                    intervals.insert(d)
                    #expect(column.keys.allSatisfy { engine.playable($0.clef).contains($0) })
                } else {
                    singles += 1
                }
            }
            engine.playPick(pick)
        }
        #expect(dyads > 50 && singles > 50, "\(dyads) dyads, \(singles) singles")
        #expect(intervals == [2, 3, 4], "thirds, fourths and fifths")
    }

    @Test func thirdsAndFifthsLessonsStayThere() {
        var engine = ready("4.1")
        var rng = SeededRandom(seed: 3)
        for _ in 0..<60 {
            for column in engine.pickScreen(using: &rng).item.notes where column.isChord {
                let d = column.pitches[1].diatonicIndex - column.pitches[0].diatonicIndex
                #expect(d == 2 || d == 4)
            }
        }
    }

    @Test func aDyadCountsForBothNotes() {
        var bench = Bench(ready("4.1"), seed: 4)
        _ = bench.start()
        while !bench.expected.indices.contains(1) {
            _ = bench.playCurrent()
            if bench.session.phase == .success { _ = bench.next() }
        }
        let dyad = bench.session.item!.notes[bench.session.noteIndex].keys
        while bench.session.phase.isPlaying { _ = bench.playCurrent() }
        let recorded = bench.session.summary.screens.last!.notes.map(\.itemID)
        #expect(dyad.allSatisfy { recorded.contains($0.id) })
    }

    @Test func dyadHintLooksAtBothKeys() {
        var bench = Bench(ready("4.1"), seed: 4)
        _ = bench.start()
        while !bench.expected.indices.contains(1) {
            _ = bench.playCurrent()
            if bench.session.phase == .success { _ = bench.next() }
        }
        // a dyad is judged when its chord window closes: by the next key, or a tick
        let wrong = Pitch(midi: bench.expected[0].midi + 1)
        var cues: [Cue] = []
        for _ in 0..<3 {
            cues += bench.press(wrong)
            cues += bench.tick(at: bench.now + 0.2)
        }
        #expect(cues.contains(.say(.hintLook)))
        #expect(bench.session.keyboardHint == bench.expected)
    }

    @Test func dyadLessonOpensWithTwoAtOnce() {
        var bench = Bench(engine(in: "4.1"), seed: 1)
        let cues = bench.start()
        #expect(bench.session.isLessonIntro)
        let dyad = bench.session.item!.notes[0].pitches
        #expect(dyad.count == 2)
        #expect(cues.suffix(2) == [.say(.twoAtOnce), .playPitches(dyad)])
        #expect(bench.session.keyboardHint == dyad, "we do: both keys lit")
        _ = bench.playScreen()
        #expect(bench.session.summary.notesPlayed == 0, "the intro doesn't count")
        _ = bench.next()
        #expect(!bench.session.isLessonIntro, "once per lesson")
    }

    @Test func rhythmLessonOpensWithListen() {
        var bench = Bench(engine(in: "5.1"), seed: 1)
        let cues = bench.start()
        #expect(bench.session.isLessonIntro)
        #expect(bench.session.item!.meter != nil)
        #expect(cues.suffix(2) == [.say(.listen), .playPhrase(beat: NoteCoreConfig.default.demoBeat)])
    }

    @Test func oneNoteRhythmScreens() {
        var engine = ready("5.2")
        var rng = SeededRandom(seed: 5)
        var sawEighths = false
        for _ in 0..<60 {
            let pick = engine.pickScreen(using: &rng)
            let item = pick.item
            #expect(Set(item.notes.flatMap(\.pitches)).count == 1, "one key: only the rhythm is new")
            #expect(item.totalBeats == Double(item.meter!.beats * pick.size), "size counts bars")
            sawEighths = sawEighths || item.values.contains(.eighth)
            engine.playPick(pick)
        }
        #expect(sawEighths)
        #expect(engine.screenSize == 2, "grows to 2 bars")
    }

    @Test func rhythmLinesMovePitchToo() {
        var engine = ready("5.3")
        var rng = SeededRandom(seed: 6)
        var moving = 0
        for _ in 0..<40 {
            let item = engine.pickScreen(using: &rng).item
            if Set(item.notes.flatMap(\.pitches)).count > 1 { moving += 1 }
            #expect(item.values.count >= 3 && Set(item.values).count >= 2)
        }
        #expect(moving > 30)
    }

    @Test func grandStaffRhythmIsABarOnEachStaff() {
        var engine = ready("5.5")
        var rng = SeededRandom(seed: 7)
        for _ in 0..<40 {
            let item = engine.pickScreen(using: &rng).item
            #expect(item.layout == .grand)
            #expect(item.totalBeats == Double(2 * item.meter!.beats))
            #expect(item.clefs.count == 2, "\(item.id)")
            #expect(item.barLinesAfter.count == 1)
            let split = item.barLinesAfter[0]
            #expect(Set(item.notes[...split].map(\.clef)).count == 1 && Set(item.notes[(split + 1)...].map(\.clef)).count == 1)
            engine.playPick(Pick(item: item, intro: nil, isLessonIntro: false, usedStrongest: false, isStretch: false, size: 2))
        }
    }

    @Test func noStretchOnRhythm() {
        var engine = ready("5.3")
        var rng = SeededRandom(seed: 8)
        for _ in 0..<200 {
            let pick = engine.pickScreen(using: &rng)
            #expect(!pick.isStretch)
            engine.playPick(pick)
        }
    }

    @Test func aRhythmLessonWaitsForItsRhythm() {
        var engine = engine(in: "5.1")
        var rng = SeededRandom(seed: 9)
        engine.playPick(engine.pickScreen(using: &rng)) // the lesson intro
        for _ in 0..<30 {
            let pick = engine.pickScreen(using: &rng)
            engine.play(pick.item.notes.flatMap(\.keys), time: 1, rhythmOK: false, size: pick.size)
        }
        #expect(engine.lesson.id == "5.1", "notes are solid, the rhythm isn't")
        for _ in 0..<6 {
            let pick = engine.pickScreen(using: &rng)
            engine.play(pick.item.notes.flatMap(\.keys), time: 1, rhythmOK: true, size: pick.size)
        }
        #expect(engine.lesson.id == "5.2")
    }

    @Test func fullRhythmSessionThroughTheJudge() {
        var bench = Bench(engine(in: "5.4"), seed: 3)
        _ = bench.start()
        var judged = 0
        for _ in 0..<12 where bench.session.phase != .done {
            let item = bench.session.item!
            // play it in time at 0.5s a beat, holding the last note
            for (i, note) in item.notes.enumerated() {
                _ = bench.press(note.pitches[0], after: i == 0 ? 0.8 : item.gapBeats[i - 1] * 0.5)
            }
            _ = bench.release(item.notes.last!.pitches[0], after: item.notes.last!.value.beats * 0.5)
            #expect(bench.session.phase == .success, "\(item.id)")
            if let rhythm = bench.session.summary.screens.last?.rhythm {
                judged += 1
                #expect(rhythm.isOK, "\(item.id)")
            }
            _ = bench.next()
        }
        #expect(judged >= 10)
    }
}
