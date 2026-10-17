import Testing
@testable import NoteCore

/// Simulated kids through real sessions with the default config, to check pacing.
/// Round 2's "4-6 notes per clef within the first session or two" was replaced in round
/// 3 by a slower, drilled level 1. The numbers are written to context/notecore-design.md.
@Suite struct PacingTests {
    struct Kid {
        var name: String
        /// seconds to find each note
        var time: Double
        /// chance a note is right first try
        var rightRate: Double
    }

    struct SessionLog {
        var lesson: LessonID
        var screens = 0
        var intros = 0
        var size = 0
        var treble = 0
        var bass = 0
        var minutes = 0.0
        var firstTryRate = 0.0
    }

    /// Plays `sessions` sessions. A miss is one wrong key, then the right one.
    static func simulate(_ kid: Kid, sessions: Int, seed: UInt64 = 1) -> [SessionLog] {
        var engine = MasteryEngine(state: MasteryState(seed: seed))
        var dice = SeededRandom(seed: seed &+ 99)
        var logs: [SessionLog] = []
        for s in 0..<sessions {
            var bench = Bench(engine, seed: seed &* 1000 &+ UInt64(s))
            var log = SessionLog(lesson: engine.lesson.id)
            _ = bench.start()
            while bench.session.phase != .done {
                if bench.session.isIntro {
                    log.intros += 1
                    _ = bench.playScreen(after: 2)
                } else {
                    log.screens += 1
                    while bench.session.phase.isPlaying {
                        if unitInterval(&dice) >= kid.rightRate {
                            _ = bench.press(bench.wrongKey, after: kid.time)
                        }
                        _ = bench.playNote(after: kid.time)
                    }
                }
                _ = bench.next(after: 1.2)
            }
            engine = bench.session.engine
            log.size = engine.screenSize
            log.treble = engine.pool(.treble).count
            log.bass = engine.pool(.bass).count
            log.minutes = bench.session.summary.activeDuration / 60
            let summary = bench.session.summary
            log.firstTryRate = Double(summary.firstTryNotes) / Double(max(1, summary.notesPlayed))
            logs.append(log)
        }
        return logs
    }

    static func report(_ kid: Kid, _ logs: [SessionLog]) -> String {
        var lines = ["\(kid.name):"]
        for (i, log) in logs.enumerated() {
            lines.append("  session \(i + 1): lesson \(log.lesson), \(log.screens) screens + \(log.intros) intros, "
                + "\(String(format: "%.1f", log.minutes)) min, size \(log.size) at the end, treble \(log.treble) bass \(log.bass) notes, "
                + "\(Int((log.firstTryRate * 100).rounded()))% first try")
        }
        return lines.joined(separator: "\n")
    }

    static let quick = Kid(name: "quick, always right, 1.2s a note", time: 1.2, rightRate: 1)
    static let steady = Kid(name: "3s a note, 90% right first try", time: 3, rightRate: 0.9)

    /// Round 3 (plans/2026-10-16-round-3-feedback.md): level 1 starts with G and A on
    /// each clef and adds one letter a lesson, each drilled. A quick kid doesn't race
    /// through it: G and A for the first session, never more than one new letter a clef
    /// in a session after that, level 1 done in about 6-8 sessions.
    @Test func quickKidIsDrilledThroughLevelOne() {
        for seed: UInt64 in 1...5 {
            let logs = Self.simulate(Self.quick, sessions: 8, seed: seed)
            #expect(logs[0].treble == 2 && logs[0].bass == 2, "seed \(seed): session 1 is G and A")
            for (a, b) in zip(logs, logs.dropFirst()) where b.lesson.hasPrefix("1.") {
                #expect(b.treble - a.treble <= 1 && b.bass - a.bass <= 1, "seed \(seed): one new letter a session at most")
            }
            let levelOne = logs.filter { $0.lesson.hasPrefix("1.") }.count
            #expect((5...8).contains(levelOne), "seed \(seed): \(levelOne) sessions in level 1")
            if seed == 1 { print(Self.report(Self.quick, logs)) }
        }
    }

    @Test func steadyKidStaysNearEightyPercentAndKeepsMoving() {
        let logs = Self.simulate(Self.steady, sessions: 8)
        print(Self.report(Self.steady, logs))
        for log in logs.dropFirst() {
            #expect(log.firstTryRate > 0.75, "\(log.firstTryRate)")
        }
        // a burst of drill screens a session takes some screens from the newest note: G
        // position by session 6 (5 before the drills round), level 2 still by session 8
        #expect(logs[5].treble >= 5 && logs[5].bass >= 5, "all of G position within 6 sessions")
        #expect(logs[logs.count - 1].lesson.hasPrefix("2.") || logs[logs.count - 1].lesson.hasPrefix("3."), "past level 1 within 8 sessions")
        #expect(logs[logs.count - 1].size >= 3)
    }
}
