import Testing
@testable import NoteCore

/// Real bars (plans/2026-10-15-real-bars.md): every screen is whole bars in 3/4 or 4/4,
/// every note has a value, rests fill out bars the notes don't fill.
@Suite struct BarsTests {
    var stay: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return config
    }

    /// `count` screens from `lesson` (every note met), each played right, so his size
    /// grows through the lesson's range.
    func screens(_ lesson: LessonID, count: Int = 150, seed: UInt64 = 1) -> [Pick] {
        var engine = engine(in: lesson, config: stay, seed: seed)
        var rng = SeededRandom(seed: seed)
        return (0..<count).map { _ in
            let pick = engine.pickScreen(using: &rng)
            engine.playPick(pick, time: 1)
            return pick
        }
    }

    @Test func everyGeneratedScreenIsWholeBars() throws {
        for lesson in Curriculum.standard.lessons {
            for pick in screens(lesson.id) {
                let item = pick.item
                let meter = try #require(item.meter, "\(item.id)")
                #expect(item.bars.count <= 2, "\(item.id)")
                for range in item.barRanges {
                    let bar = item.notes[range]
                    #expect(bar.reduce(0) { $0 + $1.span } == Double(meter.beats), "\(item.id)")
                    #expect(bar.dropLast().allSatisfy { $0.restsAfter.isEmpty }, "rests only end a bar: \(item.id)")
                    #expect(Set(bar.map(\.clef)).count == 1, "a bar's notes are on one staff: \(item.id)")
                }
                let values = Set(item.values)
                #expect(!values.contains(.whole) || meter == .fourFour, "\(item.id)")
                #expect(!values.contains(.dottedHalf) || meter == .threeFour, "\(item.id)")
                if case .rhythm(let allowed, _) = lesson.texture, allowed.contains(.eighth) {
                } else {
                    #expect(!values.contains(.eighth), "eighths only in level 5's eighth lessons: \(item.id)")
                }
                let rests = item.notes.flatMap(\.restsAfter)
                #expect(rests.allSatisfy { $0 == .quarter || $0 == .half }, "\(item.id)")
            }
        }
    }

    @Test func bothMetersInEveryLessonAndLevel() {
        for level in Curriculum.standard.levels {
            var levelMeters = Set<Meter>()
            for lesson in level.lessons {
                let meters = Set(screens(lesson.id, count: 60).compactMap(\.item.meter))
                #expect(meters == Set(Meter.allCases), "\(lesson.id): \(meters)")
                levelMeters.formUnion(meters)
            }
            #expect(levelMeters == Set(Meter.allCases), "level \(level.number)")
        }
    }

    @Test func aboutHalfTheScreensAreInFourFour() {
        let picks = screens("1.4", count: 400)
        let fourFour = picks.filter { $0.item.meter == .fourFour }.count
        #expect(fourFour > 160 && fourFour < 240, "\(fourFour) of 400")
    }

    /// The notes-per-screen ramp holds: a reading screen has his size (one more on a
    /// stretch), except that a 3/4 screen tops out at 6 notes.
    @Test func readingScreensHaveHisSize() {
        for lesson in Curriculum.standard.lessons where !lesson.texture.isRhythm {
            var engine = engine(in: lesson.id, config: stay)
            var rng = SeededRandom(seed: 3)
            var sizes = Set<Int>()
            for _ in 0..<150 {
                let size = engine.screenSize
                let pick = engine.pickScreen(using: &rng)
                engine.playPick(pick, time: 1)
                guard pick.intro == nil, !pick.isLessonIntro else { continue }
                let meter = pick.item.meter!
                let wanted = size + (pick.isStretch ? 1 : 0)
                #expect(pick.item.notes.count == min(wanted, MasteryEngine.maxNotes(meter)), "\(lesson.id) \(pick.item.id) at size \(size)")
                #expect(pick.size == size + (pick.isStretch ? 1 : 0))
                sizes.insert(pick.item.notes.count)
            }
            // the size also waits for a clef to have a note more than it (5 bass notes: 4 a screen)
            #expect(sizes.max()! >= min(lesson.sizes.upperBound, 4), "\(lesson.id) grows: \(sizes.sorted())")
        }
    }

    @Test func introsAreOneHeldNoteInOneBar() {
        var engine = MasteryEngine(state: MasteryState(seed: 11))
        var rng = SeededRandom(seed: 1)
        var meters = Set<Meter>()
        for _ in 0..<14 {
            let pick = engine.pickScreen(using: &rng)
            if pick.intro != nil {
                let item = pick.item
                #expect(item.notes.count == 1 && item.bars == [1])
                #expect(item.values == [item.meter == .fourFour ? .whole : .dottedHalf])
                meters.insert(item.meter!)
            }
            engine.playPick(pick)
        }
        #expect(meters == Set(Meter.allCases))
    }

    @Test func restsAndLongNotesShowUpOnReadingScreens() {
        var withRests = 0, wholes = 0, dottedHalves = 0, twoBarsOfFew = 0
        for pick in screens("1.4", count: 300) {
            let item = pick.item
            if item.notes.contains(where: { !$0.restsAfter.isEmpty }) { withRests += 1 }
            if item.values.contains(.whole) { wholes += 1 }
            if item.values.contains(.dottedHalf) { dottedHalves += 1 }
            if item.bars.count == 2, item.notes.count <= item.meter!.beats { twoBarsOfFew += 1 }
        }
        #expect(withRests > 30, "\(withRests) of 300 with a rest")
        #expect(wholes > 5 && dottedHalves > 5, "\(wholes) wholes, \(dottedHalves) dotted halves")
        #expect(twoBarsOfFew > 10, "some short screens spread over two bars: \(twoBarsOfFew)")
    }

    @Test func grandStaffBarsAreOneStaffEach() {
        for id in ["2.5", "3.5", "4.4", "5.5"] {
            for pick in screens(id, count: 60) where pick.intro == nil && !pick.isLessonIntro {
                let item = pick.item
                #expect(item.layout == .grand)
                if item.clefs.count == 2 {
                    #expect(item.bars.count == 2, "\(item.id)")
                    let first = item.notes[item.barRanges[0]].map(\.clef), second = item.notes[item.barRanges[1]].map(\.clef)
                    #expect(Set(first).count == 1 && Set(second).count == 1 && first[0] != second[0], "\(item.id)")
                }
            }
        }
    }

    @Test func dyadsGetValuesToo() {
        var dyadValues = Set<NoteValue>()
        for pick in screens("4.3", count: 100) {
            for note in pick.item.notes where note.isChord { dyadValues.insert(note.value) }
        }
        #expect(dyadValues.isSuperset(of: [.quarter, .half]), "\(dyadValues)")
    }

    @Test func playbackKeepsTheRests() {
        let a = WrittenNote(key("treble:G4"), .quarter)
        let b = WrittenNote(key("treble:A4"), .quarter, rests: [.half])
        let c = WrittenNote(key("treble:B4"), .dottedHalf)
        let item = PracticeItem([a, b, c], bars: [2, 1], meter: nil)
        #expect(item.startBeats == [0, 1, 4])
        #expect(item.gapBeats == [1, 3, 3])
        let notes = item.playback(beat: 0.5)
        #expect(notes.map(\.start) == [0, 0.5, 2])
        #expect(notes.map(\.duration) == [0.5, 0.5, 1.5])
    }

    @Test func screenIDsCarryTheRhythmAndMeter() {
        let g4 = key("treble:G4"), a4 = key("treble:A4")
        let item = PracticeItem([WrittenNote(g4, .half), WrittenNote(a4, .quarter, rests: [.quarter])], meter: .fourFour)
        #expect(item.id == "treble:G4/h-A4/q/rq 4/4")
        #expect(MasteryEngine.leadingClef(item.id) == .treble)
    }
}
