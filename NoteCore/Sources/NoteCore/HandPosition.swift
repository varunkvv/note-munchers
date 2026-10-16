/// Five keys under one hand, a five-finger position: five letters in a row on one clef
/// (treble = right hand, bass = left hand). Black keys count as the letter they're spelled
/// on, so F#4 sits where F4 would.
///
/// A screen's notes on one staff stay inside one position, so his hand stays put while he
/// reads (a piano teacher's review: level 3 moved the hand around inside a screen).
/// Finger numbers come from it: the right hand counts 1-5 up from the lowest key, the left
/// hand 5-1 (the thumb on the highest key).
public struct HandPosition: Hashable, Codable, Sendable, CustomStringConvertible {
    public let clef: Clef
    /// The lowest key: the right hand's thumb, the left hand's little finger.
    public let low: Pitch

    public init(_ clef: Clef, low: Pitch) {
        self.clef = clef
        self.low = low
    }

    public func contains(_ pitch: Pitch) -> Bool {
        (0...4).contains(pitch.diatonicIndex - low.diatonicIndex)
    }

    public func contains(_ key: NoteKey) -> Bool { key.clef == clef && contains(key.pitch) }

    /// 1 = thumb. nil outside the position.
    public func finger(_ pitch: Pitch) -> Int? {
        guard contains(pitch) else { return nil }
        let up = pitch.diatonicIndex - low.diatonicIndex
        return clef == .treble ? up + 1 : 5 - up
    }

    /// "treble G4", "bass D3"
    public var description: String { "\(clef.rawValue) \(low.name)" }

    /// G position: right hand G4-D5, left hand G2-D3. Levels 1-2 and 4-5 never leave it.
    public static func g(_ clef: Clef) -> HandPosition {
        HandPosition(clef, low: clef == .treble ? Pitch(.g, 4) : Pitch(.g, 2))
    }

    /// D position (right hand D4-A4, left hand D3-A3, F# under finger 3), level 3's
    /// positions drill only.
    public static func d(_ clef: Clef) -> HandPosition {
        HandPosition(clef, low: clef == .treble ? Pitch(.d, 4) : Pitch(.d, 3))
    }

    /// The positions screens use, low to high. Every note of the curriculum is in one.
    /// Treble: middle C (C4-G4), G (G4-D5), C5-G5. Bass: G (G2-D3), C3-G3, and F#3-C4
    /// with the thumb on middle C.
    public static func standard(_ clef: Clef) -> [HandPosition] {
        switch clef {
        case .treble: [HandPosition(.treble, low: Pitch(.c, 4)), g(.treble), HandPosition(.treble, low: Pitch(.c, 5))]
        case .bass: [g(.bass), HandPosition(.bass, low: Pitch(.c, 3)), HandPosition(.bass, low: Pitch("F#3")!)]
        }
    }

    /// The standard position that holds every one of `keys` (G position first), or nil.
    public static func holding(_ keys: [NoteKey], on clef: Clef) -> HandPosition? {
        let mine = keys.filter { $0.clef == clef }
        let options = [g(clef)] + standard(clef) + [d(clef)]
        return options.first { position in mine.allSatisfy(position.contains) }
    }
}
