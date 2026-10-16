import Foundation
import NoteCore
import Observation

/// App-wide state: which screen is up, the input hub, sound, voice and the saved
/// mastery engine. One per app.
@MainActor @Observable
final class AppModel {
    enum Screen: Equatable {
        case home
        case practice
        case sessionEnd
        /// song time: title card, pages, end card
        case song
    }

    var screen: Screen = .home
    private(set) var practice: PracticeController?
    /// The song he's playing (song time).
    private(set) var song: SongController?
    /// Song time's piano samples, loaded the first time a song starts.
    @ObservationIgnored private lazy var piano = Piano()
    /// The last finished session, for the end screen.
    private(set) var lastSummary: SessionSummary?
    /// He tapped the "done for now" door (vs the session ending by itself).
    private(set) var lastEndedByKid = false
    var showParent = false
    /// DEBUG demo: open the parent area on this page.
    var parentPage: String?
    /// DEBUG demo: show the staff gallery for this lesson instead of the app.
    var galleryLesson: LessonID?

    let input = InputHub()
    let sounds = Sounds()
    let voice = Voice()
    let store: Store
    let muncherColors: MuncherColors
    /// When the running session started, for its history row.
    @ObservationIgnored private var sessionStartedAt = Date()

    /// Progress between sessions. A session works on its own copy and hands back the
    /// state after every item.
    private(set) var engine: MasteryEngine
    private(set) var config: NoteCoreConfig

    #if DEBUG
    let demo = DemoOptions()
    #endif

    init() {
        var inMemory = false
        #if DEBUG
        // demo runs never touch his real progress unless asked to
        inMemory = demo.isActive && !demo.persist
        #endif
        store = Store(inMemory: inMemory)
        muncherColors = MuncherColors(picked: store.muncherColors())
        // first launch: his own seed, so which notes he starts with is his own draw
        let (state, settings) = store.loadMastery() ?? (MasteryState(seed: UInt64.random(in: 0...UInt64.max)), ParentSettings())
        let config = settings.config
        self.config = config
        engine = MasteryEngine(config: config, state: state)
        #if DEBUG
        let counts = store.counts()
        print("store: loaded lesson \(engine.lesson.id), \(engine.allProgress.count) notes played, \(counts.attempts) attempts, \(counts.sessions) sessions, colours \(muncherColors.picked.sorted { $0.key < $1.key })\(store.isTemporary ? " (temporary)" : "")")
        #endif
    }

    /// Called once when the first window appears.
    func launch() {
        #if DEBUG
        // logs go to a file in agent runs. line buffered so a killed app still wrote them
        setvbuf(stdout, nil, _IOLBF, 0)
        if let folder = demo.renderSongs {
            SongRenders.write(to: folder)
            exit(0)
        }
        if demo.isActive {
            DemoRunner(model: self, options: demo).begin()
            return
        }
        if demo.debugKeyboard { input.debugKeyboardOn = true }
        input.logs = demo.logMIDI
        #endif
        input.startMIDI()
    }

    // MARK: sessions

    func startPractice() {
        guard practice == nil else { return }
        var seed = UInt64.random(in: 0...UInt64.max)
        #if DEBUG
        if let demoSeed = demo.seed { seed = demoSeed }
        #endif
        let controller = PracticeController(
            engine: MasteryEngine(config: config, state: engine.state),
            input: input, sounds: sounds, voice: voice, seed: seed
        )
        controller.onScreenDone = { [weak self] screen, state in
            self?.screenDone(screen, state: state)
        }
        controller.onSessionDone = { [weak self] summary, state in
            self?.sessionDone(summary, state: state)
        }
        controller.needsColor = { [weak self] id in
            !(self?.muncherColors.hasColor(id) ?? true)
        }
        controller.onColorChosen = { [weak self] id, index in
            self?.muncherColors.set(index, for: id)
            self?.store.saveMuncherColor(index, for: id)
        }
        #if DEBUG
        if demo.isActive { controller.demoAutoPick = demo.autoPick }
        #endif
        practice = controller
        screen = .practice
        sessionStartedAt = Date()
        controller.start()
    }

    /// The "done for now" door. Every finished item is already saved; the session
    /// still gets a history row if he played anything. Ends kindly on the end screen.
    func doneForNow() {
        guard let practice else { return }
        practice.stop()
        let summary = practice.session.summary
        if summary.screensPlayed > 0 {
            store.addSession(summary, startedAt: sessionStartedAt)
        }
        lastSummary = summary
        lastEndedByKid = true
        self.practice = nil
        screen = .sessionEnd
    }

    /// End screen: "one more round".
    func oneMoreRound() {
        startPractice()
    }

    /// End screen: "all done".
    func allDone() {
        screen = .home
    }

    private func screenDone(_ screen: ScreenResult, state: MasteryState) {
        engine = MasteryEngine(config: config, state: state)
        store.saveMastery(state, settings: ParentSettings(config))
        // one row per note, so the dashboard's per-note trends work as before
        for (i, note) in screen.notes.enumerated() {
            store.addAttempt(note, commit: i == screen.notes.count - 1)
        }
    }

    private func sessionDone(_ summary: SessionSummary, state: MasteryState) {
        engine = MasteryEngine(config: config, state: state)
        store.saveMastery(state, settings: ParentSettings(config))
        store.addSession(summary, startedAt: sessionStartedAt)
        lastSummary = summary
        lastEndedByKid = false
        practice = nil
        screen = .sessionEnd
    }

    // MARK: song time

    /// He has 3+ solid notes (G and A among them) in a clef. Never a lock: before that
    /// the button just isn't there.
    var canPlaySongs: Bool { engine.canPlaySongs }

    /// A new song at his level: the title card first. Remembered at once, so the next
    /// one is different even if he leaves this one.
    func startSong() {
        guard practice == nil else { return }
        song?.stop()
        var seed = UInt64.random(in: 0...UInt64.max)
        #if DEBUG
        if let demoSeed = demo.seed { seed = demoSeed &+ UInt64(songsMade) }
        songsMade += 1
        #endif
        guard let made = engine.makeSong(seed: seed) else { return }
        engine.rememberSong(made)
        store.saveMastery(engine.state, settings: ParentSettings(config))
        let engine = self.engine
        let controller = SongController(
            song: made, octavePolicy: engine.lesson.octavePolicy, fluency: { engine.stats(for: $0).peakFluency },
            input: input, sounds: sounds, voice: voice, piano: piano
        )
        controller.onAllDone = { [weak self] in self?.songAllDone() }
        controller.onNewSong = { [weak self] in self?.startSong() }
        song = controller
        screen = .song
        #if DEBUG
        print("song: \(made.title), level \(made.level), \(made.meter.rawValue), \(made.form.rawValue)\(made.isFallback ? " (fallback)" : ""): \(made.signature)")
        #endif
    }

    /// "All done" or the door on a song: home.
    func songAllDone() {
        song?.stop()
        song = nil
        screen = .home
    }

    #if DEBUG
    @ObservationIgnored private var songsMade: UInt64 = 0
    #endif

    // MARK: parent changes (never during a session)

    func updateConfig(_ change: (inout NoteCoreConfig) -> Void) {
        change(&config)
        engine = MasteryEngine(config: config, state: engine.state)
        store.saveMastery(engine.state, settings: ParentSettings(config))
    }

    func moveToLesson(_ id: LessonID) {
        guard practice == nil else { return }
        engine.moveToLesson(id)
        store.saveMastery(engine.state, settings: ParentSettings(config))
    }

    func moveToLevel(_ number: Int) {
        guard practice == nil else { return }
        engine.moveToLevel(number)
        store.saveMastery(engine.state, settings: ParentSettings(config))
    }

    #if DEBUG
    /// Demo setup only: start from a given engine.
    func demoReplaceEngine(_ engine: MasteryEngine) {
        self.engine = engine
        config = engine.config
    }
    #endif
}
