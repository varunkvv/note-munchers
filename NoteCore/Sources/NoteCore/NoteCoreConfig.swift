/// Every tunable number in NoteCore. Codable so the app can store parent changes
/// (session length). The app only saves what the parent sets; the rest always comes
/// from `.default`, so a tuning change in a new build reaches every install.
public struct NoteCoreConfig: Hashable, Codable, Sendable {
    // MARK: mastery, per note

    /// How many recent attempts per note are kept and judged.
    public var solidWindow = 8
    /// The newest note is solid when this many of the last `solidWindow` were right first try...
    public var solidRequired = 7
    /// ...and the median response time of those attempts is under this.
    public var solidMedianResponse: Double = 4

    /// Fast track: the newest note right first try this many times in a row...
    public var fastTrackCount = 3
    /// ...each one under this many seconds, counts as solid right away.
    public var fastTrackResponse: Double = 3

    /// Leitner boxes run 1...boxCount. New notes start in box 1.
    public var boxCount = 5
    /// The next notes on a clef unlock only when no note on that clef is below this box.
    public var gateMinBox = 3

    // MARK: screens

    /// Share of the notes on a clef that go to that clef's newest batch (at one note a
    /// screen, 1 screen in 4). The rest are weighted toward low boxes. Small steps,
    /// aiming for ~80% first-try success (rosenshine).
    public var newestShare = 0.25
    /// The same key never comes up more than this many times in a row (inside a screen
    /// and across screens).
    public var maxRepeats = 2
    /// Screens remembered so the same screen doesn't come back too soon. Fewer when the
    /// pool can't make that many different screens.
    public var recentScreens = 10

    /// Notes per screen grows by one when his notes over the last `sizeWindow` normal
    /// screens at the current size were at least `sizeUpRate` right first try...
    public var sizeWindow = 4
    public var sizeUpRate = 0.8
    /// ...and drops back one when they're under `sizeDownRate` (after at least
    /// `sizeWindow - 1` screens).
    public var sizeDownRate = 0.6
    /// Chance of a stretch screen (one note more than his size) when he's doing well.
    public var stretchChance = 0.125

    // MARK: lessons

    /// A lesson is done (with every note out and every gate open) after at least this
    /// many screens in it...
    public var lessonMinScreens = 10
    /// ...when his last `lessonWindow` notes in it were at least `lessonRate` right first
    /// try, with a median under `solidMedianResponse`.
    public var lessonWindow = 10
    public var lessonRate = 0.8

    // MARK: session shape

    /// Easing: when this many of his last `easingWindow` notes in a session weren't
    /// right first try (a wrong key or a hint)...
    public var easingTrigger = 3
    public var easingWindow = 5
    /// ...the next this many screens are made of his strongest notes.
    public var easingItems = 2

    // MARK: rhythm mastery

    /// A rhythm lesson's rhythm is solid when this many of its last `solidWindow`
    /// judged screens had every note ok. Looser than pitch on purpose.
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

    /// Active seconds before a session ends (checked between screens, never mid-screen).
    public var sessionMaxDuration: Double = 300
    /// Screens before a session ends. (Kept the round-1 name: the app saves it.)
    public var sessionMaxItems = 20
    /// A session opens with screens of his strongest notes until this many notes have
    /// been shown (start with success).
    public var warmUpCount = 3
    /// When time or the screen count is up, the session ends after his next screen
    /// that was all right first try. At most this many extra (easy) screens.
    public var maxExtraItems = 3
    /// No key for this many seconds counts as one step up the hint ladder (stuck).
    /// Only climbs to the keyboard picture, never repeats on a clock after that.
    public var stuckAfter: Double = 15
    /// Chance of "you looked carefully" after a screen that was all right first try.
    /// Voice is rare: roughly 1 screen in 5 gets process praise.
    public var praiseChance = 0.2
    /// Chance of "you kept trying and found it" after a screen that needed a hint.
    public var keptTryingChance = 0.5
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
        recentScreens = try c.value(.recentScreens, or: d.recentScreens)
        sizeWindow = try c.value(.sizeWindow, or: d.sizeWindow)
        sizeUpRate = try c.value(.sizeUpRate, or: d.sizeUpRate)
        sizeDownRate = try c.value(.sizeDownRate, or: d.sizeDownRate)
        stretchChance = try c.value(.stretchChance, or: d.stretchChance)
        lessonMinScreens = try c.value(.lessonMinScreens, or: d.lessonMinScreens)
        lessonWindow = try c.value(.lessonWindow, or: d.lessonWindow)
        lessonRate = try c.value(.lessonRate, or: d.lessonRate)
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
        keptTryingChance = try c.value(.keptTryingChance, or: d.keptTryingChance)
        demoBeat = try c.value(.demoBeat, or: d.demoBeat)
    }
}
