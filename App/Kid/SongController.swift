import Foundation
import NoteCore
import Observation

/// Runs one song (plans/2026-10-16-free-play.md): the title card, the pages he reads and
/// plays while the piano part follows him, then the end card with Listen.
///
/// Judging is `AttemptJudge` directly, one note at a time. Nothing is recorded: no stats,
/// no warm-up, easing, hatches or unlocks, no rhythm judging. A wrong key wobbles and the
/// backing waits (nothing new plays, the chord keeps ringing). After 2 wrong tries or ~8s
/// stuck the key lights up on the keyboard picture. The play button plays the page.
@MainActor @Observable
final class SongController {
    enum Phase: Equatable {
        case title, playing, ending, end, listening
    }

    let song: Song
    let pages: [SongPage]
    /// Three of his munchers. On each right note the next one in the row hops.
    let band: [NoteKey]
    /// What the staff is sized for: the widest system in the song, so it never changes size.
    let spec: StaffSpec
    let keyboardRange: ClosedRange<Pitch>
    /// How grown each of the band's munchers is (peak fluency), for drawing.
    let fluencies: [NoteKey: Double]

    private(set) var phase: Phase = .title
    /// The next note to play, in `song.notes`.
    private(set) var noteIndex = 0
    private(set) var page = 0
    /// Keys lit on the keyboard picture (2 wrong tries, stuck, or the right letter in the
    /// wrong octave). Empty = no picture.
    private(set) var keyboardHint: [Pitch] = []
    /// The page playing with the play button: the keys sounding now, [] between notes.
    private(set) var playingKeys: [Pitch]?
    private(set) var isPlayingBack = false
    /// Bumped on each right note (and each beat of Listen). `band[hops % 3]` hops.
    private(set) var hops = 0
    /// When the band bowed (the song's last chord).
    private(set) var bowedAt: Date?
    private(set) var isPaused = false
    /// One per system on the page: wobble on a wrong key, the soft follow highlight while
    /// the play button plays. Nothing sparkles: the band in the lane is the feedback.
    let effects = [StaffEffects(), StaffEffects()]

    /// The kid left (the door, or "All done") or asked for a new song.
    var onAllDone: (() -> Void)?
    var onNewSong: (() -> Void)?

    /// DEBUG demo: stretch every delay.
    var timeScale = 1.0 {
        didSet { effects.forEach { $0.timeScale = timeScale } }
    }

    private let input: InputHub
    private let sounds: Sounds
    private let voice: Voice
    private let piano: Piano?
    private let plan: BackingPlan
    private let octavePolicy: OctavePolicy
    @ObservationIgnored private var judge: AttemptJudge
    @ObservationIgnored private var follower: BackingFollower
    @ObservationIgnored private var wrongTries = 0
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var stuckTask: Task<Void, Never>?
    @ObservationIgnored private var windowTask: Task<Void, Never>?
    @ObservationIgnored private var fillers: [Task<Void, Never>] = []
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var track: SongMix.Track?

    /// ~8s with no key on a note lights it on the keyboard picture.
    static let stuckAfter = 8.0
    /// Two wrong tries light it too.
    static let wrongTriesForHint = 2
    /// The play button's tempo, seconds a quarter.
    static let hearItBeat = 0.75

    init(song: Song, octavePolicy: OctavePolicy, fluency: (NoteKey) -> Double, input: InputHub, sounds: Sounds, voice: Voice, piano: Piano?) {
        self.song = song
        self.octavePolicy = octavePolicy
        self.input = input
        self.sounds = sounds
        self.voice = voice
        self.piano = piano
        pages = song.pages
        plan = BackingPlan(song: song)
        follower = BackingFollower(plan: plan)
        judge = AttemptJudge(expected: song.notes[0].pitches, octavePolicy: octavePolicy)
        band = Self.band(for: song)
        fluencies = Dictionary(uniqueKeysWithValues: band.map { ($0, fluency($0)) })
        let widest = song.pages.flatMap(\.systems).map { Metrics.notesWidth($0) }.max() ?? 20
        spec = StaffSpec(layout: song.layout, keySignature: song.keySignature, hasMeter: true, noteWidth: widest)
        keyboardRange = KeyboardRange.forPitches(song.notes.flatMap(\.pitches))
    }

    /// Three of the song's notes' munchers, picked by the song's seed.
    static func band(for song: Song) -> [NoteKey] {
        var keys: [NoteKey] = []
        for note in song.notes {
            for key in note.keys where !keys.contains(key) { keys.append(key) }
        }
        var rng = SeededRandom(seed: song.seed ^ 0xBA4D)
        var picked: [NoteKey] = []
        while picked.count < 3, !keys.isEmpty {
            picked.append(keys.remove(at: Int(rng.next() % UInt64(keys.count))))
        }
        return picked
    }

    // MARK: what the views read

    var currentPage: SongPage { pages[page] }
    var isOnPages: Bool { phase == .playing || phase == .ending }
    var expected: [Pitch] { noteIndex < song.notes.count ? song.notes[noteIndex].pitches : [] }

    /// Notes of system `s` on this page drawn as played.
    func doneCount(system s: Int) -> Int {
        let page = currentPage
        guard page.systems.indices.contains(s) else { return 0 }
        if phase != .playing { return page.systems[s].notes.count }
        return min(page.systems[s].notes.count, max(0, noteIndex - page.systemStarts[s]))
    }

    /// The play button can be tapped: he's reading a page and nothing is playing.
    var canHear: Bool { phase == .playing && !isPlayingBack && !isPaused }

    // MARK: lifecycle

    /// The title card is up. Listens for keys from here (they don't count until he starts).
    func open() {
        isPaused = !input.isConnected
        let stream = input.signals()
        listenTask = Task { @MainActor [weak self] in
            for await signal in stream {
                self?.handle(signal)
            }
        }
    }

    /// "Let's play!": the first page, and one soft G chord to set the key.
    func start() {
        guard phase == .title else { return }
        phase = .playing
        if let piano { sounds.playBacking(SongMix.intro(song, piano: piano), held: true) }
        restartStuckClock()
    }

    /// Leaving (the door, "All done", "New song"). Stops every sound and task.
    func stop() {
        listenTask?.cancel()
        stuckTask?.cancel()
        windowTask?.cancel()
        playbackTask?.cancel()
        endTask?.cancel()
        cancelFillers()
        sounds.stopBacking()
        sounds.stopTrack()
        voice.stop()
    }

    func leave() {
        stop()
        onAllDone?()
    }

    func newSong() {
        stop()
        onNewSong?()
    }

    // MARK: keys

    private func handle(_ signal: InputSignal) {
        switch signal {
        case .note(let event):
            guard event.kind == .on else { return }
            noteOn(event.pitch, at: event.time)
        case .connection(let connected):
            isPaused = !connected
            if connected, phase == .playing {
                follower.rest()
                restartStuckClock()
            } else {
                stuckTask?.cancel()
            }
        }
    }

    private func noteOn(_ pitch: Pitch, at time: Double) {
        guard phase == .playing, !isPaused else { return }
        if let verdict = judge.noteOn(pitch, at: time) {
            judged(verdict, at: time)
        }
        scheduleWindow()
        // after judging, so the clock is on the note he's looking for now
        if phase == .playing { restartStuckClock() }
    }

    private func judged(_ verdict: PitchVerdict, at time: Double) {
        switch verdict {
        case .correct:
            correct(at: time)
        case .almost:
            // the right letter: he's close, show him where (no voice in songs)
            wobble()
            wrongTries += 1
            keyboardHint = expected
        case .wrong:
            wobble()
            wrongTries += 1
            // the backing waits: nothing new plays, the chord keeps ringing
            cancelFillers()
            if wrongTries >= Self.wrongTriesForHint { keyboardHint = expected }
        }
    }

    private func correct(at time: Double) {
        let index = noteIndex
        if let piano { sound(follower.played(index, at: time), piano: piano) }
        hops += 1
        noteIndex += 1
        wrongTries = 0
        keyboardHint = []
        guard noteIndex < song.notes.count else {
            finish(at: time)
            return
        }
        judge.expect(song.notes[noteIndex].pitches)
        let next = song.page(ofNote: noteIndex)
        if next != page {
            effects.forEach { $0.clear() }
            page = next
        }
    }

    /// The last G: the tag plays at his tempo, the band bows, then the end card.
    private func finish(at time: Double) {
        phase = .ending
        stuckTask?.cancel()
        let tag = plan.events.filter { $0.part == .outro }.map(\.offset).max() ?? 2
        let bow = tag * follower.beat
        endTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(bow * (self?.timeScale ?? 1)))
            guard let self, !Task.isCancelled else { return }
            self.bowedAt = Date()
            try? await Task.sleep(for: .seconds(1.8 * self.timeScale))
            guard !Task.isCancelled else { return }
            self.phase = .end
            self.voice.say(.showGrownUp)
        }
    }

    private func wobble() {
        let (system, column) = position(of: noteIndex)
        effects[system].add(.wobble, column: column, duration: 0.6)
    }

    /// Which system of the current page, and which column in it, a song note is.
    private func position(of index: Int) -> (Int, Int) {
        let starts = currentPage.systemStarts
        let s = starts.lastIndex { $0 <= index } ?? 0
        return (s, index - starts[s])
    }

    // MARK: the backing

    /// What the follower says to sound: now (with his key, the held chord) or at his beat
    /// (fillers, dropped if his next key or a wrong one comes first).
    private func sound(_ timed: [TimedBackingEvent], piano: Piano) {
        cancelFillers()
        let now = HostClock.now
        var groups: [(time: Double, events: [BackingEvent])] = []
        for t in timed {
            if let i = groups.firstIndex(where: { abs($0.time - t.time) < 0.005 }) { groups[i].events.append(t.event) } else { groups.append((t.time, [t.event])) }
        }
        #if DEBUG
        print(String(format: "backing: note %d, his beat %.2fs, %@", noteIndex, follower.beat,
                     groups.map { String(format: "%@ +%.2fs", $0.events.map(\.part.rawValue).joined(separator: "+"), max(0, $0.time - now)) }.joined(separator: ", ")))
        #endif
        for group in groups {
            let held = group.events.contains { $0.isAnchored && $0.part != .arpeggio }
            let buffer = SongMix.backing(group.events, beat: follower.beat, piano: piano)
            if group.time <= now + 0.03 {
                sounds.playBacking(buffer, held: held)
                continue
            }
            let lead = (group.time - now - 0.05) * timeScale
            let at = now + (group.time - now) * timeScale
            fillers.append(Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0, lead)))
                guard let self, !Task.isCancelled else { return }
                self.sounds.playBacking(buffer, at: at, held: held)
            })
        }
    }

    private func cancelFillers() {
        fillers.forEach { $0.cancel() }
        fillers = []
    }

    // MARK: timers

    /// ~8s with no key: light the key. Restarts on every key and every new note.
    private func restartStuckClock() {
        stuckTask?.cancel()
        let index = noteIndex
        stuckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.stuckAfter * (self?.timeScale ?? 1)))
            guard let self, !Task.isCancelled, self.phase == .playing, self.noteIndex == index else { return }
            self.keyboardHint = self.expected
        }
    }

    /// A dyad collects its keys for a moment: judge it when the window closes.
    private func scheduleWindow() {
        windowTask?.cancel()
        guard let deadline = judge.windowDeadline else { return }
        windowTask = Task { @MainActor [weak self] in
            let wait = deadline - HostClock.now
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self, !Task.isCancelled else { return }
            if let verdict = self.judge.closeWindow(at: max(deadline + 0.0005, HostClock.now)) {
                self.judged(verdict, at: deadline)
            }
        }
    }

    // MARK: hear it first

    /// The play button: the page plays at a gentle tempo, each key lighting up on the
    /// keyboard picture and each note softly highlighted. Nothing is recorded, so there's
    /// no cost to using it.
    func hearIt() {
        guard canHear, let piano else { return }
        let page = currentPage
        let notes = Array(song.notes[page.firstNote..<(page.firstNote + page.noteCount)])
        let beat = Self.hearItBeat * timeScale
        var start = 0.0
        var steps: [(at: Double, note: Int?)] = []
        var melody: [Piano.Note] = []
        for (i, note) in notes.enumerated() {
            steps.append((start, i))
            steps.append((start + note.value.beats * beat * 0.85, nil))
            for p in note.pitches {
                melody.append(Piano.Note(time: start, midi: p.midi, gain: SongMix.melodyGain / Double(note.pitches.count).squareRoot(),
                                         length: note.value.beats * beat * 0.9))
            }
            start += note.span * beat
        }
        sounds.playTrack(Piano.buffer(piano.render(melody, duration: start)))
        isPlayingBack = true
        playingKeys = []
        let end = start
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let t0 = clock.now
            for (at, i) in steps {
                try? await clock.sleep(until: t0 + .seconds(at))
                guard let self, !Task.isCancelled else { return }
                if let i {
                    let (system, column) = self.position(of: page.firstNote + i)
                    self.effects[system].add(.follow, column: column, duration: notes[i].value.beats * Self.hearItBeat)
                    self.playingKeys = notes[i].pitches
                } else {
                    self.playingKeys = []
                }
            }
            try? await clock.sleep(until: t0 + .seconds(end + 0.2))
            guard let self, !Task.isCancelled else { return }
            self.playingKeys = nil
            self.isPlayingBack = false
            // listening isn't his tempo
            self.follower.rest()
            self.restartStuckClock()
        }
    }

    // MARK: listen

    /// The end card's Listen: his song as written, with its backing, at a steady gentle
    /// tempo. The band hops on the beat, one muncher at a time.
    func listen() {
        guard phase == .end, let piano else { return }
        let track = self.track ?? SongMix.listen(song, piano: piano)
        self.track = track
        sounds.playTrack(Piano.buffer(track.samples))
        phase = .listening
        let beats = Int(song.totalBeats)
        endTask?.cancel()
        endTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            let t0 = clock.now
            for b in 0..<beats {
                try? await clock.sleep(until: t0 + .seconds(track.songStart + Double(b) * track.beat))
                guard let self, !Task.isCancelled else { return }
                self.hops += 1
            }
            try? await clock.sleep(until: t0 + .seconds(Double(track.samples.count) / Piano.rate))
            guard let self, !Task.isCancelled else { return }
            self.phase = .end
        }
    }

    #if DEBUG
    /// Demo: the song as if he'd played it to the end (end card screenshots).
    func demoSkipToEnd() {
        guard phase != .end else { return }
        stuckTask?.cancel()
        noteIndex = song.notes.count
        page = pages.count - 1
        bowedAt = Date()
        phase = .end
    }
    #endif
}

extension KeyboardRange {
    /// At least C3 to C5, widened to whole octaves around `pitches`.
    static func forPitches(_ pitches: [Pitch]) -> ClosedRange<Pitch> {
        let low = min(pitches.min() ?? Pitch(.c, 3), Pitch(.c, 3))
        let high = max(pitches.max() ?? Pitch(.c, 5), Pitch(.c, 5))
        let lowC = Pitch(.c, low.octave)
        let highC = high.pitchClass == 0 ? high : Pitch(.c, high.octave + 1)
        return lowC...highC
    }
}
