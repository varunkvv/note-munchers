import Foundation
import Testing
@testable import NoteCore

@Suite struct NoteKeyTests {
    @Test func idsRoundTrip() {
        for id in ["treble:G4", "bass:G2", "treble:F#4", "bass:C4"] {
            #expect(NoteKey(id: id)?.id == id)
        }
        #expect(NoteKey(.treble, Pitch(.g, 4)).id == "treble:G4")
    }

    @Test func roundOneItemIDsAreNotNotes() {
        for id in ["treble:C4-D4", "treble:C4+E4", "treble:G4/q-G4/q-G4/h", "alto:C4", "treble:H4", "treble:Bb3", "lesson:1.1"] {
            #expect(NoteKey(id: id) == nil, "\(id)")
        }
    }

    @Test func noteNames() {
        #expect(NoteName(Pitch(.g, 4)) == .g)
        #expect(NoteName(Pitch("F#4")!) == .fSharp)
        #expect(NoteName(Pitch("C#4")!) == nil)
        #expect(NoteName.fSharp.letter == .f && NoteName.fSharp.spoken == "F sharp")
        #expect(NoteName.allCases.count == 8)
    }

    @Test func linesAndSpacesInGPosition() {
        #expect(["treble:G4", "treble:B4", "treble:D5", "bass:G2", "bass:B2", "bass:D3"].allSatisfy { key($0).isOnLine })
        #expect(["treble:A4", "treble:C5", "bass:A2", "bass:C3"].allSatisfy { !key($0).isOnLine })
    }
}

@Suite struct MasteryEngineTests {
    /// Plays each note right, fast, `times` times (the fast track takes 3).
    func makeSolid(_ engine: inout MasteryEngine, _ keys: [NoteKey], times: Int = 3) {
        for _ in 0..<times {
            for k in keys { engine.play(k, time: 1) }
        }
    }

    @Test func freshEngineStartsLessonOneWithThreeNotesPerClef() {
        let engine = MasteryEngine()
        #expect(engine.lesson.id == "1.1")
        for clef in Clef.allCases {
            let pool = engine.pool(clef)
            #expect(pool.count == 3, "\(clef)")
            #expect(pool.contains(where: \.isOnLine) && pool.contains(where: { !$0.isOnLine }), "\(clef) has a line and a space")
            #expect(engine.newestBatch(clef) == pool, "the start set counts as the newest batch")
            #expect(pool.allSatisfy(engine.needsIntro), "every start note waits for its intro")
        }
        #expect(engine.screenSize == 1)
    }

    @Test func startSetIsPickedAtRandomPerKid() {
        var sets = Set<[NoteKey]>()
        for seed in 1...30 {
            let engine = MasteryEngine(state: MasteryState(seed: UInt64(seed)))
            let treble = engine.pool(.treble)
            #expect(treble.contains(where: \.isOnLine) && treble.contains(where: { !$0.isOnLine }), "seed \(seed)")
            sets.insert(treble)
            // same seed, same choice
            #expect(MasteryEngine(state: MasteryState(seed: UInt64(seed))).pool(.treble) == treble)
        }
        #expect(sets.count >= 5, "start sets vary between kids: \(sets.count)")
        #expect(!sets.contains([key("treble:G4"), key("treble:B4"), key("treble:D5")]), "never all lines")
    }

    @Test func initIsIdempotent() {
        let engine = MasteryEngine(state: MasteryState(seed: 3))
        let again = MasteryEngine(state: engine.state)
        #expect(again.state == engine.state, "rebuilding an engine from its state changes nothing")
    }

    @Test func leitnerMovesOneBoxAndStaysInRange() {
        var engine = engine(in: "1.1")
        let g = engine.pool(.treble)[0]
        engine.play(g, right: false)
        #expect(engine.stats(for: g).box == 1)
        for _ in 0..<7 { engine.play(g) }
        #expect(engine.stats(for: g).box == 5)
        engine.play(g, right: false)
        #expect(engine.stats(for: g).box == 4)
    }

    @Test func stuckWithoutAWrongKeyHoldsTheBox() {
        var engine = engine(in: "1.1")
        let g = engine.pool(.treble)[0]
        engine.play(g)
        engine.play(g)
        let note = AttemptResult(itemID: g.id, lesson: "1.1", level: 1, firstTry: false, stuckSteps: 1, hints: .wobble, responseTime: 16)
        engine.record(ScreenResult(screenID: g.id, lesson: "1.1", reason: .warmUp, notes: [note]))
        #expect(engine.stats(for: g).box == 3)
        #expect(!engine.stats(for: g).recent.last!.firstTry)
    }

    @Test func solidIsSevenOfEightOrThreeFastInARow() {
        var engine = engine(in: "1.1")
        let g = engine.pool(.treble)[0]
        engine.play(g, time: 1)
        engine.play(g, time: 1)
        #expect(!engine.isSolid(g))
        engine.play(g, time: 1)
        #expect(engine.isSolid(g), "fast track: 3 in a row under 3s")

        var slow = NoteCoreTests.engine(in: "1.1")
        for _ in 0..<3 { slow.play(g, time: 3.2) }
        #expect(!slow.isSolid(g), "3.2s is too slow for the fast track")
        slow.play(g, right: false, time: 3.2)
        for _ in 0..<4 { slow.play(g, time: 3.2) }
        #expect(slow.isSolid(g), "7 of 8 with a median under 4s")
    }

    @Test func gateIsPerClefAndUnlocksAPair() {
        var engine = engine(in: "1.1")
        let treble = engine.pool(.treble)
        let bass = engine.pool(.bass)
        makeSolid(&engine, Array(treble.dropLast()))
        #expect(engine.pool(.treble).count == 3, "one start note isn't solid yet")
        let update = engine.play(treble.last!, time: 1) // box 2
        #expect(update.unlocked.isEmpty)
        engine.play(treble.last!, time: 1)
        let opened = engine.play(treble.last!, time: 1)
        #expect(opened.unlocked.count == 2, "pairs early on: \(opened.unlocked)")
        #expect(engine.pool(.treble).count == 5)
        #expect(engine.pool(.bass) == bass, "bass has its own gate")
        #expect(Set(engine.newestBatch(.treble).map(\.id)) == Set(opened.unlocked))
        #expect(engine.newestBatch(.treble).allSatisfy(engine.needsIntro))
    }

    @Test func gateWaitsForEveryNoteOnTheClefAtBoxThree() {
        var engine = engine(in: "1.1")
        let start = engine.pool(.treble)
        makeSolid(&engine, start)
        let pair = engine.newestBatch(.treble)
        #expect(pair.count == 2)
        for k in pair { engine.intro(k) }
        engine.play(start[0], right: false)
        engine.play(start[0], right: false) // box 4 -> 2
        makeSolid(&engine, pair)
        #expect(!engine.isGateOpen(.treble), "\(start[0]) slipped to box 2")
        engine.play(start[0], time: 1)
        #expect(engine.isGateOpen(.treble), "box 3 again")
    }

    @Test func introsDontCount() {
        var engine = MasteryEngine()
        let first = engine.pool(.treble)[0]
        engine.intro(first)
        #expect(!engine.needsIntro(first))
        #expect(engine.stats(for: first).attempts == 0)
        #expect(engine.stats(for: first).box == 1)
        #expect(engine.metNotes.contains(first))
    }

    @Test func sizeGrowsAfterFourGoodScreensAndDropsBack() {
        var engine = engine(in: "1.2")
        #expect(engine.screenSize == 2)
        let notes = engine.pool(.treble)
        let screen = Array(notes.prefix(2))
        for i in 0..<3 {
            let update = engine.play(screen)
            #expect(update.screenSize == nil, "screen \(i)")
        }
        #expect(engine.play(screen).screenSize == 3)
        // three bad screens at 3 drop it back to 2
        let three = Array(notes.prefix(3))
        engine.play(three, right: false)
        engine.play(three, right: false)
        #expect(engine.play(three, right: false).screenSize == 2)
        // never below the lesson's range
        for _ in 0..<6 { engine.play(screen, right: false) }
        #expect(engine.screenSize == 2)
    }

    @Test func screensAtAnotherSizeDontCountTowardGrowing() {
        var engine = engine(in: "1.2")
        let notes = engine.pool(.treble)
        for _ in 0..<6 { engine.play(Array(notes.prefix(3))) } // stretch-sized, size is 2
        #expect(engine.screenSize == 2)
        for _ in 0..<6 { engine.play(Array(notes.prefix(2)), reason: .warmUp) }
        #expect(engine.screenSize == 2, "warm-up and easing screens don't count")
    }

    @Test func lessonCompletesAndTheNextOneStarts() {
        var engine = engine(in: "1.1")
        var rng = SeededRandom(seed: 1)
        var entered: LessonID?
        for _ in 0..<200 where entered == nil {
            let pick = engine.pickScreen(using: &rng)
            if let intro = pick.intro {
                engine.intro(intro)
                continue
            }
            let update = engine.play(pick.item.notes.flatMap(\.keys), time: 1)
            entered = update.enteredLesson
        }
        #expect(entered == "1.2")
        #expect(engine.state.completedLessons == ["1.1"])
        #expect(engine.pool.count == 10)
        #expect(engine.screenSize >= 2, "1.2 starts at 2 per screen")
        #expect(engine.status(ofLesson: "1.1") == .completed)
        #expect(engine.status(ofLesson: "1.2") == .current)
        #expect(engine.status(ofLesson: "1.3") == .upcoming)
    }

    @Test func lessonNeedsEnoughScreensEvenWhenHeKnowsEverything() {
        var engine = engine(in: "1.2")
        let t = engine.pool(.treble), b = engine.pool(.bass)
        // every note twice (box 3), right and quick, over exactly 10 screens
        let screens = [[t[0], t[1]], [t[2], t[3]], [t[4], t[0]], [t[1], t[2]], [t[3], t[4]],
                       [b[0], b[1]], [b[2], b[3]], [b[4], b[0]], [b[1], b[2]], [b[3], b[4]]]
        for (i, screen) in screens.enumerated() {
            engine.play(screen, time: 1)
            #expect(engine.lesson.id == (i < 9 ? "1.2" : "1.3"), "after screen \(i + 1)")
        }
    }

    @Test func parentJumpsAndMovingBack() {
        var engine = MasteryEngine()
        engine.moveToLesson("1.3")
        #expect(engine.lesson.id == "1.3")
        #expect(engine.pool.count == 10, "known notes unlock on entry")
        #expect(engine.pendingIntros.isEmpty, "known notes don't get intros")
        #expect(engine.status(ofLesson: "1.1") == .skipped)
        #expect(engine.status(ofLevel: 1) == .current)
        engine.moveToLevel(1)
        #expect(engine.lesson.id == "1.1", "a level starts at its first lesson not done")
        #expect(engine.moveToLesson("9.9").isEmpty)
        #expect(engine.lesson.id == "1.1")
    }

    @Test func stateRoundTripsThroughJSONAndPicksTheSame() throws {
        var engine = engine(in: "1.1")
        var rng = SeededRandom(seed: 9)
        for _ in 0..<15 {
            let pick = engine.pickScreen(using: &rng)
            engine.play(pick.item.notes.flatMap(\.keys), right: true, time: 1.2)
        }
        let data = try JSONEncoder().encode(engine.state)
        let restored = MasteryEngine(state: try JSONDecoder().decode(MasteryState.self, from: data))
        #expect(restored.state == engine.state)
        var a = engine, b = restored
        var r1 = SeededRandom(seed: 4), r2 = SeededRandom(seed: 4)
        for _ in 0..<20 {
            #expect(a.pickScreen(using: &r1) == b.pickScreen(using: &r2))
        }
    }

    @Test func fluencyGrowsAndPeakNeverShrinks() {
        var engine = engine(in: "1.1")
        let g = engine.pool(.treble)[0]
        for _ in 0..<4 { engine.play(g, time: 1) }
        let peak = engine.stats(for: g).peakFluency
        #expect(peak > 0.5)
        for _ in 0..<3 { engine.play(g, right: false, time: 5) }
        #expect(engine.fluency(engine.stats(for: g)) < peak)
        #expect(engine.stats(for: g).peakFluency == peak)
        #expect(engine.allProgress.map(\.key) == [g])
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let state = try JSONDecoder().decode(MasteryState.self, from: Data("{}".utf8))
        #expect(state.lesson == "1.1")
        #expect(MasteryEngine(state: state).pool.count == 6)
        let config = try JSONDecoder().decode(NoteCoreConfig.self, from: Data(#"{"sessionMaxItems": 30}"#.utf8))
        #expect(config.sessionMaxItems == 30)
        #expect(config.fastTrackCount == NoteCoreConfig.default.fastTrackCount)
    }

    @Test func everyConfigFieldDecodes() throws {
        var config = NoteCoreConfig()
        config.newestShare = 0.31
        config.sizeWindow = 6
        config.lessonMinScreens = 12
        config.keptTryingChance = 0.7
        let decoded = try JSONDecoder().decode(NoteCoreConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}

/// His progress from round 1 (per curated item, units) must load, keep the single-note
/// stats where clef and pitch match, and never crash.
@Suite struct MigrationTests {
    /// Shaped like a real round-1 save: unit 1 with C4-F4 played and G4 met, a few
    /// items from later units, a whole config's worth of other keys.
    static let roundOneState = #"""
    {"unit":1,"unlockedCounts":{"1":5,"2":2},"completedUnits":[],
     "stats":{
       "treble:C4":{"box":4,"recent":[{"firstTry":true,"responseTime":1.8},{"firstTry":true,"responseTime":1.5}],"attempts":14,"firstTryCount":12,"rhythmBox":1,"rhythmRecent":[],"rhythmAttempts":0,"peakFluency":0.62},
       "treble:G4":{"box":3,"recent":[{"firstTry":true,"responseTime":2.4}],"attempts":9,"firstTryCount":7,"rhythmBox":1,"rhythmRecent":[],"rhythmAttempts":0,"peakFluency":0.41},
       "treble:E4":{"box":2,"recent":[],"attempts":3,"firstTryCount":2,"rhythmBox":1,"rhythmRecent":[],"rhythmAttempts":0,"peakFluency":0.2},
       "treble:C4-D4":{"box":2,"recent":[],"attempts":2,"firstTryCount":1,"rhythmBox":1,"rhythmRecent":[],"rhythmAttempts":0,"peakFluency":0.1},
       "treble:G4/q-G4/q-G4/h":{"box":1,"recent":[],"attempts":1,"firstTryCount":0,"rhythmBox":2,"rhythmRecent":[true],"rhythmAttempts":1,"peakFluency":0}
     },
     "introduced":["treble:C4","treble:G4","treble:E4","treble:D4","treble:C4-D4"],
     "unitRecent":[{"firstTry":true,"responseTime":1.2}],
     "recentPicks":["treble:C4","treble:E4"]}
    """#

    @Test func roundOneStateLoadsAndKeepsMatchingNotes() throws {
        let state = try JSONDecoder().decode(MasteryState.self, from: Data(Self.roundOneState.utf8))
        #expect(Set(state.stats.keys) == ["treble:C4", "treble:G4", "treble:E4"], "group and rhythm items are dropped")
        #expect(state.stats["treble:G4"]?.box == 3)
        #expect(state.stats["treble:G4"]?.peakFluency == 0.41)
        #expect(state.introduced == ["treble:C4", "treble:G4", "treble:E4", "treble:D4"])
        let engine = MasteryEngine(state: state)
        #expect(engine.lesson.id == "1.1")
        #expect(engine.pool(.treble).count == 3)
        #expect(!engine.needsIntro(key("treble:G4")), "he met G4 in round 1")
        #expect(engine.allProgress.map(\.id) == ["treble:C4", "treble:E4", "treble:G4"])
    }

    @Test func garbageNeverCrashes() {
        for json in ["[]", "\"x\"", #"{"stats": 5}"#, #"{"unit": "one"}"#, "{"] {
            _ = try? JSONDecoder().decode(MasteryState.self, from: Data(json.utf8))
        }
        let unknownLesson = try? JSONDecoder().decode(MasteryState.self, from: Data(#"{"lesson":"7.7"}"#.utf8))
        #expect(unknownLesson.map { MasteryEngine(state: $0).lesson.id } == "1.1", "an unknown lesson falls back to the first")
    }

    @Test func roundOneAttemptsAndSummariesStillDecode() throws {
        let attempt = #"{"itemID":"treble:C4","unit":1,"wasIntro":false,"firstTry":true,"wrongPresses":0,"almostPresses":0,"hints":0,"responseTime":1.4}"#
        let decoded = try JSONDecoder().decode(AttemptResult.self, from: Data(attempt.utf8))
        #expect(decoded.itemID == "treble:C4" && decoded.firstTry && decoded.responseTime == 1.4)
        let summary = #"{"startUnit":1,"endUnit":1,"itemsPlayed":12,"firstTryCount":10,"activeDuration":200,"attempts":[],"unlocked":["treble:E4"],"completedUnits":[],"practiced":[]}"#
        let s = try JSONDecoder().decode(SessionSummary.self, from: Data(summary.utf8))
        #expect(s.unlocked == ["treble:E4"])
        #expect(s.activeDuration == 200)
    }
}
