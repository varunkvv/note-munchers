/// Every tunable number in NoteCore, with the plan's defaults. Codable so the app
/// can store parent changes (session length) and tuning after the first week.
public struct NoteCoreConfig: Hashable, Codable, Sendable {
    // MARK: mastery

    /// How many recent attempts per item are kept and judged.
    public var solidWindow = 8
    /// The newest item is solid when this many of the last `solidWindow` were right first try...
    public var solidRequired = 7
    /// ...and the median response time of those attempts is under this.
    public var solidMedianResponse: Double = 4

    /// Fast track: the newest item right first try this many times in a row...
    public var fastTrackCount = 5
    /// ...each one under this many seconds, counts as solid right away.
    public var fastTrackResponse: Double = 2

    /// Leitner boxes run 1...boxCount. New items start in box 1.
    public var boxCount = 5
    /// The next item unlocks only when no item in the practice pool is below this box.
    public var gateMinBox = 3

    /// Share of picks that go to the newest item (or batch). The rest are weighted
    /// toward low boxes.
    public var newestShare = 0.4
    /// The picker never shows the same item more than this many times in a row.
    public var maxRepeats = 2

    // MARK: rhythm mastery

    /// A rhythm item's rhythm is solid when this many of its last `solidWindow`
    /// judged runs had every note ok. Looser than pitch on purpose.
    public var rhythmSolidRequired = 6

    // MARK: judging

    /// Note-ons this close together count as one chord.
    public var chordWindow: Double = 0.15
    /// After a key is judged, other note-ons this soon after are ignored
    /// (accidental two-key press).
    public var extraKeyIgnoreWindow: Double = 0.15

    /// A gap passes when it's between these multiples of the written length at his beat.
    public var rhythmMinRatio = 0.6
    public var rhythmMaxRatio = 1.6

    // MARK: session

    /// Active seconds before a session ends (checked between items, never mid-item).
    public var sessionMaxDuration: Double = 300
    /// Items before a session ends.
    public var sessionMaxItems = 20
    /// Chance of a praise phrase after a right answer. Praise isn't every time.
    public var praiseChance = 0.35
    /// Beat (seconds) used when the app plays a new rhythm line to him first.
    public var demoBeat: Double = 0.75

    public init() {}

    public static let `default` = NoteCoreConfig()
}

// see LenientDecoding.swift
extension NoteCoreConfig {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NoteCoreConfig()
        solidWindow = try c.value(.solidWindow, or: d.solidWindow)
        solidRequired = try c.value(.solidRequired, or: d.solidRequired)
        solidMedianResponse = try c.value(.solidMedianResponse, or: d.solidMedianResponse)
        fastTrackCount = try c.value(.fastTrackCount, or: d.fastTrackCount)
        fastTrackResponse = try c.value(.fastTrackResponse, or: d.fastTrackResponse)
        boxCount = try c.value(.boxCount, or: d.boxCount)
        gateMinBox = try c.value(.gateMinBox, or: d.gateMinBox)
        newestShare = try c.value(.newestShare, or: d.newestShare)
        maxRepeats = try c.value(.maxRepeats, or: d.maxRepeats)
        rhythmSolidRequired = try c.value(.rhythmSolidRequired, or: d.rhythmSolidRequired)
        chordWindow = try c.value(.chordWindow, or: d.chordWindow)
        extraKeyIgnoreWindow = try c.value(.extraKeyIgnoreWindow, or: d.extraKeyIgnoreWindow)
        rhythmMinRatio = try c.value(.rhythmMinRatio, or: d.rhythmMinRatio)
        rhythmMaxRatio = try c.value(.rhythmMaxRatio, or: d.rhythmMaxRatio)
        sessionMaxDuration = try c.value(.sessionMaxDuration, or: d.sessionMaxDuration)
        sessionMaxItems = try c.value(.sessionMaxItems, or: d.sessionMaxItems)
        praiseChance = try c.value(.praiseChance, or: d.praiseChance)
        demoBeat = try c.value(.demoBeat, or: d.demoBeat)
    }
}
