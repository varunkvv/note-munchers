import Foundation
import NoteCore
import Observation

/// Runs one practice session: feeds note events and the clock into `PracticeSession`,
/// turns its cues into sound, voice and animation, and reports finished screens so they
/// get saved. Follows context/notecore-api.md: one clock, the tick rule after every
/// call, `next` after the success animation.
@MainActor @Observable
final class PracticeController {
    private(set) var session: PracticeSession
    /// What the staff is sized for: the lesson's biggest screen on this screen's staves.
    /// Set when a screen is shown, not when the engine moves on, so finishing a lesson
    /// doesn't change the staff under the last screen.
    private(set) var spec: StaffSpec
    private(set) var keyboardRange: ClosedRange<Pitch>
    let effects = StaffEffects()
    /// When the app last played the right pitch out loud (hint 1), for the ear picture.
    private(set) var soundHintAt: Date?
    /// Bumped on every gobble, the muncher lane animates on change.
    private(set) var gobbleCount = 0
    /// The note(s) he just played. Their muncher pops into the lane and eats them. The
    /// lane never shows the next note's muncher, so it can't give the answer away.
    private(set) var eaten: [NoteKey] = []
    /// A new note's muncher hatching before its intro. While this isn't empty the hatch
    /// screen is up and he picks a colour. The session waits for him.
    private(set) var hatchQueue: [ItemID] = []
    /// Screens shown so far this session.
    private(set) var itemsShown = 0
    /// The screen is being played to him with the keyboard picture (the play button, or
    /// the play back after a wrong value): the keys sounding right now, [] between notes.
    /// nil when nothing plays with the keyboard.
    private(set) var playingKeys: [Pitch]?
    /// The screen is being played (with or without the keyboard).
    private(set) var isPlayingBack = false
    /// He just finished a level: the level-up splash is up, and the session waits for
    /// "Let's go!" (or the door).
    private(set) var levelUp: LevelUpMoment?

    /// What the level-up splash shows.
    struct LevelUpMoment: Equatable {
        /// The level he's in now.
        let level: Int
        /// The new level's path (empty, or nearly).
        let path: LevelProgress
        /// The finished level's lesson count, for its full path.
        let finishedStones: Int
        /// The muncher that walks to the flag, and the ones that cheer.
        let guide: NoteKey?
        let band: [NoteKey]
        let fluencies: [NoteKey: Double]
    }

    /// Called after each finished screen, with the result and the state to save.
    var onScreenDone: ((ScreenResult, MasteryState) -> Void)?
    /// Called once at the end of the session.
    var onSessionDone: ((SessionSummary, MasteryState) -> Void)?
    /// Does this note still need a colour (a muncher that hasn't hatched yet)?
    var needsColor: (ItemID) -> Bool = { _ in false }
    /// He picked a colour for a new muncher.
    var onColorChosen: ((ItemID, Int) -> Void)?
    /// The saved state changed between screens (the level-up splash came up).
    var onStateChanged: ((MasteryState) -> Void)?

    /// DEBUG demo: stay on the success state instead of moving on.
    var holdAfterSuccess = false
    /// DEBUG demo: pick a colour by itself after this many seconds (nil = wait for a tap).
    var demoAutoPick: Double?
    /// DEBUG demo: stretch every delay.
    var timeScale = 1.0 {
        didSet { effects.timeScale = timeScale }
    }

    private let input: InputHub
    private let sounds: Sounds
    private let voice: Voice
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var nextTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var savedScreens = 0
    @ObservationIgnored private var finished = false
    /// Stopped (the door, or the session's end): nothing more comes up.
    @ObservationIgnored private var stopped = false
    /// The level-up splash is due or up: from the end of the screen that finished the
    /// level until "Let's go!". The session doesn't move on in between.
    @ObservationIgnored private var levelUpDue = false
    /// The intro's sound and words wait until its muncher has hatched.
    @ObservationIgnored private var afterHatch: [Cue]?

    /// `day`: today as a day number in his time zone (`AppModel.today`), so habit can
    /// tell two days apart.
    init(engine: MasteryEngine, input: InputHub, sounds: Sounds, voice: Voice, seed: UInt64, day: Int) {
        self.input = input
        self.sounds = sounds
        self.voice = voice
        session = PracticeSession(engine: engine, seed: seed, pianoConnected: input.isConnected, day: day)
        let lesson = engine.lesson
        spec = StaffSpec(lesson: lesson, layout: lesson.staff(for: lesson.clefs[0]))
        keyboardRange = KeyboardRange.forLesson(lesson)
    }

    // MARK: what the views read

    var item: PracticeItem? { session.item }
    var phase: SessionPhase { session.phase }
    var isPaused: Bool { session.phase == .paused }
    var isHatching: Bool { !hatchQueue.isEmpty }
    /// Notes drawn as already played.
    var doneCount: Int {
        guard let item = session.item else { return 0 }
        switch session.phase {
        case .success: return item.notes.count
        case .replaying: return 0 // played back fresh, then he plays it again
        default: return session.noteIndex
        }
    }

    // MARK: lifecycle

    func start() {
        let stream = input.signals()
        listenTask = Task { @MainActor [weak self] in
            for await signal in stream {
                self?.handle(signal)
            }
        }
        play(session.start(at: HostClock.now))
    }

    /// He picked a colour on the hatch screen.
    func chooseColor(_ index: Int, for id: ItemID) {
        guard hatchQueue.first == id else { return }
        onColorChosen?(id, index)
        hatchQueue.removeFirst()
        guard hatchQueue.isEmpty else { return }
        // the hatch wasn't time spent looking for the note
        session.restartPromptClock(at: HostClock.now)
        if let cues = afterHatch {
            afterHatch = nil
            play(cues)
        } else {
            scheduleTick()
        }
    }

    /// Leaves early (the "done for now" door). Whatever he finished is already saved.
    func stop() {
        stopped = true
        listenTask?.cancel()
        tickTask?.cancel()
        nextTask?.cancel()
        playbackTask?.cancel()
        playingKeys = nil
        isPlayingBack = false
        voice.stop()
    }

    private func handle(_ signal: InputSignal) {
        switch signal {
        case .note(let event):
            // keys pressed while a muncher hatches don't count for or against him
            guard !isHatching else { return }
            play(session.handle(event))
        case .connection(true):
            play(session.pianoConnected(at: HostClock.now))
        case .connection(false):
            play(session.pianoDisconnected(at: HostClock.now))
        }
    }

    // MARK: cues

    private func play(_ incoming: [Cue]) {
        var cues = incoming
        // a new note: its muncher hatches first, then the intro (sound, then its name)
        if let intro = session.introNote, let show = cues.firstIndex(of: .showItem), needsColor(intro.id) {
            afterHatch = Array(cues[(show + 1)...])
            cues = Array(cues[...show])
            hatchQueue = [intro.id]
        }
        var celebrate = 1.2
        // a screen played to him waits a moment so he sees it first: a new screen (sound
        // before symbol), or the glow on a note played as a different value. The play
        // button plays straight away
        let phrase = cues.contains { if case .playPhrase = $0 { true } else if case .showAndPlay = $0 { true } else { false } }
        let glow = cues.contains { if case .rhythmGlow = $0 { true } else { false } }
        var soundDelay = 0.0
        if phrase, glow {
            soundDelay = 1.0
        } else if phrase, cues.contains(.showItem) {
            soundDelay = 0.6
        } else if cues.contains(where: { if case .correct = $0 { true } else { false } }) {
            // a note he slipped on twice: its pitch once he's back on it, after his own key
            soundDelay = 0.45
        }
        for cue in cues {
            switch cue {
            case .showItem:
                itemsShown += 1
                // a play back of the last screen stops with it, so no old keys or
                // highlights land on the new one
                playbackTask?.cancel()
                playingKeys = nil
                isPlayingBack = false
                effects.clear()
                let lesson = session.engine.lesson
                let old = spec
                spec = StaffSpec(lesson: lesson, layout: session.item?.layout ?? spec.layout)
                keyboardRange = KeyboardRange.forLesson(lesson)
                #if DEBUG
                if spec != old || itemsShown == 1 {
                    print(String(format: "staff: lesson %@ needs %.1f gaps (%.0fpt at 30pt)", lesson.id, spec.width, spec.width * 30))
                }
                #endif
            case .wobble(let note):
                effects.add(.wobble, column: note, duration: 0.6)
            case .playPitches(let pitches):
                if soundDelay > 0 {
                    later(soundDelay) { $0.sounds.play(pitches) }
                } else {
                    sounds.play(pitches)
                }
                soundHintAt = Date()
            case .correct(let note):
                // no chime or chomp mid-session (varun): the piano already made the sound
                effects.add(.sparkle, column: note, duration: 0.7)
                if let item = session.item, item.notes.indices.contains(note) {
                    eaten = item.notes[note].keys
                }
                gobbleCount += 1
            case .say(let speech):
                // only the session's end says anything now
                voice.say(speech)
            case .rhythmGlow(let note):
                let length = glowLength(note)
                effects.add(.glow, column: note, duration: length)
                celebrate = max(celebrate, length + 0.8)
            case .playPhrase(let beat):
                // sound before symbol: he still reads it, so no keyboard
                playScreen(beat: beat, keys: false, delay: soundDelay)
            case .showAndPlay(let beat):
                playScreen(beat: beat, keys: true, delay: soundDelay) { c in
                    // a wrong value's play back is over: his go again
                    if c.session.phase == .replaying || c.session.phase == .paused {
                        c.play(c.session.replayFinished(at: HostClock.now))
                    }
                }
            case .again:
                // the same screen from its first note (a rhythm retry): every note fresh
                effects.clear()
            case .startOver(let played):
                // he slipped and paused: the notes he had played ease back onto the staff
                // and the first one lights up softly. No sound, no words
                effects.clear()
                for column in 0..<played {
                    effects.add(.fadeBack, column: column, duration: Self.fadeBackLength)
                }
                // the play button after a slip plays it all with its own highlight instead
                if !phrase {
                    effects.add(.startHere, column: 0, duration: Self.startHereLength)
                }
            case .unlocked:
                break // each new note hatches when its intro comes up
            case .paused, .resumed:
                break // the view reads `isPaused`
            case .done:
                finishSession()
            }
        }
        if cues.contains(.resumed), session.phase == .success, !levelUpDue {
            // the piano dropped during the celebration. pick it up again
            scheduleNext(after: celebrate)
        }
        if session.phase == .success, session.summary.screensPlayed > savedScreens {
            savedScreens = session.summary.screensPlayed
            if let screen = session.summary.screens.last {
                onScreenDone?(screen, session.engine.state)
            }
            if session.engine.pendingLevelUp != nil {
                // a level done: the splash once this screen's celebration is over, then the
                // session goes on (or ends) when he's ready
                showLevelUp(after: celebrate)
            } else {
                scheduleNext(after: celebrate)
            }
        }
        scheduleTick()
    }

    /// A start over: played notes go from grey back to ink in this long...
    static let fadeBackLength = 0.4
    /// ...and the first note's soft light comes up as they finish, and fades in this long.
    static let startHereLength = 2.0

    /// How long the rhythm glow lasts: that note's written length at his own beat.
    private func glowLength(_ note: Int) -> Double {
        guard let item = session.item, item.notes.indices.contains(note) else { return 1 }
        let value = item.notes[note].value
        let beat = session.summary.screens.last?.rhythm?.beat ?? session.engine.config.demoBeat
        return max(0.6, min(4, value.beats * (beat > 0 ? beat : 0.75)))
    }

    /// The play button can be tapped: he's reading a screen and nothing is playing.
    var canListen: Bool {
        session.phase.isPlaying && !isPlayingBack && !isHatching && !session.isAwaitingRelease
    }

    /// Kid taps the play button: the screen plays at a gentle tempo, each key lighting
    /// up on the keyboard picture as it sounds. The notes he hasn't played yet count as
    /// hinted (NoteCore decides that).
    func listen() {
        guard canListen else { return }
        play(session.listen(at: HostClock.now))
    }

    /// Plays the screen that's up at `beat` seconds a quarter, after `delay`: the sound,
    /// each note (or rest) on the staff softly highlighted while it sounds, and with
    /// `keys` the keyboard picture lighting each key as it sounds. `done` runs when it's over.
    private func playScreen(beat: Double, keys: Bool, delay: Double, done: (@MainActor (PracticeController) -> Void)? = nil) {
        guard let item = session.item else { return }
        playbackTask?.cancel()
        playingKeys = nil
        isPlayingBack = true
        // demo runs stretch time, so screenshots can catch it mid-way
        let b = beat * timeScale
        enum Step { case on(Int), off, rest(Int) }
        var steps: [(at: Double, step: Step)] = []
        var restIndex = 0
        for (i, note) in item.notes.enumerated() {
            let start = item.startBeats[i] * b
            steps.append((start, .on(i)))
            steps.append((start + note.value.beats * b * 0.85, .off))
            var at = item.startBeats[i] + note.value.beats
            for rest in note.restsAfter {
                steps.append((at * b, .rest(restIndex)))
                restIndex += 1
                at += rest.beats
            }
        }
        steps.sort { $0.at < $1.at }
        let end = item.totalBeats * b
        playbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay * (self?.timeScale ?? 1)))
            guard let self, !Task.isCancelled else { return }
            self.sounds.play(item.playback(beat: b))
            if keys { self.playingKeys = [] }
            let clock = ContinuousClock()
            let start = clock.now
            for (at, step) in steps {
                try? await clock.sleep(until: start + .seconds(at))
                guard !Task.isCancelled else { return }
                switch step {
                case .on(let i):
                    // effects stretch by timeScale themselves
                    self.effects.add(.follow, column: i, duration: item.notes[i].value.beats * beat)
                    if keys { self.playingKeys = item.notes[i].pitches }
                case .off:
                    if keys { self.playingKeys = [] }
                case .rest(let r):
                    var beats = 0.0
                    var k = 0
                    outer: for note in item.notes {
                        for rest in note.restsAfter {
                            if k == r { beats = rest.beats; break outer }
                            k += 1
                        }
                    }
                    self.effects.add(.followRest, column: r, duration: beats * beat)
                }
            }
            try? await clock.sleep(until: start + .seconds(end + 0.2))
            guard !Task.isCancelled else { return }
            self.playingKeys = nil
            self.isPlayingBack = false
            done?(self)
        }
    }

    // MARK: level up

    /// The splash comes up once this screen's celebration is over. It's had its
    /// celebration once it's up (leaving by the door then doesn't bring it back). Leaving
    /// before it's up keeps it for the next calm moment: the end of his next screen.
    private func showLevelUp(after delay: Double) {
        levelUpDue = true
        later(delay) { c in
            guard !c.stopped, !c.finished, let level = c.session.engine.pendingLevelUp else { return }
            let engine = c.session.engine
            let finished = engine.curriculum.level(level - 1)?.lessons.count ?? 4
            // the most grown of all walks to the flag, the next most grown cheer
            let guide = LevelPathPainter.guide(engine)
            let band = engine.metNotes.filter { $0 != guide }
                .sorted { engine.stats(for: $0).peakFluency > engine.stats(for: $1).peakFluency }.prefix(4)
            c.levelUp = LevelUpMoment(
                level: level, path: engine.levelProgress, finishedStones: finished, guide: guide,
                band: Array(band), fluencies: Dictionary(uniqueKeysWithValues: band.map { ($0, engine.stats(for: $0).peakFluency) })
            )
            c.session.celebrateLevelUp()
            c.onStateChanged?(c.session.engine.state)
            // a little "ta-da" up the G chord
            let notes = ["G4", "B4", "D5"].compactMap { Pitch($0) }
            for (i, p) in notes.enumerated() { c.later(0.14 * Double(i)) { $0.sounds.play([p], volume: Sounds.effectVolume) } }
            c.later(0.45) { $0.sounds.play(["G4", "B4", "D5", "G5"].compactMap { Pitch($0) }, volume: Sounds.effectVolume) }
        }
    }

    /// "Let's go!" on the splash: the session goes on (or ends, if this was its last screen).
    func levelUpDone() {
        guard levelUp != nil else { return }
        levelUp = nil
        levelUpDue = false
        scheduleNext(after: 0.5)
    }

    /// Runs `action` after `delay` seconds (stretched in demo runs).
    private func later(_ delay: Double, _ action: @escaping @MainActor (PracticeController) -> Void) {
        let scaled = delay * timeScale
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(scaled))
            if let self { action(self) }
        }
    }

    private func finishSession() {
        guard !finished else { return }
        finished = true
        stop()
        onSessionDone?(session.summary, session.engine.state)
    }

    // MARK: timers

    /// The tick rule: after every call, if the session has a deadline, tick at it.
    /// Not while a muncher hatches (he can't be stuck on a note he can't see yet).
    private func scheduleTick() {
        tickTask?.cancel()
        guard !isHatching, let deadline = session.nextDeadline else { return }
        tickTask = Task { @MainActor [weak self] in
            let wait = deadline - HostClock.now
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled, let self else { return }
            // never earlier than the deadline, so a rounding error can't spin
            self.play(self.session.tick(at: max(deadline + 0.0005, HostClock.now)))
        }
    }

    private func scheduleNext(after delay: Double) {
        nextTask?.cancel()
        guard !holdAfterSuccess, !levelUpDue else { return }
        nextTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay * (self?.timeScale ?? 1)))
            guard !Task.isCancelled, let self, self.session.phase == .success else { return }
            self.play(self.session.next(at: HostClock.now))
        }
    }

    #if DEBUG
    /// Demo: the session opens on a drill screen of this shape. Before `start`.
    func demoOpen(with drill: Drill) {
        session.openWithDrill = drill
    }

    /// Demo: the session opens on a pattern screen of this shape. Before `start`.
    func demoOpen(pattern: PatternShape) {
        session.openWithPattern = pattern
    }

    /// Demo: move on from a held success state.
    func demoNext() {
        guard session.phase == .success else { return }
        play(session.next(at: HostClock.now))
    }

    /// Demo: show an effect again (screenshots catch it mid-way). Visual only.
    func demoReplay(_ kind: StaffEffects.Kind, column: Int) {
        switch kind {
        case .wobble: effects.add(.wobble, column: column, duration: 0.6)
        case .sparkle:
            effects.add(.sparkle, column: column, duration: 0.7)
            gobbleCount += 1
        case .glow: effects.add(.glow, column: column, duration: glowLength(column))
        case .follow, .followRest: effects.add(kind, column: column, duration: 1)
        case .fadeBack: effects.add(.fadeBack, column: column, duration: Self.fadeBackLength)
        case .startHere: effects.add(.startHere, column: column, duration: Self.startHereLength)
        }
    }

    func demoRepeatSoundHint() {
        soundHintAt = Date()
    }
    #endif
}

/// Keys shown in the keyboard picture for a lesson: always at least C3 to C5, so
/// "which C" is visible, and wide enough for every note the lesson can show.
enum KeyboardRange {
    static func forLesson(_ lesson: Lesson) -> ClosedRange<Pitch> {
        let pitches = lesson.keys.map(\.pitch)
        let low = min(pitches.min() ?? Pitch(.c, 3), Pitch(.c, 3))
        let high = max(pitches.max() ?? Pitch(.c, 5), Pitch(.c, 5))
        // widen to whole octaves: C at or below low, C at or above high
        let lowC = Pitch(.c, low.octave)
        let highC = high.pitchClass == 0 ? high : Pitch(.c, high.octave + 1)
        return lowC...highC
    }
}
