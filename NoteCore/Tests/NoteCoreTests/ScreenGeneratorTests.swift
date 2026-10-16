import Testing
@testable import NoteCore

@Suite struct ScreenGeneratorTests {
    /// Picks `count` screens, playing each one right (intros as intros).
    func run(_ engine: inout MasteryEngine, _ count: Int, seed: UInt64 = 1, style: PickStyle = .normal,
             right: (PracticeItem) -> Bool = { _ in true }) -> [Pick] {
        var rng = SeededRandom(seed: seed)
        var picks: [Pick] = []
        for _ in 0..<count {
            let pick = engine.pickScreen(style, using: &rng)
            picks.append(pick)
            if let intro = pick.intro {
                engine.intro(intro)
            } else {
                engine.play(pick.item.notes.flatMap(\.keys), right: right(pick.item), time: 1.2, reason: pick.isStretch ? .stretch : .normal)
            }
        }
        return picks
    }

    @Test func screensUseHisSizeAndOnlyNotesHeHasMet() {
        var engine = engine(in: "1.2")
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
            var engine = engine(in: "1.4")
            let picks = run(&engine, 300, seed: seed)
            let columns = picks.flatMap { $0.item.notes.map(MasteryEngine.columnID) }
            #expect(maxRun(columns) <= 2, "seed \(seed)")
        }
    }

    @Test func noScreenComesBackWhileItsRecent() {
        var engine = engine(in: "1.2")
        let ids = run(&engine, 300).map(\.item.id)
        for (i, id) in ids.enumerated() where i >= 1 {
            // 5 notes a clef, 2-3 per screen: 25+ screens per clef, so the full window of 10
            #expect(!ids[max(0, i - 10)..<i].contains(id), "screen \(i) \(id) came back too soon")
        }
    }

    @Test func aTinyPoolOnlyAvoidsTheLastScreen() {
        // 1.1 at 1 note per screen with 3 notes per clef: only 3 screens per clef exist
        var engine = engine(in: "1.1")
        let picks = run(&engine, 40)
        let ids = picks.prefix(8).map(\.item.id)
        for (a, b) in zip(ids, ids.dropFirst()) {
            #expect(a != b)
        }
    }

    @Test func contourMixesStepsSkipsAndRepeats() {
        var engine = engine(in: "1.4")
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
        var engine = engine(in: "1.4")
        let ids = Set(run(&engine, 200).map(\.item.id))
        #expect(ids.count > 80, "\(ids.count) different screens in 200")
    }

    @Test func clefsAlternateNeverThreeInARow() {
        var engine = engine(in: "1.4")
        let clefs = run(&engine, 400).map { $0.item.clefs[0] }
        #expect(maxRun(clefs) <= 2)
        let treble = clefs.filter { $0 == .treble }.count
        #expect(treble > 120 && treble < 280, "about even when he's even: \(treble) of 400")
    }

    @Test func theWeakerClefGetsMoreScreens() {
        var engine = engine(in: "1.4")
        for key in engine.pool(.treble) { for _ in 0..<4 { engine.play(key, time: 1) } } // treble box 5, bass box 1
        let clefs = run(&engine, 30, right: { _ in false }).map { $0.item.clefs[0] }
        let bass = clefs.filter { $0 == .bass }.count
        // never 3 in a row caps bass at 20 of 30
        #expect(bass >= 16, "bass is weaker: \(bass) of 30")
    }

    @Test func theFocusClefGetsAboutTwoThirds() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000 // stay in 1.2
        var engine = engine(in: "1.2", config: config)
        let clefs = run(&engine, 300).map { $0.item.clefs[0] }
        let treble = clefs.filter { $0 == .treble }.count
        #expect(treble > 170 && treble < 240, "treble focus: \(treble) of 300")
    }

    @Test func introsAreOneNoteAndSpacedOut() {
        var engine = MasteryEngine(state: MasteryState(seed: 11))
        let picks = run(&engine, 14)
        let intros = picks.compactMap(\.intro)
        #expect(intros.count == 6, "3 per clef")
        for pick in picks where pick.intro != nil {
            #expect(pick.item.notes.count == 1)
            #expect(pick.item.keys == [pick.intro!])
        }
        // the first two on each clef can come back to back. after that there's reading in between
        var met: [Clef: Int] = [:]
        for (a, b) in zip(picks, picks.dropFirst()) {
            if let intro = a.intro { met[intro.clef, default: 0] += 1 }
            if a.intro != nil, let next = b.intro {
                #expect(met[next.clef, default: 0] < 2, "\(next) came right after another intro")
            }
        }
    }

    @Test func newestNotesGetAboutOneNoteInFour() {
        var engine = engine(in: "1.1")
        // open the treble gate: the pair comes in
        for key in engine.pool(.treble) { for _ in 0..<3 { engine.play(key, time: 1) } }
        let pair = engine.newestBatch(.treble)
        #expect(pair.count == 2)
        for key in pair { engine.intro(key) }
        var rng = SeededRandom(seed: 5)
        var trebleScreens = 0, withNewest = 0
        for _ in 0..<200 {
            let pick = engine.pickScreen(using: &rng)
            guard pick.item.clefs == [.treble] else { continue }
            trebleScreens += 1
            if pick.item.keys.contains(where: pair.contains) { withNewest += 1 }
        }
        let share = Double(withNewest) / Double(trebleScreens)
        print("newest pair on \(withNewest) of \(trebleScreens) treble screens: \(share)")
        // 1 note a screen: the pair gets about 1 screen in 4 between them
        #expect(share > 0.15 && share < 0.35, "\(share)")
    }

    @Test func stretchOnlyWhenHesDoingWell() {
        var good = engine(in: "1.2")
        let stretches = run(&good, 400).filter(\.isStretch)
        #expect(stretches.count > 15 && stretches.count < 80, "about 1 in 8 once he's doing well: \(stretches.count)")
        #expect(stretches.allSatisfy { $0.item.notes.count <= good.lesson.sizes.upperBound + 1 })

        var struggling = engine(in: "1.2")
        let none = run(&struggling, 200, right: { _ in false }).filter(\.isStretch)
        #expect(none.isEmpty)
    }

    @Test func strongestUsesHisTopBoxes() {
        var engine = engine(in: "1.4")
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
        var engine = engine(in: "1.4")
        var rng = SeededRandom(seed: 3)
        let pick = engine.pickScreen(.strongest, using: &rng)
        #expect(!pick.usedStrongest)
    }

    @Test func sameSeedSameScreens() {
        var a = engine(in: "1.1"), b = engine(in: "1.1")
        #expect(run(&a, 60, seed: 8) == run(&b, 60, seed: 8))
        var c = engine(in: "1.1")
        #expect(run(&c, 60, seed: 9) != run(&a, 60, seed: 8))
    }

    @Test func barsSplitEvenly() {
        #expect(MasteryEngine.bars(1) == [1])
        #expect(MasteryEngine.bars(4) == [4])
        #expect(MasteryEngine.bars(5) == [3, 2])
        #expect(MasteryEngine.bars(8) == [4, 4])
        #expect(MasteryEngine.bars(9) == [3, 3, 3])
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
