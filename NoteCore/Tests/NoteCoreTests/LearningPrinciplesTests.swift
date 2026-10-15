import Foundation
import Testing
@testable import NoteCore

/// The session shape from the plan's "learning principles" section.
@Suite struct LearningPrinciplesTests {
    let c4 = "treble:C4", g4 = "treble:G4", e4 = "treble:E4"

    /// Unit 1 with C4 and G4 learned (box 5) and E4 just unlocked, not introduced yet.
    func engineWithANewNoteDue() -> MasteryEngine {
        var engine = MasteryEngine()
        for id in [c4, g4] {
            engine.intro(id)
            for _ in 0..<5 { engine.play(id, time: 1) }
        }
        return engine
    }

    func config(_ change: (inout NoteCoreConfig) -> Void) -> NoteCoreConfig {
        var config = NoteCoreConfig()
        change(&config)
        return config
    }

    func effectiveBox(_ engine: MasteryEngine, _ item: PracticeItem) -> Int {
        let s = engine.stats(for: item.id)
        return item.isRhythm ? min(s.box, s.rhythmBox) : s.box
    }

    /// The current item is the highest box among items he's played, leaving out the
    /// pick before it (strongest picks a different one each time when it can).
    func isStrongest(_ session: PracticeSession) -> Bool {
        let engine = session.engine
        let previous = engine.state.recentPicks.dropLast().last
        var others = engine.playedPool
        if others.count > 1 { others.removeAll { $0.id == previous } }
        let top = others.map { effectiveBox(engine, $0) }.max()
        return effectiveBox(engine, session.item!) == top
    }

    // MARK: picker

    @Test func newestShareIsAQuarter() {
        #expect(NoteCoreConfig().newestShare == 0.25)
    }

    @Test func strongestPicksHisHighestBoxAndNeverANewItem() {
        var engine = engineWithANewNoteDue()
        engine.play(g4, right: false) // G4 drops to box 4, C4 stays at 5
        #expect(engine.newestBatch.map(\.id) == [e4])
        var rng = SeededRandom(seed: 1)
        let picks = (0..<20).map { _ in engine.pickNext(.strongest, using: &rng).id }
        #expect(picks[0] == c4, "highest box first")
        #expect(!picks.contains(e4), "no new or unplayed item")
        #expect(maxRun(picks) == 1, "a different one each time when there's a choice")
    }

    @Test func strongestFallsBackWhenNothingIsPlayedYet() {
        var engine = MasteryEngine()
        var rng = SeededRandom(seed: 1)
        let item = engine.pickNext(.strongest, using: &rng)
        #expect(item.id == c4 && engine.needsIntro(item), "first session ever: straight to the intro")
    }

    // MARK: warm-up

    @Test func sessionOpensWithHisStrongestBeforeAnythingNew() {
        var bench = Bench(engineWithANewNoteDue())
        _ = bench.start()
        var seen: [(PickReason, ItemID, Bool)] = []
        for _ in 0..<3 {
            seen.append((bench.session.pickReason, bench.session.item!.id, bench.session.isIntro))
            _ = bench.playCurrent()
            _ = bench.next()
        }
        // only two items played so far, so a two-item warm-up, then the new note
        #expect(seen.map(\.0) == [.warmUp, .warmUp, .normal])
        #expect(Set(seen.prefix(2).map(\.1)) == [c4, g4])
        #expect(seen[2].1 == e4 && seen[2].2, "the new note comes after the warm-up")
    }

    @Test func warmUpIsThreeStrongestWhenHeKnowsEnough() {
        var engine = MasteryEngine()
        engine.simulate(400, seed: 30)
        #expect(engine.playedPool.count >= 3)
        var bench = Bench(engine, seed: 4)
        _ = bench.start()
        var reasons: [PickReason] = []
        var ids: [ItemID] = []
        for _ in 0..<4 {
            reasons.append(bench.session.pickReason)
            ids.append(bench.session.item!.id)
            if bench.session.pickReason == .warmUp {
                #expect(isStrongest(bench.session), "\(bench.session.item!.id) is one of his strongest")
                #expect(!bench.session.isIntro)
            }
            _ = bench.playCurrent()
            _ = bench.next()
        }
        #expect(reasons == [.warmUp, .warmUp, .warmUp, .normal])
        #expect(maxRun(ids.prefix(3).map { $0 }) == 1)
    }

    @Test func firstSessionEverHasNoWarmUp() {
        var bench = Bench(MasteryEngine())
        _ = bench.start()
        #expect(bench.session.pickReason == .normal)
        #expect(bench.session.isIntro)
    }

    // MARK: easing

    @Test func threeStrugglesInFiveBringHisTwoStrongest() {
        var engine = engineWithANewNoteDue()
        engine.config = config { $0.warmUpCount = 0 }
        var bench = Bench(engine, seed: 9)
        _ = bench.start()
        // three in a row with a wrong key first
        for _ in 0..<3 {
            #expect(bench.session.pickReason == .normal)
            _ = bench.press(bench.wrongKey)
            _ = bench.playCurrent()
            _ = bench.next()
        }
        for _ in 0..<2 {
            #expect(bench.session.pickReason == .easing)
            #expect(!bench.session.isIntro)
            #expect(isStrongest(bench.session), "\(bench.session.item!.id) is one of his strongest")
            _ = bench.playCurrent()
            _ = bench.next()
        }
        #expect(bench.session.pickReason == .normal, "back to normal after two")
        // the window started over: one more miss doesn't bring easing back
        _ = bench.press(bench.wrongKey)
        _ = bench.playCurrent()
        _ = bench.next()
        #expect(bench.session.pickReason == .normal)
    }

    @Test func easingKeepsTheNoRepeatRule() {
        var engine = engineWithANewNoteDue()
        engine.config = config { $0.warmUpCount = 0; $0.sessionMaxItems = 400; $0.sessionMaxDuration = 1e6 }
        var bench = Bench(engine, seed: 3)
        _ = bench.start()
        // a kid who misses a lot: easing keeps kicking in
        var easing = 0
        for i in 0..<300 {
            if bench.session.pickReason == .easing { easing += 1 }
            if i % 3 != 0 { _ = bench.press(bench.wrongKey) }
            _ = bench.playCurrent()
            _ = bench.next()
        }
        #expect(easing > 50)
        #expect(maxRun(bench.session.summary.attempts.map(\.itemID)) <= 2)
    }

    // MARK: end on success

    @Test func endsAfterHisNextFirstTrySuccess() {
        var engine = engineWithANewNoteDue()
        engine.config = config { $0.sessionMaxItems = 2; $0.warmUpCount = 0 }
        var bench = Bench(engine)
        _ = bench.start()
        _ = bench.playCurrent()
        _ = bench.next()
        // the last one before the limit needed a hint
        _ = bench.press(bench.wrongKey)
        _ = bench.playCurrent()
        #expect(bench.next() == [.showItem], "not over yet - one more, an easy one")
        #expect(bench.session.pickReason == .extra)
        #expect(!bench.session.isIntro)
        _ = bench.playCurrent()
        #expect(bench.next() == [.done, .say(.sessionDone)])
        #expect(bench.session.summary.endedBy == .itemLimit)
        #expect(bench.session.summary.extraItems == 1)
        #expect(bench.session.summary.itemsPlayed == 3)
        #expect(bench.session.summary.attempts.last!.firstTry)
    }

    @Test func atMostThreeExtraThenEndsAnyway() {
        var engine = engineWithANewNoteDue()
        engine.config = config { $0.sessionMaxItems = 1; $0.warmUpCount = 0 }
        var bench = Bench(engine)
        _ = bench.start()
        var extras = 0
        while bench.session.phase != .done {
            if bench.session.pickReason == .extra { extras += 1 }
            _ = bench.press(bench.wrongKey)
            _ = bench.playCurrent()
            _ = bench.next()
        }
        #expect(extras == 3)
        #expect(bench.session.summary.extraItems == 3)
        #expect(bench.session.summary.itemsPlayed == 4)
    }

    @Test func timeUpAlsoEndsOnASuccess() {
        var engine = engineWithANewNoteDue()
        engine.config = config { $0.sessionMaxDuration = 10; $0.warmUpCount = 0 }
        var bench = Bench(engine)
        _ = bench.start()
        _ = bench.press(bench.wrongKey, after: 11)
        _ = bench.playCurrent()
        #expect(bench.next() == [.showItem])
        #expect(bench.session.pickReason == .extra)
        _ = bench.playCurrent()
        #expect(bench.next() == [.done, .say(.sessionDone)])
        #expect(bench.session.summary.endedBy == .timeLimit)
    }

    // MARK: intro: i do, we do, you do

    @Test func newChordAndGroupAreShownBeforeHePlays() {
        var chords = MasteryEngine()
        chords.moveToUnit(8)
        var bench = Bench(chords)
        #expect(bench.start() == [.showItem, .playPitches([Pitch(.c, 4), Pitch(.e, 4)]), .say(.meetNotes([.c, .e]))])
        #expect(bench.session.keyboardHint == [Pitch(.c, 4), Pitch(.e, 4)])

        var groups = MasteryEngine()
        groups.moveToUnit(7)
        bench = Bench(groups)
        #expect(bench.start() == [.showItem, .playPhrase(beat: 0.75), .say(.meetNotes([.c, .d]))])
        #expect(bench.session.keyboardHint == [Pitch(.c, 4)], "the picture follows the note he's on")
        _ = bench.playCurrent()
        #expect(bench.session.keyboardHint == [Pitch(.d, 4)])
    }

    @Test func afterTheIntroThePictureOnlyComesBackAsAHint() {
        var bench = Bench(MasteryEngine())
        _ = bench.start()
        #expect(bench.session.isIntro && !bench.session.keyboardHint.isEmpty) // we do
        _ = bench.playCurrent()
        _ = bench.next()
        #expect(bench.session.isIntro) // G4's intro
        _ = bench.playCurrent()
        _ = bench.next()
        // you do: C4 or G4 again, no picture
        #expect(!bench.session.isIntro)
        #expect(bench.session.keyboardHint.isEmpty)
        for _ in 0..<3 { _ = bench.press(bench.wrongKey) }
        #expect(!bench.session.keyboardHint.isEmpty, "back as a hint after three tries")
    }

    // MARK: stuck

    @Test func stuckClimbsTheLadderAndStops() throws {
        var bench = Bench(engine(inUnit: 1))
        _ = bench.start()
        let expected = bench.expected
        #expect(bench.session.nextDeadline == 15)
        #expect(bench.tick(at: 14.9).isEmpty)
        #expect(bench.tick(at: 15) == [.wobble(note: 0)])
        #expect(bench.session.phase == .waiting)
        #expect(bench.session.nextDeadline == 30)
        #expect(bench.tick(at: 30) == [.wobble(note: 0), .playPitches(expected)])
        #expect(bench.session.phase == .hint1)
        #expect(bench.tick(at: 45) == [.wobble(note: 0)])
        #expect(bench.session.phase == .hint2)
        #expect(bench.session.keyboardHint == expected)
        #expect(bench.session.nextDeadline == nil, "top of the ladder: nothing repeats on a clock")
        #expect(bench.tick(at: 500).isEmpty)

        let cues = bench.press(expected[0])
        #expect(cues.contains(.say(.keptTrying)))
        let attempt = bench.session.summary.attempts[0]
        #expect(!attempt.firstTry, "not first try")
        #expect(attempt.wrongPresses == 0, "but not a wrong press either")
        #expect(attempt.stuckSteps == 3)
        #expect(attempt.hints == .keyboard)
    }

    @Test func anyKeyResetsTheStuckTimer() {
        var bench = Bench(engine(inUnit: 1))
        _ = bench.start()
        _ = bench.press(bench.wrongKey, after: 10)
        #expect(bench.session.nextDeadline == 25)
        #expect(bench.session.phase == .waiting)
        #expect(bench.tick(at: 25) == [.wobble(note: 0), .playPitches(bench.expected)], "stuck after the wrong key: next rung")
    }

    @Test func pausedTimeDoesNotCountAsStuck() {
        var bench = Bench(engine(inUnit: 1))
        _ = bench.start()
        _ = bench.session.pianoDisconnected(at: 10)
        #expect(bench.session.nextDeadline == nil)
        _ = bench.session.pianoConnected(at: 100)
        #expect(bench.session.nextDeadline == 105, "5 active seconds left before the first stuck step")
    }

    @Test func noStuckStepWhileHeHoldsTheLastNoteOfALine() throws {
        var bench = Bench(engine(inUnit: 10))
        _ = bench.start()
        let notes = bench.session.item!.notes
        for (i, note) in notes.enumerated() {
            _ = bench.press(note.pitches[0], after: i == 0 ? 0.5 : notes[i - 1].value!.beats * 0.6)
        }
        let deadline = try #require(bench.session.nextDeadline)
        #expect(deadline < bench.now + 3, "only the rhythm settle time")
    }

    // MARK: praise

    @Test func processPraiseOnly() {
        var engine = engineWithANewNoteDue()
        engine.config = config { $0.sessionMaxItems = 1000; $0.warmUpCount = 0; $0.sessionMaxDuration = 1e6 }
        var bench = Bench(engine, seed: 8)
        _ = bench.start()
        var firstTry = 0, looked = 0
        for i in 0..<300 {
            let hinted = i % 4 == 0
            if hinted { _ = bench.press(bench.wrongKey) }
            let item = bench.session.item!
            let cues = bench.playCurrent()
            if item.kind == .note {
                #expect(cues.contains(.say(.letter(item.notes[0].pitches[0].naturalLetter))), "the letter, always")
            }
            if hinted {
                #expect(cues.contains(.say(.keptTrying)))
                #expect(!cues.contains(.say(.lookedCarefully)))
            } else {
                firstTry += 1
                #expect(!cues.contains(.say(.keptTrying)))
                if cues.contains(.say(.lookedCarefully)) { looked += 1 }
            }
            _ = bench.next()
        }
        let rate = Double(looked) / Double(firstTry)
        #expect(rate > 0.2 && rate < 0.5, "now and then, not every time: \(rate)")
    }

    @Test func almostThenRightIsStillFirstTryPraise() {
        var bench = Bench(engine(inUnit: 1))
        _ = bench.start()
        let expected = bench.expected[0]
        _ = bench.press(Pitch(midi: expected.midi + 12))
        let cues = bench.press(expected)
        #expect(!cues.contains(.say(.keptTrying)))
        #expect(bench.session.summary.attempts[0].firstTry)
    }

    // MARK: saved json

    /// Every key of a saved config is read back. Bumps every number, decodes, and
    /// checks nothing came back at its default - catches a field missing from init(from:).
    @Test func everyConfigFieldDecodes() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NoteCoreConfig())) as! [String: Any]
        let bumped = json.mapValues { ($0 as! NSNumber).doubleValue + 1 }
        let decoded = try JSONDecoder().decode(NoteCoreConfig.self, from: JSONSerialization.data(withJSONObject: bumped.mapValues { value -> Any in
            value.rounded() == value ? Int(value) : value
        }))
        let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
        for (key, value) in bumped {
            #expect((back[key] as! NSNumber).doubleValue == value, "\(key) isn't decoded")
        }
    }

    @Test func oldAttemptsAndSummariesStillDecode() throws {
        let attempt = try JSONDecoder().decode(AttemptResult.self, from: Data(#"{"itemID": "treble:C4", "unit": 1, "firstTry": true, "responseTime": 1.5}"#.utf8))
        #expect(attempt.stuckSteps == 0 && attempt.hints == .none)
        let summary = try JSONDecoder().decode(SessionSummary.self, from: Data(#"{"startUnit": 2, "itemsPlayed": 20}"#.utf8))
        #expect(summary.extraItems == 0 && summary.endUnit == 2 && summary.itemsPlayed == 20)
    }
}
