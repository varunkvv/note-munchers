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

    /// Called after each finished screen, with the result and the state to save.
    var onScreenDone: ((ScreenResult, MasteryState) -> Void)?
    /// Called once at the end of the session.
    var onSessionDone: ((SessionSummary, MasteryState) -> Void)?
    /// Does this note still need a colour (a muncher that hasn't hatched yet)?
    var needsColor: (ItemID) -> Bool = { _ in false }
    /// He picked a colour for a new muncher.
    var onColorChosen: ((ItemID, Int) -> Void)?

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
    /// The intro's sound and words wait until its muncher has hatched.
    @ObservationIgnored private var afterHatch: [Cue]?

    init(engine: MasteryEngine, input: InputHub, sounds: Sounds, voice: Voice, seed: UInt64) {
        self.input = input
        self.sounds = sounds
        self.voice = voice
        session = PracticeSession(engine: engine, seed: seed, pianoConnected: input.isConnected)
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

    func playHatchPop() {
        sounds.pop()
    }

    func sayPickColor() {
        voice.say(.pickColor)
    }

    /// Leaves early (the "done for now" door). Whatever he finished is already saved.
    func stop() {
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
        // let a sound finish before the voice talks over it, and the voice before a sound:
        // intro: pitch, then "this is D". hint: "listen", then the pitch.
        // rhythm intro: "here's a new one! listen", then the phrase
        let meets = cues.contains { if case .say(.meetNote) = $0 { true } else { false } }
        let pitchDemo = cues.contains { if case .playPitches = $0 { true } else { false } }
        let phraseBeat = cues.lazy.compactMap { cue -> Double? in
            switch cue {
            case .playPhrase(let beat), .showAndPlay(let beat): beat
            default: nil
            }
        }.first
        var speechDelay = 0.0
        var soundDelay = 0.0
        if meets, pitchDemo {
            speechDelay = 0.9
        }
        if cues.contains(.say(.hintListen)) || cues.contains(.say(.twoAtOnce)) {
            soundDelay = 0.7
        }
        if phraseBeat != nil, cues.contains(where: { if case .say = $0 { true } else { false } }) {
            // "listen", "it's a long one": the screen plays once she's done
            soundDelay = 1.7
        }
        for cue in cues {
            switch cue {
            case .showItem:
                itemsShown += 1
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
                effects.add(.sparkle, column: note, duration: 0.7)
                sounds.chime()
                if let item = session.item, item.notes.indices.contains(note) {
                    eaten = item.notes[note].keys
                }
                gobbleCount += 1
                // the chomp lands when the note reaches the mouth
                later(MuncherLane.gobbleLength * 0.5) { $0.sounds.chomp() }
            case .say(let speech):
                var talking = 0.0
                if case .meetNote = speech, speechDelay > 0 {
                    later(speechDelay) { $0.voice.say(speech) }
                } else {
                    talking = voice.say(speech)
                }
                // "listen" / "two at once" lines vary in length: the sound waits until she's done
                if soundDelay > 0 { soundDelay = max(soundDelay, talking + 0.15) }
                if speech == .keepGoing { celebrate = max(celebrate, talking + 0.3) }
                if speech == .keptTrying || speech == .lookedCarefully {
                    // the next screen waits for the praise to finish
                    celebrate = max(celebrate + 0.8, talking + 0.3)
                }
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
            case .unlocked:
                break // each new note hatches when its intro comes up
            case .paused, .resumed:
                break // the view reads `isPaused`
            case .done:
                finishSession()
            }
        }
        if cues.contains(.resumed), session.phase == .success {
            // the piano dropped during the celebration. pick it up again
            scheduleNext(after: celebrate)
        }
        if session.phase == .success, session.summary.screensPlayed > savedScreens {
            savedScreens = session.summary.screensPlayed
            if let screen = session.summary.screens.last {
                onScreenDone?(screen, session.engine.state)
            }
            scheduleNext(after: celebrate)
        }
        scheduleTick()
    }

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
        guard !holdAfterSuccess else { return }
        nextTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay * (self?.timeScale ?? 1)))
            guard !Task.isCancelled, let self, self.session.phase == .success else { return }
            self.play(self.session.next(at: HostClock.now))
        }
    }

    #if DEBUG
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
