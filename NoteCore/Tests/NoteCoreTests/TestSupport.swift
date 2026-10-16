import Testing
@testable import NoteCore

/// `NoteKey(id:)` that must parse.
func key(_ id: String) -> NoteKey { NoteKey(id: id)! }

extension MasteryEngine {
    /// Records one normal screen of these notes, every one right (or every one wrong)
    /// at `time` each.
    @discardableResult
    mutating func play(_ keys: [NoteKey], right: Bool = true, time: Double = 1.5, reason: PickReason = .normal) -> MasteryUpdate {
        let notes = keys.map {
            AttemptResult(itemID: $0.id, lesson: lesson.id, level: lesson.level, firstTry: right, wrongPresses: right ? 0 : 1, responseTime: time)
        }
        return record(ScreenResult(screenID: "test", lesson: lesson.id, reason: reason, notes: notes, size: keys.count))
    }

    @discardableResult
    mutating func play(_ key: NoteKey, right: Bool = true, time: Double = 1.5) -> MasteryUpdate {
        play([key], right: right, time: time, reason: .warmUp) // not counted toward the size
    }

    /// The note's intro screen, played right.
    mutating func intro(_ key: NoteKey) {
        let note = AttemptResult(itemID: key.id, lesson: lesson.id, level: lesson.level, wasIntro: true, firstTry: true, responseTime: 3)
        record(ScreenResult(screenID: key.id, lesson: lesson.id, wasIntro: true, notes: [note], size: 1))
    }

    /// Every note waiting for its intro gets it.
    mutating func introduceAll() {
        for key in pendingIntros { intro(key) }
    }
}

/// Drives a session with a moving clock.
struct Bench {
    var session: PracticeSession
    var now = 0.0

    init(_ engine: MasteryEngine, seed: UInt64 = 1, connected: Bool = true) {
        session = PracticeSession(engine: engine, seed: seed, pianoConnected: connected)
    }

    var expected: [Pitch] { session.item!.notes[session.noteIndex].pitches }
    /// A key that's wrong for the current note in any octave policy, and never the
    /// natural next to a sharp.
    var wrongKey: Pitch { Pitch(midi: expected[0].midi + 2) }

    mutating func start() -> [Cue] { session.start(at: now) }

    mutating func press(_ pitch: Pitch, after dt: Double = 0.5) -> [Cue] {
        now += dt
        return session.handle(.on(pitch, at: now))
    }

    mutating func release(_ pitch: Pitch, after dt: Double = 0) -> [Cue] {
        now += dt
        return session.handle(.off(pitch, at: now))
    }

    /// Presses every key of the current note at once (well, 10ms apart).
    mutating func playCurrent(after dt: Double = 0.5) -> [Cue] {
        var cues: [Cue] = []
        for (i, pitch) in expected.enumerated() {
            cues += press(pitch, after: i == 0 ? dt : 0.01)
        }
        return cues
    }

    /// Plays every note left on the screen, right first try.
    mutating func playScreen(after dt: Double = 0.5) -> [Cue] {
        var cues: [Cue] = []
        while session.phase.isPlaying {
            cues += playCurrent(after: dt)
        }
        return cues
    }

    mutating func next(after dt: Double = 1) -> [Cue] {
        now += dt
        return session.next(at: now)
    }

    mutating func tick(at time: Double) -> [Cue] {
        now = time
        return session.tick(at: time)
    }
}

/// An engine in `lesson` with every note met (no intros pending), so screens are normal ones.
func engine(in lesson: LessonID, config: NoteCoreConfig = .default, seed: UInt64 = 7) -> MasteryEngine {
    var engine = MasteryEngine(config: config, state: MasteryState(seed: seed))
    engine.moveToLesson(lesson)
    engine.introduceAll()
    return engine
}

func speeches(_ cues: [Cue]) -> [Speech] {
    cues.compactMap { if case .say(let s) = $0 { s } else { nil } }
}

/// Longest run of the same value.
func maxRun<T: Equatable>(_ values: [T]) -> Int {
    var best = 0, run = 0
    var last: T?
    for value in values {
        run = value == last ? run + 1 : 1
        last = value
        best = max(best, run)
    }
    return best
}
