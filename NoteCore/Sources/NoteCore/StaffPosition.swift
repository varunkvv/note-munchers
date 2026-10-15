public enum Clef: String, CaseIterable, Codable, Hashable, Sendable {
    case treble, bass

    /// The pitch on the bottom line: E4 for treble, G2 for bass.
    public var bottomLine: Pitch {
        switch self {
        case .treble: Pitch(.e, 4)
        case .bass: Pitch(.g, 2)
        }
    }

    public func position(of pitch: Pitch) -> StaffPosition {
        StaffPosition(pitch: pitch, clef: self)
    }
}

/// Which staves the screen shows for a unit.
public enum StaffLayout: String, CaseIterable, Codable, Hashable, Sendable {
    case treble, bass, grand

    public func contains(_ clef: Clef) -> Bool {
        switch self {
        case .treble: clef == .treble
        case .bass: clef == .bass
        case .grand: true
        }
    }
}

/// Where a pitch sits on a five-line staff.
///
/// `step` counts lines and spaces up from the bottom line: 0 is the bottom line,
/// 1 the first space, 2 the second line ... 8 the top line. Negative is below the
/// staff, above 8 is above it. Even steps are lines, odd steps are spaces.
///
/// Black keys sit on their white key's step (sharp spelling). Drawing the sharp
/// sign is out of scope for now.
public struct StaffPosition: Hashable, Codable, Sendable {
    public static let bottomLineStep = 0
    public static let middleLineStep = 4
    public static let topLineStep = 8

    public let step: Int

    public init(step: Int) {
        self.step = step
    }

    public init(pitch: Pitch, clef: Clef) {
        self.init(step: pitch.diatonicIndex - clef.bottomLine.diatonicIndex)
    }

    public var isOnLine: Bool { step.isMultiple(of: 2) }

    public var isInsideStaff: Bool { (Self.bottomLineStep...Self.topLineStep).contains(step) }

    /// Steps where short ledger lines are drawn, nearest the staff first.
    /// Empty when the note is inside the staff or in the space right next to it.
    public var ledgerLineSteps: [Int] {
        if step <= -2 {
            return Array(stride(from: -2, through: step, by: -2))
        }
        if step >= Self.topLineStep + 2 {
            return Array(stride(from: Self.topLineStep + 2, through: step, by: 2))
        }
        return []
    }

    public var ledgerLineCount: Int { ledgerLineSteps.count }

    /// Single-note stem rule: notes below the middle line get stems up.
    public var stemUp: Bool { step < Self.middleLineStep }
}
