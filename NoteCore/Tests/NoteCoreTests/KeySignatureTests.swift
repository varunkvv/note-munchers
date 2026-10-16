import Testing
@testable import NoteCore

@Suite struct KeySignatureTests {
    static let fs4 = Pitch("F#4")!

    /// One G major lesson, one note a screen: F#4, G4, A4 on treble, G2, A2 on bass.
    static func gMajor(newFSharp: Bool = false) -> Curriculum {
        let treble = newFSharp
            ? ClefNotes(known: [Pitch(.g, 4), Pitch(.a, 4)], new: [fs4], start: 1)
            : ClefNotes(known: [fs4, Pitch(.g, 4), Pitch(.a, 4)])
        return Curriculum(levels: [Level(number: 1, title: "test", lessons: [
            Lesson("1.1", level: 1, title: "G major", focus: .treble, treble: treble,
                   bass: ClefNotes(known: [Pitch(.g, 2), Pitch(.a, 2)]), sizes: 1...1,
                   octavePolicy: .strict, keySignature: .gMajor),
        ])])
    }

    /// A session whose current note is F#4.
    func onFSharp() -> Bench {
        for seed: UInt64 in 1...50 {
            var bench = Bench(MasteryEngine(curriculum: Self.gMajor()), seed: seed)
            _ = bench.start()
            for _ in 0..<12 {
                if bench.expected == [Self.fs4] { return bench }
                _ = bench.playScreen()
                _ = bench.next()
            }
        }
        fatalError("F#4 never came up")
    }

    @Test func screensCarryTheKeySignature() {
        var engine = MasteryEngine(curriculum: Self.gMajor())
        var rng = SeededRandom(seed: 1)
        for _ in 0..<20 {
            #expect(engine.pickScreen(using: &rng).item.keySignature == .gMajor)
        }
    }

    @Test func fSharpIsRight() {
        var bench = onFSharp()
        #expect(bench.press(Self.fs4) == [.correct(note: 0)])
    }

    @Test func fNaturalOnAnFSharpGetsTheBlackKeyHint() {
        var bench = onFSharp()
        let cues = bench.press(Pitch(.f, 4))
        #expect(cues == [.wobble(note: 0), .say(.sharpHint(.fSharp))])
        #expect(bench.session.keyboardHint == [Self.fs4], "the keyboard picture shows the black key")
        #expect(bench.session.phase == .waiting, "it's a wrong key: one step up the ladder")
        _ = bench.press(Self.fs4)
        let note = bench.session.summary.screens.last!.notes[0]
        #expect(!note.firstTry && note.wrongPresses == 1)
    }

    @Test func fNaturalAgainClimbsTheLadderWithTheSameHint() {
        var bench = onFSharp()
        _ = bench.press(Pitch(.f, 4))
        let second = bench.press(Pitch(.f, 4))
        #expect(second == [.wobble(note: 0), .playPitches([Self.fs4]), .say(.sharpHint(.fSharp))])
    }

    @Test func otherWrongKeysOnFSharpAreOrdinary() {
        var bench = onFSharp()
        let cues = bench.press(Pitch(.a, 4))
        #expect(cues.first == .wobble(note: 0) && !speeches(cues).contains(.sharpHint(.fSharp)))
        #expect(!speeches(bench.press(Pitch(.f, 5))).contains(.sharpHint(.fSharp)), "F in another octave isn't the next-door natural")
    }

    @Test func aNewFSharpIsIntroducedAsFSharp() {
        var bench = Bench(MasteryEngine(curriculum: Self.gMajor(newFSharp: true)), seed: 1)
        var cues = bench.start()
        for _ in 0..<10 where bench.session.introNote == nil {
            _ = bench.playScreen()
            cues = bench.next()
        }
        #expect(bench.session.introNote?.pitch == Self.fs4)
        #expect(cues.contains(.say(.meetNote(.fSharp))))
        #expect(bench.session.keyboardHint == [Self.fs4])
    }
}
