import Testing
@testable import NoteCore

@Suite struct AttemptJudgeTests {
    let c4 = Pitch(.c, 4), d4 = Pitch(.d, 4), e4 = Pitch(.e, 4), g4 = Pitch(.g, 4), c5 = Pitch(.c, 5)

    @Test func singleNoteRightAndWrong() {
        var judge = AttemptJudge(expected: [c4], octavePolicy: .strict)
        #expect(judge.noteOn(d4, at: 0) == .wrong(played: [d4]))
        #expect(judge.noteOn(c4, at: 1) == .correct)
    }

    @Test func octavePolicy() {
        var lenient = AttemptJudge(expected: [c4], octavePolicy: .lenient)
        #expect(lenient.noteOn(c5, at: 0) == .almost(played: [c5]))
        var strict = AttemptJudge(expected: [c4], octavePolicy: .strict)
        #expect(strict.noteOn(c5, at: 0) == .wrong(played: [c5]))
        var other = AttemptJudge(expected: [c4], octavePolicy: .lenient)
        #expect(other.noteOn(Pitch(midi: 61), at: 0) == .wrong(played: [Pitch(midi: 61)]), "C#4 is not a C")
    }

    @Test func twoKeyPressOnSingleNoteJudgesTheFirst() {
        var judge = AttemptJudge(expected: [c4], octavePolicy: .strict)
        #expect(judge.noteOn(c4, at: 1.0) == .correct)
        #expect(judge.noteOn(d4, at: 1.08) == nil, "second key inside 150ms is ignored")

        var wrongFirst = AttemptJudge(expected: [c4], octavePolicy: .strict)
        #expect(wrongFirst.noteOn(d4, at: 1.0) == .wrong(played: [d4]))
        #expect(wrongFirst.noteOn(c4, at: 1.05) == nil, "the first key is what counts, even if the second was right")
        #expect(wrongFirst.noteOn(c4, at: 1.2) == .correct, "a press after the window counts")
    }

    @Test func ignoreWindowCarriesIntoTheNextNote() {
        var judge = AttemptJudge(expected: [c4], octavePolicy: .strict)
        #expect(judge.noteOn(c4, at: 0) == .correct)
        judge.expect([d4])
        #expect(judge.noteOn(e4, at: 0.05) == nil, "stray key from the last press doesn't count against the next note")
        #expect(judge.noteOn(d4, at: 0.5) == .correct)
    }

    @Test func chordInsideWindowIsCorrectRightAway() {
        var judge = AttemptJudge(expected: [c4, e4, g4], octavePolicy: .strict)
        #expect(judge.noteOn(e4, at: 2.00) == nil)
        #expect(abs(judge.windowDeadline! - 2.15) < 1e-9)
        #expect(judge.noteOn(c4, at: 2.04) == nil)
        #expect(judge.noteOn(g4, at: 2.09) == .correct, "no need to wait for the window once the set is down")
        #expect(judge.windowDeadline == nil)
    }

    @Test func chordSplitBeyondWindowIsNotCorrect() {
        var judge = AttemptJudge(expected: [c4, e4], octavePolicy: .strict)
        #expect(judge.noteOn(c4, at: 0) == nil)
        #expect(judge.closeWindow(at: 0.1) == nil, "window still open")
        #expect(judge.closeWindow(at: 0.15) == .wrong(played: [c4]))
        // the late key, past the ignore window, starts a fresh chord rather than completing the old one
        #expect(judge.noteOn(e4, at: 0.4) == nil)
        #expect(judge.closeWindow(at: 0.6) == .wrong(played: [e4]))
    }

    @Test func lateNoteClosesTheOpenWindow() {
        var judge = AttemptJudge(expected: [c4, e4], octavePolicy: .strict)
        #expect(judge.noteOn(c4, at: 0) == nil)
        #expect(judge.noteOn(e4, at: 0.5) == .wrong(played: [c4]), "no tick came, the next key closes the window")
    }

    @Test func chordWithAnExtraKeyIsWrong() {
        var judge = AttemptJudge(expected: [c4, e4], octavePolicy: .strict)
        _ = judge.noteOn(c4, at: 0)
        _ = judge.noteOn(d4, at: 0.02)
        #expect(judge.noteOn(e4, at: 0.04) == nil, "set isn't exact, wait for the window")
        #expect(judge.closeWindow(at: 0.2) == .wrong(played: [c4, d4, e4]))
    }

    @Test func chordOctaveShiftIsAlmostOnlyWhenLenient() {
        var lenient = AttemptJudge(expected: [c4, e4], octavePolicy: .lenient)
        _ = lenient.noteOn(c5, at: 0)
        _ = lenient.noteOn(Pitch(.e, 5), at: 0.01)
        #expect(lenient.closeWindow(at: 0.2) == .almost(played: [c5, Pitch(.e, 5)]))
    }

    @Test func resetDropsAHalfCollectedChord() {
        var judge = AttemptJudge(expected: [c4, e4], octavePolicy: .strict)
        _ = judge.noteOn(c4, at: 0)
        judge.reset()
        #expect(judge.windowDeadline == nil)
        #expect(judge.closeWindow(at: 1) == nil)
    }
}
