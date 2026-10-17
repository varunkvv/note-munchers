/// Real tunes he may know, all in G position so they fit either clef (G = the right
/// hand's thumb, the left hand's little finger). Public domain children's tunes, checked
/// against printed sources (artifacts/free-play/composer.md, "familiar tunes"), with
/// dotted quarter + eighth written as two quarters and eighths merged into quarters (the
/// app has no dotted quarters, and no eighths before level 5).
///
/// One list for two things: drill screens take the first bar or two of a tune now and
/// then (plans/2026-10-16-drills-and-habit.md), and song time plays a whole one as a
/// "mystery song" now and then (plans/2026-10-16-progress-and-tunes.md section 4,
/// FamiliarTunes.swift). The tunes are curated: they skip the song generator's hard
/// rules (Jingle Bells has more than 4 of one key in a row).
public struct Tune: Hashable, Sendable {
    /// One note: how far above G (0 = G, 4 = D) and how long.
    public struct Note: Hashable, Sendable {
        public let degree: Int
        public let value: NoteValue
    }

    /// Its real name, as the end card shows it ("Mary Had a Little Lamb").
    public let name: String
    /// The first level it fits: its moves (a skip of a 4th or 5th is level 2) and how
    /// long it is.
    public let level: Int
    public let meter: Meter
    public let bars: [[Note]]
    /// G major chords, one or two a bar (the second from beat 3), for song time's backing.
    public let chords: [[Chord]]

    /// `melody`: letters G-D with an optional value ("G/h"), bars split by "|". `chords`:
    /// "I | V7 | I V | I", one entry a bar.
    init(_ name: String, level: Int, _ meter: Meter, _ melody: String, chords: String) {
        self.name = name
        self.level = level
        self.meter = meter
        bars = melody.split(separator: "|").map { bar in
            bar.split(separator: " ").map { token in
                let parts = token.split(separator: "/")
                let degree = ["G": 0, "A": 1, "B": 2, "C": 3, "D": 4][String(parts[0])]!
                let value = parts.count > 1 ? NoteValue(rawValue: String(parts[1]))! : .quarter
                return Note(degree: degree, value: value)
            }
        }
        self.chords = chords.split(separator: "|").map { bar in bar.split(separator: " ").map { Chord(rawValue: String($0))! } }
        precondition(bars.allSatisfy { $0.reduce(0) { $0 + $1.value.beats } == Double(meter.beats) }, "\(name) has a bar that doesn't add up")
        precondition(self.chords.count == bars.count && self.chords.allSatisfy { (1...2).contains($0.count) }, "\(name): one or two chords a bar")
    }

    /// The keys in G position on `clef`, bar by bar.
    public func keys(_ clef: Clef) -> [[NoteKey]] {
        let g = HandPosition.g(clef).low
        let letters = [Letter.g, .a, .b, .c, .d]
        return bars.map { bar in
            bar.map { note in
                let octave = g.octave + (note.degree >= 3 ? 1 : 0) // C and D are above the next C
                return NoteKey(clef, Pitch(letters[note.degree], octave))
            }
        }
    }

    /// Every key it uses on `clef`.
    public func allKeys(_ clef: Clef) -> Set<NoteKey> { Set(keys(clef).joined()) }

    public static let all: [Tune] = [
        // the common version: B A G | B A G | G G G G A A A A (eighths) | B A G. "one a
        // penny, two a penny" is a bar of quarters each
        Tune("Hot Cross Buns", level: 1, .fourFour, "B A G/h | B A G/h | G G G G | A A A A | B A G/h",
             chords: "I | I | I | V | I"),
        Tune("Mary Had a Little Lamb", level: 1, .fourFour, "B A G A | B B B/h | A A A/h | B D D/h | B A G A | B B B B | A A B A | G/w",
             chords: "I | I | V | I | I | I | V | I"),
        // the A section and its answer (the middle drops below G position). the dotted
        // quarter + eighth before each phrase end is two quarters
        Tune("Ode to Joy", level: 1, .fourFour, "B B C D | D C B A | G G A B | B A A/h | B B C D | D C B A | G G A B | A G G/h",
             chords: "I | V7 | I | I V | I | V7 | I | V7 I"),
        // the first phrase
        Tune("Au Clair de la Lune", level: 1, .fourFour, "G G G A | B/h A/h | G B A A | G/w",
             chords: "I | I V | I V | I"),
        // Hänschen klein / Suzuki's Lightly Row, A section with its second ending, 2/4
        // eighths and quarters written as 4/4 quarters and halves
        Tune("Lightly Row", level: 2, .fourFour, "D B B/h | C A A/h | G A B C | D D D/h | D B B/h | C A A/h | G B D D | G/w",
             chords: "I | V7 | I | I | I | V7 | I V | I"),
        // the chorus. "C. D" and "F. F" are two quarters, "E E" eighths are one quarter
        Tune("Jingle Bells", level: 2, .fourFour,
             "B B B/h | B B B/h | B D G A | B/w | C C C C | C B B B | B A A B | A/h D/h | B B B/h | B B B/h | B D G A | B/w | C C C C | C B B B | D D C A | G/w",
             chords: "I | I | I | I | IV | IV I | I V | V | I | I | I | I | IV | IV I | V7 | I"),
    ]
}
