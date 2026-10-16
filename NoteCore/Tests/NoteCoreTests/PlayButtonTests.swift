import Testing
@testable import NoteCore

/// The play button (plans/2026-10-15-real-bars.md): he can hear and see any screen.
/// It's help, so notes he hasn't played yet count as hinted. Nothing else.
@Suite struct PlayButtonTests {
    var long: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        config.sessionMaxItems = 10_000
        config.sessionMaxDuration = 1e9
        config.rhythmDemoScreens = 0
        return config
    }

    @Test func itPlaysTheScreenWithTheKeyboardAtAGentleTempo() {
        var bench = Bench(engine(in: "1.2", config: long), seed: 1)
        _ = bench.start()
        bench.now += 1
        #expect(bench.session.listen(at: bench.now) == [.showAndPlay(beat: NoteCoreConfig.default.demoBeat)])
        #expect(bench.session.phase == .prompt, "he can play as soon as he likes")
    }

    @Test func notesNotPlayedYetCountAsHinted() {
        var bench = Bench(engine(in: "1.2", config: long), seed: 1)
        _ = bench.start()
        #expect(bench.session.item!.notes.count == 2)
        _ = bench.playCurrent()
        bench.now += 0.5
        _ = bench.session.listen(at: bench.now)
        _ = bench.playCurrent(after: 3)
        let notes = bench.session.summary.screens.last!.notes
        #expect(notes[0].firstTry && notes[0].hints == .none, "he played the first one before he asked")
        #expect(!notes[1].firstTry && notes[1].hints == .keyboard && notes[1].wrongPresses == 0)
    }

    @Test func itsHelpNotAMiss() {
        var engine = engine(in: "1.2", config: long)
        // a note in box 3, then a screen where he listens first
        var bench = Bench(engine, seed: 2)
        _ = bench.start()
        let keys = bench.session.item!.notes.flatMap(\.keys)
        for key in keys { for _ in 0..<2 { engine.play(key, time: 1) } }
        bench = Bench(engine, seed: 2)
        _ = bench.start()
        let before = bench.session.item!.notes.flatMap(\.keys).map { bench.session.engine.stats(for: $0).box }
        bench.now += 0.5
        _ = bench.session.listen(at: bench.now)
        _ = bench.playScreen(after: 2)
        let after = bench.session.item!.notes.flatMap(\.keys).map { bench.session.engine.stats(for: $0).box }
        #expect(before == after, "the box holds: \(before) -> \(after)")
        #expect(bench.session.summary.screens.last!.usedHints, "so kept-trying praise can follow")
    }

    @Test func theStuckClockStartsAfterThePlayBack() {
        var bench = Bench(engine(in: "1.2", config: long), seed: 1)
        _ = bench.start()
        bench.now += 10
        _ = bench.session.listen(at: bench.now)
        let length = bench.session.item!.totalBeats * NoteCoreConfig.default.demoBeat
        #expect(bench.session.nextDeadline! >= bench.now + length + NoteCoreConfig.default.stuckAfter - 1e-9)
        // and his time on the note counts from the end of it
        _ = bench.playCurrent(after: length + 1.5)
        _ = bench.playScreen()
        let first = bench.session.summary.screens.last!.notes[0]
        #expect(abs(first.responseTime - 1.5) < 1e-6)
    }

    @Test func midLineItStopsTheRhythmBeingJudgedBeforeItDoesnt() {
        func judgedScreen() -> Bench {
            var bench = Bench(engine(in: "5.3", config: long), seed: 4)
            _ = bench.start()
            while bench.session.rhythmLine == nil || bench.session.isIntro {
                _ = bench.playScreen()
                _ = bench.next()
            }
            return bench
        }
        // tapped before the first note: he heard it, then played it. judged
        var before = judgedScreen()
        before.now += 0.5
        _ = before.session.listen(at: before.now)
        before.now += 5
        _ = before.playScreen()
        #expect(before.session.summary.screens.last!.rhythm != nil)
        // tapped after the first note: the line isn't his any more
        var mid = judgedScreen()
        _ = mid.playCurrent()
        mid.now += 0.3
        _ = mid.session.listen(at: mid.now)
        _ = mid.playScreen()
        #expect(mid.session.phase == .success)
        #expect(mid.session.summary.screens.last!.rhythm == nil)
    }

    @Test func nothingWhileItCantBePlayed() {
        var bench = Bench(engine(in: "1.2", config: long), seed: 1)
        #expect(bench.session.listen(at: 0).isEmpty, "before the session starts")
        _ = bench.start()
        _ = bench.playScreen()
        #expect(bench.session.phase == .success)
        #expect(bench.session.listen(at: bench.now).isEmpty, "during the celebration")
    }
}
