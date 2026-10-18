import Testing
@testable import NoteCore

/// A seeded kid through the whole curriculum, one session a day (plans/2026-10-16-
/// drills-and-habit.md, checks): drill share per session, the pattern mix, no pattern
/// twice running, level 3's notes in levels 4-5, and when each level's notes became habit.
@Suite struct SeededRunTests {
    struct Kid {
        var name: String
        /// seconds a note, give or take `jitter` (a fraction)
        var time: Double
        var jitter: Double
        var rightRate: Double
    }

    struct LevelLog {
        var sessions = 0
        var screens = 0
        var drillScreens = 0
        var burstShares: [Double] = []
        var patterns: [Drill: Int] = [:]
        var levelThreeNotes = 0
        var drillLessonSessions = 0
        var drillLessonEndedOnHabit: Bool?
        var habitAtEnd = 0
        var notesAtEnd = 0
        var missing: [String] = []
        /// Normal screens in practice lessons (not intros, warm-ups, easing, extras, drills
        /// or second reads), and how many were pattern screens, of which shapes.
        var normalScreens = 0
        var patternScreens = 0
        var shapes: [PatternShape: Int] = [:]
        /// The same, on a clef's 3 screens right after a new note's intro there.
        var introWindowScreens = 0
        var introWindowPatterns = 0
    }

    static func run(_ kid: Kid, seed: UInt64, maxSessions: Int = 160) -> (levels: [Int: LevelLog], twiceRunning: Int, sessions: Int, shapeTwice: Int) {
        var engine = MasteryEngine(state: MasteryState(seed: seed))
        var dice = SeededRandom(seed: seed &+ 7)
        var levels: [Int: LevelLog] = [:]
        var twice = 0
        var lastShape: PatternShape?
        var shapeTwice = 0
        // screens on each clef since a new note's intro there
        var sinceIntro: [Clef: Int] = [:]
        let levelThree = Set(Curriculum.standard.level(3)!.lessons.flatMap(\.keys)).subtracting(Curriculum.standard.level(1)!.lessons.flatMap(\.keys))
        var sessions = 0
        while !engine.isCurriculumComplete, sessions < maxSessions {
            sessions += 1
            let level = engine.lesson.level
            let lesson = engine.lesson
            var bench = Bench(engine, seed: seed &* 1000 &+ UInt64(sessions))
            var log = levels[level] ?? LevelLog()
            log.sessions += 1
            if lesson.isDrillLesson { log.drillLessonSessions += 1 }
            var lastDrill: Drill?
            var screens = 0, drills = 0, practiceScreens = 0, bursts = 0
            var lessonsSeen = Set<LessonID>()
            var endedOnHabit = false
            var habitAtEnd = (reached: 0, played: 0)
            var missing: [String] = []
            _ = bench.start()
            while bench.session.phase != .done {
                let s = bench.session
                lessonsSeen.insert(s.engine.lesson.id)
                if s.engine.lesson.isDrillLesson {
                    let notes = s.engine.drillLessonNotes
                    habitAtEnd = (notes.filter { s.engine.state.lessonHabit.contains($0.id) }.count, notes.count)
                    missing = notes.filter { !s.engine.state.lessonHabit.contains($0.id) }.map { key in
                        let h = s.engine.habit(key)
                        return "\(key.id) \(h.samples)/\(h.firstTries) \(h.median.map { String(format: "%.1fs", $0) } ?? "-") cv \(h.steadiness.map { String(format: "%.2f", $0) } ?? "-") days \(h.cleanDays)"
                    }
                    // the day cap needs `drillLessonMaxDays` days in the lesson: ending with
                    // fewer can only be habit (read before the last screen, so not `drillLessonReady`)
                    endedOnHabit = s.engine.state.lessonDays.count < s.engine.config.drillLessonMaxDays
                }
                // a rhythm retry is the same screen again, not a new one
                if let intro = s.introNote, s.retries == 0 {
                    sinceIntro[intro.clef] = 0
                } else if s.retries == 0, s.restarts == 0, let clef = s.item?.clefs.first {
                    let window = (sinceIntro[clef] ?? 99) < s.engine.config.blockedScreens
                    sinceIntro[clef] = (sinceIntro[clef] ?? 99) + 1
                    if !s.isIntro, !s.engine.lesson.isDrillLesson, [.normal, .stretch].contains(s.pickReason) {
                        log.normalScreens += 1
                        if window { log.introWindowScreens += 1 }
                        if let shape = s.pattern {
                            log.patternScreens += 1
                            log.shapes[shape, default: 0] += 1
                            if window { log.introWindowPatterns += 1 }
                            if shape == lastShape { shapeTwice += 1 }
                            lastShape = shape
                        }
                    }
                }
                if !s.isIntro, s.retries == 0 {
                    screens += 1
                    let drillLesson = s.engine.lesson.isDrillLesson
                    if !drillLesson {
                        practiceScreens += 1
                        if s.pickReason == .drill { bursts += 1 }
                    }
                    if let drill = s.drill, s.pickReason != .again, s.pickReason != .warmUp {
                        drills += 1
                        log.patterns[drill, default: 0] += 1
                        // a lesson with one drill (5.6) can't help it. with two (4.5) the other
                        // one can't always be made from his notes, and the picker falls back
                        // to the last one by design
                        if drill == lastDrill, s.engine.lesson.drills.count > 2 { twice += 1 }
                        lastDrill = drill
                        if level >= 4 { log.levelThreeNotes += s.item!.keys.filter(levelThree.contains).count }
                    } else if s.pickReason != .again {
                        lastDrill = nil
                    }
                }
                var n = 0
                while bench.session.phase.isPlaying {
                    n += 1
                    if !bench.session.isIntro, unitInterval(&dice) >= kid.rightRate {
                        _ = bench.press(bench.wrongKey, after: kid.time)
                    }
                    let jitter = 1 + kid.jitter * (2 * unitInterval(&dice) - 1)
                    _ = bench.playNote(after: kid.time * jitter)
                }
                _ = bench.next(after: 1)
            }
            engine = bench.session.engine
            log.screens += screens
            log.drillScreens += drills
            // sessions that stayed in one practice lesson all through
            if lessonsSeen.count == 1, !lesson.isDrillLesson, practiceScreens > 0 {
                log.burstShares.append(Double(bursts) / Double(practiceScreens))
            }
            if lesson.isDrillLesson, bench.session.summary.completedLessons.contains(lesson.id) {
                let before = bench.session.engine.state.completedLessons
                _ = before
                log.drillLessonEndedOnHabit = endedOnHabit
                log.habitAtEnd = endedOnHabit ? habitAtEnd.played : habitAtEnd.reached
                log.notesAtEnd = habitAtEnd.played
                log.missing = endedOnHabit ? [] : missing
            }
            levels[level] = log
        }
        return (levels, twice, sessions, shapeTwice)
    }

    static func report(_ kid: Kid, seed: UInt64, _ result: (levels: [Int: LevelLog], twiceRunning: Int, sessions: Int, shapeTwice: Int)) -> String {
        var lines = ["\(kid.name), seed \(seed): \(result.sessions) sessions for the whole curriculum, \(result.twiceRunning) drills twice running, "
            + "\(result.shapeTwice) pattern shapes twice running"]
        for level in result.levels.keys.sorted() {
            let log = result.levels[level]!
            let shares = log.burstShares
            let share = shares.isEmpty ? 0 : shares.reduce(0, +) / Double(shares.count)
            let mix = log.patterns.sorted { $0.value > $1.value }.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", ")
            let end = log.drillLessonEndedOnHabit.map { $0 ? "on habit (\(log.habitAtEnd) of \(log.notesAtEnd) notes)" : "on the day cap (\(log.habitAtEnd) of \(log.notesAtEnd) notes reached habit)" } ?? "not finished"
            lines.append("  level \(level): \(log.sessions) sessions, \(log.screens) screens, drills \(log.drillScreens) "
                + "(bursts \(Int((share * 100).rounded()))% of a practice lesson's screens), drill lesson \(log.drillLessonSessions) sessions, ended \(end)")
            lines.append("    patterns: \(mix)" + (level >= 4 ? "; level 3 notes on drill screens: \(log.levelThreeNotes)" : ""))
            let shapes = log.shapes.sorted { $0.value > $1.value }.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", ")
            lines.append("    pattern screens \(percent(log.patternScreens, log.normalScreens)) of \(log.normalScreens) normal screens, "
                + "\(percent(log.introWindowPatterns, log.introWindowScreens)) of \(log.introWindowScreens) right after an intro; shapes: \(shapes)")
            if !log.missing.isEmpty { lines.append("    not habit at the end (plays mid-screen/first try, median, cv, clean days): \(log.missing.joined(separator: "; "))") }
        }
        return lines.joined(separator: "\n")
    }

    static func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "-" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }

    static let steady = Kid(name: "steady reader, 1.3s a note +-30%, 92% right first try", time: 1.3, jitter: 0.3, rightRate: 0.92)
    static let automatic = Kid(name: "automatic reader, 1.1s a note +-25%, 98% right first try", time: 1.1, jitter: 0.25, rightRate: 0.98)
    static let slow = Kid(name: "slow reader, 2.6s a note +-30%, 85% right first try", time: 2.6, jitter: 0.3, rightRate: 0.85)

    @Test func aSteadyKidThroughEveryLevel() {
        for seed: UInt64 in [1, 2] {
            let result = Self.run(Self.steady, seed: seed)
            print(Self.report(Self.steady, seed: seed, result))
            #expect(result.sessions < 160, "the whole curriculum")
            #expect(result.twiceRunning == 0, "never the same drill twice running")
            for (level, log) in result.levels {
                if !log.burstShares.isEmpty {
                    let share = log.burstShares.reduce(0, +) / Double(log.burstShares.count)
                    #expect(share > 0.08 && share < 0.3, "level \(level): bursts are \(share) of a practice lesson's screens")
                }
                #expect(log.drillLessonEndedOnHabit != nil, "level \(level)'s drill lesson ends")
            }
            #expect(result.levels[4]!.levelThreeNotes > 0 && result.levels[5]!.levelThreeNotes > 0, "level 3's notes come back in levels 4-5")
            // pattern screens: 1 in 4 normal screens in levels 1-2, 1 in 5 after, more right
            // after an intro, never the same shape twice running
            #expect(result.shapeTwice == 0)
            var window = (screens: 0, patterns: 0), outside = (screens: 0, patterns: 0)
            var shapes = Set<PatternShape>()
            for (level, log) in result.levels {
                let n = log.normalScreens - log.introWindowScreens
                let patterns = log.patternScreens - log.introWindowPatterns
                window = (window.screens + log.introWindowScreens, window.patterns + log.introWindowPatterns)
                outside = (outside.screens + n, outside.patterns + patterns)
                shapes.formUnion(log.shapes.keys)
                guard n >= 15 else { continue }
                let wanted = level <= 2 ? 0.25 : 0.2
                let share = Double(patterns) / Double(n)
                // three standard deviations of a share of n screens
                #expect(abs(share - wanted) < 3 * (wanted * (1 - wanted) / Double(n)).squareRoot() + 0.02,
                        "level \(level): pattern screens \(patterns) of \(n) normal screens outside an intro's")
            }
            let windowShare = Double(window.patterns) / Double(max(1, window.screens))
            let outsideShare = Double(outside.patterns) / Double(max(1, outside.screens))
            #expect(windowShare > outsideShare + 0.05, "right after an intro \(windowShare), else \(outsideShare)")
            #expect(shapes == Set(PatternShape.allCases), "\(shapes)")

        }
    }

    /// A kid whose notes really are automatic gets out of the drill lessons on habit.
    @Test func anAutomaticKidEndsDrillLessonsOnHabit() {
        let result = Self.run(Self.automatic, seed: 4)
        print(Self.report(Self.automatic, seed: 4, result))
        let onHabit = result.levels.values.filter { $0.drillLessonEndedOnHabit == true }.count
        #expect(onHabit >= 3, "\(onHabit) of 5 drill lessons ended on habit")
    }

    /// Habit never comes for a slow reader (median over 2s): every drill lesson ends on the day cap.
    @Test func aSlowKidStillGetsThroughLevelOne() {
        let result = Self.run(Self.slow, seed: 3, maxSessions: 30)
        print(Self.report(Self.slow, seed: 3, result))
        #expect(result.levels[1]!.drillLessonEndedOnHabit == false)
        #expect(result.levels[1]!.drillLessonSessions <= NoteCoreConfig().drillLessonMaxDays)
        #expect(result.levels[2] != nil, "on to level 2")
    }
}

