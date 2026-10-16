/// One note as he reads it: a clef and a key. Mastery is kept per note key, so treble
/// G4 and bass G2 are different notes, and so are treble C4 and bass C4 (ledger line
/// below vs ledger line above).
///
/// The id is `"treble:G4"`, `"bass:G2"`, `"treble:F#4"`. It's what stats, munchers and
/// muncher colours are stored under. A round-1 single-note item had the same id, so
/// those stats carry over.
public struct NoteKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let clef: Clef
    public let pitch: Pitch

    public init(_ clef: Clef, _ pitch: Pitch) {
        self.clef = clef
        self.pitch = pitch
    }

    /// Parses `"treble:G4"`. nil for anything else, including round-1 group, chord and
    /// rhythm item ids (`"treble:C4-D4"`, `"treble:C4+E4"`, `"treble:G4/q-G4/h"`).
    public init?(id: ItemID) {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let clef = Clef(rawValue: String(parts[0])),
              let pitch = Pitch(String(parts[1])), pitch.name == parts[1]
        else { return nil }
        self.init(clef, pitch)
    }

    public var id: ItemID { "\(clef.rawValue):\(pitch.name)" }

    public var position: StaffPosition { clef.position(of: pitch) }

    public var isOnLine: Bool { position.isOnLine }

    /// What the voice calls it. nil only for black keys other than F#.
    public var name: NoteName? { NoteName(pitch) }

    public var description: String { id }

    /// Treble before bass, then low to high.
    public static func < (lhs: NoteKey, rhs: NoteKey) -> Bool {
        lhs.clef != rhs.clef ? lhs.clef == .treble : lhs.pitch < rhs.pitch
    }
}
