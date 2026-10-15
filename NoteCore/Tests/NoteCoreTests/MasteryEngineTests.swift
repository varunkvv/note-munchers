import Foundation
import Testing
@testable import NoteCore

extension MasteryEngine {
    /// Records a non-intro attempt.
    @discardableResult
    mutating func play(_ id: ItemID, right: Bool = true, time: Double = 1.5, rhythmOK: Bool? = nil) -> MasteryUpdate {
        var rhythm: RhythmResult?
        if let ok = rhythmOK {
            rhythm = RhythmResult(verdicts: [ok ? .ok : .tooShort], beat: 0.6)
        }
        return record(AttemptResult(itemID: id, unit: state.unit, firstTry: right, wrongPresses: right ? 0 : 1, responseTime: time, rhythm: rhythm))
    }

    mutating func intro(_ id: ItemID) {
        record(AttemptResult(itemID: id, unit: state.unit, wasIntro: true, firstTry: true, responseTime: 3))
    }

    /// Picks and plays `count` items with a player that answers per item.
    /// Returns the picked ids in order.
    @discardableResult
    mutating func simulate(_ count: Int, seed: UInt64, player: (PracticeItem) -> (right: Bool, time: Double, rhythmOK: Bool?) = { _ in (true, 1.0, true) }) -> [ItemID] {
        var rng = SeededRandom(seed: seed)
        var picks: [ItemID] = []
        for _ in 0..<count {
            let item = pickNext(using: &rng)
            picks.append(item.id)
            if needsIntro(item) {
                intro(item.id)
            } else {
                let answer = player(item)
                play(item.id, right: answer.right, time: answer.time, rhythmOK: item.isRhythm ? answer.rhythmOK : nil)
            }
        }
        return picks
    }
}

func maxRun(_ ids: [ItemID]) -> Int {
    var best = 0, run = 0
    var last: ItemID?
    for id in ids {
        run = id == last ? run + 1 : 1
        last = id
        best = max(best, run)
    }
    return best
}

@Suite struct MasteryEngineTests {
    let c4 = "treble:C4", g4 = "treble:G4", e4 = "treble:E4", d4 = "treble:D4", f4 = "treble:F4"

    @Test func freshEngineStartsUnitOneWithCAndG() {
        let engine = MasteryEngine()
        #expect(engine.unit.number == 1)
        #expect(engine.pool.map(\.id) == [c4, g4])
        #expect(engine.newestBatch.map(\.id) == [c4, g4])
    }

    @Test func leitnerMovesOneBoxAndStaysInRange() {
        var engine = MasteryEngine()
        engine.play(c4, right: false)
        #expect(engine.stats(for: c4).box == 1)
        for _ in 0..<10 { engine.play(c4) }
        #expect(engine.stats(for: c4).box == 5)
        engine.play(c4, right: false)
        #expect(engine.stats(for: c4).box == 4)
        #expect(engine.stats(for: c4).recent.count == 8, "only the last 8 are kept")
    }

    @Test func solidIsSevenOfEightWithMedianUnderFourSeconds() {
        var engine = MasteryEngine()
        // slow enough to stay off the fast track
        for i in 0..<8 { engine.play(c4, right: i != 3, time: 3.0) }
        #expect(engine.isPitchSolid(c4))

        var twoMisses = MasteryEngine()
        for i in 0..<8 { twoMisses.play(c4, right: i != 3 && i != 5, time: 3.0) }
        #expect(!twoMisses.isPitchSolid(c4))

        var slow = MasteryEngine()
        for _ in 0..<8 { slow.play(c4, time: 4.5) }
        #expect(!slow.isPitchSolid(c4), "all right but median 4.5s")
    }

    @Test func fastTrackFiveInARowUnderTwoSeconds() {
        var engine = MasteryEngine()
        for _ in 0..<4 { engine.play(c4, time: 1.2) }
        #expect(!engine.isPitchSolid(c4))
        engine.play(c4, time: 1.9)
        #expect(engine.isPitchSolid(c4), "solid after 5, no need to wait for 8")

        var oneSlow = MasteryEngine()
        for t in [1.2, 1.2, 2.5, 1.2, 1.2] { oneSlow.play(c4, time: t) }
        #expect(!oneSlow.isPitchSolid(c4), "one of the five was over 2s")

        var broken = MasteryEngine()
        for right in [true, true, false, true, true] { broken.play(c4, right: right, time: 1) }
        #expect(!broken.isPitchSolid(c4))
    }

    @Test func unlockNeedsNewestSolidAndNobodyBelowBoxThree() {
        var engine = MasteryEngine()
        // both of the starting pair are newest. C solid, G not yet
        for _ in 0..<5 { engine.play(c4, time: 1) }
        #expect(!engine.isGateOpen)
        for _ in 0..<4 { engine.play(g4, time: 1) }
        let update = engine.play(g4, time: 1)
        #expect(update.unlocked == [e4])
        #expect(engine.newestBatch.map(\.id) == [e4])

        // E gets solid, but C slipped to box 2: the gate stays shut
        engine.play(c4, right: false)
        engine.play(c4, right: false)
        engine.play(c4, right: false)
        #expect(engine.stats(for: c4).box == 2)
        for _ in 0..<5 { engine.play(e4, time: 1) }
        #expect(engine.isPitchSolid(e4))
        #expect(!engine.isGateOpen, "C is below box 3")
        #expect(engine.unlockedCount(1) == 3)

        // one right C brings it back to box 3. older notes don't need 8 fresh attempts
        let reopened = engine.play(c4)
        #expect(engine.stats(for: c4).box == 3)
        #expect(reopened.unlocked == [d4])
    }

    @Test func introsComeFirstAndDontCount() {
        var engine = MasteryEngine()
        var rng = SeededRandom(seed: 1)
        let first = engine.pickNext(using: &rng)
        #expect(first.id == c4 && engine.needsIntro(first))
        engine.intro(first.id)
        #expect(engine.stats(for: c4).attempts == 0)
        #expect(engine.stats(for: c4).box == 1)
        let second = engine.pickNext(using: &rng)
        #expect(second.id == g4 && engine.needsIntro(second))
        engine.intro(second.id)
        let third = engine.pickNext(using: &rng)
        #expect(!engine.needsIntro(third))
    }

    @Test func pickerNeverThreeInARowAcrossUnitsAndIntros() {
        var engine = MasteryEngine()
        // a kid who's quick and right: flies through the units, lots of intros and unit changes
        let picks = engine.simulate(4000, seed: 7)
        #expect(maxRun(picks) <= 2)
        #expect(engine.state.completedUnits.count >= 6, "crossed several unit boundaries")

        // and a kid who struggles: stays on small pools for a long time
        var slow = MasteryEngine()
        var rng = SeededRandom(seed: 99)
        let slowPicks = slow.simulate(4000, seed: 8) { _ in (unitInterval(&rng) < 0.6, 3.5, true) }
        #expect(maxRun(slowPicks) <= 2)
    }

    @Test func poolOfExactlyTwoAlternatesAtLeastEveryThird() {
        var engine = MasteryEngine()
        engine.intro(c4)
        engine.intro(g4)
        // keep the pool at two: never solid
        let picks = engine.simulate(2000, seed: 3) { _ in (false, 5, nil) }
        #expect(Set(picks) == [c4, g4])
        #expect(maxRun(picks) <= 2)
    }

    @Test func newestIsExcludedAfterTwoInARow() {
        var engine = MasteryEngine()
        for id in [c4, g4] { engine.intro(id); for _ in 0..<5 { engine.play(id, time: 1) } }
        #expect(engine.newestBatch.map(\.id) == [e4])
        engine.intro(e4)
        var rng = SeededRandom(seed: 5)
        var picks: [ItemID] = []
        for _ in 0..<3000 { picks.append(engine.pickNext(using: &rng).id) }
        #expect(maxRun(picks) <= 2)
        // newest still gets close to its 40% even with the cap on runs
        let share = Double(picks.filter { $0 == e4 }.count) / Double(picks.count)
        #expect(share > 0.3 && share < 0.45, "newest share \(share)")
    }

    @Test func lowBoxesGetShownMore() {
        var engine = MasteryEngine()
        for id in [c4, g4] { engine.intro(id); for _ in 0..<5 { engine.play(id, time: 1) } }
        engine.intro(e4)
        // knock C down to box 1, G stays at 5
        for _ in 0..<5 { engine.play(c4, right: false) }
        var rng = SeededRandom(seed: 11)
        var counts: [ItemID: Int] = [:]
        for _ in 0..<6000 { counts[engine.pickNext(using: &rng).id, default: 0] += 1 }
        #expect(counts[c4]! > counts[g4]! * 3, "box 1 is weighted 5x box 5: \(counts)")
    }

    @Test func reviewUnitThreeCompletesOnFreshSolidAttempts() {
        var engine = MasteryEngine()
        engine.moveToUnit(3)
        #expect(engine.newestBatch.isEmpty)
        #expect(engine.pool.count == 10, "units 1 and 2 on the grand staff")
        // everything is box 1 (skipped there), so the gate is shut until each is box 3
        for item in engine.pool { engine.play(item.id) }
        #expect(engine.unit.number == 3)
        var update = MasteryUpdate()
        for item in engine.pool { update = engine.play(item.id) }
        #expect(update.completedUnit == 3)
        #expect(update.enteredUnit == 4)
        #expect(update.unlocked == ["treble:A4"])
        #expect(engine.unit.number == 4)
        #expect(engine.state.unitRecent.isEmpty)
    }

    @Test func movingBackNeedsFreshAttemptsThenReturns() {
        var engine = MasteryEngine()
        var seed: UInt64 = 0
        while engine.unit.number < 5 {
            engine.simulate(1, seed: seed)
            seed += 1
        }
        #expect(engine.status(ofUnit: 1) == .completed)

        engine.moveToUnit(1)
        #expect(engine.status(ofUnit: 1) == .current)
        #expect(engine.pool.count == 5)
        #expect(engine.newestBatch.map(\.id) == [f4])
        #expect(engine.isGateOpen, "his old stats are still solid")
        // but the unit wants fresh attempts before moving on (3s each, so no fast track)
        var update = MasteryUpdate()
        for _ in 0..<6 {
            update = engine.play(c4, time: 3)
            #expect(update.completedUnit == nil)
        }
        update = engine.play(c4, time: 3)
        #expect(update.completedUnit == 1, "7 fresh right answers")
        #expect(update.enteredUnit == 5, "back to where he was, not unit 2")
    }

    @Test func skippingAheadDoesNotMarkUnitsDone() {
        var engine = MasteryEngine()
        engine.moveToUnit(4)
        #expect(engine.status(ofUnit: 2) == .skipped)
        #expect(engine.status(ofUnit: 5) == .upcoming)
        #expect(engine.pool.map(\.id).first == "treble:A4")
        #expect(engine.pool.count == 6, "A4 plus unit 1 review")
    }

    @Test func rhythmSlipNeverHoldsBackTheBoxGate() {
        var engine = MasteryEngine()
        engine.moveToUnit(10)
        let first = engine.pool[0].id, second = engine.pool[1].id
        // pitch right every time, rhythm wrong every time
        for _ in 0..<8 {
            engine.play(first, time: 1, rhythmOK: false)
            engine.play(second, time: 1, rhythmOK: false)
        }
        #expect(engine.stats(for: first).box == 5, "rhythm never moves the pitch box")
        #expect(engine.stats(for: first).rhythmBox == 1)
        #expect(engine.isPitchSolid(first) && !engine.isRhythmSolid(first))
        #expect(!engine.isGateOpen, "the newest rhythm items need their rhythm to unlock the next rhythm")

        // rhythm comes good on both
        for _ in 0..<5 {
            engine.play(first, time: 1, rhythmOK: true)
        }
        var update = MasteryUpdate()
        for _ in 0..<5 {
            update = engine.play(second, time: 1, rhythmOK: true)
        }
        #expect(update.unlocked.count == 1)

        // now rhythm slips on an older item: box gate uses the pitch box only
        let third = update.unlocked[0]
        for _ in 0..<4 { engine.play(first, time: 1, rhythmOK: false) }
        #expect(engine.stats(for: first).rhythmBox < 3)
        for _ in 0..<4 { engine.play(third, time: 1, rhythmOK: true) }
        update = engine.play(third, time: 1, rhythmOK: true)
        #expect(update.unlocked.count == 1, "a rhythm slip on an old item doesn't block the next unlock")
    }

    @Test func rhythmNotJudgedLeavesTheRhythmTrackAlone() {
        var engine = MasteryEngine()
        engine.moveToUnit(10)
        let id = engine.pool[0].id
        engine.play(id, right: false, rhythmOK: nil)
        #expect(engine.stats(for: id).rhythmAttempts == 0)
        #expect(engine.stats(for: id).attempts == 1)
    }

    @Test func stateRoundTripsThroughJSONAndPicksTheSame() throws {
        var engine = MasteryEngine()
        engine.simulate(400, seed: 4) { item in (item.id != "treble:D4", 1.5, true) }
        let data = try JSONEncoder().encode(engine.state)
        let restoredState = try JSONDecoder().decode(MasteryState.self, from: data)
        #expect(restoredState == engine.state)
        var restored = MasteryEngine(state: restoredState)
        let a = engine.simulate(200, seed: 9)
        let b = restored.simulate(200, seed: 9)
        #expect(a == b)
    }

    @Test func fluencyGrowsAndPeakNeverShrinks() {
        var engine = MasteryEngine()
        #expect(engine.progress(for: c4)!.fluency == 0)
        for _ in 0..<6 { engine.play(c4, time: 1) }
        let high = engine.progress(for: c4)!
        #expect(high.fluency > 0.9)
        for _ in 0..<3 { engine.play(c4, right: false, time: 6) }
        let after = engine.progress(for: c4)!
        #expect(after.fluency < high.fluency)
        #expect(after.peakFluency == high.peakFluency, "his muncher never shrinks")
        #expect(engine.allProgress.map(\.id) == [c4])
    }

    @Test func playsTheWholeCurriculum() {
        var engine = MasteryEngine()
        var picks = 0
        while !engine.isCurriculumComplete, picks < 20_000 {
            engine.simulate(50, seed: UInt64(picks))
            picks += 50
        }
        #expect(engine.isCurriculumComplete, "a quick, right kid gets through all 12 units")
        #expect(picks < 5000, "took \(picks) picks")
        #expect(engine.state.completedUnits == Set(1...12))
        #expect(engine.unit.number == 12, "stays on the last unit")
    }
}

@Suite struct SavedStateTests {
    @Test func missingKeysFallBackToDefaults() throws {
        let empty = Data("{}".utf8)
        #expect(try JSONDecoder().decode(NoteCoreConfig.self, from: empty) == NoteCoreConfig())
        #expect(try JSONDecoder().decode(MasteryState.self, from: empty) == MasteryState())
        #expect(try JSONDecoder().decode(ItemStats.self, from: empty) == ItemStats())
    }

    @Test func stateSavedBeforeAFieldExistedStillLoads() throws {
        var engine = MasteryEngine()
        engine.simulate(200, seed: 3)
        // pretend an older build saved this, before peakFluency and recentPicks existed
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.state)) as! [String: Any]
        json.removeValue(forKey: "recentPicks")
        var stats = json["stats"] as! [String: [String: Any]]
        for key in stats.keys { stats[key]!.removeValue(forKey: "peakFluency") }
        json["stats"] = stats
        let old = try JSONSerialization.data(withJSONObject: json)
        let state = try JSONDecoder().decode(MasteryState.self, from: old)
        #expect(state.unit == engine.state.unit)
        #expect(state.stats.mapValues(\.box) == engine.state.stats.mapValues(\.box))
        #expect(state.recentPicks.isEmpty)
    }

    @Test func partialConfigKeepsTheRestAtDefaults() throws {
        let config = try JSONDecoder().decode(NoteCoreConfig.self, from: Data(#"{"sessionMaxItems": 30}"#.utf8))
        #expect(config.sessionMaxItems == 30)
        #expect(config.solidRequired == 7)
    }
}
