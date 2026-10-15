/// How far the hints went on an item.
public enum HintLevel: Int, Comparable, Codable, Hashable, Sendable {
    case none
    /// one wrong key: the note wobbled
    case wobble
    /// two wrong keys: the app played the right pitch
    case playedPitch
    /// three or more: the keyboard picture lit up the key
    case keyboard

    public static func < (lhs: HintLevel, rhs: HintLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One finished item: what the session hands the mastery engine, and what the app
/// stores (with its own date) for the parent dashboard.
public struct AttemptResult: Hashable, Codable, Sendable {
    public var itemID: ItemID
    /// The unit he was in when he played it.
    public var unit: Int
    /// First time this item was shown, with the keyboard picture up from the start.
    /// Not counted in mastery stats.
    public var wasIntro: Bool
    /// Every key right on the first press. An "almost" (right letter, wrong octave in
    /// a lenient unit) doesn't count against him.
    public var firstTry: Bool
    public var wrongPresses: Int
    public var almostPresses: Int
    public var hints: HintLevel
    /// Seconds to find it, not counting time the piano was disconnected.
    /// Single notes and chords: prompt to the right key(s). Groups: per note, averaged.
    /// Rhythm items: prompt to the first right key (how fast he read it, not how long the line is).
    public var responseTime: Double
    /// nil when the item has no rhythm, or rhythm wasn't judged this time (a wrong key
    /// mid-line, or the piano dropped) - the timing isn't his in those cases.
    public var rhythm: RhythmResult?

    public init(
        itemID: ItemID, unit: Int, wasIntro: Bool = false, firstTry: Bool, wrongPresses: Int = 0,
        almostPresses: Int = 0, hints: HintLevel = .none, responseTime: Double, rhythm: RhythmResult? = nil
    ) {
        self.itemID = itemID
        self.unit = unit
        self.wasIntro = wasIntro
        self.firstTry = firstTry
        self.wrongPresses = wrongPresses
        self.almostPresses = almostPresses
        self.hints = hints
        self.responseTime = responseTime
        self.rhythm = rhythm
    }
}
