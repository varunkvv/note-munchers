import Foundation
import Testing
@testable import NoteCore

/// Section 4 of plans/2026-10-16-drills-and-habit.md: knowing a note vs it being automatic.
@Suite struct HabitTests {
    let g = key("treble:G4")

    /// `count` in-line plays of G4 at these times (cycled), in one session on `day`.
    func session(_ engine: inout MasteryEngine, day: Int, times: [Double], count: Int = 10, firstClean: Bool = true, almost: Bool = false) {
        engine.beginSession(day: day)
        for i in 0..<count {
            let clean = i > 0 || firstClean
            let note = AttemptResult(itemID: g.id, lesson: engine.lesson.id, level: engine.lesson.level, firstTry: clean,
                                     wrongPresses: clean ? 0 : 1, almostPresses: almost ? 1 : 0,
                                     responseTime: times[i % times.count], inLine: true)
            engine.record(ScreenResult(screenID: "t\(i)", lesson: engine.lesson.id, reason: .warmUp, notes: [note]))
        }
    }

    @Test func aSteadyNoteOnTwoDaysIsHabit() {
        var engine = engine(in: "1.5")
        session(&engine, day: 1, times: [1.2, 1.4, 1.1, 1.3])
        #expect(!engine.isHabit(g), "a steady note on one day isn't habit")
        #expect(engine.habit(g).cleanDays == 1)
        session(&engine, day: 1, times: [1.2, 1.4, 1.1, 1.3])
        #expect(!engine.isHabit(g), "two sessions on the same day are still one day")
        session(&engine, day: 2, times: [1.2, 1.4, 1.1, 1.3])
        #expect(engine.isHabit(g), "steady on two different days: \(engine.habit(g))")
        #expect(engine.habit(g).fraction == 1)
    }

    @Test func fastButShakyIsntHabit() {
        var engine = engine(in: "1.5")
        session(&engine, day: 1, times: [0.4, 2.6, 0.5, 1.9, 0.6])
        session(&engine, day: 2, times: [0.4, 2.6, 0.5, 1.9, 0.6])
        let habit = engine.habit(g)
        #expect(habit.median! < 2, "fast enough on the median")
        #expect(habit.steadiness! > 0.4, "but shaky: \(habit.steadiness!)")
        #expect(!habit.isHabit)
    }

    @Test func slowIsntHabit() {
        var engine = engine(in: "1.5")
        session(&engine, day: 1, times: [2.5, 2.6, 2.4])
        session(&engine, day: 2, times: [2.5, 2.6, 2.4])
        #expect(!engine.isHabit(g))
        #expect(engine.habit(g).fraction > 0.7, "close, though: \(engine.habit(g).fraction)")
    }

    @Test func aMissedFirstShowingOnTheLatestDayIsntHabit() {
        var engine = engine(in: "1.5")
        session(&engine, day: 1, times: [1.2])
        session(&engine, day: 2, times: [1.2])
        #expect(engine.isHabit(g))
        session(&engine, day: 3, times: [1.2], count: 1, firstClean: false)
        #expect(!engine.isHabit(g), "today's first one was a miss")
    }

    /// The right letter in the wrong octave holds the box, but it isn't automatic.
    @Test func aWrongOctaveIsntAutomatic() {
        var engine = engine(in: "1.5")
        session(&engine, day: 1, times: [1.2], almost: true)
        session(&engine, day: 2, times: [1.2], almost: true)
        #expect(engine.stats(for: g).box >= 3, "the box holds")
        #expect(engine.habit(g).firstTries == 0)
        #expect(!engine.isHabit(g))
    }

    /// In-line means reading from one note to the next: not a screen's first note, not
    /// the same key again, not a rhythm-judged screen, not an intro or a second read, not
    /// bar 2 of a pattern screen played from memory.
    @Test func whatCountsAsInLine() {
        var bench = Bench(engine(in: "1.4"), seed: 2)
        _ = bench.start()
        var checked = 0
        while bench.session.phase != .done {
            let item = bench.session.item!
            let reason = bench.session.pickReason
            _ = bench.playScreen()
            let recalled = bench.session.recalledNotes
            let notes = bench.session.summary.screens.last!.notes
            for (i, note) in notes.enumerated() {
                let repeated = i > 0 && item.notes[i].pitches == item.notes[i - 1].pitches
                #expect(note.inLine == (i > 0 && !repeated && reason != .again && !note.wasIntro && !recalled.contains(i)), "\(item.id) note \(i)")
                #expect(note.fromMemory == recalled.contains(i))
                checked += 1
            }
            _ = bench.next()
        }
        #expect(checked > 30)
        // rhythm lines and rhythm-judged screens give no in-line times (their gaps are the rhythm)
        var rhythm = Bench(engine(in: "5.3"), seed: 2)
        _ = rhythm.start()
        for _ in 0..<12 {
            let judged = rhythm.session.rhythmLine != nil
            _ = rhythm.playScreen()
            if judged {
                #expect(rhythm.session.summary.screens.last!.notes.allSatisfy { !$0.inLine })
            }
            _ = rhythm.next()
        }
    }

    /// Drill screens lean toward notes that aren't habit yet.
    @Test func drillsLeanTowardNotesThatArentHabit() {
        var stay = NoteCoreConfig()
        stay.lessonMinScreens = 10_000
        var engine = engine(in: "2.1", config: stay)
        let treble = engine.pool(.treble)
        let b4 = key("treble:B4")
        for day in 1...2 {
            engine.beginSession(day: day)
            for _ in 0..<10 {
                // B4 is only ever a screen's first note: no in-line times, so not habit
                let notes = treble.map { AttemptResult(itemID: $0.id, lesson: "2.1", level: 2, firstTry: true, responseTime: 1, inLine: $0 != b4) }
                engine.record(ScreenResult(screenID: "x", lesson: "2.1", reason: .warmUp, notes: notes))
            }
        }
        #expect(!engine.isHabit(b4))
        #expect(treble.filter { $0 != b4 }.allSatisfy(engine.isHabit))
        var rng = SeededRandom(seed: 1)
        var b = 0, all = 0
        for _ in 0..<200 {
            let keys = engine.pickScreen(.drill, clef: .treble, using: &rng).item.notes.flatMap(\.keys)
            b += keys.filter { $0 == b4 }.count
            all += keys.count
        }
        #expect(Double(b) / Double(all) > 0.25, "B4 gets more than its 1 in 5: \(b) of \(all)")
    }

    /// The drill lesson waits for habit on two days, and lets him go after
    /// `drillLessonMaxDays` days in it even if habit doesn't come.
    @Test func aDrillLessonEndsOnHabitOrAfterEnoughDays() {
        func sessions(time: Double, jitter: Double, days: Int, maxDays: Int = NoteCoreConfig().drillLessonMaxDays,
                      seed: UInt64 = 0) -> (lesson: LessonID, day: Int?) {
            var config = NoteCoreConfig()
            config.drillLessonMaxDays = maxDays
            var engine = engine(in: "1.5", config: config)
            var finished: Int?
            for day in 1...days where finished == nil {
                var bench = Bench(engine, seed: seed &* 100 &+ UInt64(day))
                _ = bench.start()
                var n = 0
                while bench.session.phase != .done {
                    while bench.session.phase.isPlaying {
                        n += 1
                        _ = bench.playNote(after: time * (1 + jitter * (n % 2 == 0 ? 1 : -1)))
                    }
                    _ = bench.next()
                }
                engine = bench.session.engine
                if engine.lesson.id != "1.5" { finished = day }
            }
            return (engine.lesson.id, finished)
        }
        // with no way out but habit, a quick steady reader gets there in a few days
        var quickDays: [Int] = []
        for seed: UInt64 in 1...6 {
            let quick = sessions(time: 1.2, jitter: 0.2, days: 8, maxDays: 99, seed: seed)
            #expect(quick.lesson != "1.5", "seed \(seed): \(quick)")
            quickDays.append(quick.day ?? 99)
        }
        print("quick kid, 1.5 done on day \(quickDays)")
        #expect(quickDays.allSatisfy { (2...5).contains($0) }, "\(quickDays)")
        let slow = sessions(time: 3, jitter: 0.1, days: 6)
        #expect(slow.lesson != "1.5" && slow.day == NoteCoreConfig().drillLessonMaxDays, "a slow reader still moves on: \(slow)")
        let shaky = sessions(time: 1.2, jitter: 0.8, days: 6, maxDays: 99)
        #expect(shaky.lesson == "1.5", "shaky isn't habit: \(shaky)")
    }

    /// His iPad's saved state has notes saved before habit: they decode, with no habit.
    @Test func samplesSavedBeforeHabitStillDecode() throws {
        let json = #"""
        {"lesson": "1.2", "unlocked": ["treble:G4"], "introduced": ["treble:G4"],
         "stats": {"treble:G4": {"box": 4, "recent": [{"firstTry": true, "responseTime": 1.5}, {"firstTry": false, "responseTime": 3}],
                                 "attempts": 12, "firstTryCount": 10, "peakFluency": 0.5}},
         "lessonRecent": [{"firstTry": true, "responseTime": 1.5}]}
        """#
        let state = try JSONDecoder().decode(MasteryState.self, from: Data(json.utf8))
        #expect(state.stats["treble:G4"]?.recent.count == 2)
        #expect(state.stats["treble:G4"]?.recent[0].session == 0)
        #expect(state.stats["treble:G4"]?.inLine == [])
        #expect(state.lessonRecent.count == 1 && state.session == 0)
        let engine = MasteryEngine(state: state)
        #expect(!engine.isHabit(g))
        #expect(engine.habit(g).fraction == 0)
        let attempt = try JSONDecoder().decode(AttemptResult.self, from: Data(#"{"itemID": "treble:G4", "firstTry": true, "responseTime": 1}"#.utf8))
        #expect(!attempt.inLine)
    }

    @Test func habitRoundTripsThroughJSON() throws {
        var engine = engine(in: "1.5")
        session(&engine, day: 1, times: [1.2])
        session(&engine, day: 2, times: [1.2])
        let decoded = try JSONDecoder().decode(MasteryState.self, from: JSONEncoder().encode(engine.state))
        #expect(decoded == engine.state)
        #expect(MasteryEngine(state: decoded).isHabit(g))
    }
}

@Suite struct ParentMoveDayTests {
    /// A parent moving him into a drill lesson between sessions: his last session's day
    /// isn't a day in the new lesson, so the 2-day floor and the day cap start fresh.
    @Test func aParentMoveStartsTheLessonsDaysFresh() {
        var engine = engine(in: "1.4")
        engine.beginSession(day: 5)
        engine.moveToLesson("1.5")
        #expect(engine.state.lessonDays.isEmpty)
        engine.beginSession(day: 6)
        #expect(engine.state.lessonDays == [6])
    }
}
