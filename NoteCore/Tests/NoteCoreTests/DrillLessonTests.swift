import Testing
@testable import NoteCore

/// The lesson that ends each level: every screen a drill (plans/2026-10-16-drills-and-habit.md).
@Suite struct DrillLessonTests {
    var stay: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return config
    }

    func picks(_ id: LessonID, count: Int = 150, seed: UInt64 = 2) -> [Pick] {
        var engine = engine(in: id, config: stay)
        var rng = SeededRandom(seed: seed)
        var out: [Pick] = []
        for _ in 0..<count {
            let pick = engine.pickScreen(using: &rng)
            out.append(pick)
            engine.playPick(pick)
        }
        return out
    }

    func bars(_ item: PracticeItem) -> [[WrittenNote]] { item.barRanges.map { Array(item.notes[$0]) } }

    @Test func everyScreenIsADrillOfTheLesson() {
        for lesson in Curriculum.standard.lessons where lesson.isDrillLesson {
            var seen = Set<Drill>()
            for pick in picks(lesson.id) {
                #expect(!pick.isLessonIntro && pick.intro == nil, "\(lesson.id): no intros")
                if let drill = pick.drill { seen.insert(drill) } else { Issue.record("\(lesson.id): \(pick.item.id) isn't a drill") }
            }
            #expect(seen == Set(lesson.drills), "\(lesson.id): \(seen)")
        }
    }

    @Test func levelOneDrillsAllTenNotes() {
        let all = Set(picks("1.5", count: 200).flatMap(\.item.keys))
        #expect(all.count == 10)
    }

    /// 3.7: shift screens move the hand once, at the bar line. Home is middle C. Motifs
    /// stay in G or D position.
    @Test func handPositionsLesson() throws {
        for pick in picks("3.7", count: 240) {
            let item = pick.item
            switch pick.drill {
            case .shift?:
                let b = bars(item)
                try #require(b.count == 2)
                let (first, second) = (pick.positions[0], pick.positions[item.notes.count - 1])
                #expect(first != second, "\(item.id)")
                #expect(b[0].flatMap(\.keys).allSatisfy(first.contains) && b[1].flatMap(\.keys).allSatisfy(second.contains))
                #expect(!first.contains(b[1][0].keys[0]), "bar 2 starts where the old position can't reach: \(item.id)")
            case .home?:
                let homes = item.notes.filter { $0.pitches[0] == .middleC }.count
                #expect(homes >= item.notes.count / 2, "home on middle C: \(item.id)")
            case .motif?:
                let gOrD = pick.positions.allSatisfy { $0 == HandPosition.g($0.clef) || $0 == HandPosition.d($0.clef) }
                #expect(gOrD, "\(item.id) \(pick.positions)")
            default:
                Issue.record("3.7: \(String(describing: pick.drill))")
            }
        }
    }

    /// 4.5: a two at once moved by step, or broken then together.
    @Test func sameShapeMoved() {
        for pick in picks("4.5", count: 120) {
            let notes = pick.item.notes
            switch pick.drill {
            case .movedTwo?:
                #expect(notes.allSatisfy { $0.isChord }, "\(pick.item.id)")
                let lows = notes.map { $0.pitches[0].diatonicIndex }
                #expect(zip(lows, lows.dropFirst()).allSatisfy { abs($0 - $1) == 1 }, "\(pick.item.id)")
                let gaps = Set(notes.map { $0.pitches[1].diatonicIndex - $0.pitches[0].diatonicIndex })
                #expect(gaps.count == 1, "the same shape: \(pick.item.id)")
            case .brokenTwo?:
                for bar in bars(pick.item) {
                    #expect(bar.count == 3 && !bar[0].isChord && !bar[1].isChord && bar[2].isChord, "\(pick.item.id)")
                    #expect(bar[2].pitches == bar[0].pitches + bar[1].pitches, "broken, then together: \(pick.item.id)")
                }
            default:
                Issue.record("4.5: \(String(describing: pick.drill))")
            }
        }
    }

    /// 5.6: a one-bar rhythm, then the same rhythm a step away or the same notes in a new
    /// rhythm, and the rhythm is judged.
    @Test func rhythmMotifs() throws {
        for pick in picks("5.6", count: 120) {
            #expect(pick.drill == .rhythmMotif)
            let b = bars(pick.item)
            try #require(b.count == 2 && b[0].count == b[1].count, "\(pick.item.id)")
            let sameRhythm = b[0].map(\.value) == b[1].map(\.value)
            let letters = b.map { $0.map { $0.pitches[0].diatonicIndex } }
            let moved = Set(zip(letters[0], letters[1]).map { $1 - $0 }).count == 1 && abs(letters[1][0] - letters[0][0]) == 1
            #expect((sameRhythm && moved) || (!sameRhythm && letters[0] == letters[1]), "\(pick.item.id)")
            #expect(pick.item.rhythmLine(.all) != nil, "rhythm judged: \(pick.item.id)")
        }
    }

    /// The level 2 merge: two both-clef lessons, then the grand staff, then patterns.
    @Test func levelTwoIsStepsSkipsGrandAndPatterns() {
        let level = Curriculum.standard.level(2)!
        #expect(level.lessons.map(\.title) == ["Steps, both clefs", "Skips, both clefs", "Grand staff: a treble bar and a bass bar", "Patterns and echoes"])
        #expect(level.lessons.prefix(2).allSatisfy { $0.layout == .alternating && $0.focus == .both })
    }

    /// Ending a level's last practice lesson leads into its drill lesson, then the next level.
    @Test func levelOneEndsInItsDrillLesson() {
        var engine = engine(in: "1.4")
        var rng = SeededRandom(seed: 4)
        var lessons: [LessonID] = []
        for _ in 0..<400 where engine.lesson.level == 1 || lessons.last != engine.lesson.id {
            if lessons.last != engine.lesson.id { lessons.append(engine.lesson.id) }
            engine.playPick(engine.pickScreen(using: &rng))
            if engine.lesson.level == 2 { lessons.append(engine.lesson.id); break }
        }
        #expect(lessons == ["1.4", "1.5", "2.1"])
    }
}
