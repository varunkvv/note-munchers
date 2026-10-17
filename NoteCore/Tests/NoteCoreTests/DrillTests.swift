import Testing
@testable import NoteCore

/// Section 2 of plans/2026-10-16-drills-and-habit.md: drill screens in every level.
@Suite struct DrillTests {
    /// Stays in the lesson however well he plays.
    var stay: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return config
    }

    /// `count` drill picks on `clef` (the grand staff picks its own), each played right.
    func drills(_ id: LessonID, clef: Clef = .treble, count: Int = 200, seed: UInt64 = 1) -> [Pick] {
        var engine = engine(in: id, config: stay)
        var rng = SeededRandom(seed: seed)
        var picks: [Pick] = []
        for _ in 0..<count {
            let pick = engine.pickScreen(.drill, clef: clef, using: &rng)
            picks.append(pick)
            engine.playPick(pick)
        }
        return picks
    }

    func bars(_ item: PracticeItem) -> [[WrittenNote]] { item.barRanges.map { Array(item.notes[$0]) } }

    func letters(_ notes: [WrittenNote]) -> [Int] { notes.map { $0.pitches[0].diatonicIndex } }

    @Test func everyLessonHasDrills() {
        for lesson in Curriculum.standard.lessons {
            #expect(!lesson.drills.isEmpty, "\(lesson.id)")
            #expect(lesson.drills.contains(.echo) == (lesson.layout == .grand), "\(lesson.id): echoes are grand staff only")
        }
    }

    @Test func drillScreensHaveTheirShape() throws {
        var seen = Set<Drill>()
        for id in ["1.4", "2.1", "2.3", "3.6", "4.1", "5.3"] {
            var previous: Drill?
            for pick in drills(id, clef: id == "2.1" ? .bass : .treble) {
                let drill = try #require(pick.drill, "\(id): a drill screen has its drill")
                seen.insert(drill)
                #expect(drill != previous, "\(id): never the same drill twice running")
                previous = drill
                let item = pick.item
                let notes = item.notes
                #expect(notes.allSatisfy { !$0.isChord }, "\(id): bursts are single notes")
                #expect(notes.count <= Curriculum.standard.lesson(id)!.drillSizes.upperBound, "\(id) \(item.id) fits the staff")
                switch drill {
                case .run:
                    let steps = zip(letters(notes), letters(notes).dropFirst()).map { $1 - $0 }
                    #expect(steps.allSatisfy { abs($0) == 1 }, "\(id) run \(item.id)")
                    // it only turns at an end: never down-up-down inside the stretch
                    for (i, step) in steps.enumerated().dropFirst() where step != steps[i - 1] {
                        let turn = letters(notes)[i]
                        let span = letters(notes)
                        #expect(turn == span.max() || turn == span.min(), "\(id) run turns at an edge: \(item.id)")
                    }
                case .motif:
                    let b = bars(item)
                    try #require(b.count == 2 && b[0].count == b[1].count, "\(id) motif \(item.id)")
                    #expect(b[0].map(\.value) == b[1].map(\.value), "\(id) a motif's cells share a rhythm: \(item.id)")
                    let (x, y) = (letters(b[0]), letters(b[1]))
                    let moved = Set(zip(x, y).map { $1 - $0 }).count == 1 && abs(y[0] - x[0]) == 1
                    let turned = Array(x.reversed()) == y
                    let changed = zip(x, y).filter { $0 != $1 }.count == 1 && x[0] == y[0]
                    #expect(moved || turned || changed, "\(id) motif \(item.id)")
                case .home:
                    let homes = notes.enumerated().filter { $0.offset % 2 == (notes[0].pitches[0].letter == .g ? 0 : 1) }
                    #expect(homes.allSatisfy { $0.element.pitches[0].letter == .g }, "\(id) home \(item.id)")
                case .repeatNote:
                    for bar in bars(item) {
                        #expect(Set(bar.map(\.pitches)).count == 1, "\(id) repeat \(item.id)")
                    }
                case .echo:
                    let b = bars(item)
                    try #require(b.count == 2, "\(id) echo \(item.id)")
                    #expect(item.layout == .grand && b[0][0].clef != b[1][0].clef, "\(id) echo \(item.id)")
                    #expect(b[0].map { $0.pitches[0].pitchClass } == b[1].map { $0.pitches[0].pitchClass }, "\(id) echo \(item.id)")
                    #expect(b[0].map(\.value) == b[1].map(\.value))
                    #expect(Set(b[0].map(\.pitches)).count >= 2, "\(id) an echo of one key echoes nothing")
                case .tune:
                    let clef = notes[0].clef
                    let match = Tune.all.contains { tune in
                        let keys = tune.keys(clef)
                        let taken = bars(item).count
                        return taken <= keys.count && Array(keys.prefix(taken).joined()) == notes.flatMap(\.keys)
                            && Array(tune.bars.prefix(taken).joined().map(\.value)) == notes.map(\.value)
                    }
                    #expect(match, "\(id) tune \(item.id)")
                default:
                    Issue.record("\(id): \(drill) isn't a burst drill")
                }
            }
        }
        #expect(seen == [.run, .motif, .home, .repeatNote, .echo, .tune])
    }

    /// One hand position per bar, every note inside it.
    @Test func drillScreensStayInAHandPosition() throws {
        for id in ["1.2", "2.3", "3.1", "3.5", "3.6", "4.4"] {
            for pick in drills(id, count: 120) {
                try #require(pick.positions.count == pick.item.notes.count, "\(id) \(pick.item.id)")
                for range in pick.item.barRanges {
                    let hands = Set(pick.positions[range])
                    #expect(hands.count == 1, "\(id) \(pick.item.id)")
                    #expect(pick.item.notes[range].flatMap(\.keys).allSatisfy(hands.first!.contains), "\(id) \(pick.item.id)")
                }
            }
        }
    }

    /// Levels 4-5 only declare G position. Drill screens bring back the level 3 notes he
    /// has met, so they keep getting practice (a piano teacher's review).
    @Test func levelFourDrillsBringBackLevelThreeNotes() {
        var engine = engine(in: "4.1", config: stay)
        for id in ["treble:E5", "treble:F#5", "treble:G5", "treble:C4", "treble:D4", "bass:C4", "bass:B3", "bass:E3"] {
            engine.state.introduced.insert(id)
            engine.state.unlocked.insert(id)
        }
        #expect(engine.drillNotes(.treble).map(\.id).contains("treble:E5"))
        #expect(!engine.pool(.treble).map(\.id).contains("treble:E5"), "normal screens stay in G position")
        var rng = SeededRandom(seed: 3)
        var outside = 0
        for _ in 0..<200 {
            let pick = engine.pickScreen(.drill, clef: .treble, using: &rng)
            if pick.item.keys.contains(where: { !HandPosition.g($0.clef).contains($0) }) { outside += 1 }
            engine.playPick(pick)
        }
        #expect(outside > 40, "\(outside) of 200 drill screens use level 3's notes")
    }

    /// An old save can hold notes level 1 hasn't reached yet. Drills never use them.
    @Test func drillsNeverJumpAheadOfTheLessons() {
        var engine = engine(in: "1.1", config: stay)
        for id in ["treble:B4", "treble:C5", "treble:D5", "bass:C3"] {
            engine.state.introduced.insert(id)
            engine.state.unlocked.insert(id)
        }
        #expect(engine.drillNotes(.treble).map(\.id) == ["treble:G4", "treble:A4"])
        #expect(engine.drillNotes(.bass).map(\.id) == ["bass:G2", "bass:A2"])
    }

    /// A session he's played before opens on one run screen of his strongest notes.
    @Test func theWarmUpIsOneRun() {
        for id in ["1.3", "2.1", "3.6", "4.2", "5.1"] {
            var engine = engine(in: id, config: stay)
            for key in engine.pool { engine.play(key, time: 1) }
            var bench = Bench(engine, seed: 5)
            _ = bench.start()
            #expect(bench.session.pickReason == .warmUp, "\(id)")
            #expect(bench.session.drill == .run, "\(id)")
            let item = bench.session.item!
            #expect(item.notes.allSatisfy { !$0.isChord } && item.notes.count >= 3, "\(id) \(item.id)")
            let strongest = Set(Clef.allCases.flatMap(engine.strongestNotes))
            #expect(item.keys.allSatisfy(strongest.contains), "\(id): his strongest notes")
            _ = bench.playScreen()
            _ = bench.next()
            #expect(bench.session.pickReason != .warmUp, "\(id): one screen of it")
        }
    }

    struct SessionShape {
        var bursts: [[(drill: Drill, clef: Clef)]] = []
        var firstRun = 0
        var againScreens = 0
        var againMatches = true
        var drillOnExtra = false
        var offRun = false
    }

    func shape(_ id: LessonID, seed: UInt64) -> SessionShape {
        var engine = engine(in: id, config: stay)
        for key in engine.pool { engine.play(key, time: 1) }
        var bench = Bench(engine, seed: seed)
        var out = SessionShape()
        var current: [(drill: Drill, clef: Clef)] = []
        var previous: PracticeItem?
        var firstClef: Clef?
        var switched = false
        _ = bench.start()
        while bench.session.phase != .done {
            let s = bench.session
            let clef = s.item!.notes[0].clef
            if firstClef == nil { firstClef = s.runClef }
            if s.runClef != firstClef { switched = true }
            if s.pickReason == .drill {
                current.append((s.drill!, clef))
                if let run = s.runClef, s.item!.clefs != [run] { out.offRun = true }
                if !switched, current.count == 1 { out.firstRun += 1 }
            } else if s.pickReason != .again, !current.isEmpty {
                out.bursts.append(current)
                current = []
            }
            if s.pickReason == .extra, s.drill != nil, s.drill != .run { out.drillOnExtra = true }
            if s.pickReason == .again {
                out.againScreens += 1
                if s.item != previous { out.againMatches = false }
            }
            previous = s.item
            _ = bench.playScreen()
            _ = bench.next()
        }
        if !current.isEmpty { out.bursts.append(current) }
        return out
    }

    /// One burst of 3-4 drill screens a session, inside one clef run, the first run about
    /// half the time, never the same drill twice running.
    @Test func oneBurstASessionInsideOneRun() {
        for id in ["1.2", "2.2", "3.3", "4.1", "5.4", "2.3"] {
            var firstRuns = 0
            for seed: UInt64 in 1...40 {
                let s = shape(id, seed: seed)
                #expect(s.bursts.count == 1, "\(id) seed \(seed): \(s.bursts.count) bursts")
                guard let burst = s.bursts.first else { continue }
                #expect((3...4).contains(burst.count), "\(id) seed \(seed): \(burst.count) drill screens")
                #expect(!s.offRun, "\(id) seed \(seed): a drill off the run's clef")
                #expect(!s.drillOnExtra, "\(id) seed \(seed)")
                for (a, b) in zip(burst, burst.dropFirst()) {
                    #expect(a.drill != b.drill, "\(id) seed \(seed): \(burst.map(\.drill))")
                }
                if Curriculum.standard.lesson(id)!.layout == .alternating {
                    #expect(Set(burst.map(\.clef)).count == 1, "\(id) seed \(seed): one clef \(burst.map { "\($0.drill) \($0.clef)" })")
                }
                firstRuns += s.firstRun
            }
            if Curriculum.standard.lesson(id)!.layout == .alternating {
                #expect((8...32).contains(firstRuns), "\(id): \(firstRuns) of 40 bursts in the first run")
            }
        }
    }

    /// Now and then a clean screen comes once more, the same screen, at most once a
    /// session, and nothing about it is counted.
    @Test func againIsTheSameScreenOnceAtMost() {
        var sessions = 0, withAgain = 0
        for id in ["1.3", "2.1", "3.2", "4.3"] {
            for seed: UInt64 in 1...25 {
                let s = shape(id, seed: seed)
                sessions += 1
                #expect(s.againScreens <= 1, "\(id) seed \(seed)")
                #expect(s.againMatches, "\(id) seed \(seed)")
                if s.againScreens > 0 { withAgain += 1 }
            }
        }
        #expect(withAgain > sessions / 4 && withAgain < sessions * 9 / 10, "\(withAgain) of \(sessions) sessions")
    }

    @Test func anAgainScreenDoesntCount() {
        var engine = engine(in: "2.1", config: stay)
        let before = engine.state
        let note = AttemptResult(itemID: "treble:G4", lesson: "2.1", level: 2, firstTry: true, responseTime: 0.5)
        engine.record(ScreenResult(screenID: "x", lesson: "2.1", reason: .again, notes: [note]))
        #expect(engine.state == before)
    }

    /// Blocked, then mixed: a new note's first screens on its clef after its intro are
    /// mostly that note, then it mixes in at the lesson's share.
    @Test func aNewNoteIsBlockedThenMixed() {
        var blocked = 0, blockedAll = 0, mixed = 0, mixedAll = 0
        for seed: UInt64 in 1...30 {
            var engine = MasteryEngine(config: stay, state: MasteryState(seed: seed))
            engine.moveToLesson("1.3")
            engine.introduceAll()
            for key in engine.pool { engine.play(key, time: 1) }
            // C comes in again, as if new
            engine.state.introduced.remove("treble:C5")
            var rng = SeededRandom(seed: seed)
            var sinceIntro: Int?
            for _ in 0..<40 {
                let pick = engine.pickScreen(clef: .treble, using: &rng)
                if pick.intro == key("treble:C5") {
                    sinceIntro = 0
                } else if let n = sinceIntro {
                    let keys = pick.item.notes.flatMap(\.keys)
                    let c = keys.filter { $0 == key("treble:C5") }.count
                    if n < 3 { blocked += c; blockedAll += keys.count } else if n < 15 { mixed += c; mixedAll += keys.count }
                    sinceIntro = n + 1
                }
                engine.playPick(pick)
            }
        }
        let b = Double(blocked) / Double(blockedAll), m = Double(mixed) / Double(mixedAll)
        print("blocked then mixed: \(b) of notes for 3 screens, then \(m)")
        #expect(b > 0.5, "mostly the new note: \(b)")
        #expect(m > 0.2 && m < 0.42, "then about 1 in 3: \(m)")
    }
}
