import Foundation
import NoteCore
import Observation

/// Runs one practice session: feeds note events and the clock into `PracticeSession`,
/// turns its cues into sound, voice and animation, and reports finished items so they
/// get saved. Follows context/notecore-api.md: one clock, the tick rule after every
/// call, `next` after the success animation.
@MainActor @Observable
final class PracticeController {
    private(set) var session: PracticeSession
    /// What the staff is sized for. Set when an item is shown, not when the engine
    /// moves on, so finishing a unit doesn't resize the staff under the last item.
    private(set) var spec: StaffSpec
    private(set) var keyboardRange: ClosedRange<Pitch>
    let effects = StaffEffects()
    /// When the app last played the right pitch out loud (hint 1), for the ear picture.
    private(set) var soundHintAt: Date?
    /// Bumped on every gobble, the muncher lane animates on change.
    private(set) var gobbleCount = 0
    /// Eggs waiting to hatch in the lane.
    private(set) var hatching: [ItemID] = []
    /// Items shown so far this session.
    private(set) var itemsShown = 0

    /// Called after each finished item, with the attempt and the state to save.
    var onItemDone: ((AttemptResult, MasteryState) -> Void)?
    /// Called once at the end of the session.
    var onSessionDone: ((SessionSummary, MasteryState) -> Void)?

    /// DEBUG demo: stay on the success state instead of moving on.
    var holdAfterSuccess = false
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
    @ObservationIgnored private var savedItems = 0
    @ObservationIgnored private var finished = false

    init(engine: MasteryEngine, input: InputHub, sounds: Sounds, voice: Voice, seed: UInt64) {
        self.input = input
        self.sounds = sounds
        self.voice = voice
        session = PracticeSession(engine: engine, seed: seed, pianoConnected: input.isConnected)
        spec = StaffSpec(unit: engine.unit)
        keyboardRange = KeyboardRange.forUnit(engine.unit)
    }

    // MARK: what the views read

    var item: PracticeItem? { session.item }
    var phase: SessionPhase { session.phase }
    var isPaused: Bool { session.phase == .paused }
    /// Notes drawn as already played.
    var doneCount: Int {
        guard let item = session.item else { return 0 }
        return session.phase == .success ? item.notes.count : session.noteIndex
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

    /// Leaves early (parent hold). Whatever he finished is already saved.
    func stop() {
        listenTask?.cancel()
        tickTask?.cancel()
        nextTask?.cancel()
        voice.stop()
    }

    private func handle(_ signal: InputSignal) {
        switch signal {
        case .note(let event):
            play(session.handle(event))
        case .connection(true):
            play(session.pianoConnected(at: HostClock.now))
        case .connection(false):
            play(session.pianoDisconnected(at: HostClock.now))
        }
    }

    // MARK: cues

    private func play(_ cues: [Cue]) {
        var celebrate = 1.2
        for cue in cues {
            switch cue {
            case .showItem:
                itemsShown += 1
                effects.clear()
                spec = StaffSpec(unit: session.engine.unit)
                keyboardRange = KeyboardRange.forUnit(session.engine.unit)
            case .wobble(let note):
                effects.add(.wobble, column: note, duration: 0.6)
            case .playPitches(let pitches):
                sounds.play(pitches)
                soundHintAt = Date()
            case .correct(let note):
                effects.add(.sparkle, column: note, duration: 0.7)
                sounds.chime()
                gobbleCount += 1
            case .say(let speech):
                voice.say(speech)
                if speech == .holdLonger { celebrate += 1.2 }
            case .rhythmGlow(let note):
                let length = glowLength(note)
                effects.add(.glow, column: note, duration: length)
                celebrate = max(celebrate, length + 0.8)
            case .playPhrase(let beat):
                if let item = session.item {
                    sounds.play(item.playback(beat: beat))
                }
            case .unlocked(let ids):
                hatching += ids
                celebrate += 2.0
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
        if session.phase == .success, session.summary.itemsPlayed > savedItems {
            savedItems = session.summary.itemsPlayed
            if let attempt = session.summary.attempts.last {
                onItemDone?(attempt, session.engine.state)
            }
            scheduleNext(after: celebrate)
        }
        scheduleTick()
    }

    /// How long the rhythm glow lasts: that note's written length at his own beat.
    private func glowLength(_ note: Int) -> Double {
        guard let item = session.item, let value = item.notes[note].value else { return 1 }
        let beat = session.summary.attempts.last?.rhythm?.beat ?? session.engine.config.demoBeat
        return max(0.6, min(4, value.beats * (beat > 0 ? beat : 0.75)))
    }

    func hatched(_ id: ItemID) {
        hatching.removeAll { $0 == id }
    }

    private func finishSession() {
        guard !finished else { return }
        finished = true
        stop()
        onSessionDone?(session.summary, session.engine.state)
    }

    // MARK: timers

    /// The tick rule: after every call, if the session has a deadline, tick at it.
    private func scheduleTick() {
        tickTask?.cancel()
        guard let deadline = session.nextDeadline else { return }
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
        }
    }

    func demoRepeatSoundHint() {
        soundHintAt = Date()
    }
    #endif
}

/// Keys shown in the keyboard picture for a unit: always at least C3 to C5, so
/// "which C" is visible, and wide enough for every note the unit can show.
enum KeyboardRange {
    static func forUnit(_ unit: NoteCore.Unit, curriculum: Curriculum = .standard) -> ClosedRange<Pitch> {
        let reviewed = unit.reviews.flatMap { curriculum.unit($0)?.newItems ?? [] }
        let pitches = (unit.newItems + reviewed).flatMap { $0.notes.flatMap(\.pitches) }
        let low = min(pitches.min() ?? Pitch(.c, 3), Pitch(.c, 3))
        let high = max(pitches.max() ?? Pitch(.c, 5), Pitch(.c, 5))
        // widen to whole octaves: C at or below low, C at or above high
        let lowC = Pitch(.c, low.octave)
        let highC = high.pitchClass == 0 ? high : Pitch(.c, high.octave + 1)
        return lowC...highC
    }
}
