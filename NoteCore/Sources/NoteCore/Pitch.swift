/// A white-key letter name. Sharps and flats are out of scope for the curriculum,
/// but black keys still come in over MIDI, so `Pitch` can represent them.
public enum Letter: String, CaseIterable, Codable, Hashable, Sendable {
    case c = "C", d = "D", e = "E", f = "F", g = "G", a = "A", b = "B"

    /// 0 for C up to 6 for B. Used for staff math (one step per letter).
    public var index: Int {
        switch self {
        case .c: 0
        case .d: 1
        case .e: 2
        case .f: 3
        case .g: 4
        case .a: 5
        case .b: 6
        }
    }

    /// Semitones above C.
    public var semitone: Int {
        switch self {
        case .c: 0
        case .d: 2
        case .e: 4
        case .f: 5
        case .g: 7
        case .a: 9
        case .b: 11
        }
    }

    /// "C", "D" ... what the voice says after a right key.
    public var name: String { rawValue }
}

/// A piano key, stored as its MIDI note number. Octaves use scientific pitch
/// notation: middle C is C4 = MIDI 60.
public struct Pitch: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let midi: Int

    public init(midi: Int) {
        precondition((0...127).contains(midi), "MIDI note \(midi) out of range")
        self.midi = midi
    }

    /// A white key, e.g. `Pitch(.c, 4)` is middle C.
    public init(_ letter: Letter, _ octave: Int) {
        self.init(midi: (octave + 1) * 12 + letter.semitone)
    }

    /// Parses names like "C4", "G2", "F#3", "Bb5". Returns nil for anything else.
    public init?(_ name: String) {
        var chars = Substring(name)
        guard let first = chars.first, let letter = Letter(rawValue: first.uppercased()) else { return nil }
        chars = chars.dropFirst()
        var shift = 0
        if chars.first == "#" { shift = 1; chars = chars.dropFirst() }
        else if chars.first == "b" { shift = -1; chars = chars.dropFirst() }
        guard let octave = Int(chars) else { return nil }
        let midi = (octave + 1) * 12 + letter.semitone + shift
        guard (0...127).contains(midi) else { return nil }
        self.init(midi: midi)
    }

    public static let middleC = Pitch(.c, 4)

    /// 0 = C ... 11 = B. Same for every octave.
    public var pitchClass: Int { midi % 12 }

    /// Scientific octave number. C4 is middle C. Black keys take the octave of the
    /// white key below them.
    public var octave: Int { midi / 12 - 1 }

    /// The letter for a white key, nil for a black key.
    public var letter: Letter? { Letter.allCases.first { $0.semitone == pitchClass } }

    public var isWhiteKey: Bool { letter != nil }

    /// The white key at or just below this pitch (C# -> C). Black keys are spelled as sharps.
    public var naturalLetter: Letter {
        letter ?? Letter.allCases.last { $0.semitone < pitchClass }!
    }

    /// "C4", "F#3". Sharp spelling for black keys.
    public var name: String {
        "\(naturalLetter.name)\(isWhiteKey ? "" : "#")\(octave)"
    }

    public var description: String { name }

    /// Counts letters, not semitones: C4 = 28, D4 = 29 ... One per staff line or space.
    /// Black keys count as the white key below them.
    public var diatonicIndex: Int { octave * 7 + naturalLetter.index }

    /// True when both are the same letter (or black key) in any octave.
    public func isSamePitchClass(as other: Pitch) -> Bool { pitchClass == other.pitchClass }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }
}
