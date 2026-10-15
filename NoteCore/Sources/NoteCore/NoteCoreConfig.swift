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
    /// toward low boxes. Small steps, aiming for ~80% first-try success (rosenshine).
    public var newestShare = 0.25
    /// The picker never shows the same item more than this many times in a row.
    public var maxRepeats = 2

    /// Easing: when this many of his last `easingWindow` attempts in a session weren't
    /// right first try (a wrong key or a hint)...
    public var easingTrigger = 3
    public var easingWindow = 5
    /// ...the next this many items are his strongest ones.
    public var easingItems = 2

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
    /// A session opens with up to this many of his strongest items before anything new
    /// or weak (start with success).
    public var warmUpCount = 3
    /// When time or the item count is up, the session ends after his next first-try
    /// success. At most this many extra (easy) items, then it ends anyway.
    public var maxExtraItems = 3
    /// No key for this many seconds counts as one step up the hint ladder (stuck).
    /// Only climbs to the keyboard picture, never repeats on a clock after that.
    public var stuckAfter: Double = 15
    /// Chance of "you looked carefully" after a first-try success. Not every time.
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
        easingTrigger = try c.value(.easingTrigger, or: d.easingTrigger)
        easingWindow = try c.value(.easingWindow, or: d.easingWindow)
        easingItems = try c.value(.easingItems, or: d.easingItems)
        rhythmSolidRequired = try c.value(.rhythmSolidRequired, or: d.rhythmSolidRequired)
        chordWindow = try c.value(.chordWindow, or: d.chordWindow)
        extraKeyIgnoreWindow = try c.value(.extraKeyIgnoreWindow, or: d.extraKeyIgnoreWindow)
        rhythmMinRatio = try c.value(.rhythmMinRatio, or: d.rhythmMinRatio)
        rhythmMaxRatio = try c.value(.rhythmMaxRatio, or: d.rhythmMaxRatio)
        sessionMaxDuration = try c.value(.sessionMaxDuration, or: d.sessionMaxDuration)
        sessionMaxItems = try c.value(.sessionMaxItems, or: d.sessionMaxItems)
        warmUpCount = try c.value(.warmUpCount, or: d.warmUpCount)
        maxExtraItems = try c.value(.maxExtraItems, or: d.maxExtraItems)
        stuckAfter = try c.value(.stuckAfter, or: d.stuckAfter)
        praiseChance = try c.value(.praiseChance, or: d.praiseChance)
        demoBeat = try c.value(.demoBeat, or: d.demoBeat)
    }
}
