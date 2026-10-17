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
        #expect(path.stones.count == 5, "1.1-1.4 and the drill lesson")
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
        var engine = engine("2.1", config: config)
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
        var engine = engine("2.1", config: config)
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
        var engine = engine("2.1")
        for _ in 0..<40 { engine.play(engine.pool.prefix(3).map { $0 }, time: 5, reason: .normal) }
        #expect(engine.lesson.id == "2.1")
        #expect(engine.lessonProgress == MasteryEngine.lessonFractionCap)
    }

    /// Finishing a lesson fills its stone and he steps onto the next, empty one.
    @Test func finishingALessonMovesHimOn() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        var engine = engine("2.2", config: config)
        solid(&engine)
        engine.config.lessonMinScreens = NoteCoreConfig().lessonMinScreens
        var moved = false
        for _ in 0..<40 where !moved {
            let update = engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal)
            moved = update.completedLesson == "2.2"
        }
        #expect(moved)
        let path = engine.levelProgress
        #expect(engine.lesson.id == "2.3")
        #expect(path.current == 2)
        #expect(path.stones[1] == 1)
        #expect(path.stones[2] < 0.2, "a new lesson starts nearly empty: \(path.stones[2])")
        #expect(path.stones[0] == 0, "2.1 was skipped over (the test moved him), so it's empty")
    }

    /// Finishing the last lesson of a level: the new level's path, empty.
    @Test func finishingALevelStartsAnEmptyPath() {
        var engine = engine("1.5")
        solid(&engine)
        // a drill lesson ends on habit, which takes two days
        for day in 1...3 {
            engine.beginSession(day: day)
            for i in 0..<20 where engine.lesson.level == 1 {
                // each note first now and then: the first note of a screen isn't in-line
                let pool = engine.pool
                engine.play(Array(pool[(i % pool.count)...] + pool[..<(i % pool.count)]), reason: .normal, size: engine.screenSize)
            }
        }
        #expect(engine.lesson.id == "2.1")
        let path = engine.levelProgress
        #expect(path.level == 2 && path.stones.count == 4 && path.current == 0)
        #expect(engine.levelProgress(ofLevel: 1).stones[4] == 1)
        #expect(engine.levelProgress(ofLevel: 1).current == nil)
    }

    /// A parent moving him starts that lesson's stone from empty.
    @Test func aParentMoveStartsTheLessonFresh() {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        var engine = engine("2.1", config: config)
        for _ in 0..<6 { engine.play(engine.pool.prefix(3).map { $0 }, reason: .normal) }
        #expect(engine.lessonProgress > 0.3)
        engine.moveToLesson("2.3")
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

    /// A drill lesson's stone keeps filling while its new notes get their 10 plays, so it
    /// doesn't sit at the cap for half the lesson once they reach box 3.
    @Test func aDrillLessonsStoneFillsWithPlays() {
        var engine = engine("1.2")
        let b = [key("treble:B4"), key("bass:B2")]
        for k in b { for _ in 0..<3 { engine.play(k) } } // box 4, 3 plays
        let atBoxThree = engine.lessonProgress
        for k in b { for _ in 0..<5 { engine.play(k) } } // 8 plays
        #expect(engine.lessonProgress > atBoxThree, "\(atBoxThree) -> \(engine.lessonProgress)")
        #expect(engine.lesson.id == "1.2")
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

/// The level-up splash (plans/2026-10-16-progress-and-tunes.md, section 2): once per
/// level, ever, only when he finished the level before.
@Suite struct LevelUpTests {
    func engine(_ lesson: LessonID) -> MasteryEngine {
        NoteCoreTests.engine(in: lesson, seed: 3)
    }

    /// Plays right screens, a session a day, until he leaves `level` (each level ends on
    /// its drill lesson, which finishes on habit over two days). Returns the updates.
    @discardableResult
    func finish(level: Int, _ engine: inout MasteryEngine, seed: UInt64 = 4) -> [MasteryUpdate] {
        var rng = SeededRandom(seed: seed)
        var updates: [MasteryUpdate] = []
        var day = (engine.state.sessionDay) + 1
        for i in 0..<1200 where engine.lesson.level == level {
            if i % 20 == 0 {
                engine.beginSession(day: day)
                day += 1
            }
            updates.append(engine.playPick(engine.pickScreen(using: &rng)))
        }
        return updates
    }

    @Test func finishingALevelWaitsForItsSplash() {
        var engine = engine("1.4")
        #expect(engine.pendingLevelUp == nil)
        let updates = finish(level: 1, &engine)
        #expect(engine.lesson.id == "2.1")
        #expect(updates.compactMap(\.levelUp) == [2])
        #expect(engine.pendingLevelUp == 2)
        engine.celebrateLevelUp()
        #expect(engine.pendingLevelUp == nil)
        #expect(engine.state.celebratedLevels == [2])
    }

    @Test func aLessonInsideALevelIsNoLevelUp() {
        var engine = engine("1.2")
        let updates = finish(level: 1, &engine)
        let entered = updates.compactMap(\.enteredLesson)
        #expect(entered.first == "1.3")
        // 1.2 -> 1.3 -> 1.4 -> 1.5 -> 2.1: only the last one is a new level
        #expect(updates.compactMap(\.levelUp) == [2])
    }

    @Test func oncePerLevelEver() {
        var engine = engine("1.4")
        finish(level: 1, &engine)
        engine.celebrateLevelUp()
        // a parent moves him back, and he finishes level 1 again
        engine.moveToLesson("1.5")
        let updates = finish(level: 1, &engine)
        #expect(engine.lesson.level == 2)
        #expect(updates.compactMap(\.levelUp).isEmpty)
        #expect(engine.pendingLevelUp == nil)
    }

    @Test func theLevelPickerIsNoLevelUp() {
        var engine = engine("1.2")
        engine.moveToLevel(2)
        #expect(engine.lesson.level == 2)
        #expect(engine.pendingLevelUp == nil)
        engine.moveToLevel(3)
        #expect(engine.pendingLevelUp == nil)
        #expect(engine.state.celebratedLevels.isEmpty)
    }

    /// A parent move while a splash is waiting drops it: it would be for a level he isn't in.
    @Test func aParentMoveDropsAWaitingSplash() {
        var engine = engine("1.4")
        finish(level: 1, &engine)
        #expect(engine.pendingLevelUp == 2)
        engine.moveToLesson("1.2")
        #expect(engine.pendingLevelUp == nil)
    }

    @Test func theSessionPassesItOn() {
        var engine = engine("1.4")
        finish(level: 1, &engine)
        var session = PracticeSession(engine: engine, seed: 1, pianoConnected: true)
        #expect(session.engine.pendingLevelUp == 2)
        session.celebrateLevelUp()
        #expect(session.engine.pendingLevelUp == nil)
        #expect(session.engine.state.celebratedLevels.contains(2))
    }

    @Test func savedStateWithoutLevelUpsStillDecodes() throws {
        var engine = engine("1.4")
        finish(level: 1, &engine)
        let data = try JSONEncoder().encode(engine.state)
        let back = try JSONDecoder().decode(MasteryState.self, from: data)
        #expect(back.levelUps == [2])
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "levelUps")
        json.removeValue(forKey: "celebratedLevels")
        let old = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.levelUps.isEmpty && old.celebratedLevels.isEmpty)
        #expect(old.lesson == engine.state.lesson)
    }
}
