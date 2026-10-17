import Testing
@testable import NoteCore

/// Finger numbers (plans/2026-10-16-drills-and-habit.md section 5): a drill screen's first
/// note and the lit key of the hint picture, fading as the note becomes habit.
@Suite struct FingerTests {
    func bench(_ id: LessonID, drill: Drill, seed: UInt64 = 1) -> Bench {
        var bench = Bench(engine(in: id), seed: seed)
        bench.session.openWithDrill = drill
        _ = bench.start()
        return bench
    }

    @Test func aDrillScreensFirstNoteHasItsFinger() throws {
        var bench = bench("1.4", drill: .run)
        #expect(bench.session.drill == .run)
        let marks = bench.session.fingerMarks
        try #require(marks.count == 1, "\(marks)")
        let first = bench.session.item!.notes[0]
        let expected = HandPosition.g(first.clef).finger(first.pitches[0])
        #expect(marks[0].note == 0 && marks[0].finger == expected)
        #expect(marks[0].strength == 1, "nothing is habit yet")
        // a normal screen has none on the staff
        _ = bench.playScreen()
        _ = bench.next()
        if bench.session.drill == nil { #expect(bench.session.fingerMarks.isEmpty) }
    }

    @Test func theHintPictureShowsTheFingerOnTheLitKey() throws {
        var bench = bench("2.1", drill: .home)
        for _ in 0..<3 { _ = bench.press(bench.wrongKey) }
        #expect(bench.session.phase == .hint2)
        let hint = bench.session.hintFingers
        try #require(hint.count == 1)
        #expect(hint[0].pitch == bench.expected[0])
        #expect(hint[0].finger == HandPosition.g(hint[0].clef).finger(hint[0].pitch))
    }

    @Test func noFingersOnIntros() {
        var bench = Bench(MasteryEngine(state: MasteryState(seed: 1)), seed: 1)
        _ = bench.start()
        #expect(bench.session.isIntro)
        #expect(bench.session.fingerMarks.isEmpty && bench.session.hintFingers.isEmpty, "the letter is on the key there")
    }

    /// It fades: gone once the note is habit.
    @Test func aHabitNoteHasNoFinger() {
        var engine = engine(in: "1.5")
        for day in 1...2 {
            engine.beginSession(day: day)
            for _ in 0..<10 {
                let notes = engine.pool.map { AttemptResult(itemID: $0.id, lesson: "1.5", level: 1, firstTry: true, responseTime: 1, inLine: true) }
                engine.record(ScreenResult(screenID: "x", lesson: "1.5", reason: .warmUp, notes: notes))
            }
        }
        #expect(engine.pool.allSatisfy(engine.isHabit))
        var bench = Bench(engine, seed: 2)
        bench.session.openWithDrill = .run
        _ = bench.start()
        #expect(bench.session.drill == .run)
        #expect(bench.session.fingerMarks.isEmpty)
    }

    /// Level 3's shift screens: a finger on the first note, and on the note where the hand moves.
    @Test func aShiftScreenMarksTheShiftNote() throws {
        var bench = bench("3.7", drill: .shift)
        try #require(bench.session.drill == .shift)
        let marks = bench.session.fingerMarks
        let item = bench.session.item!
        let shift = item.bars[0]
        #expect(marks.map(\.note) == [0, shift], "\(item.id) \(marks)")
        #expect(marks[1].finger == bench.session.positions[shift].finger(item.notes[shift].pitches[0]))
    }

    /// An echo's second bar is the other hand starting, not a shift: one finger.
    @Test func anEchoHasOneFinger() {
        let bench = bench("2.4", drill: .echo)
        #expect(bench.session.drill == .echo)
        #expect(bench.session.fingerMarks.map(\.note) == [0])
    }

    /// Two at once: a finger for each key.
    @Test func aColumnOfTwoHasTwoFingers() {
        let bench = bench("4.5", drill: .movedTwo)
        #expect(bench.session.fingerMarks.count == 2)
        #expect(Set(bench.session.fingerMarks.map(\.note)) == [0])
    }
}
