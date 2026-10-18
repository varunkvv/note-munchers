import Foundation
import Testing
@testable import NoteCore

/// Pattern screens in sessions (plans/2026-10-17-reset-and-repetition.md section 2).
@Suite struct PatternSessionTests {
    /// Plays `sessions` sessions, every note right, and hands each screen to `look` before
    /// it's played.
    static func play(_ engine: MasteryEngine, sessions: Int, seed: UInt64, look: (PracticeSession) -> Void) -> MasteryEngine {
        var engine = engine
        for s in 0..<sessions {
            var bench = Bench(engine, seed: seed &* 100 &+ UInt64(s))
            _ = bench.start()
            while bench.session.phase != .done {
                look(bench.session)
                _ = bench.playScreen(after: 1)
                _ = bench.next()
            }
            engine = bench.session.engine
        }
        return engine
    }

    /// Only normal screens: never an intro, the warm-up, easing, an extra, a drill burst or
    /// a drill lesson's screen, and never a second read of one.
    @Test func patternScreensAreNormalScreens() {
        var stay = NoteCoreConfig()
        stay.lessonMinScreens = 10_000
        for id in ["1.3", "2.1", "3.1", "4.1", "5.3"] {
            var patterns = 0, normal = 0
            var last: PracticeSession?
            _ = Self.play(engine(in: id, config: stay), sessions: 4, seed: 7) { s in
                if s.pickReason == .again { #expect(last?.pattern == nil, "\(id): a second read of a pattern screen") }
                if [.normal, .stretch].contains(s.pickReason), !s.isIntro { normal += 1 }
                if s.pattern != nil {
                    patterns += 1
                    #expect(s.pickReason == .normal && !s.isIntro && s.drill == nil, "\(id): \(s.pickReason)")
                }
                last = s
            }
            #expect(patterns > 0 && patterns < normal, "\(id): \(patterns) of \(normal)")
        }
        for id in ["1.5", "2.4", "4.5"] {
            _ = Self.play(engine(in: id, config: stay), sessions: 2, seed: 7) { s in
                #expect(s.pattern == nil, "\(id) is all drills")
            }
        }
    }

    /// Bar 2 comes from bar 1, so a pattern screen says nothing about how many notes he
    /// can read: it doesn't count toward his size.
    @Test func aPatternScreenDoesntMoveHisSize() {
        var e = engine(in: "2.1")
        let keys = [key("treble:G4"), key("treble:A4"), key("treble:G4"), key("treble:A4")]
        var state = e.state
        state.screenSize = 4
        e = MasteryEngine(config: e.config, state: state)
        for _ in 0..<6 {
            let notes = keys.enumerated().map { i, k in
                AttemptResult(itemID: k.id, lesson: "2.1", level: 2, firstTry: true, responseTime: 1, inLine: i > 0)
            }
            e.record(ScreenResult(screenID: "t", lesson: "2.1", notes: notes, size: 4, pattern: .twin))
        }
        #expect(e.state.sizeRecent.isEmpty && e.screenSize == 4)
        e.play(keys, size: 4)
        #expect(e.state.sizeRecent.count == 1, "a normal screen still counts")
    }

    /// The app keeps every screen as JSON: a screen saved before pattern screens has no
    /// shape, and a shape a later build drops reads as none.
    @Test func screensSavedWithoutAShapeStillDecode() throws {
        let screen = ScreenResult(screenID: "t", lesson: "1.3", notes: [], pattern: .moved)
        let data = try JSONEncoder().encode(screen)
        #expect(try JSONDecoder().decode(ScreenResult.self, from: data).pattern == .moved)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["pattern"] = "turnedAround"
        #expect(try JSONDecoder().decode(ScreenResult.self, from: JSONSerialization.data(withJSONObject: json)).pattern == nil)
        json["pattern"] = nil
        let old = try JSONDecoder().decode(ScreenResult.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.pattern == nil && old.lesson == "1.3")
    }

    /// The new note's blocked screens right after its intro lean on pattern screens.
    @Test func moreRightAfterAnIntro() {
        var window = 0, windowPatterns = 0, other = 0, otherPatterns = 0
        for seed: UInt64 in 1...30 {
            var e = engine(in: "1.3", seed: seed)
            var state = e.state
            state.lastIntro["treble"] = "treble:C5"
            state.introGap["treble"] = 0
            e = MasteryEngine(config: e.config, state: state)
            var rng = SeededRandom(seed: seed)
            for _ in 0..<6 {
                let inWindow = e.blockedNote(.treble) != nil
                let pick = e.pickScreen(clef: .treble, using: &rng)
                if inWindow { window += 1 } else { other += 1 }
                if pick.pattern != nil { if inWindow { windowPatterns += 1 } else { otherPatterns += 1 } }
                e.playPick(pick)
            }
        }
        let inside = Double(windowPatterns) / Double(window), outside = Double(otherPatterns) / Double(other)
        #expect(inside > 0.35 && outside < 0.35 && inside > outside, "\(windowPatterns) of \(window) right after, \(otherPatterns) of \(other) after that")
    }
}
