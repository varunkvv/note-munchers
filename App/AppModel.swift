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

    /// Progress between sessions. A session works on its own copy and hands back the
    /// state after every item.
    private(set) var engine: MasteryEngine
    private(set) var config: NoteCoreConfig

    #if DEBUG
    let demo = DemoOptions()
    #endif

    init() {
        let config = NoteCoreConfig()
        self.config = config
        engine = MasteryEngine(config: config)
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
        controller.start()
    }

    /// Parent ends the session early. Every finished item is already saved.
    func leavePractice() {
        practice?.stop()
        practice = nil
        screen = .home
    }

    func goHome() {
        screen = .home
    }

    private func itemDone(_ attempt: AttemptResult, state: MasteryState) {
        engine = MasteryEngine(config: config, state: state)
    }

    private func sessionDone(_ summary: SessionSummary, state: MasteryState) {
        engine = MasteryEngine(config: config, state: state)
        lastSummary = summary
        practice = nil
        screen = .home
    }

    // MARK: parent changes (never during a session)

    func updateConfig(_ change: (inout NoteCoreConfig) -> Void) {
        change(&config)
        engine = MasteryEngine(config: config, state: engine.state)
    }

    func moveToUnit(_ number: Int) {
        guard practice == nil else { return }
        engine.moveToUnit(number)
    }

    #if DEBUG
    /// Demo setup only: start from a given engine.
    func demoReplaceEngine(_ engine: MasteryEngine) {
        self.engine = engine
        config = engine.config
    }
    #endif
}
