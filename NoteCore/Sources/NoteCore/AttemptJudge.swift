/// What one press (or one chord) was, against the keys written for the current note.
public enum PitchVerdict: Hashable, Codable, Sendable {
    case correct
    /// Right letter(s), wrong octave, in a unit with the lenient octave policy.
    /// Doesn't count against him.
    case almost(played: [Pitch])
    case wrong(played: [Pitch])
}

/// Judges note-ons against the keys written for one column of an item.
///
/// - single key: the first note-on is judged right away. Other note-ons within
///   `extraKeyIgnoreWindow` are ignored, so an accidental two-key press counts once
/// - chord: note-ons are collected for `chordWindow` from the first one. Once the
///   exact written set is down it's correct right away. Otherwise it's judged when
///   the window closes - by the next note-on after the window, or by `closeWindow(at:)`
///   once `windowDeadline` has passed
///
/// Note-offs don't matter here. Times are seconds on the app's clock.
public struct AttemptJudge: Sendable {
    public private(set) var expected: [Pitch]
    public var octavePolicy: OctavePolicy
    public let chordWindow: Double
    public let extraKeyIgnoreWindow: Double

    private var collected: [Pitch] = []
    private var windowStart: Double?
    private var ignoreUntil = -Double.infinity

    public init(expected: [Pitch], octavePolicy: OctavePolicy, config: NoteCoreConfig = .default) {
        precondition(!expected.isEmpty)
        self.expected = expected.sorted()
        self.octavePolicy = octavePolicy
        chordWindow = config.chordWindow
        extraKeyIgnoreWindow = config.extraKeyIgnoreWindow
    }

    /// Moves on to the next column. Keeps the extra-key ignore window running, so a
    /// stray second key from the last press doesn't count against the next note.
    public mutating func expect(_ pitches: [Pitch]) {
        precondition(!pitches.isEmpty)
        expected = pitches.sorted()
        collected = []
        windowStart = nil
    }

    /// Drops a half-collected chord (e.g. the piano was unplugged mid-chord).
    public mutating func reset() {
        collected = []
        windowStart = nil
        ignoreUntil = -.infinity
    }

    private var isChord: Bool { expected.count > 1 }

    /// When an open chord window closes. The app should call `closeWindow(at:)` then.
    public var windowDeadline: Double? { windowStart.map { $0 + chordWindow } }

    /// Judges an open chord window if it has closed by `time`. nil otherwise.
    public mutating func closeWindow(at time: Double) -> PitchVerdict? {
        guard let deadline = windowDeadline, time >= deadline else { return nil }
        return finish(at: deadline)
    }

    /// Judges a key going down. nil while a chord is still collecting or the key was
    /// ignored. If a chord window had already closed by `time`, that window's verdict
    /// is returned and this key starts a new window (a single key can't complete a chord).
    public mutating func noteOn(_ pitch: Pitch, at time: Double) -> PitchVerdict? {
        let closed = closeWindow(at: time)
        if time < ignoreUntil {
            return closed
        }
        if !isChord {
            ignoreUntil = time + extraKeyIgnoreWindow
            return judge([pitch])
        }
        if windowStart == nil {
            windowStart = time
        }
        if !collected.contains(pitch) {
            collected.append(pitch)
        }
        if closed == nil, collected.sorted() == expected {
            return finish(at: time)
        }
        return closed
    }

    private mutating func finish(at time: Double) -> PitchVerdict {
        let played = collected.sorted()
        collected = []
        windowStart = nil
        ignoreUntil = time + extraKeyIgnoreWindow
        return judge(played)
    }

    private func judge(_ played: [Pitch]) -> PitchVerdict {
        if played == expected {
            return .correct
        }
        if octavePolicy == .lenient, isOctaveShift(played) {
            return .almost(played: played)
        }
        return .wrong(played: played)
    }

    /// Same shape, moved by whole octaves.
    private func isOctaveShift(_ played: [Pitch]) -> Bool {
        guard played.count == expected.count else { return false }
        let shifts = Set(zip(played, expected).map { $0.midi - $1.midi })
        guard shifts.count == 1, let shift = shifts.first else { return false }
        return shift != 0 && shift.isMultiple(of: 12)
    }
}
