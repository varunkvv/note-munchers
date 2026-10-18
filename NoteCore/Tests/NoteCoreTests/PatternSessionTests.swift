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
        json["secondBar"] = nil
        let old = try JSONDecoder().decode(ScreenResult.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.pattern == nil && old.secondBar == nil && old.lesson == "1.3")
        let split = ScreenResult(screenID: "t", lesson: "1.3", notes: [], secondBar: 2)
        #expect(try JSONDecoder().decode(ScreenResult.self, from: JSONEncoder().encode(split)).secondBar == 2)
    }

    /// Plays one pattern screen of `shape` (the session opens on it), all right, and
    /// returns what was recorded.
    static func playOne(_ shape: PatternShape, in id: LessonID, seed: UInt64 = 1) -> (item: PracticeItem, screen: ScreenResult, engine: MasteryEngine)? {
        var bench = Bench(engine(in: id, seed: seed), seed: seed)
        bench.session.openWithPattern = shape
        _ = bench.start()
        guard bench.session.pattern == shape, let item = bench.session.item else { return nil }
        _ = bench.playScreen(after: 1)
        return (item, bench.session.summary.screens.last!, bench.session.engine)
    }

    /// Habit: bar 2 of a twin, an answer or a new rhythm is bar 1 again from memory, so it
    /// isn't in-line (and isn't one of a paced lesson's plays of a note). A moved bar is
    /// read by its shape, a frame's notes are new, an answer's last note is read.
    @Test func barTwoFromMemoryIsntInLine() throws {
        for seed: UInt64 in 1...6 {
            for shape in PatternShape.allCases {
                let id = shape == .oneNote ? "1.3" : "2.1"
                guard let (item, screen, _) = Self.playOne(shape, in: id, seed: seed) else { continue }
                let bar2 = item.barRanges[1]
                #expect(screen.pattern == shape && screen.secondBar == item.bars[0])
                for (i, note) in screen.notes.enumerated() {
                    let repeatedKey = i > 0 && item.notes[i].pitches == item.notes[i - 1].pitches
                    let memory = shape.repeatsNotes && bar2.contains(i) && item.notes[i].pitches == item.notes[i - bar2.lowerBound].pitches
                    #expect(note.fromMemory == memory, "\(shape) \(item.id) note \(i)")
                    #expect(note.inLine == (i > 0 && !repeatedKey && !memory), "\(shape) \(item.id) note \(i)")
                }
                switch shape {
                case .twin, .newRhythm: #expect(screen.notes[bar2].allSatisfy { $0.fromMemory })
                case .answer:
                    #expect(screen.notes[bar2].dropLast().allSatisfy { $0.fromMemory } && !screen.notes[bar2.upperBound - 1].fromMemory)
                case .moved, .frame, .oneNote: #expect(!screen.notes.contains { $0.fromMemory })
                }
            }
        }
    }

    /// A paced lesson's 10 plays of a new note count reads: a twin's bar 2 isn't one.
    @Test func memoryIsntAPlay() throws {
        let (item, _, engine) = try #require(Self.playOne(.twin, in: "1.3", seed: 2))
        for key in Set(item.notes.flatMap(\.keys)) {
            let inBarOne = item.notes[item.barRanges[0]].filter { $0.keys.contains(key) }.count
            #expect(engine.lessonPlays(key) == inBarOne, "\(key.id) in \(item.id)")
        }
    }

    /// Two at once: bar 2 starts after both keys of every column of bar 1.
    @Test func secondBarCountsKeys() throws {
        for seed: UInt64 in 1...8 {
            guard let (item, screen, _) = Self.playOne(.moved, in: "4.3", seed: seed) else { continue }
            #expect(screen.secondBar == item.notes[item.barRanges[0]].flatMap(\.keys).count)
            #expect(screen.notes.count == item.notes.flatMap(\.keys).count)
        }
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
