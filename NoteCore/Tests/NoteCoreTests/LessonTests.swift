import Testing
@testable import NoteCore

@Suite struct LessonTests {
    let curriculum = Curriculum.standard

    @Test func levelsAndLessonsAreNumberedInOrder() {
        #expect(curriculum.levels.map(\.number) == Array(1...curriculum.levels.count))
        for level in curriculum.levels {
            #expect(level.lessons.count >= 4, "many lessons per level")
            #expect(level.lessons.map(\.id) == level.lessons.indices.map { "\(level.number).\($0 + 1)" })
            #expect(level.lessons.allSatisfy { $0.level == level.number })
        }
        #expect(Set(curriculum.lessons.map(\.id)).count == curriculum.lessons.count)
    }

    @Test func gPosition() {
        let level1 = curriculum.level(1)!
        let notes = Set(level1.lessons.flatMap(\.keys).map(\.id))
        #expect(notes == ["treble:G4", "treble:A4", "treble:B4", "treble:C5", "treble:D5",
                          "bass:G2", "bass:A2", "bass:B2", "bass:C3", "bass:D3"])
    }

    /// Every session mixes clefs, so every lesson has notes on both.
    @Test func everyLessonHasBothClefs() {
        for lesson in curriculum.lessons {
            #expect(lesson.clefs == [.treble, .bass], "\(lesson.id)")
        }
    }

    @Test func everyLevelHasTrebleBassAndMixedLessons() {
        for level in curriculum.levels {
            let focuses = Set(level.lessons.map(\.focus))
            #expect(focuses == [.treble, .bass, .both], "level \(level.number)")
        }
    }

    /// Something to show on each clef the moment a lesson starts.
    @Test func everyClefStartsWithNotes() {
        for lesson in curriculum.lessons {
            for clef in lesson.clefs {
                let notes = lesson.notes(clef)!
                #expect(!notes.known.isEmpty || notes.start >= 2, "\(lesson.id) \(clef)")
            }
        }
    }

    @Test func aStartSetCanHaveALineAndASpace() {
        for lesson in curriculum.lessons {
            for clef in lesson.clefs {
                let keys = lesson.notes(clef)!.all.map { NoteKey(clef, $0) }
                #expect(keys.contains(where: \.isOnLine) && keys.contains(where: { !$0.isOnLine }), "\(lesson.id) \(clef)")
            }
        }
    }

    @Test func noteSetsHaveNoRepeats() {
        for lesson in curriculum.lessons {
            for clef in lesson.clefs {
                let all = lesson.notes(clef)!.all
                #expect(Set(all).count == all.count, "\(lesson.id) \(clef)")
            }
        }
    }

    @Test func sizesFitAnIpadScreen() {
        for lesson in curriculum.lessons {
            #expect(lesson.sizes.lowerBound >= 1 && lesson.sizes.upperBound <= 8, "\(lesson.id)")
        }
        #expect(curriculum.lesson("1.1")!.sizes.lowerBound == 1, "1 note a screen for the first few screens")
        #expect(curriculum.level(2)!.lessons.filter { $0.layout == .alternating }.allSatisfy { $0.sizes == 3...4 })
    }

    @Test func octavePolicyAndKeySignaturePerLevel() {
        for lesson in curriculum.lessons {
            #expect(lesson.octavePolicy == (lesson.level <= 2 ? .lenient : .strict), "\(lesson.id)")
            if lesson.level <= 2 {
                #expect(lesson.keySignature == .none, "\(lesson.id)")
                #expect(!lesson.keys.contains { $0.pitch.naturalLetter == .f }, "\(lesson.id) has no F")
            }
        }
    }

    /// Level 3 adds F#: every F there is F#, read from the G major key signature.
    @Test func levelThreeIsInGMajorWithFSharp() {
        let level = curriculum.level(3)!
        #expect(level.lessons.allSatisfy { $0.keySignature == .gMajor })
        let fs = Set(level.lessons.flatMap(\.keys).filter { $0.pitch.naturalLetter == .f }.map(\.id))
        #expect(fs == ["treble:F#4", "treble:F#5", "bass:F#3"], "F#2 is below bass G2, out of range")
        #expect(curriculum.lessons.allSatisfy { lesson in
            lesson.keys.allSatisfy { $0.pitch.isWhiteKey || lesson.keySignature.sharpPitchClasses.contains($0.pitch.pitchClass) }
        }, "no black key without a key signature that sharps it")
        #expect(level.lessons.filter { !$0.newKeys.isEmpty }.allSatisfy { lesson in
            lesson.newKeys.contains { !$0.pitch.isWhiteKey } || lesson.id == "3.4"
        }, "each lesson that widens a staff past an F brings its F# in")
    }

    @Test func levelThreeReachesMiddleCFromBothSides() {
        let notes = Set(curriculum.level(3)!.lessons.flatMap(\.keys).map(\.id))
        #expect(notes.contains("treble:C4") && notes.contains("bass:C4"))
        #expect(notes.contains("treble:G5") && notes.contains("bass:G3"))
        #expect(curriculum.lesson("3.5")!.layout == .grand)
    }

    @Test func mixedLessonsUseTheGrandStaffFromLevelTwo() {
        #expect(curriculum.level(1)!.lessons.allSatisfy { $0.layout == .alternating })
        for level in curriculum.levels.dropFirst() {
            #expect(level.lessons.contains { $0.layout == .grand && $0.focus == .both }, "level \(level.number)")
        }
    }

    @Test func knownNotesComeFromEarlierLessons() {
        var seen = Set<NoteKey>()
        for lesson in curriculum.lessons {
            for clef in lesson.clefs {
                for pitch in lesson.notes(clef)!.known {
                    #expect(seen.contains(NoteKey(clef, pitch)), "\(lesson.id) treats \(clef) \(pitch) as known before any lesson brings it in")
                }
            }
            seen.formUnion(lesson.newKeys)
            seen.formUnion(lesson.keys.filter { !lesson.newKeys.contains($0) })
        }
    }
}

@Suite struct MixedClefTests {
    @Test func everySessionMixesClefs() {
        for id in ["1.1", "1.2", "1.3", "2.1", "2.4", "3.1", "3.4"] {
            var bench = Bench(engine(in: id), seed: 3)
            _ = bench.start()
            var clefs = Set<Clef>()
            for _ in 0..<6 {
                clefs.formUnion(bench.session.item!.clefs)
                _ = bench.playScreen()
                _ = bench.next()
            }
            #expect(clefs == [.treble, .bass], "\(id)")
        }
    }

    @Test func alternatingLessonsDrawOneStaffPerScreen() {
        var engine = engine(in: "2.1")
        var rng = SeededRandom(seed: 1)
        for _ in 0..<50 {
            let item = engine.pickScreen(using: &rng).item
            #expect(item.clefs.count == 1)
            #expect(item.layout != .grand)
            #expect(item.bars == [item.notes.count])
        }
    }

    /// Stays in the lesson however well he plays.
    var stay: NoteCoreConfig {
        var config = NoteCoreConfig()
        config.lessonMinScreens = 10_000
        return config
    }

    @Test func grandStaffScreensAreATrebleBarAndABassBar() throws {
        var engine = engine(in: "2.5", config: stay)
        #expect(engine.screenSize == 4)
        var rng = SeededRandom(seed: 2)
        var firstClefs = Set<Clef>()
        for _ in 0..<60 {
            let item = engine.pickScreen(using: &rng).item
            #expect(item.layout == .grand)
            try #require(item.bars.count == 2, "\(item.id)")
            let first = Array(item.notes.prefix(item.bars[0])), second = Array(item.notes.suffix(item.bars[1]))
            #expect(Set(first.map(\.clef)).count == 1 && Set(second.map(\.clef)).count == 1)
            #expect(first[0].clef != second[0].clef, "one bar on each staff: \(item.id)")
            #expect(item.barLinesAfter == [item.bars[0] - 1])
            firstClefs.insert(first[0].clef)
            engine.play(item.notes.flatMap(\.keys), time: 1)
        }
        #expect(firstClefs == [.treble, .bass], "either staff can go first")
    }

    @Test func grandStaffSizeGrowsPastOneClefsRoom() {
        var engine = engine(in: "2.5", config: stay)
        var rng = SeededRandom(seed: 4)
        for _ in 0..<40 {
            let pick = engine.pickScreen(using: &rng)
            engine.play(pick.item.notes.flatMap(\.keys), time: 1, reason: pick.isStretch ? .stretch : .normal)
        }
        #expect(engine.screenSize == 6, "two bars of 3")
    }

    @Test func stepsLessonsStepAndSkipsLessonsSkip() {
        func moves(_ id: LessonID) -> (steps: Int, skips: Int) {
            var engine = engine(in: id)
            var rng = SeededRandom(seed: 6)
            var steps = 0, skips = 0
            for _ in 0..<200 {
                let keys = engine.pickScreen(using: &rng).item.notes.flatMap(\.keys)
                for (a, b) in zip(keys, keys.dropFirst()) {
                    let d = abs(a.pitch.diatonicIndex - b.pitch.diatonicIndex)
                    if d == 1 { steps += 1 } else if d > 1 { skips += 1 }
                }
            }
            return (steps, skips)
        }
        let steps = moves("2.1"), skips = moves("2.3")
        #expect(steps.steps > steps.skips * 2, "\(steps)")
        #expect(skips.skips > skips.steps * 2, "\(skips)")
    }

    @Test func levelThreeIsStrictAboutOctaves() {
        var bench = Bench(engine(in: "3.1"))
        _ = bench.start()
        let expected = bench.expected[0]
        let cues = bench.press(Pitch(midi: expected.midi + 12))
        #expect(cues == [.wobble(note: 0)])
    }

    @Test func levelThreeBringsInNewNotesWithIntros() {
        var engine = MasteryEngine(state: MasteryState(seed: 4))
        engine.moveToLesson("3.1")
        let pending = engine.pendingIntros
        #expect(pending.count == 1, "one of E5 / F#5 / G5 starts")
        #expect(pending.allSatisfy { ["treble:E5", "treble:F#5", "treble:G5"].contains($0.id) })
        #expect(engine.screenSize == 4)
    }

    @Test func middleCOnBothStaves() {
        var engine = engine(in: "3.5")
        var rng = SeededRandom(seed: 8)
        var both = Set<ItemID>()
        for _ in 0..<300 {
            let item = engine.pickScreen(using: &rng).item
            for key in item.keys where key.pitch == .middleC { both.insert(key.id) }
        }
        #expect(both == ["treble:C4", "bass:C4"])
    }

    @Test func aWholeLevelPlaysThrough() {
        var engine = MasteryEngine(state: MasteryState(seed: 2))
        var rng = SeededRandom(seed: 2)
        var lessons: [LessonID] = []
        for _ in 0..<3000 where !engine.isCurriculumComplete {
            if lessons.last != engine.lesson.id { lessons.append(engine.lesson.id) }
            engine.playPick(engine.pickScreen(using: &rng))
        }
        #expect(engine.isCurriculumComplete)
        #expect(lessons == Curriculum.standard.lessons.map(\.id), "every lesson, in order")
    }
}
