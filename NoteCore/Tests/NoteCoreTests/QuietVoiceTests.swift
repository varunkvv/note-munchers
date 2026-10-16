import Testing
@testable import NoteCore

/// The voice the way he hears it (plans/2026-10-16-round-3-feedback.md): nothing at
/// the start of a screen, at most one earned line mid-session, one line at the end.
/// Driven by a scripted kid through real level 1 sessions.
@Suite struct QuietVoiceTests {
    /// What a scripted kid does on each note he reads (intros he plays right).
    struct Kid {
        var name: String
        /// right first try
        var right: Double
        /// a wrong key first (then the right one)
        var wrong: Double
        /// the right letter an octave up first (then the right one)
        var octave: Double
        // the rest: stuck past `stuckAfter`, one to three rungs, then the right key
    }

    static let scripted = Kid(name: "65% right first try", right: 0.65, wrong: 0.15, octave: 0.10)
    static let steady = Kid(name: "90% right first try", right: 0.9, wrong: 0.06, octave: 0.02)
    static let struggling = Kid(name: "50% right first try", right: 0.5, wrong: 0.25, octave: 0.1)

    struct Heard {
        var screens = 0
        /// lines in the cues that put a screen up
        var atScreenStart = 0
        /// every line, in order
        var lines: [Speech] = []
        /// lines before the session's end
        var midSession: [Speech] = []
    }

    /// One session from `engine`. Returns what was said and the engine after it.
    static func session(_ kid: Kid, _ engine: MasteryEngine, seed: UInt64) -> (heard: Heard, engine: MasteryEngine) {
        var bench = Bench(engine, seed: seed)
        var dice = SeededRandom(seed: seed &+ 0xD1CE)
        var heard = Heard()
        func hear(_ cues: [Cue]) {
            let said = speeches(cues)
            heard.lines += said
            if cues.contains(.showItem) { heard.atScreenStart += said.count }
            if !cues.contains(.done) { heard.midSession += said }
        }
        hear(bench.start())
        var guardRail = 0
        while bench.session.phase != .done, guardRail < 200 {
            guardRail += 1
            if bench.session.isIntro {
                hear(bench.playScreen(after: 2))
            } else {
                while bench.session.phase.isPlaying {
                    let roll = unitInterval(&dice)
                    if roll < kid.right {
                        // right first try
                    } else if roll < kid.right + kid.wrong {
                        hear(bench.press(bench.wrongKey, after: 1.5))
                    } else if roll < kid.right + kid.wrong + kid.octave {
                        hear(bench.press(Pitch(midi: bench.expected[0].midi + 12), after: 1.5))
                    } else {
                        let rungs = 1 + Int(unitInterval(&dice) * 3)
                        for _ in 0..<rungs {
                            if let deadline = bench.session.nextDeadline { hear(bench.tick(at: deadline)) }
                        }
                    }
                    hear(bench.playNote(after: 1.5))
                }
            }
            hear(bench.next(after: 1.2))
        }
        heard.screens = bench.session.summary.screensPlayed
        return (heard, bench.session.engine)
    }

    /// `count` sessions in a row for a new kid.
    static func sessions(_ kid: Kid, _ count: Int, kidSeed: UInt64) -> [Heard] {
        var engine = MasteryEngine(state: MasteryState(seed: kidSeed))
        var all: [Heard] = []
        for s in 0..<count {
            let (heard, after) = session(kid, engine, seed: kidSeed &* 1000 &+ UInt64(s))
            all.append(heard)
            engine = after
        }
        return all
    }

    /// The test from the plan: a seeded level 1 session, the 65% kid. Nothing at a
    /// screen's start, at most 2 lines in the whole session (1 mid + 1 end).
    @Test func aLevelOneSessionIsQuiet() {
        var report: [String] = []
        for kidSeed: UInt64 in 1...10 {
            for (i, heard) in Self.sessions(Self.scripted, 3, kidSeed: kidSeed).enumerated() {
                if kidSeed == 1 {
                    report.append("kid 1 session \(i + 1): \(heard.screens) screens, \(heard.lines.count) lines (\(heard.atScreenStart) at screen starts): \(heard.lines)")
                }
                #expect(heard.atScreenStart == 0, "kid \(kidSeed) session \(i + 1): \(heard.lines)")
                #expect(heard.lines.count <= 2, "kid \(kidSeed) session \(i + 1): \(heard.lines)")
                #expect(heard.midSession.count <= 1, "kid \(kidSeed) session \(i + 1): \(heard.midSession)")
            }
        }
        print(report.joined(separator: "\n"))
    }

    /// Across a long run, mid-session lines average 1 per 20 screens or fewer, for kids
    /// doing well and kids finding it hard.
    @Test func midSessionLinesAreRare() {
        for kid in [Self.scripted, Self.steady, Self.struggling] {
            var screens = 0, mid = 0, sessionsWithOne = 0, total = 0
            for kidSeed: UInt64 in 1...4 {
                for heard in Self.sessions(kid, 10, kidSeed: kidSeed) {
                    screens += heard.screens
                    mid += heard.midSession.count
                    sessionsWithOne += heard.midSession.isEmpty ? 0 : 1
                    total += 1
                }
            }
            let rate = Double(mid) / Double(max(1, screens))
            print("\(kid.name): \(mid) mid-session lines in \(screens) screens (1 per \(mid == 0 ? "-" : String(screens / mid))), in \(sessionsWithOne) of \(total) sessions")
            #expect(rate <= 1.0 / 20, "\(kid.name): \(mid) in \(screens)")
        }
    }
}
