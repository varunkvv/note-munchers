/// Song time never leaves him stuck on a note (plans/2026-10-16-progress-and-tunes.md,
/// section 3: "dont let him get stuck there - they lose patience").
///
/// - 2 wrong keys, or 8s with no key, lights the key on the keyboard picture (the right
///   letter in the wrong octave lights it at once)
/// - still stuck after that, 2 more wrong keys or 10s more with no key: the band plays
///   the note for him with the backing, it counts as played and the song moves on
///
/// No voice, no fuss. Times are seconds on the app's clock. One of these per note: call
/// `next` when the song moves on.
public struct BandHelp: Hashable, Sendable {
    public enum Step: Hashable, Sendable {
        /// nothing yet
        case wait
        /// light the key
        case light
        /// the band plays it for him
        case play
    }

    public static let lightAfterWrongs = 2
    public static let lightAfter = 8.0
    public static let playAfterWrongs = 2
    public static let playAfter = 10.0

    /// The key is lit on the keyboard picture.
    public private(set) var isLit = false
    /// Wrong keys since the note came up, then since it lit.
    public private(set) var wrongs = 0
    private var lastActivity: Double

    public init(at time: Double) {
        lastActivity = time
    }

    /// The next note is up (he played it, or the band did).
    public mutating func next(at time: Double) {
        self = BandHelp(at: time)
    }

    /// A wrong key. `almost`: the right letter in another octave, which lights it at once.
    public mutating func wrong(at time: Double, almost: Bool = false) -> Step {
        lastActivity = time
        wrongs += 1
        guard isLit else {
            guard almost || wrongs >= Self.lightAfterWrongs else { return .wait }
            isLit = true
            wrongs = 0
            return .light
        }
        return wrongs >= Self.playAfterWrongs ? .play : .wait
    }

    /// A key that isn't judged yet (the first key of two at once), or a pause that isn't
    /// him being stuck (the play button, the piano gone): the clock starts again.
    public mutating func touch(at time: Double) {
        lastActivity = time
    }

    /// When to `tick` if no key comes before it.
    public var deadline: Double { lastActivity + (isLit ? Self.playAfter : Self.lightAfter) }

    /// No key since the last call: lights the key at 8s, then the band plays it 10s later.
    public mutating func tick(at time: Double) -> Step {
        guard time >= deadline else { return .wait }
        guard isLit else {
            isLit = true
            wrongs = 0
            lastActivity = time
            return .light
        }
        return .play
    }
}
