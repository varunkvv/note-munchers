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

    /// Round 3: 4 notes to start, G and A on each clef, every kid the same.
    @Test func freshEngineStartsWithGAndAOnEachClef() {
        for seed: UInt64 in 1...10 {
            let engine = MasteryEngine(state: MasteryState(seed: seed))
            #expect(engine.lesson.id == "1.1")
            #expect(engine.pool(.treble) == [key("treble:G4"), key("treble:A4")])
            #expect(engine.pool(.bass) == [key("bass:G2"), key("bass:A2")])
            for clef in Clef.allCases {
                #expect(engine.newestBatch(clef) == engine.pool(clef), "the start set counts as the newest batch")
                #expect(engine.pool(clef).allSatisfy(engine.needsIntro), "every start note waits for its intro")
            }
            #expect(engine.screenSize == 2)
        }
    }

    /// Outside level 1 a lesson's start notes are a random draw per kid (level 3 here).
    @Test func startSetIsPickedAtRandomPerKid() {
        var picks = Set<[NoteKey]>()
        for seed in 1...30 {
            var engine = MasteryEngine(state: MasteryState(seed: UInt64(seed)))
            engine.moveToLesson("3.1")
            picks.insert(engine.pendingIntros)
            var again = MasteryEngine(state: MasteryState(seed: UInt64(seed)))
            again.moveToLesson("3.1")
            #expect(again.pendingIntros == engine.pendingIntros, "same seed, same choice")
        }
        #expect(picks.count >= 2, "start notes vary between kids: \(picks)")
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
        var engine = MasteryEngine(curriculum: gateCurriculum(), state: MasteryState(seed: 7))
        engine.introduceAll()
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
        var engine = MasteryEngine(curriculum: gateCurriculum(), state: MasteryState(seed: 7))
        engine.introduceAll()
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
        #expect(engine.pool.count == 6, "G, A and B on each clef")
        #expect(engine.pendingIntros == [key("treble:B4"), key("bass:B2")])
        #expect(engine.screenSize >= 2, "1.2 starts at 2 per screen")
        #expect(engine.status(ofLesson: "1.1") == .completed)
        #expect(engine.status(ofLesson: "1.2") == .current)
        #expect(engine.status(ofLesson: "1.3") == .upcoming)
    }

    @Test func lessonNeedsEnoughScreensEvenWhenHeKnowsEverything() {
        var engine = engine(in: "2.1")
        let t = engine.pool(.treble), b = engine.pool(.bass)
        // every note twice (box 3), right and quick, over exactly 10 screens
        let screens = [[t[0], t[1]], [t[2], t[3]], [t[4], t[0]], [t[1], t[2]], [t[3], t[4]],
                       [b[0], b[1]], [b[2], b[3]], [b[4], b[0]], [b[1], b[2]], [b[3], b[4]]]
        for (i, screen) in screens.enumerated() {
            engine.play(screen, time: 1)
            #expect(engine.lesson.id == (i < 9 ? "2.1" : "2.2"), "after screen \(i + 1)")
        }
    }

    /// Level 1 drills: a new note needs 10 plays in its lesson, however fast he is (the
    /// fast track can't end the lesson early).
    @Test func aDrillLessonWaitsForTenPlaysOfEachNewNote() {
        var engine = engine(in: "1.2")
        let known = [key("treble:G4"), key("treble:A4"), key("bass:G2"), key("bass:A2")]
        let new = [key("treble:B4"), key("bass:B2")]
        var screens = 0
        // B a little at a time: box 3 and the fast track come long before 10 plays
        while engine.lesson.id == "1.2", screens < 100 {
            screens += 1
            for k in known { engine.play([k, k], time: 1) }
            for k in new { engine.play([k], time: 1) }
            if engine.lesson.id == "1.2" {
                #expect(new.contains { engine.lessonPlays($0) < 10 }, "still in 1.2 with every B played 10 times")
            }
        }
        #expect(engine.lesson.id == "1.3")
        #expect(screens == 10, "B played once a round: 10 rounds")
    }

    @Test func parentJumpsAndMovingBack() {
        var engine = MasteryEngine()
        engine.moveToLesson("1.3")
        #expect(engine.lesson.id == "1.3")
        #expect(engine.pool.count == 8, "known notes and C unlock on entry")
        #expect(engine.pendingIntros == [key("treble:C5"), key("bass:C3")], "known notes don't get intros, only the new C")
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
        #expect(MasteryEngine(state: state).pool.count == 4)
        let config = try JSONDecoder().decode(NoteCoreConfig.self, from: Data(#"{"sessionMaxItems": 30}"#.utf8))
        #expect(config.sessionMaxItems == 30)
        #expect(config.fastTrackCount == NoteCoreConfig.default.fastTrackCount)
    }

    @Test func everyConfigFieldDecodes() throws {
        var config = NoteCoreConfig()
        config.newestShare = 0.31
        config.sizeWindow = 6
        config.lessonMinScreens = 12
        config.lessonMinNewPlays = 12
        config.pacedNewestShare = 0.4
        config.introSpacing = 3
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
        #expect(engine.pool(.treble).count == 2)
        #expect(!engine.needsIntro(key("treble:G4")), "he met G4 in round 1")
        #expect(engine.allProgress.map(\.id) == ["treble:C4", "treble:E4", "treble:G4"])
    }

    /// A round 2 save in the old 1.1, like his iPad's: 3 notes a clef drawn at random
    /// (treble B4 C5 D5, bass A2 C3 D3), met and played, mid-lesson.
    static let oldOnePointOne = #"""
    {"lesson":"1.1","completedLessons":[],
     "unlocked":["treble:B4","treble:C5","treble:D5","bass:A2","bass:C3","bass:D3"],
     "introduced":["treble:B4","treble:C5","treble:D5","bass:A2","bass:C3","bass:D3"],
     "stats":{
       "treble:B4":{"box":4,"recent":[{"firstTry":true,"responseTime":2.1},{"firstTry":true,"responseTime":1.8}],"attempts":11,"firstTryCount":9,"peakFluency":0.5},
       "treble:C5":{"box":2,"recent":[{"firstTry":false,"responseTime":5.2}],"attempts":8,"firstTryCount":5,"peakFluency":0.3},
       "treble:D5":{"box":3,"recent":[{"firstTry":true,"responseTime":2.9}],"attempts":9,"firstTryCount":7,"peakFluency":0.4},
       "bass:A2":{"box":3,"recent":[{"firstTry":true,"responseTime":3.3}],"attempts":10,"firstTryCount":7,"peakFluency":0.35},
       "bass:C3":{"box":2,"recent":[{"firstTry":false,"responseTime":6.0}],"attempts":7,"firstTryCount":4,"peakFluency":0.25},
       "bass:D3":{"box":2,"recent":[{"firstTry":true,"responseTime":4.1}],"attempts":6,"firstTryCount":4,"peakFluency":0.2}
     },
     "newest":{"treble":["treble:B4","treble:C5","treble:D5"],"bass":["bass:A2","bass:C3","bass:D3"]},
     "lessonScreens":14,"lessonRecent":[{"firstTry":true,"responseTime":2.0},{"firstTry":false,"responseTime":4.0}],
     "rhythmRecent":[],"rhythmDemos":{},"screenSize":2,"sizeRecent":[{"notes":2,"firstTry":2}],
     "recentScreens":["treble:B4-C5","bass:A2-D3"],"recentColumns":["bass:A2","bass:D3"],"lastScreenWasIntro":false,
     "recentSongs":[],"lessonPeak":0.4,"dice":{"state":12345}}
    """#

    /// The first screens of a session from `state`, as note ids (intros marked).
    static func firstScreens(_ state: MasteryState, count: Int = 24) -> [String] {
        var bench = Bench(MasteryEngine(state: state), seed: 4)
        _ = bench.start()
        var screens: [String] = []
        // only this lesson's screens: a quick finish moves him on
        while bench.session.phase != .done, screens.count < count, bench.session.engine.lesson.id == state.lesson {
            let keys = bench.session.item!.notes.flatMap(\.keys).map(\.id)
            screens.append(bench.session.isIntro ? "intro " + keys[0] : keys.joined(separator: " "))
            _ = bench.playScreen()
            _ = bench.next()
        }
        return screens
    }

    /// His iPad after round 3: the new 1.1 shows only G and A, with intros for the ones
    /// he never met. Nothing is reset: his old notes keep their stats and stay unlocked.
    @Test func hisOldOnePointOneBecomesGAndA() throws {
        let state = try JSONDecoder().decode(MasteryState.self, from: Data(Self.oldOnePointOne.utf8))
        let engine = MasteryEngine(state: state)
        #expect(engine.lesson.id == "1.1")
        #expect(engine.pool(.treble) == [key("treble:G4"), key("treble:A4")])
        #expect(engine.pool(.bass) == [key("bass:G2"), key("bass:A2")])
        #expect(engine.pendingIntros == [key("treble:G4"), key("treble:A4"), key("bass:G2")], "he met A2 already")
        #expect(engine.newestBatch(.treble) == [key("treble:G4"), key("treble:A4")], "the old B C D don't leak in")
        #expect(engine.newestBatch(.bass) == [key("bass:G2")])
        #expect(engine.stats(for: key("treble:B4")).box == 4 && engine.isUnlocked(key("treble:B4")))
        #expect(!engine.canPlaySongs)
        let screens = Self.firstScreens(state)
        let allowed: Set<String> = ["treble:G4", "treble:A4", "bass:G2", "bass:A2"]
        for screen in screens {
            #expect(screen.replacingOccurrences(of: "intro ", with: "").split(separator: " ").allSatisfy { allowed.contains(String($0)) }, "\(screen)")
        }
        #expect(screens.filter { $0.hasPrefix("intro") } == ["intro treble:G4", "intro treble:A4", "intro bass:G2"], "\(screens)")
    }

    /// A save in the old 1.2 (all of G position met): the new 1.2 is G, A and B, no
    /// intros, B drilled before it moves on.
    @Test func hisOldOnePointTwoIsAddB() throws {
        var json = try JSONSerialization.jsonObject(with: Data(Self.oldOnePointOne.utf8)) as! [String: Any]
        let all = Curriculum.trebleG.map { "treble:\($0.name)" } + Curriculum.bassG.map { "bass:\($0.name)" }
        json["lesson"] = "1.2"
        json["completedLessons"] = ["1.1"]
        json["unlocked"] = all
        json["introduced"] = all
        json["newest"] = [String: Any]()
        var stats = json["stats"] as! [String: Any]
        for id in all where stats[id] == nil {
            stats[id] = ["box": 4, "recent": [["firstTry": true, "responseTime": 2.0]], "attempts": 12, "firstTryCount": 10, "peakFluency": 0.5]
        }
        json["stats"] = stats
        let state = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        let engine = MasteryEngine(state: state)
        #expect(engine.lesson.id == "1.2")
        #expect(engine.pool.map(\.id) == ["treble:G4", "treble:A4", "treble:B4", "bass:G2", "bass:A2", "bass:B2"])
        #expect(engine.pendingIntros.isEmpty)
        #expect(engine.newestBatch(.treble) == [key("treble:B4")], "B still gets its share")
        #expect(!engine.hasMinPlays(key("treble:B4")))
        for screen in Self.firstScreens(state) {
            #expect(!screen.contains("C5") && !screen.contains("D5") && !screen.contains("C3") && !screen.contains("D3"), "\(screen)")
        }
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
