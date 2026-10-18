import Foundation
import Testing
@testable import NoteCore

/// Level 2 measures rhythm silently on screens whose two bars share one, level 3's
/// halves check prefers them (plans/2026-10-17-reset-and-repetition.md section 2).
@Suite struct RhythmMeasureTests {
    static func item(_ values: [NoteValue], meter: Meter = .fourFour) -> PracticeItem {
        let keys = ["G4", "A4", "B4", "C5", "B4", "A4", "G4", "A4"].map { key("treble:\($0)") }
        let notes = (values + values).enumerated().map { i, v in WrittenNote(keys[i], v) }
        return PracticeItem(notes, bars: [values.count, values.count], meter: meter)
    }

    let judge = RhythmJudge()

    @Test func halvesHeldLongerAndBarTwoLikeBarOne() throws {
        let m = try #require(judge.measure(Self.item([.quarter, .quarter, .half]), onsets: [0, 1, 2, 4, 5, 6]))
        #expect(m.halvesLonger == true && m.barsMatch == true && m.gaps == [1, 1, 2, 1, 1])
    }

    @Test func halvesPlayedAsQuarters() throws {
        let m = try #require(judge.measure(Self.item([.quarter, .quarter, .half]), onsets: [0, 1, 2, 3, 4, 5]))
        #expect(m.halvesLonger == false && m.barsMatch == true)
    }

    @Test func barTwoRushed() throws {
        // bar 2's quarters rushed, its half held
        let m = try #require(judge.measure(Self.item([.half, .quarter, .quarter]), onsets: [0, 2, 3, 4, 6, 6.4]))
        #expect(m.halvesLonger == true && m.barsMatch == false)
        // all of bar 2 rushed, the half too
        let all = try #require(judge.measure(Self.item([.half, .quarter, .quarter]), onsets: [0, 2, 3, 4, 4.5, 4.9]))
        #expect(all.halvesLonger == false && all.barsMatch == false)
    }

    /// h h | h h: no quarter to hold a half against.
    @Test func nothingToCompareIsNil() throws {
        let m = try #require(judge.measure(Self.item([.half, .half]), onsets: [0, 2, 4, 6]))
        #expect(m.halvesLonger == nil && m.barsMatch == true)
        // two bars in different rhythms aren't measured
        let mixed = PracticeItem([WrittenNote(key("treble:G4"), .half), WrittenNote(key("treble:A4"), .half),
                                  WrittenNote(key("treble:B4"), .whole)], bars: [2, 1], meter: .fourFour)
        #expect(judge.measure(mixed, onsets: [0, 2, 4]) == nil)
    }

    /// In a session: level 2, a clean go on a same-rhythm screen. Nothing is said or shown.
    @Test func levelTwoMeasuresSilently() throws {
        var measured = 0
        for seed: UInt64 in 1...6 {
            var bench = Bench(engine(in: "2.1", seed: seed), seed: seed)
            bench.session.openWithPattern = .twin
            let cues = bench.start()
            _ = bench.playScreen(after: 1)
            let screen = try #require(bench.session.summary.screens.last)
            #expect(screen.rhythm == nil && bench.session.rhythmLine == nil, "level 2 isn't judged")
            #expect(speeches(cues).isEmpty)
            if let m = screen.rhythmMeasure {
                measured += 1
                #expect(m.gaps.count == screen.notes.count - 1)
            }
        }
        #expect(measured == 6)
        // the play button: not his rhythm
        var bench = Bench(engine(in: "2.1"), seed: 1)
        bench.session.openWithPattern = .twin
        _ = bench.start()
        _ = bench.playNote(after: 1)
        _ = bench.session.listen(at: bench.now)
        _ = bench.playScreen(after: 1)
        #expect(bench.session.summary.screens.last?.rhythmMeasure == nil)
        // level 1 isn't measured
        var one = Bench(engine(in: "1.3"), seed: 1)
        one.session.openWithPattern = .twin
        _ = one.start()
        _ = one.playScreen(after: 1)
        #expect(one.session.summary.screens.last?.rhythmMeasure == nil)
    }

    @Test func savedScreensWithoutAMeasureStillDecode() throws {
        let measure = RhythmMeasure(gaps: [1, 2], halvesLonger: true, barsMatch: nil)
        let screen = ScreenResult(screenID: "t", lesson: "2.1", notes: [], rhythmMeasure: measure)
        let data = try JSONEncoder().encode(screen)
        #expect(try JSONDecoder().decode(ScreenResult.self, from: data).rhythmMeasure == measure)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["rhythmMeasure"] = nil
        #expect(try JSONDecoder().decode(ScreenResult.self, from: JSONSerialization.data(withJSONObject: json)).rhythmMeasure == nil)
    }

    /// Level 3: the first judged screens (played to him first) have both bars in one
    /// rhythm, others are judged 3 times in 4, so about 1 in 3 is judged.
    @Test func levelThreeJudgesSameRhythmFirst() {
        var screens = 0, judged = 0, judgedSame = 0
        var stay = NoteCoreConfig()
        stay.lessonMinScreens = 10_000
        for seed: UInt64 in 1...4 {
            var engine = engine(in: "3.1", config: stay, seed: seed)
            var firstJudged: [Bool] = []
            for s in 0..<5 {
                var bench = Bench(engine, seed: seed &* 10 &+ UInt64(s))
                _ = bench.start()
                while bench.session.phase != .done {
                    let ss = bench.session
                    if !ss.isIntro, ss.retries == 0, let item = ss.item, ss.engine.lesson.id == "3.1" {
                        screens += 1
                        if ss.rhythmLine != nil {
                            judged += 1
                            if item.hasSameRhythmBars { judgedSame += 1 }
                            firstJudged.append(item.hasSameRhythmBars)
                        }
                    }
                    _ = bench.playScreen(after: 0.8)
                    _ = bench.next()
                }
                engine = bench.session.engine
            }
            #expect(firstJudged.prefix(2).allSatisfy { $0 }, "seed \(seed): the level's first judged screens share a rhythm")
        }
        let share = Double(judged) / Double(screens)
        #expect(share > 0.22 && share < 0.42, "\(judged) of \(screens) judged")
        // about 1 in 5 of the judged screens shared a rhythm before (3.1-3.6, 2026-10-17)
        #expect(Double(judgedSame) / Double(judged) > 0.4, "\(judgedSame) of \(judged) judged screens share a rhythm")
    }
}
