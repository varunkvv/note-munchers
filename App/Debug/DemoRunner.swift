#if DEBUG
import Foundation
import NoteCore

/// DEBUG launch arguments for driving the app without a piano (simulator, agents).
///
///     -demoScript <name>   play a scripted sequence through InputHub.emit (see DemoRunner.run)
///     -demoScreen <name>   open a screen directly: parent, monitor, gallery, end, munchers
///     -demoUnit <n>        start in unit n
///     -demoSeed <n>        fixed picker seed, for repeatable screenshots
///     -demoSlow <x>        stretch animations and delays x times
///     -demoProgress YES    fake a few weeks of history first
///     -demoMaxItems <n>    session length in items
///     -demoLandscape YES   draw the app at landscape size, turned 90 degrees inside the
///                          portrait screen. iPadOS windowing refuses programmatic rotation
///                          and simctl can't rotate, so this is how screenshots see landscape
///     -demoPersist YES     use the real store instead of an in-memory one
///     -demoSound YES       make sound (demo runs are silent by default)
///     -debugKeyboard YES   show the on-screen keyboard (not a demo, works with MIDI too)
///     -logMIDI YES         print every input event and MIDI source change (not a demo)
struct DemoOptions {
    var script: String?
    var screen: String?
    var unit: Int?
    var seed: UInt64?
    var slow = 1.0
    var progress = false
    var maxItems: Int?
    var landscape = false
    var persist = false
    var sound = false
    var debugKeyboard = false
    var galleryUnit: Int?
    var logMIDI = false

    init(defaults: UserDefaults = .standard) {
        script = defaults.string(forKey: "demoScript")
        screen = defaults.string(forKey: "demoScreen")
        unit = defaults.string(forKey: "demoUnit").flatMap(Int.init)
        seed = defaults.string(forKey: "demoSeed").flatMap { UInt64($0) }
        slow = defaults.string(forKey: "demoSlow").flatMap(Double.init) ?? 1
        progress = defaults.bool(forKey: "demoProgress")
        maxItems = defaults.string(forKey: "demoMaxItems").flatMap(Int.init)
        landscape = defaults.bool(forKey: "demoLandscape")
        persist = defaults.bool(forKey: "demoPersist")
        sound = defaults.bool(forKey: "demoSound")
        debugKeyboard = defaults.bool(forKey: "debugKeyboard")
        galleryUnit = defaults.string(forKey: "demoGalleryUnit").flatMap(Int.init)
        logMIDI = defaults.bool(forKey: "logMIDI")
    }

    var isActive: Bool { script != nil || screen != nil }
}

/// Plays scripted key presses through the same input path as the piano, so every
/// kid screen state can be reached and screenshotted on a simulator.
@MainActor
final class DemoRunner {
    private static var current: DemoRunner?

    let model: AppModel
    let options: DemoOptions

    init(model: AppModel, options: DemoOptions) {
        self.model = model
        self.options = options
    }

    func begin() {
        Self.current = self
        model.sounds.isMuted = !options.sound
        model.voice.isMuted = !options.sound
        model.voice.logs = true
        model.input.demoConnected = true
        if options.debugKeyboard { model.input.debugKeyboardOn = true }

        // in-memory store: start fresh. -demoPersist: keep what the real store loaded
        var engine = options.persist ? model.engine : MasteryEngine()
        if let maxItems = options.maxItems { engine.config.sessionMaxItems = maxItems }
        if let unit = options.unit { engine.moveToUnit(unit) }
        model.demoReplaceEngine(engine)

        Task { await run() }
    }

    // MARK: scripts

    private func run() async {
        await sleep(1.0)
        if let screen = options.screen {
            log("screen \(screen)")
            switch screen {
            case "parent":
                model.showParent = true
            case "monitor":
                model.parentPage = "monitor"
                model.showParent = true
                await sleep(1.5)
                // a few keys across the range, through the same path as the piano
                for name in ["C4", "G4", "E5", "A2", "F3", "C6", "B3", "D4", "C2", "G5"] {
                    let pitch = Pitch(name)!
                    model.input.emit(.on(pitch, velocity: 70, at: HostClock.now))
                    await sleep(0.1)
                    model.input.emit(.off(pitch, at: HostClock.now))
                    await sleep(0.1)
                }
            default:
                break
            }
            return
        }
        guard let script = options.script else { return }
        model.startPractice()
        guard let c = model.practice else { return }
        // setup steps run fast. the slow factor is for the state being screenshotted
        c.timeScale = 0.3
        log("start", c)
        await sleep(0.6)

        switch script {
        case "intro":
            c.timeScale = options.slow // first item is an intro: keyboard picture up, "here's a new one"
        case "prompt":
            await skipIntros(c)
        case "wobble":
            await skipIntros(c)
            await wrong(c)
            await repeatEffect(.wobble, c)
        case "hint1":
            await skipIntros(c)
            await wrong(c)
            await wrong(c)
            while true {
                await sleep(2.2 * options.slow)
                c.demoRepeatSoundHint()
            }
        case "hint2":
            await skipIntros(c)
            await wrong(c)
            await wrong(c)
            await wrong(c)
        case "almost":
            await skipIntros(c)
            await wrongOctave(c)
        case "success":
            await skipIntros(c)
            c.holdAfterSuccess = true
            await playItem(c)
            await repeatEffect(.sparkle, c)
        case "piano":
            await skipIntros(c)
            model.input.demoConnected = false
            log("piano off", c)
        case "pianoBack":
            await skipIntros(c)
            await wrong(c)
            model.input.demoConnected = false
            log("piano off", c)
            await sleep(2)
            model.input.demoConnected = true
            await waitUntil { c.phase.isPlaying }
            log("piano back", c)
            let shown = c.itemsShown
            await playItem(c)
            await waitForNext(c, after: shown)
            log("after resume", c)
        case "tour":
            await tour(c)
        case "learn", "hatch":
            // right first try, quickly, until something unlocks (hatch holds there)
            c.holdOnUnlock = script == "hatch"
            var rounds = 0
            while c.phase.isPlaying, rounds < 200 {
                rounds += 1
                let shown = c.itemsShown
                await playItem(c)
                if script == "hatch", !c.hatching.isEmpty {
                    c.timeScale = options.slow
                    log("unlocked \(c.hatching)", c)
                    return
                }
                await waitForNext(c, after: shown)
            }
            log("learn finished after \(rounds) rounds", c)
        default:
            log("unknown script \(script)")
        }
    }

    /// One full session with wrong keys, a wrong octave, a dropped piano and right keys,
    /// logged step by step.
    private func tour(_ c: PracticeController) async {
        var round = 0
        while c.phase != .done, round < 60 {
            round += 1
            let shown = c.itemsShown
            if c.session.isIntro {
                await playItem(c)
            } else {
                switch round % 5 {
                case 0:
                    await wrong(c)
                    await wrong(c)
                    await wrong(c)
                case 1:
                    await wrongOctave(c)
                case 2:
                    await wrong(c)
                case 3 where round == 8:
                    model.input.demoConnected = false
                    log("piano off", c)
                    await sleep(1)
                    model.input.demoConnected = true
                    await waitUntil { c.phase.isPlaying }
                    log("piano back", c)
                default:
                    break
                }
                await playItem(c)
            }
            await waitForNext(c, after: shown)
        }
        log("tour finished after \(round) rounds", c)
    }

    // MARK: steps

    private func skipIntros(_ c: PracticeController) async {
        while c.session.isIntro, c.phase.isPlaying {
            let shown = c.itemsShown
            await playItem(c)
            await waitForNext(c, after: shown)
        }
        c.timeScale = options.slow
        log("intros done", c)
    }

    /// The right key(s) for the note he's on.
    private func right(_ c: PracticeController) async {
        guard let item = c.item, c.phase.isPlaying else { return }
        let pitches = item.notes[c.session.noteIndex].pitches
        let label = "\(item.id)\(c.session.isIntro ? " (intro)" : "")"
        await press(pitches)
        log("right \(pitches.map(\.name)) on \(label)", c)
    }

    private func wrong(_ c: PracticeController) async {
        guard let item = c.item, c.phase.isPlaying else { return }
        // two white keys up: never the right letter
        let pitches = item.notes[c.session.noteIndex].pitches.map { whiteKey($0, steps: 2) }
        await press(pitches)
        log("wrong \(pitches.map(\.name))", c)
    }

    private func wrongOctave(_ c: PracticeController) async {
        guard let item = c.item, c.phase.isPlaying else { return }
        let pitches = item.notes[c.session.noteIndex].pitches.map { Pitch(midi: $0.midi + 12) }
        await press(pitches)
        log("wrong octave \(pitches.map(\.name))", c)
    }

    /// Plays every remaining note of the item. Rhythm items at a steady beat;
    /// `stretch` scales each note's length (e.g. 0.5 plays a half as a quarter).
    private func playItem(_ c: PracticeController, beat: Double = 0.5, stretch: [Double]? = nil) async {
        guard let item = c.item, c.phase.isPlaying else { return }
        if item.isRhythm {
            for index in c.session.noteIndex..<item.notes.count {
                let pitches = item.notes[index].pitches
                let length = (item.notes[index].value?.beats ?? 1) * beat * (stretch?[index] ?? 1)
                for p in pitches { model.input.emit(.on(p, at: HostClock.now)) }
                await sleep(length * 0.8)
                for p in pitches { model.input.emit(.off(p, at: HostClock.now)) }
                await sleep(length * 0.2)
            }
            log("played rhythm line", c)
            return
        }
        let shown = c.itemsShown
        while c.phase.isPlaying, c.itemsShown == shown, c.item == item {
            await right(c)
            await sleep(0.3)
        }
    }

    private func press(_ pitches: [Pitch]) async {
        for p in pitches {
            model.input.emit(.on(p, at: HostClock.now))
            await sleep(0.02)
        }
        await sleep(0.12)
        for p in pitches { model.input.emit(.off(p, at: HostClock.now)) }
        // past the extra-key ignore window before the next press
        await sleep(0.25)
    }

    /// Waits until a later item than `shown` is up (or the session is over).
    private func waitForNext(_ c: PracticeController, after shown: Int) async {
        for _ in 0..<600 {
            if c.phase == .done || (c.phase.isPlaying && c.itemsShown > shown) { return }
            await sleep(0.05)
        }
        log("waitForNext timed out", c)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await sleep(0.05)
        }
    }

    private func repeatEffect(_ kind: StaffEffects.Kind, _ c: PracticeController) async {
        let column = max(0, c.doneCount - (kind == .sparkle ? 1 : 0))
        while true {
            await sleep(1.6 * options.slow)
            c.demoReplay(kind, column: column)
        }
    }

    private func whiteKey(_ pitch: Pitch, steps: Int) -> Pitch {
        var midi = pitch.midi
        var moved = 0
        while moved < steps {
            midi += 1
            if Pitch(midi: midi).isWhiteKey { moved += 1 }
        }
        return Pitch(midi: midi)
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func log(_ message: String, _ c: PracticeController? = nil) {
        guard let c else {
            print("demo: \(message)")
            return
        }
        let hint = c.session.keyboardHint.map(\.name).joined(separator: ",")
        print("demo: \(message) | phase=\(c.phase.rawValue) unit=\(c.session.engine.unit.number) item=\(c.item?.id ?? "-") note=\(c.session.noteIndex) intro=\(c.session.isIntro) keyboard=[\(hint)] played=\(c.session.summary.itemsPlayed) unlocked=\(c.session.summary.unlocked)")
    }
}
#endif
