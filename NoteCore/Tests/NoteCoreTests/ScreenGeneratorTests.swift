import Testing
@testable import NoteCore

@Suite struct ScreenGeneratorTests {
    /// In `lesson` with every note met, staying there however well he plays.
    func stayIn(_ lesson: LessonID) -> MasteryEngine {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return engine(in: lesson, config: config)
    }

    /// Picks `count` screens, playing each one right (intros as intros).
    func run(_ engine: inout MasteryEngine, _ count: Int, seed: UInt64 = 1, style: PickStyle = .normal,
             right: (PracticeItem) -> Bool = { _ in true }) -> [Pick] {
        var rng = SeededRandom(seed: seed)
        var picks: [Pick] = []
        for _ in 0..<count {
            let pick = engine.pickScreen(style, using: &rng)
            picks.append(pick)
            engine.playPick(pick, right: right(pick.item), time: 1.2)
        }
        return picks
    }

    @Test func screensUseHisSizeAndOnlyNotesHeHasMet() {
        var engine = stayIn("1.2")
        var rng = SeededRandom(seed: 2)
        for _ in 0..<100 {
            let pick = engine.pickScreen(using: &rng)
            let item = pick.item
            #expect(pick.intro == nil)
            #expect(item.notes.count == engine.screenSize || pick.isStretch)
            #expect(item.clefs.count == 1, "one clef per screen in an alternating lesson")
            #expect(item.layout == (item.clefs[0] == .treble ? .treble : .bass))
            #expect(item.keys.allSatisfy { engine.playable($0.clef).contains($0) })
            #expect(item.keySignature == .none)
        }
    }

    @Test func neverTheSameKeyThreeTimesInARow() {
        for seed: UInt64 in 1...5 {
            var engine = stayIn("1.4")
            let picks = run(&engine, 300, seed: seed)
            let columns = picks.flatMap { $0.item.notes.map(MasteryEngine.columnID) }
            #expect(maxRun(columns) <= 2, "seed \(seed)")
        }
    }

    @Test func noScreenComesBackWhileItsRecent() {
        var engine = stayIn("2.1")
        let ids = run(&engine, 300).map(\.item.id)
        for (i, id) in ids.enumerated() where i >= 1 {
            // 5 notes a clef, 3-4 per screen: 125+ screens per clef, so the full window of 10
            #expect(!ids[max(0, i - 10)..<i].contains(id), "screen \(i) \(id) came back too soon")
        }
    }

    @Test func aTinyPoolOnlyAvoidsTheLastScreen() {
        // 1.1 at 2 notes a screen with G and A on each clef: only 4 screens per clef exist
        var engine = stayIn("1.1")
        let picks = run(&engine, 40)
        let ids = picks.prefix(8).map(\.item.id)
        for (a, b) in zip(ids, ids.dropFirst()) {
            #expect(a != b)
        }
    }

    @Test func contourMixesStepsSkipsAndRepeats() {
        var engine = stayIn("3.1")
        var steps = 0, skips = 0, repeats = 0
        for pick in run(&engine, 300) {
            let keys = pick.item.notes.flatMap(\.keys)
            for (a, b) in zip(keys, keys.dropFirst()) {
                let d = abs(a.pitch.diatonicIndex - b.pitch.diatonicIndex)
                if d == 0 { repeats += 1 } else if d == 1 { steps += 1 } else { skips += 1 }
            }
        }
        #expect(steps > 100 && skips > 100 && repeats > 20, "steps \(steps) skips \(skips) repeats \(repeats)")
        #expect(repeats < steps && repeats < skips)
    }

    @Test func screensVaryInShape() {
        var engine = stayIn("1.4")
        let ids = Set(run(&engine, 200).map(\.item.id))
        #expect(ids.count > 80, "\(ids.count) different screens in 200")
    }

    /// Asked for no clef (engine-only callers), one-clef lessons lean to the weaker clef.
    /// Sessions ask for a clef: ClefRunTests.
    @Test func theWeakerClefGetsMoreScreens() {
        var engine = stayIn("1.4")
        for key in engine.pool(.treble) { for _ in 0..<4 { engine.play(key, time: 1) } } // treble box 5, bass box 1
        let clefs = run(&engine, 30, right: { _ in false }).map { $0.item.clefs[0] }
        let bass = clefs.filter { $0 == .bass }.count
        #expect(bass >= 18, "bass is weaker: \(bass) of 30")
    }

    /// Level 1: G first, then a couple of screens of G alone, then A. Intros are one
    /// note, in order, and spaced out on their clef.
    @Test func levelOneIntroducesGThenA() {
        for seed: UInt64 in 1...5 {
            var engine = MasteryEngine(state: MasteryState(seed: seed))
            var rng = SeededRandom(seed: seed)
            var picks: [Pick] = []
            for _ in 0..<12 {
                let pick = engine.pickScreen(clef: .treble, using: &rng)
                picks.append(pick)
                engine.playPick(pick, time: 1.2)
            }
            let ids = picks.map { $0.intro.map { "intro \($0.pitch.name)" } ?? $0.item.notes.flatMap(\.keys).map(\.pitch.name).joined(separator: " ") }
            #expect(ids[0] == "intro G4", "\(ids)")
            #expect(ids[1] == "G4 G4" && ids[2] == "G4 G4", "one note is enough for 2-note screens: \(ids)")
            #expect(ids[3] == "intro A4", "\(ids)")
            #expect(picks[4...].allSatisfy { $0.intro == nil && $0.item.notes.count >= 2 })
            for pick in picks where pick.intro != nil {
                #expect(pick.item.notes.count == 1 && pick.item.keys == [pick.intro!])
            }
        }
    }

    /// Repeats are fine on a clef with one note (maxRepeats can't hold), and hold again
    /// once there are two.
    @Test func oneNoteOnAClefRepeatsTwoDont() {
        var engine = MasteryEngine(state: MasteryState(seed: 1))
        var rng = SeededRandom(seed: 1)
        var columns: [ItemID] = []
        for _ in 0..<30 {
            let pick = engine.pickScreen(clef: .treble, using: &rng)
            if engine.playable(.treble).count >= 2, pick.intro == nil {
                columns += pick.item.notes.map(MasteryEngine.columnID)
            }
            engine.playPick(pick)
        }
        #expect(columns.count > 40)
        #expect(maxRun(columns) <= 2, "\(columns)")
    }

    /// After an intro on a clef, `introSpacing` screens on that clef before its next one.
    @Test func introsAreSpacedOutOnTheirClef() {
        var engine = MasteryEngine(state: MasteryState(seed: 3))
        var rng = SeededRandom(seed: 3)
        var sinceIntro: [Clef: Int] = [:]
        var intros = 0
        for _ in 0..<20 {
            let pick = engine.pickScreen(using: &rng)
            let clef = pick.item.clefs[0]
            if pick.intro != nil {
                intros += 1
                if let gap = sinceIntro[clef] { #expect(gap >= 2, "\(pick.intro!) after \(gap) screens") }
                sinceIntro[clef] = 0
            } else if let gap = sinceIntro[clef] {
                sinceIntro[clef] = gap + 1
            }
            engine.playPick(pick)
        }
        #expect(intros == 4, "G and A on each clef")
    }

    @Test func newestNotesGetAboutOneNoteInFour() {
        // 3.1: one of E5 / F#5 / G5 joins treble G position
        var engine = stayIn("3.1")
        let newest = engine.newestBatch(.treble)
        #expect(newest.count == 1)
        var rng = SeededRandom(seed: 5)
        var notes = 0, newestNotes = 0
        for _ in 0..<300 {
            let keys = engine.pickScreen(clef: .treble, using: &rng).item.notes.flatMap(\.keys)
            notes += keys.count
            newestNotes += keys.filter(newest.contains).count
        }
        let share = Double(newestNotes) / Double(notes)
        print("newest note: \(newestNotes) of \(notes) treble notes: \(share)")
        #expect(share > 0.18 && share < 0.32, "\(share)")
    }

    /// Level 1 drills its new note harder: about 1 in 3 of the notes on its clef.
    @Test func aDrillLessonsNewNoteGetsAboutOneInThree() {
        for (id, new) in [("1.2", key("treble:B4")), ("1.4", key("treble:D5"))] {
            var engine = stayIn(id)
            #expect(engine.newestBatch(.treble) == [new])
            var rng = SeededRandom(seed: 5)
            var notes = 0, newestNotes = 0
            for _ in 0..<300 {
                let keys = engine.pickScreen(clef: .treble, using: &rng).item.notes.flatMap(\.keys)
                notes += keys.count
                newestNotes += keys.filter { $0 == new }.count
            }
            let share = Double(newestNotes) / Double(notes)
            print("\(id): \(new) is \(newestNotes) of \(notes) treble notes: \(share)")
            #expect(share > 0.26 && share < 0.4, "\(id): \(share)")
        }
    }

    /// Level 1 reads steps and repeats, a third the only skip (a piano teacher's review).
    @Test func levelOneMovesByStepsRepeatsAndThirds() {
        for id in ["1.1", "1.2", "1.3", "1.4"] {
            var engine = stayIn(id)
            var moves: [Int: Int] = [:]
            for pick in run(&engine, 300) {
                let keys = pick.item.notes.flatMap(\.keys)
                for (a, b) in zip(keys, keys.dropFirst()) {
                    moves[abs(a.pitch.diatonicIndex - b.pitch.diatonicIndex), default: 0] += 1
                }
            }
            let total = moves.values.reduce(0, +)
            print("\(id) moves (letters: count): \(moves.sorted { $0.key < $1.key })")
            #expect(moves.keys.allSatisfy { $0 <= 2 }, "\(id): nothing wider than a third: \(moves)")
            let stepsAndRepeats = Double((moves[0] ?? 0) + (moves[1] ?? 0)) / Double(total)
            #expect(stepsAndRepeats > 0.7, "\(id): mostly steps and repeats: \(moves)")
            if id != "1.1" { #expect((moves[2] ?? 0) > 0, "\(id): a third now and then: \(moves)") }
        }
        // level 2 is unchanged: skips lessons still skip a fourth or a fifth
        var skips = stayIn("2.2")
        let wide = run(&skips, 200).contains { pick in
            let keys = pick.item.notes.flatMap(\.keys)
            return zip(keys, keys.dropFirst()).contains { abs($0.pitch.diatonicIndex - $1.pitch.diatonicIndex) > 2 }
        }
        #expect(wide)
    }

    @Test func stretchOnlyWhenHesDoingWell() {
        var good = stayIn("1.2")
        let stretches = run(&good, 400).filter(\.isStretch)
        #expect(stretches.count > 15 && stretches.count < 80, "about 1 in 8 once he's doing well: \(stretches.count)")
        #expect(stretches.allSatisfy { $0.item.notes.count <= good.lesson.sizes.upperBound + 1 })

        var struggling = stayIn("1.2")
        let none = run(&struggling, 200, right: { _ in false }).filter(\.isStretch)
        #expect(none.isEmpty)
    }

    @Test func strongestUsesHisTopBoxes() {
        var engine = stayIn("1.4")
        let strong = [key("treble:G4"), key("treble:A4"), key("bass:B2"), key("bass:C3")]
        for key in strong { for _ in 0..<4 { engine.play(key, time: 1) } }
        for key in engine.pool where !strong.contains(key) { engine.play(key, time: 1) } // box 2
        var rng = SeededRandom(seed: 3)
        for _ in 0..<40 {
            let pick = engine.pickScreen(.strongest, using: &rng)
            #expect(pick.usedStrongest)
            #expect(pick.item.keys.allSatisfy(strong.contains), "\(pick.item.id)")
        }
    }

    @Test func strongestFallsBackWhenNothingIsPlayedYet() {
        var engine = stayIn("1.4")
        var rng = SeededRandom(seed: 3)
        let pick = engine.pickScreen(.strongest, using: &rng)
        #expect(!pick.usedStrongest)
    }

    @Test func sameSeedSameScreens() {
        var a = stayIn("1.1"), b = stayIn("1.1")
        #expect(run(&a, 60, seed: 8) == run(&b, 60, seed: 8))
        var c = stayIn("1.1")
        #expect(run(&c, 60, seed: 9) != run(&a, 60, seed: 8))
    }

    @Test func barSizesHoldOneNoteABeatInOneOrTwoBars() {
        var rng = SeededRandom(seed: 4)
        for meter in Meter.allCases {
            for count in 1...9 {
                var shapes = Set<[Int]>()
                for _ in 0..<200 {
                    let sizes = MasteryEngine.barSizes(count, meter: meter, twoBars: false, using: &rng)
                    shapes.insert(sizes)
                    #expect(sizes.reduce(0, +) == min(count, MasteryEngine.maxNotes(meter)))
                    #expect(sizes.allSatisfy { (1...meter.beats).contains($0) }, "\(sizes) in \(meter.rawValue)")
                    #expect(sizes.count <= 2)
                }
                if count == 1 { #expect(shapes == [[1]]) }
                if count == 3, meter == .fourFour { #expect(shapes.contains([3]) && shapes.contains { $0.count == 2 }, "one bar or two") }
            }
            #expect(MasteryEngine.barSizes(5, meter: meter, twoBars: true, using: &rng) == [3, 2])
        }
    }

    @Test func everyReadingBarPatternFillsItsBar() {
        for meter in Meter.allCases {
            for notes in 1...meter.beats {
                for (rhythm, weight) in MasteryEngine.readingBars(notes: notes, meter: meter) {
                    #expect(rhythm.beats == Double(meter.beats))
                    #expect(rhythm.count == notes && weight > 0)
                    #expect(!rhythm.values.contains(.eighth), "eighths only in level 5")
                }
            }
        }
    }

    @Test func screenIDs() {
        let g4 = key("treble:G4"), a4 = key("treble:A4"), g2 = key("bass:G2")
        #expect(PracticeItem(g4).id == "treble:G4")
        #expect(PracticeItem([WrittenNote(g4), WrittenNote(a4)]).id == "treble:G4-A4")
        let grand = PracticeItem([WrittenNote(g4), WrittenNote(a4), WrittenNote(g2)], bars: [2, 1])
        #expect(grand.layout == .grand)
        #expect(grand.id == "treble:G4-A4 bass:G2")
        #expect(grand.barLinesAfter == [1])
        #expect(grand.keys == [g4, a4, g2])
    }
}
