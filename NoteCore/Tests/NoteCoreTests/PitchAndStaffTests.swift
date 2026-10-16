import Testing
@testable import NoteCore

@Suite struct PitchTests {
    @Test func middleCIsMidi60() {
        #expect(Pitch.middleC.midi == 60)
        #expect(Pitch(.c, 4).name == "C4")
        #expect(Pitch(.a, 4).midi == 69)
        #expect(Pitch(.c, 2).midi == 36)
        #expect(Pitch(.c, 6).midi == 84)
    }

    @Test func namesRoundTripForEveryKey() {
        for midi in 21...108 {
            let pitch = Pitch(midi: midi)
            #expect(Pitch(pitch.name) == pitch, "\(pitch.name)")
        }
    }

    @Test func blackKeysUseSharps() {
        #expect(Pitch(midi: 61).name == "C#4")
        #expect(Pitch(midi: 61).letter == nil)
        #expect(Pitch(midi: 61).naturalLetter == .c)
        #expect(Pitch("Bb3") == Pitch(midi: 58))
        #expect(Pitch(midi: 58).name == "A#3")
    }

    @Test func badNamesAreNil() {
        #expect(Pitch("H4") == nil)
        #expect(Pitch("C") == nil)
        #expect(Pitch("") == nil)
        #expect(Pitch("C99") == nil)
    }

    @Test func octaveAndLetter() {
        #expect(Pitch(midi: 59).name == "B3")
        #expect(Pitch(midi: 59).octave == 3)
        #expect(Pitch(.b, 3).letter == .b)
        #expect(Pitch(.c, 5).isSamePitchClass(as: .middleC))
        #expect(!Pitch(.d, 4).isSamePitchClass(as: .middleC))
    }
}

@Suite struct NoteEventTests {
    @Test func midiBytes() {
        #expect(NoteEvent(status: 0x90, data1: 60, data2: 100, at: 1) == .on(.middleC, velocity: 100, at: 1))
        #expect(NoteEvent(status: 0x93, data1: 60, data2: 100, at: 1)?.kind == .on, "any channel")
        #expect(NoteEvent(status: 0x80, data1: 60, data2: 40, at: 2) == .off(.middleC, at: 2))
        #expect(NoteEvent(status: 0x90, data1: 60, data2: 0, at: 3) == .off(.middleC, at: 3), "velocity 0 is note-off")
        #expect(NoteEvent(status: 0xB0, data1: 64, data2: 127, at: 4) == nil, "sustain pedal is ignored")
    }

    @Test func umpWords() {
        #expect(NoteEvent(umpWord: 0x2090_3C64, at: 1) == .on(.middleC, velocity: 100, at: 1))
        #expect(NoteEvent(umpWord: 0x2090_3C00, at: 1)?.kind == .off)
        #expect(NoteEvent(umpWord: 0x4090_3C00, at: 1) == nil, "MIDI 2.0 words are not parsed")
    }

    @Test func umpPacketWalksByMessageSize() {
        // note on C4, a 2-word sysex whose second word looks like a note on (0x2...),
        // active sensing (type 1), then note off C4
        let words: [UInt32] = [0x2090_3C64, 0x3002_7E7F, 0x2090_4040, 0x10FE_0000, 0x2080_3C00]
        let events = NoteEvent.events(inUMPWords: words, at: 2)
        #expect(events == [.on(.middleC, velocity: 100, at: 2), .off(.middleC, at: 2)])
    }

    @Test func umpPacketWithTruncatedMessageStops() {
        // a 4-word message type with only one word left must not run past the end
        #expect(NoteEvent.events(inUMPWords: [0x2090_3C64, 0xF000_0000], at: 0).count == 1)
    }
}

@Suite struct StaffPositionTests {
    func step(_ name: String, _ clef: Clef) -> Int {
        clef.position(of: Pitch(name)!).step
    }

    @Test func trebleLines() {
        #expect(["E4", "G4", "B4", "D5", "F5"].map { step($0, .treble) } == [0, 2, 4, 6, 8])
        #expect(["F4", "A4", "C5", "E5"].map { step($0, .treble) } == [1, 3, 5, 7])
    }

    @Test func bassLines() {
        #expect(["G2", "B2", "D3", "F3", "A3"].map { step($0, .bass) } == [0, 2, 4, 6, 8])
        #expect(["A2", "C3", "E3", "G3"].map { step($0, .bass) } == [1, 3, 5, 7])
    }

    @Test func middleCIsOneLedgerLineInBothClefs() {
        let treble = Clef.treble.position(of: .middleC)
        let bass = Clef.bass.position(of: .middleC)
        #expect(treble.step == -2)
        #expect(treble.ledgerLineSteps == [-2])
        #expect(bass.step == 10)
        #expect(bass.ledgerLineSteps == [10])
        #expect(treble.isOnLine && bass.isOnLine)
    }

    /// Expected step of every pitch the curriculum uses, worked out by hand from the
    /// bottom line (treble E4, bass G2), one step per letter.
    static let trebleSteps: [String: Int] = [
        "C2": -16, "D2": -15, "E2": -14, "F2": -13, "G2": -12, "A2": -11, "B2": -10,
        "C3": -9, "D3": -8, "E3": -7, "F3": -6, "G3": -5, "A3": -4, "B3": -3,
        "C4": -2, "D4": -1, "E4": 0, "F4": 1, "G4": 2, "A4": 3, "B4": 4,
        "C5": 5, "D5": 6, "E5": 7, "F5": 8, "G5": 9, "A5": 10, "B5": 11, "C6": 12,
    ]

    @Test func everyCurriculumNoteInBothClefs() throws {
        let pitches = Set(Curriculum.standard.allKeys.map(\.pitch) + Self.trebleSteps.keys.map { Pitch($0)! })
        #expect(pitches.count >= 29)
        for pitch in pitches {
            let expectedTreble = try #require(Self.trebleSteps[pitch.name], "\(pitch.name) missing from table")
            #expect(Clef.treble.position(of: pitch).step == expectedTreble, "\(pitch.name) treble")
            // bass bottom line G2 is 12 steps below treble bottom line E4
            #expect(Clef.bass.position(of: pitch).step == expectedTreble + 12, "\(pitch.name) bass")
        }
    }

    @Test func ledgerCounts() {
        let treble: [String: Int] = [
            "D4": 0, "C4": 1, "B3": 1, "A3": 2, "G5": 0, "A5": 1, "B5": 1, "C6": 2, "E4": 0, "F5": 0,
        ]
        for (name, count) in treble {
            #expect(Clef.treble.position(of: Pitch(name)!).ledgerLineCount == count, "\(name) treble")
        }
        let bass: [String: Int] = [
            "B3": 0, "C4": 1, "D4": 1, "E4": 2, "F2": 0, "E2": 1, "D2": 1, "C2": 2, "G2": 0, "A3": 0,
        ]
        for (name, count) in bass {
            #expect(Clef.bass.position(of: Pitch(name)!).ledgerLineCount == count, "\(name) bass")
        }
        #expect(Clef.bass.position(of: Pitch("C2")!).ledgerLineSteps == [-2, -4])
        #expect(Clef.treble.position(of: Pitch("C6")!).ledgerLineSteps == [10, 12])
    }

    @Test func linesAndSpacesNearTheStaff() {
        #expect(!Clef.treble.position(of: Pitch("D4")!).isOnLine, "D4 hangs below the staff in a space")
        #expect(Clef.treble.position(of: Pitch("E4")!).isOnLine)
        #expect(Clef.treble.position(of: Pitch("E4")!).isInsideStaff)
        #expect(!Clef.treble.position(of: Pitch("D4")!).isInsideStaff)
    }

    @Test func stems() {
        #expect(Clef.treble.position(of: Pitch("G4")!).stemUp)
        #expect(!Clef.treble.position(of: Pitch("B4")!).stemUp, "middle line gets stem down")
        #expect(!Clef.treble.position(of: Pitch("D5")!).stemUp)
    }

    @Test func layouts() {
        #expect(StaffLayout.grand.contains(.bass) && StaffLayout.grand.contains(.treble))
        #expect(!StaffLayout.treble.contains(.bass))
    }
}
