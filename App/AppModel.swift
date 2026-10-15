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
    }

    var screen: Screen = .home
    private(set) var practice: PracticeController?
    /// The last finished session, for the end screen.
    private(set) var lastSummary: SessionSummary?
    var showParent = false
    /// DEBUG demo: open the parent area on this page.
    var parentPage: String?

    let input = InputHub()
    let sounds = Sounds()
    let voice = Voice()
    let store: Store
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
        let (state, config) = store.loadMastery() ?? (MasteryState(), NoteCoreConfig())
        self.config = config
        engine = MasteryEngine(config: config, state: state)
        #if DEBUG
        let counts = store.counts()
        print("store: loaded unit \(engine.unit.number), \(engine.allProgress.count) items played, \(counts.attempts) attempts, \(counts.sessions) sessions\(store.isTemporary ? " (temporary)" : "")")
        #endif
    }

    /// Called once when the first window appears.
    func launch() {
        #if DEBUG
        // logs go to a file in agent runs. line buffered so a killed app still wrote them
        setvbuf(stdout, nil, _IOLBF, 0)
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
        controller.onItemDone = { [weak self] attempt, state in
            self?.itemDone(attempt, state: state)
        }
        controller.onSessionDone = { [weak self] summary, state in
            self?.sessionDone(summary, state: state)
        }
        practice = controller
        screen = .practice
        sessionStartedAt = Date()
        controller.start()
    }

    /// Parent ends the session early. Every finished item is already saved; the
    /// session still gets a history row if he played anything.
    func leavePractice() {
        if let practice {
            practice.stop()
            if practice.session.summary.itemsPlayed > 0 {
                store.addSession(practice.session.summary, startedAt: sessionStartedAt)
            }
        }
        practice = nil
        screen = .home
    }

    func goHome() {
        screen = .home
    }

    private func itemDone(_ attempt: AttemptResult, state: MasteryState) {
        engine = MasteryEngine(config: config, state: state)
        store.saveMastery(state, config: config)
        store.addAttempt(attempt)
    }

    private func sessionDone(_ summary: SessionSummary, state: MasteryState) {
        engine = MasteryEngine(config: config, state: state)
        store.saveMastery(state, config: config)
        store.addSession(summary, startedAt: sessionStartedAt)
        lastSummary = summary
        practice = nil
        screen = .home
    }

    // MARK: parent changes (never during a session)

    func updateConfig(_ change: (inout NoteCoreConfig) -> Void) {
        change(&config)
        engine = MasteryEngine(config: config, state: engine.state)
        store.saveMastery(engine.state, config: config)
    }

    func moveToUnit(_ number: Int) {
        guard practice == nil else { return }
        engine.moveToUnit(number)
        store.saveMastery(engine.state, config: config)
    }

    #if DEBUG
    /// Demo setup only: start from a given engine.
    func demoReplaceEngine(_ engine: MasteryEngine) {
        self.engine = engine
        config = engine.config
    }
    #endif
}
