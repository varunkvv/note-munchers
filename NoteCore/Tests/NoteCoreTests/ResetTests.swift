import Foundation
import Testing
@testable import NoteCore

/// A parent starting a lesson (or his level) over, plans/2026-10-17-reset-and-repetition.md
/// section 1: where he is goes back, what he knows stays.
@Suite struct ResetTests {
    /// Plays whatever is picked, right first try, a session a day every 20 screens, until
    /// he's in `lesson`. Returns the updates.
    @discardableResult
    func walk(_ engine: inout MasteryEngine, to lesson: LessonID, seed: UInt64 = 4) -> [MasteryUpdate] {
        var rng = SeededRandom(seed: seed)
        var updates: [MasteryUpdate] = []
        var day = engine.state.sessionDay + 1
        for i in 0..<2000 where engine.lesson.id != lesson {
            if i % 20 == 0 {
                engine.beginSession(day: day)
                day += 1
            }
            updates.append(engine.playPick(engine.pickScreen(using: &rng)))
        }
        #expect(engine.lesson.id == lesson, "never got to \(lesson)")
        return updates
    }

    /// `count` more screens in the lesson he's in.
    func play(_ engine: inout MasteryEngine, screens count: Int, seed: UInt64 = 5) {
        var rng = SeededRandom(seed: seed)
        for _ in 0..<count { engine.playPick(engine.pickScreen(using: &rng)) }
    }

    func kid() -> MasteryEngine { MasteryEngine(state: MasteryState(seed: 3)) }

    /// The lesson's own windows are all back to zero, as when he entered it.
    func expectFresh(_ engine: MasteryEngine, _ lesson: LessonID, sourceLocation: SourceLocation = #_sourceLocation) {
        let s = engine.state
        #expect(s.lesson == lesson, sourceLocation: sourceLocation)
        #expect(s.lessonScreens == 0, sourceLocation: sourceLocation)
        #expect(s.lessonRecent.isEmpty, sourceLocation: sourceLocation)
        #expect(s.lessonPlays.isEmpty, sourceLocation: sourceLocation)
        #expect(s.lessonHabit.isEmpty, sourceLocation: sourceLocation)
        #expect(s.lessonDays.isEmpty, sourceLocation: sourceLocation)
        #expect(s.lessonPeak == 0, sourceLocation: sourceLocation)
        #expect(s.rhythmRecent.isEmpty, sourceLocation: sourceLocation)
        #expect(!engine.isLessonDone, sourceLocation: sourceLocation)
    }

    /// His notes: everything a muncher, a box or the dashboard is made of.
    func expectKnowledgeKept(_ engine: MasteryEngine, _ before: MasteryState, sourceLocation: SourceLocation = #_sourceLocation) {
        let s = engine.state
        #expect(s.stats == before.stats, sourceLocation: sourceLocation)
        #expect(s.unlocked == before.unlocked, sourceLocation: sourceLocation)
        #expect(s.introduced == before.introduced, sourceLocation: sourceLocation)
        #expect(s.celebratedLevels == before.celebratedLevels, sourceLocation: sourceLocation)
        #expect(s.session == before.session, sourceLocation: sourceLocation)
    }

    @Test func restartTheLessonHesIn() {
        var engine = kid()
        walk(&engine, to: "1.3")
        play(&engine, screens: 8)
        let before = engine.state
        let stoneBefore = engine.lessonProgress
        #expect(before.lesson == "1.3" && before.lessonScreens > 0 && before.lessonPeak > 0 && !before.lessonPlays.isEmpty)
        let unlocked = engine.restartLesson("1.3")
        #expect(unlocked.isEmpty)
        expectFresh(engine, "1.3")
        expectKnowledgeKept(engine, before)
        #expect(engine.state.completedLessons == ["1.1", "1.2"])
        #expect(engine.pendingIntros.isEmpty, "C was met already")
        #expect(engine.newestBatch(.treble) == [key("treble:C5")], "C still gets its share")
        #expect(!engine.hasMinPlays(key("treble:C5")), "its 10 plays start again")
        #expect(engine.levelProgress.current == 2)
        #expect(engine.lessonProgress < stoneBefore, "\(engine.lessonProgress) vs \(stoneBefore)")
    }

    @Test func restartAnEarlierLessonEmptiesTheLaterStones() {
        var engine = kid()
        walk(&engine, to: "1.4")
        play(&engine, screens: 4)
        let before = engine.state
        #expect(before.completedLessons == ["1.1", "1.2", "1.3"])
        engine.restartLesson("1.2")
        expectFresh(engine, "1.2")
        expectKnowledgeKept(engine, before)
        #expect(engine.state.completedLessons == ["1.1"])
        #expect(engine.status(ofLesson: "1.3") == .upcoming)
        #expect(engine.status(ofLesson: "1.4") == .upcoming)
        let path = engine.levelProgress
        #expect(path.current == 1)
        #expect(path.stones[0] == 1)
        #expect(path.stones[2...].allSatisfy { $0 == 0 }, "\(path.stones)")
        #expect(path.stones[1] < 1)
        #expect(engine.pool.map(\.id) == ["treble:G4", "treble:A4", "treble:B4", "bass:G2", "bass:A2", "bass:B2"])
        // he walks the level again from there: 1.2, then 1.3, nothing new to meet
        let updates = walk(&engine, to: "1.4")
        #expect(updates.compactMap(\.completedLesson) == ["1.2", "1.3"])
        #expect(updates.allSatisfy { $0.unlocked.isEmpty && $0.levelUp == nil })
    }

    /// His iPad today: G A B C D met. Level 1 over from 1.1 is G and A again, no intros.
    @Test func restartLevelOneWithEveryNoteMet() {
        var engine = kid()
        walk(&engine, to: "1.5")
        play(&engine, screens: 6)
        let before = engine.state
        let met = engine.metNotes
        #expect(met.count == 10)
        let unlocked = engine.restartLevel(1)
        #expect(unlocked.isEmpty)
        expectFresh(engine, "1.1")
        expectKnowledgeKept(engine, before)
        #expect(engine.metNotes == met, "every muncher stays")
        #expect(engine.state.completedLessons.isEmpty)
        #expect(engine.pool(.treble) == [key("treble:G4"), key("treble:A4")])
        #expect(engine.pool(.bass) == [key("bass:G2"), key("bass:A2")])
        #expect(engine.pendingIntros.isEmpty)
        #expect(!engine.hasMinPlays(key("treble:G4")))
        #expect(engine.levelProgress.stones.dropFirst().allSatisfy { $0 == 0 })
        // his screens are G and A only, as long as he's in 1.1 (10 plays of each is enough
        // to finish it again)
        var rng = SeededRandom(seed: 9)
        var screens = 0
        var updates: [MasteryUpdate] = []
        for _ in 0..<40 where engine.lesson.id == "1.1" {
            screens += 1
            let pick = engine.pickScreen(using: &rng)
            #expect(pick.intro == nil)
            let ids = Set(pick.item.notes.flatMap(\.keys).map(\.id))
            #expect(ids.isSubset(of: ["treble:G4", "treble:A4", "bass:G2", "bass:A2"]), "\(ids)")
            updates.append(engine.playPick(pick))
        }
        #expect(screens >= 10, "1.1 takes its 10 screens again: \(screens)")
        // then 1.2 brings B back as its newest, with no intro
        updates += walk(&engine, to: "1.2")
        #expect(updates.allSatisfy { $0.unlocked.isEmpty && $0.levelUp == nil })
        #expect(updates.compactMap(\.completedLesson) == ["1.1"])
        #expect(engine.newestBatch(.treble) == [key("treble:B4")])
        #expect(engine.pendingIntros.isEmpty)
        #expect(engine.state.stats[key("treble:D5").id] == before.stats[key("treble:D5").id], "D waits untouched")
    }

    @Test func otherLevelsAreUntouched() {
        var engine = kid()
        var state = engine.state
        state.completedLessons = ["1.1", "1.2", "1.3", "1.4", "1.5", "2.1", "2.2"]
        state.lesson = "2.3"
        engine = MasteryEngine(state: state)
        engine.restartLesson("2.2")
        #expect(engine.state.completedLessons == ["1.1", "1.2", "1.3", "1.4", "1.5", "2.1"])
        engine.restartLevel(2)
        #expect(engine.lesson.id == "2.1")
        #expect(engine.state.completedLessons == ["1.1", "1.2", "1.3", "1.4", "1.5"])
        #expect(engine.status(ofLevel: 1) == .completed)
    }

    /// A restart is never a level-up, and a level he celebrated never celebrates again.
    @Test func aCelebratedLevelNeverCelebratesAgain() {
        var engine = kid()
        walk(&engine, to: "2.1")
        #expect(engine.pendingLevelUp == 2)
        // the splash he earned stays while he stays in level 2
        var inLevel = engine
        inLevel.restartLesson("2.1")
        #expect(inLevel.pendingLevelUp == 2)
        // one for a level he's no longer in goes
        var back = engine
        back.restartLevel(1)
        #expect(back.pendingLevelUp == nil)
        #expect(back.state.celebratedLevels.isEmpty)
        engine.celebrateLevelUp()
        #expect(engine.state.celebratedLevels == [2])
        engine.restartLevel(1)
        #expect(engine.pendingLevelUp == nil)
        let updates = walk(&engine, to: "2.1")
        #expect(updates.allSatisfy { $0.levelUp == nil })
        #expect(engine.pendingLevelUp == nil)
        #expect(engine.state.celebratedLevels == [2])
    }

    @Test func aSavedStateRoundTrips() throws {
        var engine = kid()
        walk(&engine, to: "1.4")
        engine.restartLesson("1.2")
        let data = try JSONEncoder().encode(engine.state)
        let decoded = try JSONDecoder().decode(MasteryState.self, from: data)
        #expect(decoded == engine.state)
        let reloaded = MasteryEngine(state: decoded)
        #expect(reloaded.lesson.id == "1.2")
        #expect(reloaded.levelProgress == engine.levelProgress)
        #expect(reloaded.pool == engine.pool)
    }

    /// His real saved state (an old 1.1 save moved on to 1.2, like `hisOldOnePointTwoIsAddB`)
    /// can start 1.1 over.
    @Test func hisIPadCanStartOnePointOneOver() throws {
        var json = try JSONSerialization.jsonObject(with: Data(MigrationTests.oldOnePointOne.utf8)) as! [String: Any]
        let all = Curriculum.trebleG.map { "treble:\($0.name)" } + Curriculum.bassG.map { "bass:\($0.name)" }
        json["lesson"] = "1.2"
        json["completedLessons"] = ["1.1"]
        json["unlocked"] = all
        json["introduced"] = all
        let state = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        var engine = MasteryEngine(state: state)
        engine.restartLesson("1.1")
        #expect(engine.lesson.id == "1.1")
        #expect(engine.state.completedLessons.isEmpty)
        #expect(engine.pool.map(\.id) == ["treble:G4", "treble:A4", "bass:G2", "bass:A2"])
        #expect(engine.pendingIntros.isEmpty)
        #expect(engine.state.stats == state.stats)
        let again = try JSONDecoder().decode(MasteryState.self, from: JSONEncoder().encode(engine.state))
        #expect(again == engine.state)
    }
}
