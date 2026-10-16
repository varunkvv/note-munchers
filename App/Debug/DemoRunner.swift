#if DEBUG
import Foundation
import NoteCore

/// DEBUG launch arguments for driving the app without a piano (simulator, agents).
///
///     -demoScript <name>   play a scripted sequence through InputHub.emit (see DemoRunner.run).
///                          sharpPrompt / sharp stop on the next F# (sharp also presses F natural).
///                          wrongValue plays a rhythm screen's halves as quarters (the retry),
///                          keepGoing plays them short all three goes (then "let's keep going").
///                          play taps the play button after the first note and holds there,
///                          playAlong then finishes the screen while it's still playing
///                          show plays like a kid at -demoSlow from the start, for screen recordings
///                          kid plays a whole session like the scripted kid in QuietVoiceTests: about
///                          65% right first try, wrong keys (now and then three, so the keyboard
///                          picture comes up), the wrong octave, stuck past 15s now and then.
///                          Prints the clefs of the session (TTTBBB) at the end
///     -demoScreen <name>   open a screen directly: home, parent, parent#levels, parent#staff,
///                          parent#history, levels (the level picker), monitor, gallery
///                          (generated screens of -demoLesson)
///     -demoLesson <id>     start in lesson id (e.g. 2.5)
///     -demoLevel <n>       start in level n (its first lesson)
///     -demoMet YES         every note in the lesson already met (no intros or hatches)
///     -demoSize <n>        notes per screen to start at (kept inside the lesson's range)
///     -demoFirstClef <c>   treble|bass: the clef the session's first run is on (one-clef lessons
///                          without a focus clef)
///     -demoSeed <n>        fixed seed (screens and the kid's note draw), for repeatable screenshots
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
///     -demoAutoPick <s>    pick a hatching muncher's colour after s seconds (default 0.8)
///     -demoGate <how>      open|right|wrong: open the parent gate on home by itself and
///                          optionally answer it (read in ParentGate.swift)
///     -renderSongs <dir>   write one song per level with its backing (the Listen track) to
///                          <dir> as m4a, then quit. Not a demo, works best on the mac build
///     -demoSolid YES       every note in his level's song range is solid (box 4), so song
///                          time shows up (home, end screen) and the song scripts can run
///   song time scripts (with -demoSolid YES, -demoLevel n):
///     -demoScript song     a kid playing a song: the title card, then one note at a time
///                          (~1s each x -demoSlow), a wrong key now and then, the play
///                          button once, to the end card, then Listen
///     -demoScript songTitle  stays on the title card
///     -demoSongPage <n>    the song script stops when page n (1 = first) comes up
///     -demoSongStop <n>    ...or after n notes
///     -demoSongEnd YES     ...or jumps straight to the end card
///     -demoPath <x>        the level path: every lesson before his in the level done, his
///                          stone at x (0...0.9), for home / lane screenshots
struct DemoOptions {
    var script: String?
    var screen: String?
    var lesson: LessonID?
    var level: Int?
    var met = false
    var size: Int?
    var firstClef: Clef?
    var seed: UInt64?
    var slow = 1.0
    var progress = false
    var maxItems: Int?
    var landscape = false
    var persist = false
    var sound = false
    var debugKeyboard = false
    var logMIDI = false
    /// seconds before a demo picks a muncher colour by itself
    var autoPick = 0.8
    /// write the song renders here and quit
    var renderSongs: String?
    var solid = false
    var songPage: Int?
    var songStop: Int?
    var songEnd = false
    var path: Double?

    init(defaults: UserDefaults = .standard) {
        script = defaults.string(forKey: "demoScript")
        screen = defaults.string(forKey: "demoScreen")
        lesson = defaults.string(forKey: "demoLesson")
        level = defaults.string(forKey: "demoLevel").flatMap(Int.init)
        met = defaults.bool(forKey: "demoMet")
        size = defaults.string(forKey: "demoSize").flatMap(Int.init)
        firstClef = defaults.string(forKey: "demoFirstClef").flatMap(Clef.init(rawValue:))
        seed = defaults.string(forKey: "demoSeed").flatMap { UInt64($0) }
        slow = defaults.string(forKey: "demoSlow").flatMap(Double.init) ?? 1
        progress = defaults.bool(forKey: "demoProgress")
        maxItems = defaults.string(forKey: "demoMaxItems").flatMap(Int.init)
        landscape = defaults.bool(forKey: "demoLandscape")
        persist = defaults.bool(forKey: "demoPersist")
        sound = defaults.bool(forKey: "demoSound")
        debugKeyboard = defaults.bool(forKey: "debugKeyboard")
        logMIDI = defaults.bool(forKey: "logMIDI")
        autoPick = defaults.string(forKey: "demoAutoPick").flatMap(Double.init) ?? 0.8
        renderSongs = defaults.string(forKey: "renderSongs")
        solid = defaults.bool(forKey: "demoSolid")
        songPage = defaults.string(forKey: "demoSongPage").flatMap(Int.init)
        songStop = defaults.string(forKey: "demoSongStop").flatMap(Int.init)
        songEnd = defaults.bool(forKey: "demoSongEnd")
        path = defaults.string(forKey: "demoPath").flatMap(Double.init)
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
        var engine = options.persist ? model.engine : MasteryEngine(state: MasteryState(seed: options.seed ?? 1))
        if options.progress { engine = DemoHistory.seed(into: model.store) }
        if let maxItems = options.maxItems { engine.config.sessionMaxItems = maxItems }
        if let level = options.level { engine.moveToLevel(level) }
        if let lesson = options.lesson { engine.moveToLesson(lesson) }
        if options.met { engine = Self.meetEverything(engine) }
        if options.solid { engine = Self.solidEverything(engine) }
        if let size = options.size {
            var state = engine.state
            state.screenSize = size
            engine = MasteryEngine(config: engine.config, state: state)
        }
        if let first = options.firstClef {
            // the session starts on the clef the last one didn't
            var state = engine.state
            state.lastFirstClef = first == .treble ? .bass : .treble
            engine = MasteryEngine(config: engine.config, state: state)
        }
        if let path = options.path {
            var state = engine.state
            for lesson in engine.level.lessons.prefix(while: { $0.id != engine.lesson.id }) {
                state.completedLessons.insert(lesson.id)
            }
            state.lessonPeak = path
            engine = MasteryEngine(config: engine.config, state: state)
        }
        model.demoReplaceEngine(engine)

        Task { await run() }
    }

    // MARK: scripts

    private func run() async {
        await sleep(1.0)
        if let screen = options.screen {
            log("screen \(screen)")
            switch screen {
            case "gallery":
                model.galleryLesson = options.lesson ?? model.engine.lesson.id
            case "levels":
                model.parentPage = "levels"
                model.showParent = true
            case "parent":
                model.showParent = true
            case let page where page.hasPrefix("parent#"):
                model.parentPage = String(page.dropFirst("parent".count))
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
        if script.hasPrefix("song") {
            await runSong(script)
            return
        }
        model.startPractice()
        guard let c = model.practice else { return }
        // setup steps run fast. the slow factor is for the state being screenshotted.
        // show is recorded from the first hatch, so it's slow from the start
        c.timeScale = script == "show" ? options.slow : 0.3
        await waitUntil(seconds: 40) { c.phase != .notStarted }
        log("start", c)
        await sleep(0.6)

        switch script {
        case "intro":
            // a fresh kid's first screen is an intro: the muncher hatches, then keyboard picture up, "this is G"
            await waitUntil(seconds: 20) { !c.isHatching }
            c.timeScale = options.slow
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
        case "door":
            // a few right notes, then he taps "done for now"
            for _ in 0..<3 {
                let shown = c.itemsShown
                await playItem(c)
                await waitForNext(c, after: shown)
            }
            log("done for now", c)
            model.doneForNow()
        case "partial":
            // first note of a group or line right, then wait: played notes go grey
            await skipIntros(c)
            await right(c)
        case "chord":
            await skipIntros(c)
            c.holdAfterSuccess = true
            await playItem(c)
        case "rhythm":
            // play the line in time, then hold on the success
            await skipIntros(c)
            c.holdAfterSuccess = true
            await playItem(c)
        case "rhythmShort", "wrongValue", "keepGoing":
            // a rhythm-judged screen with a half, every half cut short: a wrong value, so
            // the glow, "it's a long one", the screen played back with the keyboard, then
            // his go again. rhythmShort stops there, wrongValue plays the retry right
            await skipIntros(c)
            for _ in 0..<40 {
                guard let item = c.item, let line = c.session.rhythmLine, c.phase.isPlaying else {
                    let shown = c.itemsShown
                    await playItem(c)
                    await waitForNext(c, after: shown)
                    continue
                }
                if item.notes.indices.dropLast().contains(where: { line.judged[$0] && item.notes[$0].value == .half }) { break }
                let shown = c.itemsShown
                await playItem(c)
                await waitForNext(c, after: shown)
            }
            c.timeScale = options.slow
            guard let item = c.item else { break }
            log("playing the halves short on \(item.id)", c)
            await playItem(c, stretch: item.notes.map { $0.value == .half ? 0.45 : 1 })
            await waitUntil(seconds: 5) { c.phase == .replaying }
            log("wrong value, playing it back", c)
            if script == "keepGoing" {
                for go in 2...3 {
                    await waitUntil(seconds: 60) { c.phase.isPlaying }
                    await playItem(c, stretch: item.notes.map { $0.value == .half ? 0.45 : 1 })
                    await sleep(1.0)
                    log("go \(go) played short", c)
                }
                break
            }
            guard script == "wrongValue" else { break }
            await waitUntil(seconds: 60) { c.phase.isPlaying }
            log("his go again", c)
            c.holdAfterSuccess = true
            await playItem(c)
            await sleep(1.0)
            log("retry played: retries \(c.session.summary.screens.last?.rhythmRetries ?? -1)", c)
        case "play", "playAlong":
            // the play button after his first note: the screen plays with the keyboard.
            // playAlong then finishes the screen while it's still playing
            await skipIntros(c)
            await right(c)
            await sleep(0.6)
            c.listen()
            log("play button", c)
            guard script == "playAlong" else { break }
            let shown = c.itemsShown
            await playItem(c)
            await waitForNext(c, after: shown)
            await sleep(0.5)
            log("next screen: keys \(c.playingKeys.map { "\($0)" } ?? "none"), playing \(c.isPlayingBack)", c)
        case "almost":
            await skipIntros(c)
            await wrongOctave(c)
        case "sharp", "sharpPrompt":
            // right notes until an F# is next, then (sharp) the F natural next to it:
            // "that's F - this one is F sharp, the black key"
            await skipIntros(c)
            for _ in 0..<200 {
                guard let item = c.item, c.phase.isPlaying else { break }
                if !item.notes[c.session.noteIndex].pitches[0].isWhiteKey { break }
                let shown = c.itemsShown
                await right(c)
                if c.phase == .success { await waitForNext(c, after: shown) }
            }
            c.timeScale = options.slow
            guard script == "sharp", let item = c.item, c.phase.isPlaying else {
                log("on an F#", c)
                break
            }
            let natural = Pitch(midi: item.notes[c.session.noteIndex].pitches[0].midi - 1)
            await press([natural])
            log("natural \(natural.name) on an F#", c)
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
        case "hatch":
            // a new note's muncher hatches right before its intro. stops there so the
            // colour picker can be screenshotted (use -demoAutoPick 60)
            await waitUntil(seconds: 60) { c.isHatching }
            c.timeScale = options.slow
            log("hatching \(c.hatchQueue)", c)
        case "learn":
            // right first try, quickly
            var rounds = 0
            while c.phase.isPlaying, rounds < 200 {
                rounds += 1
                let shown = c.itemsShown
                await playItem(c)
                await waitForNext(c, after: shown)
            }
            log("learn finished after \(rounds) rounds", c)
            logClefs(c)
        case "show":
            // a kid playing, for screen recordings: a look at each screen, then one note
            // at a time at his pace, now and then a wrong key first. hatches pick by
            // themselves (-demoAutoPick). runs to the end screen
            var round = 0
            while c.phase != .done, round < 200 {
                round += 1
                let shown = c.itemsShown
                await waitUntil(seconds: 60) { !c.isHatching }
                await sleep((c.session.isIntro ? 1.6 : 1.0) * options.slow)
                if c.session.rhythmLine != nil {
                    await playItem(c)
                } else {
                    if !c.session.isIntro, round % 4 == 3 {
                        await wrong(c)
                        await sleep(0.8 * options.slow)
                    }
                    while c.phase.isPlaying, c.itemsShown == shown {
                        await right(c)
                        await sleep(0.75 * options.slow)
                    }
                }
                await waitForNext(c, after: shown)
            }
            log("show finished after \(round) rounds", c)
            logClefs(c)
        case "kid":
            await kid(c)
        default:
            log("unknown script \(script)")
        }
    }

    /// One full session played like QuietVoiceTests' scripted kid, at a kid's pace. The
    /// voice log (`voice: ...`) shows every line she says.
    private func kid(_ c: PracticeController) async {
        var dice = SeededRandom(seed: (options.seed ?? 1) &+ 0xD1CE)
        var round = 0
        while c.phase != .done, round < 80 {
            round += 1
            let shown = c.itemsShown
            await waitUntil(seconds: 60) { !c.isHatching }
            await sleep(0.8)
            while c.phase.isPlaying, c.itemsShown == shown {
                guard !c.session.isIntro else {
                    await right(c)
                    continue
                }
                let roll = Double(dice.next() >> 11) * 0x1p-53
                if roll < 0.65 {
                    // right first try
                } else if roll < 0.80 {
                    let tries = dice.next() % 3 == 0 ? 3 : 1
                    for _ in 0..<tries { await wrong(c) }
                } else if roll < 0.90 {
                    await wrongOctave(c)
                } else {
                    log("stuck", c)
                    await sleep(c.session.engine.config.stuckAfter + 0.5)
                }
                await right(c)
                await sleep(0.4)
            }
            await waitForNext(c, after: shown)
        }
        log("kid finished after \(round) rounds", c)
        logClefs(c)
    }

    /// The session's clefs, one letter a screen (lower case for a new note's intro), e.g.
    /// `TtTTT...BBB`.
    private func logClefs(_ c: PracticeController) {
        let screens = c.session.summary.screens
        let clefs = screens.map { screen -> String in
            let letter = screen.screenID.hasPrefix("bass") ? "B" : "T"
            return screen.wasIntro ? letter.lowercased() : letter
        }.joined()
        log("clefs \(clefs) (\(screens.count) screens, lesson \(c.session.summary.startLesson) -> \(c.session.summary.endLesson))")
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
        logClefs(c)
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
        await waitUntil(seconds: 30) { !c.isHatching }
        guard let item = c.item, c.phase.isPlaying else { return }
        let pitches = item.notes[c.session.noteIndex].pitches
        let label = "\(item.id)\(c.session.isIntro ? " (intro)" : "")"
        await press(pitches)
        log("right \(pitches.map(\.name)) on \(label)", c)
    }

    private func wrong(_ c: PracticeController) async {
        await waitUntil(seconds: 30) { !c.isHatching }
        guard let item = c.item, c.phase.isPlaying else { return }
        // two white keys up: never the right letter
        let pitches = item.notes[c.session.noteIndex].pitches.map { whiteKey($0, steps: 2) }
        await press(pitches)
        log("wrong \(pitches.map(\.name))", c)
    }

    private func wrongOctave(_ c: PracticeController) async {
        await waitUntil(seconds: 30) { !c.isHatching }
        guard let item = c.item, c.phase.isPlaying else { return }
        let pitches = item.notes[c.session.noteIndex].pitches.map { Pitch(midi: $0.midi + 12) }
        await press(pitches)
        log("wrong octave \(pitches.map(\.name))", c)
    }

    /// Plays every remaining note of the item. Rhythm items at a steady beat;
    /// `stretch` scales each note's length (e.g. 0.5 plays a half as a quarter).
    private func playItem(_ c: PracticeController, beat: Double = 0.5, stretch: [Double]? = nil) async {
        await waitUntil(seconds: 30) { !c.isHatching }
        guard let item = c.item, c.phase.isPlaying else { return }
        if c.session.rhythmLine != nil || c.session.engine.lesson.texture.isRhythm {
            for index in c.session.noteIndex..<item.notes.count {
                let pitches = item.notes[index].pitches
                let length = item.gapBeats[index] * beat * (stretch?[index] ?? 1)
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

    private func waitUntil(seconds: Double = 10, _ condition: () -> Bool) async {
        for _ in 0..<Int(seconds / 0.05) where !condition() {
            await sleep(0.05)
        }
    }

    private func repeatEffect(_ kind: StaffEffects.Kind, _ c: PracticeController) async {
        var column = max(0, c.doneCount - (kind == .sparkle ? 1 : 0))
        if kind == .glow, let nudge = c.session.summary.screens.last?.rhythm?.nudgeIndex {
            column = nudge
        }
        while true {
            await sleep(1.6 * options.slow)
            c.demoReplay(kind, column: column)
        }
    }

    // MARK: song time

    private func runSong(_ script: String) async {
        model.startSong()
        guard let c = model.song else {
            log("song: no song (does he have 3 solid notes with G and A? try -demoSolid YES)")
            return
        }
        c.timeScale = options.slow
        log("song: \(c.song.title), \(c.pages.count) pages, \(c.song.notes.count) notes")
        guard script == "song" else { return }
        await sleep(2.5 * options.slow)
        c.start()
        log("song: let's play")
        if options.songEnd {
            await sleep(0.5)
            c.demoSkipToEnd()
            log("song: end card")
            return
        }
        await sleep(1.6 * options.slow)
        var heard = false
        var played = 0
        while c.phase == .playing {
            if let page = options.songPage, c.page + 1 >= page {
                log("song: on page \(c.page + 1)")
                return
            }
            if let stop = options.songStop, played >= stop {
                log("song: stopped after \(played) notes")
                return
            }
            if !heard, played == 2 {
                heard = true
                c.hearIt()
                log("song: play button")
                await waitUntil(seconds: 30) { !c.isPlayingBack }
                await sleep(0.8 * options.slow)
            }
            if played % 7 == 5 {
                let wrong = c.expected.map { whiteKey($0, steps: 2) }
                await press(wrong)
                log("song: wrong \(wrong.map(\.name))")
                await sleep(0.9 * options.slow)
            }
            let page = c.page
            let keys = c.expected
            await press(keys)
            played += 1
            log("song: right \(keys.map(\.name)) (note \(played))")
            // a look at a new page before playing on, like reading it
            await sleep((c.page != page ? 1.6 : 0.85) * options.slow)
        }
        await waitUntil(seconds: 30) { c.phase == .end }
        log("song: end card")
        await sleep(2.5 * options.slow)
        c.listen()
        log("song: listen")
        await waitUntil(seconds: 90) { c.phase == .end }
        log("song: listen over")
    }

    /// Every note in his level's song range at box 4 with a few right answers (`-demoSolid`).
    static func solidEverything(_ engine: MasteryEngine) -> MasteryEngine {
        var state = engine.state
        for clef in Clef.allCases {
            for pitch in MasteryEngine.songRange(level: engine.lesson.level, clef: clef) {
                let id = NoteKey(clef, pitch).id
                var stats = state.stats[id] ?? ItemStats()
                stats.box = max(stats.box, 4)
                stats.attempts = max(stats.attempts, 6)
                stats.firstTryCount = max(stats.firstTryCount, 6)
                stats.recent = Array(repeating: AttemptSample(firstTry: true, responseTime: 1.5), count: 6)
                stats.peakFluency = max(stats.peakFluency, 0.55)
                state.stats[id] = stats
                state.unlocked.insert(id)
                state.introduced.insert(id)
            }
        }
        state.newest = [:]
        return MasteryEngine(config: engine.config, state: state)
    }

    /// Every note waiting for its intro gets one, as if he'd met them all (`-demoMet`).
    static func meetEverything(_ engine: MasteryEngine) -> MasteryEngine {
        var engine = engine
        let lesson = engine.lesson
        for key in engine.pendingIntros {
            let note = AttemptResult(itemID: key.id, lesson: lesson.id, level: lesson.level, wasIntro: true, firstTry: true, responseTime: 2)
            engine.record(ScreenResult(screenID: key.id, lesson: lesson.id, wasIntro: true, notes: [note], size: 1))
        }
        return engine
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
        print("demo: \(message) | phase=\(c.phase.rawValue) lesson=\(c.session.engine.lesson.id) size=\(c.session.engine.screenSize) screen=\(c.item?.id ?? "-") note=\(c.session.noteIndex) intro=\(c.session.isIntro) keyboard=[\(hint)] screens=\(c.session.summary.screensPlayed) unlocked=\(c.session.summary.unlocked)")
    }
}
#endif
