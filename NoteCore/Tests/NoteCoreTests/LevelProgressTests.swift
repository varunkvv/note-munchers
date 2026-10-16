import Foundation
import Testing
@testable import NoteCore

/// The level path (LevelProgress.swift): one stone per lesson, the current one filling
/// from the lesson-done rule's parts, never going backwards.
@Suite struct LevelProgressTests {
    func engine(_ lesson: LessonID, config: NoteCoreConfig = NoteCoreConfig()) -> MasteryEngine {
        var engine = MasteryEngine(config: config, state: MasteryState(seed: 3))
        engine.moveToLesson(lesson)
        engine.introduceAll()
        return engine
    }

    /// Box 3+ for every note in the lesson.
    func solid(_ engine: inout MasteryEngine) {
        for key in engine.pool { for _ in 0..<3 { engine.play(key) } }
    }

    @Test func aNewKidStandsOnTheFirstEmptyStone() {
        let engine = MasteryEngine(state: MasteryState(seed: 3))
        let path = engine.levelProgress
        #expect(path.level == 1)
        #expect(path.stones.count == 4)
        #expect(path.current == 0)
        #expect(path.stones.allSatisfy { $0 == 0 }, "\(path.stones)")
        #expect(path.value == 0)
    }

    @Test func meetingNewNotesFillsTheStone() {
        var engine = MasteryEngine(state: MasteryState(seed: 3))
        let before = engine.lessonProgress
        engine.introduceAll()
        let met = engine.lessonProgress
        #expect(met > before)
        for key in engine.pool { for _ in 0..<2 { engine.play(key) } }
        #expect(engine.lessonProgress > met)
        #expect(engine.lessonProgress < MasteryEngine.lessonFractionCap + 1e-9)
    }

    /// A practice lesson (no new notes) fills with screens and right first tries.
    @Test func practiceLessonFillsWithScreensAndRightNotes() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        var engine = engine("1.2", config: config)
        #expect(engine.lessonProgress == 0)
        var last = 0.0
        for i in 0..<12 {
            engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal)
            let now = engine.lessonProgress
            #expect(now >= last, "screen \(i): \(now) < \(last)")
            last = now
        }
        #expect(last > 0.4 && last <= MasteryEngine.lessonFractionCap)
    }

    /// A bad day doesn't undo his path: misses lower the live fraction, not what he sees.
    @Test func neverGoesBackwards() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        var engine = engine("1.2", config: config)
        for _ in 0..<5 { engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal) }
        let peak = engine.lessonProgress
        for _ in 0..<5 { engine.play(engine.pool.prefix(3).map { $0 }, right: false, reason: .normal) }
        #expect(engine.liveLessonFraction < peak)
        #expect(engine.lessonProgress == peak)
        #expect(engine.state.lessonPeak == peak)
    }

    /// Right first try but slow (a median over 4s): every part is full, the lesson isn't
    /// done, the stone stops short of full.
    @Test func staysUnderFullUntilTheLessonIsDone() {
        var engine = engine("1.2")
        for _ in 0..<40 { engine.play(engine.pool.prefix(3).map { $0 }, time: 5, reason: .normal) }
        #expect(engine.lesson.id == "1.2")
        #expect(engine.lessonProgress == MasteryEngine.lessonFractionCap)
    }

    /// Finishing a lesson fills its stone and he steps onto the next, empty one.
    @Test func finishingALessonMovesHimOn() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        var engine = engine("1.2", config: config)
        solid(&engine)
        engine.config.lessonMinScreens = NoteCoreConfig().lessonMinScreens
        var moved = false
        for _ in 0..<40 where !moved {
            let update = engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal)
            moved = update.completedLesson == "1.2"
        }
        #expect(moved)
        let path = engine.levelProgress
        #expect(engine.lesson.id == "1.3")
        #expect(path.current == 2)
        #expect(path.stones[1] == 1)
        #expect(path.stones[2] < 0.2, "a new lesson starts nearly empty: \(path.stones[2])")
        #expect(path.stones[0] == 0, "1.1 was skipped over (the test moved him), so it's empty")
    }

    /// Finishing the last lesson of a level: the new level's path, empty.
    @Test func finishingALevelStartsAnEmptyPath() {
        var engine = engine("1.4")
        solid(&engine)
        for _ in 0..<40 where engine.lesson.level == 1 {
            engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal)
        }
        #expect(engine.lesson.id == "2.1")
        let path = engine.levelProgress
        #expect(path.level == 2 && path.stones.count == 5 && path.current == 0)
        #expect(engine.levelProgress(ofLevel: 1).stones[3] == 1)
        #expect(engine.levelProgress(ofLevel: 1).current == nil)
    }

    /// A parent moving him starts that lesson's stone from empty.
    @Test func aParentMoveStartsTheLessonFresh() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        var engine = engine("1.2", config: config)
        for _ in 0..<6 { engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal) }
        #expect(engine.lessonProgress > 0.3)
        engine.moveToLesson("1.3")
        #expect(engine.state.lessonPeak == 0)
        #expect(engine.lessonProgress == 0)
        #expect(engine.levelProgress.current == 2)
    }

    @Test func rhythmLessonsWaitForTheRhythm() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        var good = engine("5.1", config: config)
        var off = engine("5.1", config: config)
        for _ in 0..<10 {
            good.play([good.pool[0]], rhythmOK: true, size: 1)
            off.play([off.pool[0]], rhythmOK: false, size: 1)
        }
        #expect(good.lessonProgress > off.lessonProgress)
    }

    @Test func savedStateWithoutAPeakStillDecodes() throws {
        var engine = engine("1.2")
        for _ in 0..<4 { engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal) }
        let data = try JSONEncoder().encode(engine.state)
        #expect(try JSONDecoder().decode(MasteryState.self, from: data) == engine.state)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "lessonPeak")
        let old = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.lessonPeak == 0)
        #expect(old.stats == engine.state.stats)
    }
}
