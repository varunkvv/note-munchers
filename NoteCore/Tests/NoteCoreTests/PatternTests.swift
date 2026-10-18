import Foundation
import Testing
@testable import NoteCore

/// Repetition inside a screen (plans/2026-10-17-reset-and-repetition.md section 2): pattern
/// screens are two even bars, bar 1 fresh, bar 2 made from it by a shape.
@Suite struct PatternTests {
    /// Columns of each bar, without values.
    static func bars(_ item: PracticeItem) -> (first: [WrittenNote], second: [WrittenNote]) {
        let r = item.barRanges
        return (item.notes[r[0]].map { WrittenNote($0.clef, $0.pitches) }, item.notes[r[1]].map { WrittenNote($0.clef, $0.pitches) })
    }

    static func rhythms(_ item: PracticeItem) -> [BarRhythm] {
        item.barRanges.map { r in BarRhythm(item.notes[r].map(\.value), rests: item.notes[r].last!.restsAfter) }
    }

    /// Checks one pattern screen against its shape's rule. Returns what's wrong, nil when fine.
    static func problem(_ pick: Pick, _ shape: PatternShape, lesson: Lesson) -> String? {
        let item = pick.item
        guard pick.pattern == shape else { return "shape \(String(describing: pick.pattern))" }
        guard item.bars.count == 2 else { return "\(item.bars.count) bars" }
        guard item.bars[0] == item.bars[1] else { return "uneven split \(item.bars)" }
        if lesson.level == 1, item.bars != [2, 2] { return "level 1 is 2+2" }
        let (one, two) = bars(item)
        let (r1, r2) = (rhythms(item)[0], rhythms(item)[1])
        for r in [r1, r2] where !MasteryEngine.isPatternCell(r) { return "no long note or rest in \(r)" }
        if shape == .newRhythm {
            guard r1 != r2 else { return "a new rhythm is the same rhythm" }
        } else if r1 != r2 {
            return "bars in different rhythms"
        }
        guard Set(pick.positions).count == 1, let hand = pick.positions.first,
              item.notes.allSatisfy({ $0.keys.allSatisfy(hand.contains) }) else { return "more than one hand position" }
        let oneKey = if case .rhythm(_, true) = lesson.texture { true } else { false }
        if shape != .oneNote, !oneKey, maxRepeatRun(item.notes.map(MasteryEngine.columnID)) > 2 { return "a key 3 times running" }
        switch shape {
        case .frame:
            if !oneKey, one == two { return "a frame is a twin" }
        case .moved:
            let ways = Set(zip(one, two).flatMap { a, b in zip(a.pitches, b.pitches).map { $1.diatonicIndex - $0.diatonicIndex } })
            guard ways == [1] || ways == [-1], zip(one, two).allSatisfy({ $0.pitches.count == $1.pitches.count }) else { return "not moved a step: \(item.id)" }
        case .answer:
            guard one.dropLast() == two.dropLast(), one.last != two.last else { return "not an answer: \(item.id)" }
        case .twin, .newRhythm:
            guard one == two else { return "notes differ: \(item.id)" }
        case .oneNote:
            guard Set(one).count == 1, Set(two).count == 1, one[0] != two[0] else { return "not one note a bar: \(item.id)" }
        }
        return nil
    }

    /// Lessons and the shapes they use (`patternShapes`), level 1 with three notes a clef.
    static let lessons: [(LessonID, [PatternShape])] = [
        ("1.3", [.frame, .moved, .twin, .newRhythm, .oneNote]),
        ("2.1", [.frame, .moved, .answer, .twin, .newRhythm]),
        ("2.3", [.frame, .moved, .answer, .twin, .newRhythm]),
        ("3.1", [.frame, .moved, .answer, .twin, .newRhythm]),
        ("4.3", [.frame, .moved, .answer, .twin, .newRhythm]),
        ("5.1", [.frame, .newRhythm]),
        ("5.4", [.frame, .answer, .twin, .newRhythm]),
    ]

    @Test func everyShapeFollowsItsRule() {
        for (id, shapes) in Self.lessons {
            for shape in shapes {
                var made = 0
                for seed: UInt64 in 1...40 {
                    var e = engine(in: id, seed: seed)
                    // half his sizes: 3+3 screens too
                    if seed.isMultiple(of: 2) { e = MasteryEngine(config: e.config, state: { var s = e.state; s.screenSize = e.lesson.sizes.upperBound; return s }()) }
                    var rng = SeededRandom(seed: seed)
                    guard let pick = e.pickPattern(shape, using: &rng) else { continue }
                    made += 1
                    #expect(Self.problem(pick, shape, lesson: e.lesson) == nil, "\(id) \(shape): \(Self.problem(pick, shape, lesson: e.lesson) ?? "") \(pick.item.id)")
                }
                #expect(made >= 30, "\(id) \(shape) made \(made) of 40")
            }
        }
    }

    /// Normal screens whose two bars hold as many notes: one rhythm for both about half
    /// the time (costs nothing, the notes stay fresh).
    @Test func evenNormalScreensShareARhythmHalfTheTime() {
        var even = 0, same = 0
        var stay = NoteCoreConfig()
        stay.lessonMinScreens = 10_000
        for id in ["2.1", "2.3", "3.6"] {
            var e = engine(in: id, config: stay, seed: 5)
            var rng = SeededRandom(seed: 5)
            for _ in 0..<400 {
                let pick = e.pickScreen(using: &rng)
                e.playPick(pick, time: 1)
                // bars with one way to write them (q q q in 3/4) always match
                guard pick.pattern == nil, pick.intro == nil, !pick.isLessonIntro, pick.item.bars.count == 2,
                      pick.item.bars[0] == pick.item.bars[1],
                      MasteryEngine.readingBars(notes: pick.item.bars[0], meter: pick.item.meter!).count > 1 else { continue }
                even += 1
                if pick.item.hasSameRhythmBars { same += 1 }
            }
        }
        let share = Double(same) / Double(even)
        #expect(even > 100 && share > 0.5 && share < 0.75, "\(same) of \(even)")
    }

    @Test func threeAndThreeIsFourFourWithALongNote() {
        var sizes = Set<Int>()
        for seed: UInt64 in 1...60 {
            var e = engine(in: "2.3", seed: seed)
            e = MasteryEngine(config: e.config, state: { var s = e.state; s.screenSize = 6; return s }())
            var rng = SeededRandom(seed: seed)
            guard let pick = e.pickPattern(.frame, using: &rng) else { continue }
            sizes.insert(pick.item.bars[0])
            if pick.item.bars[0] == 3 { #expect(pick.item.meter == .fourFour, "\(pick.item.id)") }
        }
        #expect(sizes == [3], "\(sizes)")
    }

    /// 1.1 has two notes a clef: nothing to move to.
    @Test func smallPoolsSkipWhatTheyCantMake() {
        var e = engine(in: "1.1")
        var rng = SeededRandom(seed: 1)
        #expect(e.pickPattern(.moved, using: &rng) == nil)
        #expect(e.pickPattern(.twin, using: &rng) != nil)
        #expect(e.pickPattern(.oneNote, using: &rng) != nil)
    }

    @Test func answersEndOnGNowAndThenNot() {
        var onG = 0, total = 0, longEnd = 0
        for seed: UInt64 in 1...200 {
            var e = engine(in: "2.1", seed: seed)
            var rng = SeededRandom(seed: seed)
            guard let pick = e.pickPattern(.answer, using: &rng) else { continue }
            total += 1
            let last = pick.item.notes.last!
            if last.pitches[0].letter == .g { onG += 1 }
            if last.value.beats >= 2 { longEnd += 1 }
        }
        let share = Double(onG) / Double(total)
        #expect(total > 180)
        #expect(share > 0.6 && share < 0.9, "\(onG) of \(total) end on G")
        #expect(Double(longEnd) / Double(total) > 0.5, "\(longEnd) of \(total) end on a long note")
    }

    /// Level 4: two at once move together, and an answer ends on a two at once.
    @Test func levelFourMovesAndEndsOnTwoAtOnce() {
        var movedDyads = 0, answers = 0
        for seed: UInt64 in 1...60 {
            var e = engine(in: "4.3", seed: seed)
            var rng = SeededRandom(seed: seed)
            if let pick = e.pickPattern(.moved, using: &rng) {
                let (one, two) = Self.bars(pick.item)
                if one.contains(where: \.isChord) {
                    movedDyads += 1
                    for (a, b) in zip(one, two) where a.isChord {
                        #expect(b.isChord && b.pitches[1].diatonicIndex - b.pitches[0].diatonicIndex == a.pitches[1].diatonicIndex - a.pitches[0].diatonicIndex)
                    }
                }
            }
            if let pick = e.pickPattern(.answer, using: &rng) {
                answers += 1
                #expect(pick.item.notes.last!.isChord, "\(pick.item.id)")
            }
        }
        #expect(movedDyads > 20 && answers > 40, "\(movedDyads) moved with two at once, \(answers) answers")
    }

    /// Level 5's eighths lessons: a frame has the eighth pair, in the same spot both bars.
    @Test func levelFiveFramesKeepThePairInPlace() {
        var withPair = 0, total = 0
        for seed: UInt64 in 1...60 {
            var e = engine(in: "5.4", seed: seed)
            var rng = SeededRandom(seed: seed)
            guard let pick = e.pickPattern(.frame, using: &rng) else { continue }
            total += 1
            let r = Self.rhythms(pick.item)
            #expect(r[0] == r[1])
            if r[0].values.contains(.eighth) { withPair += 1 }
            #expect(pick.size == 2, "level 5 counts bars")
            #expect(pick.item.rhythmLine(.all) != nil, "rhythm judged: \(pick.item.id)")
        }
        #expect(withPair >= total - 2, "\(withPair) of \(total) with the pair")
    }

    /// The new note in bar 1, the shape brings it back in bar 2.
    @Test func afterAnIntroBarOneHasTheNewNote() {
        var e = engine(in: "1.3")
        // C5 just met: its blocked screens
        var state = e.state
        state.lastIntro["treble"] = "treble:C5"
        state.introGap["treble"] = 0
        e = MasteryEngine(config: e.config, state: state)
        let c5 = key("treble:C5")
        #expect(e.blockedNote(.treble) == c5)
        var back = 0, total = 0
        for shape in [PatternShape.twin, .moved, .oneNote, .frame] {
            for seed: UInt64 in 1...20 {
                var copy = e
                var rng = SeededRandom(seed: seed)
                guard let pick = copy.patternPick(on: .treble, only: shape, using: &rng) else { continue }
                let (one, two) = Self.bars(pick.item)
                #expect(one.contains { $0.keys.contains(c5) }, "\(shape): \(pick.item.id)")
                total += 1
                if two.contains(where: { $0.keys.contains(c5) }) { back += 1 }
                if shape != .oneNote { #expect(two.contains { $0.keys.contains(c5) }, "\(shape) brings it back: \(pick.item.id)") }
            }
        }
        #expect(back >= total - 20 && total >= 50, "\(back) of \(total)")
    }

    /// The bar rhythm isn't one of the last few pattern screens' while others are left.
    @Test func rhythmsTakeTurns() {
        var e = engine(in: "2.1")
        var rng = SeededRandom(seed: 3)
        var cells: [String] = []
        for _ in 0..<40 {
            guard let pick = e.pickPattern(.frame, using: &rng) else { continue }
            cells.append(MasteryEngine.patternCellIDs(pick.item)[0])
        }
        // 2 a bar: 7 rhythms (4 in 4/4, 3 in 3/4), so the last 3 are always avoided
        for i in 3..<cells.count {
            #expect(!cells[(i - 3)..<i].contains(cells[i]), "\(cells[(i - 3)...i])")
        }
        #expect(Set(cells).count >= 6, "\(Set(cells))")
    }

    @Test func shapeAndRecentListsAreSaved() throws {
        var e = engine(in: "2.1")
        var rng = SeededRandom(seed: 1)
        _ = e.pickPattern(.moved, using: &rng)
        _ = e.pickPattern(.answer, using: &rng)
        #expect(e.state.lastShape == .answer)
        #expect(e.state.recentPatterns.count == 2 && e.state.recentPatterns[0].hasPrefix("moved "))
        #expect(e.state.recentCells.count == 2)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(MasteryState.self, from: data)
        #expect(back.lastShape == .answer)
        #expect(back.recentPatterns == e.state.recentPatterns)
        #expect(back.recentCells == e.state.recentCells)
    }

    /// His iPad's save from before pattern screens decodes, and a shape a later build
    /// drops doesn't wipe his state.
    @Test func savesBeforePatternsStillDecode() throws {
        var e = engine(in: "1.3")
        var rng = SeededRandom(seed: 1)
        _ = e.pickPattern(.twin, using: &rng)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(e.state)) as? [String: Any])
        json["lastShape"] = "turnedAround"
        json["recentCells"] = 7
        let odd = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(odd.lastShape == nil && odd.recentCells == [] && odd.recentPatterns.count == 1 && odd.lesson == "1.3")
        for field in ["lastShape", "recentPatterns", "recentCells"] { json[field] = nil }
        let old = try JSONDecoder().decode(MasteryState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.lastShape == nil && old.recentPatterns.isEmpty && old.recentCells.isEmpty)
        #expect(old.lesson == "1.3" && old.stats == e.state.stats)
    }
}
