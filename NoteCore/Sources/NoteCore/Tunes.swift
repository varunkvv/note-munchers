/// Bits of real tunes he may know, all in G position so they fit either clef (G = the
/// right hand's thumb, the left hand's little finger). Public domain children's tunes,
/// first phrases only, dotted rhythms written as plain quarters (the app has no dotted
/// quarters). Drill screens take the first bar or two of one now and then
/// (plans/2026-10-16-drills-and-habit.md), and the familiar tunes shelf in song time is
/// meant to share this list (plans/2026-10-16-progress-and-tunes.md section 4).
public struct Tune: Hashable, Sendable {
    /// One note: how far above G (0 = G, 4 = D) and how long.
    public struct Note: Hashable, Sendable {
        public let degree: Int
        public let value: NoteValue
    }

    /// Parent-facing ("Hot cross buns").
    public let name: String
    public let meter: Meter
    public let bars: [[Note]]

    /// `melody`: letters G-D with an optional value ("G/h"), bars split by "|".
    init(_ name: String, _ meter: Meter, _ melody: String) {
        self.name = name
        self.meter = meter
        bars = melody.split(separator: "|").map { bar in
            bar.split(separator: " ").map { token in
                let parts = token.split(separator: "/")
                let degree = ["G": 0, "A": 1, "B": 2, "C": 3, "D": 4][String(parts[0])]!
                let value = parts.count > 1 ? NoteValue(rawValue: String(parts[1]))! : .quarter
                return Note(degree: degree, value: value)
            }
        }
        precondition(bars.allSatisfy { $0.reduce(0) { $0 + $1.value.beats } == Double(meter.beats) }, "\(name) has a bar that doesn't add up")
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

    public static let all: [Tune] = [
        Tune("Hot cross buns", .fourFour, "B A G/h | B A G/h"),
        Tune("Mary had a little lamb", .fourFour, "B A G A | B B B/h"),
        Tune("Ode to joy", .fourFour, "B B C D | D C B A | G G A B | B A A/h"),
        Tune("Au clair de la lune", .fourFour, "G G G A | B/h A/h | G B A A | G/w"),
    ]
}
