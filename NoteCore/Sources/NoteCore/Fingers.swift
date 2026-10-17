/// A finger number to show (plans/2026-10-16-drills-and-habit.md section 5, varun ok'd
/// it): 1 is the thumb, from the hand position the note is played in. On a drill
/// screen's first note (and a shift screen's first note in its new position), and on
/// the lit key of the hint picture. Never on every note, or he'd read numbers instead of
/// notes. It fades as the note becomes habit (scaffolding that fades: Wood, Bruner & Ross
/// 1976), and isn't there once it is.
public struct FingerMark: Hashable, Sendable {
    /// Which note of the screen (column).
    public let note: Int
    /// Which key: a column of two at once has a mark for each.
    public let pitch: Pitch
    public let clef: Clef
    /// 1 (thumb) to 5.
    public let finger: Int
    /// How strong to draw it, 0...1: 1 - how close the note is to habit.
    public let strength: Double
}

extension PracticeSession {
    /// Below this a finger number isn't drawn at all.
    static let fingerFloor = 0.2

    /// Finger numbers for the staff: the first note of a drill screen (the warm-up's run
    /// too), and on a shift screen the first note in the new position. None on intros
    /// (the letter is on the key there).
    public var fingerMarks: [FingerMark] {
        guard let item, drill != nil, !isIntro, positions.count == item.notes.count else { return [] }
        var columns = [0]
        // the hand moving on its own staff (not an echo's other hand)
        if let shift = positions.indices.dropFirst().first(where: { positions[$0] != positions[$0 - 1] && positions[$0].clef == positions[$0 - 1].clef }) {
            columns.append(shift)
        }
        return columns.flatMap { marks(note: $0) }
    }

    /// Finger numbers for the keys lit in the keyboard picture (a hint, a wrong octave):
    /// the current note's, in its hand position. None on intros.
    public var hintFingers: [FingerMark] {
        guard let item, !keyboardHint.isEmpty, !isIntro, item.notes.indices.contains(noteIndex) else { return [] }
        return marks(note: noteIndex).filter { keyboardHint.contains($0.pitch) }
    }

    private func marks(note index: Int) -> [FingerMark] {
        guard let item, positions.indices.contains(index) else { return [] }
        let column = item.notes[index]
        let position = positions[index]
        return column.pitches.compactMap { pitch in
            guard let finger = position.finger(pitch) else { return nil }
            let strength = 1 - engine.habit(NoteKey(column.clef, pitch)).fraction
            guard strength >= Self.fingerFloor else { return nil }
            return FingerMark(note: index, pitch: pitch, clef: column.clef, finger: finger, strength: strength)
        }
    }
}
