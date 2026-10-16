import Foundation
import Testing
@testable import NoteCore

/// Section 1 of plans/2026-10-16-drills-and-habit.md: the fixes to the lessons we have.
@Suite struct LessonFixTests {
    /// Levels 1-2: three quick ones in a row don't open the gate, 7 of 8 do.
    @Test func noFastTrackForUnlocksInLevelsOneAndTwo() {
        var engine = MasteryEngine(curriculum: gateCurriculum(level: 1), state: MasteryState(seed: 3))
        engine.introduceAll()
        let treble = engine.pool(.treble)
        for _ in 0..<3 {
            for key in treble { engine.play(key, time: 1) }
        }
        #expect(engine.pool(.treble).count == treble.count, "3 quick right isn't enough in level 1")
        for _ in 0..<4 {
            for key in engine.pool(.treble) { engine.play(key, time: 1) }
        }
        #expect(engine.pool(.treble).count > treble.count, "7 of 8 opens it")
    }

    @Test func theFastTrackStillWorksFromLevelThree() {
        var engine = engine(in: "3.1")
        let newest = engine.newestBatch(.treble)
        #expect(newest.count == 1)
        for _ in 0..<3 {
            for key in engine.pool(.treble) { engine.play(key, time: 1) }
        }
        #expect(engine.pool(.treble).count > 6, "3 quick right open the gate in level 3")
    }

    /// 3.3 and 3.4 split the old 4-note lesson. 3.3-3.5 come in order, middle C first.
    @Test func levelThreeMiddleCLessonsComeInOrder() {
        let curriculum = Curriculum.standard
        #expect(curriculum.lesson("3.3")!.treble!.new == [Pitch(.c, 4), Pitch(.d, 4)])
        #expect(curriculum.lesson("3.4")!.treble!.new == [Pitch(.e, 4), Pitch("F#4")!])
        #expect(curriculum.lesson("3.5")!.bass!.new.first == .middleC)
        for (id, clef, order) in [("3.3", Clef.treble, ["C4", "D4"]), ("3.4", .treble, ["E4", "F#4"]), ("3.5", .bass, ["C4", "B3", "A3"])] {
            for seed: UInt64 in 1...6 {
                var engine = MasteryEngine(state: MasteryState(seed: seed))
                engine.moveToLesson(id)
                var met: [String] = []
                var rng = SeededRandom(seed: seed)
                for _ in 0..<600 where met.count < order.count {
                    let pick = engine.pickScreen(using: &rng)
                    if let intro = pick.intro, intro.clef == clef { met.append(intro.pitch.name) }
                    engine.playPick(pick)
                    if engine.lesson.id != id { break }
                }
                #expect(met == order, "\(id) seed \(seed): \(met)")
            }
        }
    }

    /// Each level 3 screen stays inside one five-finger position per staff.
    @Test func levelThreeScreensStayInOneHandPosition() throws {
        for id in ["3.1", "3.2", "3.3", "3.4", "3.5", "3.6"] {
            var engine = engine(in: id)
            var rng = SeededRandom(seed: 11)
            var used = Set<HandPosition>()
            for _ in 0..<150 {
                let pick = engine.pickScreen(using: &rng)
                try #require(pick.positions.count == pick.item.notes.count, "\(id): a position per column")
                for clef in pick.item.clefs {
                    let keys = pick.item.notes.filter { $0.clef == clef }.flatMap(\.keys)
                    let span = keys.map(\.pitch.diatonicIndex)
                    #expect(span.max()! - span.min()! <= 4, "\(id) \(pick.item.id) moves the hand")
                    let hands = Set(zip(pick.item.notes, pick.positions).filter { $0.0.clef == clef }.map(\.1))
                    #expect(hands.count == 1 && keys.allSatisfy(hands.first!.contains), "\(id) \(pick.item.id)")
                    used.formUnion(hands)
                }
                engine.playPick(pick)
            }
            #expect(used.count >= 2, "\(id) moves between positions from screen to screen: \(used)")
        }
    }

    /// Levels 1-2 and 4-5 are all G position: finger 1 on G in the right hand, 5 on G in the left.
    @Test func gPositionFingers() {
        #expect(HandPosition.g(.treble).finger(Pitch(.g, 4)) == 1)
        #expect(HandPosition.g(.treble).finger(Pitch(.d, 5)) == 5)
        #expect(HandPosition.g(.bass).finger(Pitch(.g, 2)) == 5)
        #expect(HandPosition.g(.bass).finger(Pitch(.d, 3)) == 1)
        #expect(HandPosition.d(.treble).finger(Pitch("F#4")!) == 3)
        #expect(HandPosition.d(.bass).finger(Pitch("F#3")!) == 3)
        #expect(HandPosition.g(.treble).finger(Pitch(.e, 5)) == nil)
        var engine = engine(in: "1.4")
        var rng = SeededRandom(seed: 2)
        for _ in 0..<30 {
            let pick = engine.pickScreen(using: &rng)
            #expect(pick.positions.allSatisfy { $0 == HandPosition.g($0.clef) })
            engine.playPick(pick)
        }
    }

    /// Lessons from level 2 up were renumbered. A saved lesson id that's gone lands in
    /// its own level, at the first lesson not done, never back at 1.1.
    @Test func aSavedLessonIdThatsGoneStaysInItsLevel() throws {
        var state = MasteryState(seed: 5)
        state.lesson = "2.9"
        state.completedLessons = ["1.1", "1.2", "1.3", "1.4", "2.1"]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MasteryState.self, from: data)
        let engine = MasteryEngine(state: decoded)
        #expect(engine.lesson.id == "2.2")
        state.lesson = "9.1"
        #expect(MasteryEngine(state: state).lesson.level == 1, "a level that isn't there: level 1")
    }
}
