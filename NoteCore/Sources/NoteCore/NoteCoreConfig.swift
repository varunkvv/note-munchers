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
    /// Paced lessons (level 1, level 3's middle C lessons): the newest notes get this
    /// share of the notes on their clef instead (round 3: "more repetition so that a
    /// note is really drilled in").
    public var pacedNewestShare = 1.0 / 3
    /// The same key never comes up more than this many times in a row (inside a screen
    /// and across screens). A clef with one note (G on its own) can't hold to it.
    public var maxRepeats = 2
    /// After a new note's intro, at least this many screens on that clef before the
    /// next intro on it (unless there's nothing else to show).
    public var introSpacing = 2
    /// Blocked, then mixed (varun ok'd it for young kids, Brady 2004): a new note's first
    /// this many screens on its clef after its intro are mostly that note...
    public var blockedScreens = 3
    /// ...this share of the notes on its clef. Then it mixes in at the newest share.
    public var blockedShare = 0.7
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
    /// Share of screens in 4/4. The rest are 3/4. Rolled per screen, so he checks the
    /// time signature every time (plans/2026-10-15-real-bars.md).
    public var fourFourShare = 0.5

    // MARK: repetition inside a screen (plans/2026-10-17-reset-and-repetition.md section 2)

    /// A normal screen whose two bars hold as many notes gets one rhythm for both this
    /// share of the time: the repeated rhythm is what tells him bar 2 is like bar 1 (a
    /// piano teacher's review, 2026-10-17).
    public var sameRhythmShare = 0.5
    /// The chance a normal screen is a pattern screen (two bars, bar 2 made from bar 1:
    /// `PatternShape`) in levels 1-2...
    public var patternShare = 0.25
    /// ...in levels 3-5...
    public var patternShareLater = 0.2
    /// ...and on a new note's blocked screens right after its intro: the new note in bar
    /// 1, the shape brings it back in bar 2.
    public var patternIntroShare = 0.5
    /// An answer's last note is G (home), except this share of the time, so he learns to
    /// check the end.
    public var answerAwayChance = 0.25
    /// A pattern screen's bar rhythm isn't one of the last this many pattern screens'
    /// (while at least half of the rhythms that fit are left).
    public var patternFreshCells = 5

    // MARK: lessons

    /// A lesson is done (with every note out and every gate open) after at least this
    /// many screens in it...
    public var lessonMinScreens = 10
    /// ...when his last `lessonWindow` notes in it were at least `lessonRate` right first
    /// try, with a median under `solidMedianResponse`.
    public var lessonWindow = 10
    public var lessonRate = 0.8
    /// Paced lessons: each of the lesson's new notes is played at least this many times
    /// in it before it can finish, however fast he finds them.
    public var lessonMinNewPlays = 10

    // MARK: habit (plans/2026-10-16-drills-and-habit.md section 4)
    // knowing a note vs it being automatic. Starting values, to tune from his data: 6
    // year olds are much slower than adults on speeded tasks (Kail 1991)

    /// Habit looks at a note's last this many in-line plays...
    public var habitWindow = 10
    /// ...this many of them right first try (a wrong octave counts as not automatic)...
    public var habitFirstTry = 9
    /// ...with a median under this...
    public var habitMedian: Double = 2
    /// ...and steady: sd / mean of their times under this (automatic shows as this
    /// dropping, not only the average: Segalowitz & Segalowitz 1993)...
    public var habitCV = 0.4
    /// ...and its first showing right first try in his last sessions on this many
    /// different days (practice inside one session overstates learning: Schmidt & Bjork
    /// 1992, Rohrer et al 2005).
    public var habitDays = 2
    /// A drill lesson finishes when his notes are habit, or once he has played it on
    /// this many different days with the usual lesson rule met, so a steady but slow
    /// reader never gets stuck at the end of a level.
    public var drillLessonMaxDays = 4

    // MARK: song time

    /// A note the band played for him in a song comes back in practice a bit more often
    /// (its pick weight times this)...
    public var comeBackBoost = 2.0
    /// ...until he has played it right first try this many times.
    public var comeBackPlays = 2

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
    /// Under the window is a wrong value (played as half its value), over it a wrong
    /// value up to `rhythmPauseRatio`.
    public var rhythmMinRatio = 0.6
    public var rhythmMaxRatio = 1.6
    /// Inside the window but outside these is "a bit off": still fine, nothing said.
    public var rhythmEvenMin = 0.8
    public var rhythmEvenMax = 1.25
    /// A gap this many times its written length or more is him reading the next note,
    /// not a rhythm. Not judged (plans/2026-10-15-real-bars.md: "3x+").
    public var rhythmPauseRatio = 3.0
    /// A wrong value gets the screen played back to him and another go, at most this
    /// many times a screen. Then it moves on kindly.
    public var rhythmRetries = 2
    /// The first this many rhythm-judged screens of a level that doesn't drill rhythm
    /// (3 and 4) are played to him before he reads them (sound before symbol).
    public var rhythmDemoScreens = 2
    /// Level 3's halves check prefers screens whose two bars share a rhythm (bar 1 sets his
    /// beat, so it starts with a success): those are always judged, others this share of
    /// the time (none among the level's first, played-to-him screens), so judged screens
    /// stay about 1 in 3 (a piano teacher's review, 2026-10-17).
    public var halvesMixedShare = 0.75

    // MARK: session

    /// Active seconds before a session ends (checked between screens, never mid-screen).
    public var sessionMaxDuration: Double = 300
    /// Screens before a session ends. (Kept the round-1 name: the app saves it.)
    public var sessionMaxItems = 20
    /// A session opens with this many screens of his strongest notes, a run (start with success).
    public var warmUpScreens = 1
    /// Every lesson but a drill lesson gets one burst of this many drill screens a
    /// session (3 or 4, rolled), inside one clef run, never a long string of them.
    public var burstScreens = 3...4
    /// Sessions shorter than this many screens skip the burst.
    public var burstMinSession = 10
    /// After a screen all right first try, the chance the same screen comes once more
    /// (a second read, measured silently)...
    public var againChance = 0.07
    /// ...at most this many times a session.
    public var againMax = 1
    /// When time or the screen count is up, the session ends after his next screen
    /// that was all right first try. At most this many extra (easy) screens.
    public var maxExtraItems = 3
    /// A screen of 2+ notes counts only when he plays it all right in one go (varun,
    /// 2026-10-17). After a slip past its first note, the screen goes back to its first
    /// note once he pauses: no key down for this many seconds and nothing held...
    public var restartPause: Double = 1.2
    /// ...a key held this long after it went down stops holding the reset back (a lost
    /// key-up, or a hand resting on a key), so it always comes.
    public var restartHoldLimit: Double = 4
    /// Starts over a screen can have (so at most this many + 1 goes). After that a slip
    /// works note by note again: he stays on the note with the hint ladder and finishes
    /// from there, so a screen can always be finished. 0 = note by note from the start.
    public var sequenceRestarts = 2
    /// No key for this many seconds counts as one step up the hint ladder (stuck).
    /// Only climbs to the keyboard picture, never repeats on a clock after that.
    public var stuckAfter: Double = 15
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
        pacedNewestShare = try c.value(.pacedNewestShare, or: d.pacedNewestShare)
        maxRepeats = try c.value(.maxRepeats, or: d.maxRepeats)
        introSpacing = try c.value(.introSpacing, or: d.introSpacing)
        recentScreens = try c.value(.recentScreens, or: d.recentScreens)
        sizeWindow = try c.value(.sizeWindow, or: d.sizeWindow)
        sizeUpRate = try c.value(.sizeUpRate, or: d.sizeUpRate)
        sizeDownRate = try c.value(.sizeDownRate, or: d.sizeDownRate)
        stretchChance = try c.value(.stretchChance, or: d.stretchChance)
        fourFourShare = try c.value(.fourFourShare, or: d.fourFourShare)
        sameRhythmShare = try c.value(.sameRhythmShare, or: d.sameRhythmShare)
        patternShare = try c.value(.patternShare, or: d.patternShare)
        patternShareLater = try c.value(.patternShareLater, or: d.patternShareLater)
        patternIntroShare = try c.value(.patternIntroShare, or: d.patternIntroShare)
        answerAwayChance = try c.value(.answerAwayChance, or: d.answerAwayChance)
        patternFreshCells = try c.value(.patternFreshCells, or: d.patternFreshCells)
        lessonMinScreens = try c.value(.lessonMinScreens, or: d.lessonMinScreens)
        lessonWindow = try c.value(.lessonWindow, or: d.lessonWindow)
        lessonRate = try c.value(.lessonRate, or: d.lessonRate)
        lessonMinNewPlays = try c.value(.lessonMinNewPlays, or: d.lessonMinNewPlays)
        habitWindow = try c.value(.habitWindow, or: d.habitWindow)
        habitFirstTry = try c.value(.habitFirstTry, or: d.habitFirstTry)
        habitMedian = try c.value(.habitMedian, or: d.habitMedian)
        habitCV = try c.value(.habitCV, or: d.habitCV)
        habitDays = try c.value(.habitDays, or: d.habitDays)
        drillLessonMaxDays = try c.value(.drillLessonMaxDays, or: d.drillLessonMaxDays)
        comeBackBoost = try c.value(.comeBackBoost, or: d.comeBackBoost)
        comeBackPlays = try c.value(.comeBackPlays, or: d.comeBackPlays)
        easingTrigger = try c.value(.easingTrigger, or: d.easingTrigger)
        easingWindow = try c.value(.easingWindow, or: d.easingWindow)
        easingItems = try c.value(.easingItems, or: d.easingItems)
        rhythmSolidRequired = try c.value(.rhythmSolidRequired, or: d.rhythmSolidRequired)
        chordWindow = try c.value(.chordWindow, or: d.chordWindow)
        extraKeyIgnoreWindow = try c.value(.extraKeyIgnoreWindow, or: d.extraKeyIgnoreWindow)
        rhythmMinRatio = try c.value(.rhythmMinRatio, or: d.rhythmMinRatio)
        rhythmMaxRatio = try c.value(.rhythmMaxRatio, or: d.rhythmMaxRatio)
        rhythmEvenMin = try c.value(.rhythmEvenMin, or: d.rhythmEvenMin)
        rhythmEvenMax = try c.value(.rhythmEvenMax, or: d.rhythmEvenMax)
        rhythmPauseRatio = try c.value(.rhythmPauseRatio, or: d.rhythmPauseRatio)
        rhythmRetries = try c.value(.rhythmRetries, or: d.rhythmRetries)
        rhythmDemoScreens = try c.value(.rhythmDemoScreens, or: d.rhythmDemoScreens)
        halvesMixedShare = try c.value(.halvesMixedShare, or: d.halvesMixedShare)
        sessionMaxDuration = try c.value(.sessionMaxDuration, or: d.sessionMaxDuration)
        sessionMaxItems = try c.value(.sessionMaxItems, or: d.sessionMaxItems)
        warmUpScreens = try c.value(.warmUpScreens, or: d.warmUpScreens)
        burstScreens = try c.value(.burstScreens, or: d.burstScreens)
        burstMinSession = try c.value(.burstMinSession, or: d.burstMinSession)
        againChance = try c.value(.againChance, or: d.againChance)
        againMax = try c.value(.againMax, or: d.againMax)
        blockedScreens = try c.value(.blockedScreens, or: d.blockedScreens)
        blockedShare = try c.value(.blockedShare, or: d.blockedShare)
        maxExtraItems = try c.value(.maxExtraItems, or: d.maxExtraItems)
        restartPause = try c.value(.restartPause, or: d.restartPause)
        restartHoldLimit = try c.value(.restartHoldLimit, or: d.restartHoldLimit)
        sequenceRestarts = try c.value(.sequenceRestarts, or: d.sequenceRestarts)
        stuckAfter = try c.value(.stuckAfter, or: d.stuckAfter)
        demoBeat = try c.value(.demoBeat, or: d.demoBeat)
    }
}
