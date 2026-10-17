import Foundation
import Testing
@testable import NoteCore

/// One-clef lessons: a session is two runs, one clef each, with one switch
/// (plans/2026-10-16-round-3-feedback.md, "clef runs, not flips").
@Suite struct ClefRunTests {
    struct Played {
        /// the clef of every screen, in order
        var clefs: [Clef] = []
        /// `session.runClef` when each screen came up
        var runs: [Clef?] = []
        var engine: MasteryEngine
    }

    /// A whole session, every note right (a wrong key on every `missEvery`th screen).
    static func play(_ engine: MasteryEngine, seed: UInt64, missEvery: Int = 0, noteTime: Double = 1) -> Played {
        var bench = Bench(engine, seed: seed)
        var played = Played(engine: engine)
        _ = bench.start()
        var n = 0
        while bench.session.phase != .done, n < 100 {
            n += 1
            played.clefs.append(bench.session.item!.clefs[0])
            played.runs.append(bench.session.runClef)
            if missEvery > 0, n % missEvery == 0, !bench.session.isIntro { _ = bench.press(bench.wrongKey) }
            _ = bench.playScreen(after: noteTime)
            _ = bench.next()
        }
        played.engine = bench.session.engine
        return played
    }

    /// Stays in its lesson however well he plays.
    static var stay: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return config
    }

    static func switches(_ clefs: [Clef]) -> Int {
        zip(clefs, clefs.dropFirst()).filter { $0 != $1 }.count
    }

    @Test func aSessionIsTwoRunsWithOneSwitch() {
        for id in ["1.1", "1.4", "2.1"] {
            for seed: UInt64 in 1...5 {
                let played = Self.play(engine(in: id), seed: seed, missEvery: 4)
                #expect(Self.switches(played.clefs) == 1, "\(id) seed \(seed): \(played.clefs.map(\.rawValue.first!))")
                #expect(zip(played.clefs, played.runs).allSatisfy { $0 == $1 }, "every screen on its run's clef: \(id) seed \(seed)")
            }
        }
    }

    @Test func bothLessonsSwitchHalfWay() {
        let played = Self.play(engine(in: "1.4"), seed: 3)
        let first = played.clefs.prefix { $0 == played.clefs[0] }.count
        #expect(first == NoteCoreConfig.default.sessionMaxItems / 2, "\(played.clefs.map(\.rawValue.first!))")
        #expect(played.clefs.count - first >= first, "extras stay on the second clef")
    }

    @Test func theFirstClefAlternatesFromSessionToSession() {
        var engine = engine(in: "1.4", config: Self.stay)
        var firsts: [Clef] = []
        for s: UInt64 in 0..<4 {
            let played = Self.play(engine, seed: 10 + s)
            firsts.append(played.clefs[0])
            engine = played.engine
        }
        #expect(firsts == [.treble, .bass, .treble, .bass])
        #expect(engine.state.lastFirstClef == .bass)
    }

    @Test func aFocusClefGoesFirstForAboutTwoThirds() {
        for (id, focus) in [("3.1", Clef.treble), ("3.2", .bass)] {
            var engine = engine(in: id, config: Self.stay)
            engine.state.lastFirstClef = focus == .treble ? .bass : .treble // would be its turn anyway
            for seed: UInt64 in 1...3 {
                let played = Self.play(engine, seed: seed)
                #expect(played.clefs[0] == focus, "\(id)")
                let first = played.clefs.prefix { $0 == focus }.count
                #expect(first == 13, "\(id) seed \(seed): \(first) of \(played.clefs.count)")
                engine = played.engine
            }
        }
    }

    @Test func aLongSessionSwitchesAtHalfTheTime() {
        var config = NoteCoreConfig()
        config.sessionMaxItems = 100
        config.sessionMaxDuration = 120
        let played = Self.play(engine(in: "1.4", config: config), seed: 2, noteTime: 2)
        #expect(Self.switches(played.clefs) == 1)
        let first = played.clefs.prefix { $0 == played.clefs[0] }.count
        // about 60s of screens at 2-3 notes, 2s a note and a second to move on
        #expect(first > 6 && first < 15, "\(first) screens in the first minute")
    }

    @Test func aRunWithNothingToShowUsesTheOtherClef() {
        var engine = engine(in: "1.4")
        engine.state.unlocked = engine.state.unlocked.filter { $0.hasPrefix("treble:") }
        engine.state.lastFirstClef = .treble // bass would go first
        let played = Self.play(engine, seed: 1)
        #expect(played.runs.first == .bass)
        #expect(played.clefs.first == .treble, "the run was bass, it had nothing")
    }

    @Test func warmUpAndEasingStayInTheRun() {
        var engine = engine(in: "1.4")
        for key in engine.pool { for _ in 0..<3 { engine.play(key, time: 1) } }
        for seed: UInt64 in 1...5 {
            var bench = Bench(engine, seed: seed)
            _ = bench.start()
            var seen: [(PickReason, Clef, Clef?)] = []
            for n in 0..<24 where bench.session.phase != .done {
                seen.append((bench.session.pickReason, bench.session.item!.clefs[0], bench.session.runClef))
                // a wrong key before every note for two screens brings easing
                while (8...9).contains(n), bench.session.phase.isPlaying {
                    _ = bench.press(bench.wrongKey)
                    _ = bench.playCurrent()
                }
                _ = bench.playScreen()
                _ = bench.next()
            }
            #expect(seen.contains { $0.0 == .warmUp } && seen.contains { $0.0 == .easing }, "seed \(seed)")
            #expect(seen.allSatisfy { $0.1 == $0.2 }, "seed \(seed): \(seen.map { "\($0.0) \($0.1)" })")
        }
    }

    @Test func grandStaffLessonsHaveNoRuns() {
        var bench = Bench(engine(in: "2.3"), seed: 1)
        _ = bench.start()
        #expect(bench.session.runClef == nil)
        #expect(bench.session.item!.layout == .grand)
    }

    @Test func thePickerTakesTheClefItIsGiven() {
        var engine = engine(in: "1.4")
        var rng = SeededRandom(seed: 1)
        for clef in [Clef.bass, .treble, .bass] {
            for _ in 0..<10 {
                let pick = engine.pickScreen(clef: clef, using: &rng)
                #expect(pick.item.clefs == [clef])
                engine.playPick(pick)
            }
        }
    }

    @Test func oldSavesWithoutAFirstClefStartOnTreble() throws {
        let state = try JSONDecoder().decode(MasteryState.self, from: Data(#"{"lesson":"1.4"}"#.utf8))
        #expect(state.lastFirstClef == nil)
        #expect(MasteryEngine(state: state).firstRunClef == .treble)
    }
}
