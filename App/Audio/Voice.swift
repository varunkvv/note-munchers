import AVFoundation
import NoteCore

/// Says NoteCore's `Speech` and the app's own lines with recorded clips. The kid never
/// sees text, so this is how the app talks to him.
///
/// The clips are in Resources/Voice, one per line, named `<situation>-<line>[-<note>].m4a`
/// (`meetNote-06-A`, `meetNote-06-Fs`, `hello-01`). tools/voice/voicebank.py makes them
/// from tools/voice/lines.json, the line sheet. Each situation has a few lines and it picks
/// one he hasn't heard lately. A missing clip says nothing. There's no synthesized
/// fallback on purpose.
@MainActor
final class Voice: NSObject, AVAudioPlayerDelegate {
    var isMuted = false
    /// DEBUG: print every line, so demo runs show what was said.
    var logs = false

    /// Lines the app says on its own (not from NoteCore).
    enum Line {
        /// a new muncher hatches
        case pickColor
        /// end screen, after NoteCore's "look who ate well today"
        case showGrownUp
        /// end screen after the "done for now" door: both of the above
        case lookAndShow
        /// end screen after the door, nothing played
        case seeYou
        case highFive
        case oneMore
        case allDone
    }

    private struct Clip {
        var name: String
        var line: Int
        /// the note it names, as in the file name ("A", "Fs"), or nil
        var note: String?
        var url: URL
    }

    /// situation -> its clips
    private let bank: [String: [Clip]]
    /// situation -> line numbers said lately, newest last. Kept across launches.
    private var recent: [String: [Int]]
    private static let recentKey = "voice.recent"
    private var player: AVAudioPlayer?
    /// Lines waiting for `player` to finish.
    private var queue: [AVAudioPlayer] = []
    private var sessionReady = false

    override init() {
        bank = Self.loadBank()
        recent = UserDefaults.standard.dictionary(forKey: Self.recentKey) as? [String: [Int]] ?? [:]
        super.init()
        #if DEBUG
        let missing = audit()
        print("voice: \(bank.values.map(\.count).reduce(0, +)) clips" + (missing.isEmpty ? ", every situation has one" : ", missing: \(missing.joined(separator: ", "))"))
        #endif
    }

    // MARK: saying things

    /// Says a line for this situation. A wrong-key line (almost, hints, oops) cuts off
    /// whatever she's saying, everything else waits its turn.
    /// Returns the seconds until this line is over (0 if nothing plays), so a sound can wait for it.
    @discardableResult
    func say(_ speech: Speech) -> TimeInterval {
        let cutsOff = switch speech {
        case .almost, .sharpHint, .hintListen, .hintShow, .hintLook, .oops: true
        default: false
        }
        return speak([Self.situation(of: speech)], cutOff: cutsOff)
    }

    @discardableResult
    func say(_ line: Line) -> TimeInterval {
        // a run of high-five taps shouldn't pile up a queue of them
        if line == .highFive, player != nil { return remaining }
        let parts: [(String, NoteName?)] = switch line {
        case .pickColor: [("hatch", nil)]
        case .showGrownUp: [("showGrownUp", nil)]
        case .lookAndShow: [("sessionDone", nil), ("showGrownUp", nil)]
        case .seeYou, .allDone: [("bye", nil)]
        case .highFive: [("highFive", nil)]
        case .oneMore: [("oneMore", nil)]
        }
        return speak(parts, cutOff: false)
    }

    func stop() {
        queue.removeAll()
        player?.stop()
        player = nil
    }

    /// Which lines fit: the situation (file name prefix) and the note they name.
    static func situation(of speech: Speech) -> (String, NoteName?) {
        switch speech {
        case .hello: ("hello", nil)
        case .meetNote(let name): ("meetNote", name)
        case .listen: ("listen", nil)
        case .twoAtOnce: ("twoAtOnce", nil)
        case .almost(let name, .higher): ("almostHigher", name)
        case .almost(let name, .lower): ("almostLower", name)
        case .almost(_, .middleC): ("almostMiddleC", nil)
        // the lines say "F sharp". another sharp would look for clips that don't exist
        case .sharpHint(let name): ("sharpHint", name == .fSharp ? nil : name)
        case .hintListen: ("hintListen", nil)
        case .hintShow(let name): ("hintShow", name)
        case .hintLook: ("hintLook", nil)
        case .oops: ("oops", nil)
        // process praise: what he did, never what he is (mueller & dweck). the line
        // sheet has no "smart", "genius", "good boy" or empty "great job"
        case .keptTrying: ("keptTrying", nil)
        case .lookedCarefully: ("lookedCarefully", nil)
        case .holdLonger: ("holdLonger", nil)
        case .turnOnPiano: ("turnOnPiano", nil)
        case .sessionDone: ("sessionDone", nil)
        }
    }

    private func speak(_ parts: [(String, NoteName?)], cutOff: Bool) -> TimeInterval {
        var players: [AVAudioPlayer] = []
        for (situation, note) in parts {
            guard let clip = pick(situation, note: note) else {
                #if DEBUG
                print("voice: missing \(situation)\(note.map { " " + $0.rawValue } ?? "")")
                #endif
                continue
            }
            if logs { print("voice: \(clip.name)") }
            guard !isMuted else { continue }
            do {
                let player = try AVAudioPlayer(contentsOf: clip.url)
                player.delegate = self
                player.prepareToPlay()
                players.append(player)
            } catch {
                #if DEBUG
                print("voice: can't open \(clip.name): \(error)")
                #endif
            }
        }
        guard !players.isEmpty else { return 0 }
        if cutOff { stop() }
        queue += players
        if player == nil { playNext() }
        if logs { print(String(format: "voice: over in %.1fs", remaining)) }
        return remaining
    }

    /// Seconds until everything playing or waiting is said.
    private var remaining: TimeInterval {
        (player.map { max(0, $0.duration - $0.currentTime) } ?? 0) + queue.map(\.duration).reduce(0, +)
    }

    private func playNext() {
        player = nil
        prepareSession()
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next.play() {
                player = next
                return
            }
            #if DEBUG
            print("voice: couldn't play \(next.url?.lastPathComponent ?? "a clip")")
            #endif
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(finished)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ failed: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(failed)
        Task { @MainActor in self.finished(id) }
    }

    private func finished(_ id: ObjectIdentifier) {
        // a line that was cut off doesn't move the queue on
        guard let player, ObjectIdentifier(player) == id else { return }
        playNext()
    }

    /// Same audio session as `Sounds`, in case she talks before the first sound.
    private func prepareSession() {
        #if os(iOS)
        guard !sessionReady else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .default)
        }
        try? session.setActive(true)
        sessionReady = true
        #endif
    }

    // MARK: the bank

    /// One he hasn't heard lately: never the last one, and not one of the last few
    /// when the situation has enough lines. Lines that name a note count together, so
    /// "this is D" and "this is G" from the same line are a repeat.
    private func pick(_ situation: String, note: NoteName?) -> Clip? {
        let clips = clips(situation, note: note)
        guard !clips.isEmpty else { return nil }
        let lines = Set(clips.map(\.line)).count
        let avoid = Set((recent[situation] ?? []).suffix(min(lines - 1, max(2, lines / 2), 3)))
        let fresh = clips.filter { !avoid.contains($0.line) }
        guard let clip = (fresh.isEmpty ? clips : fresh).randomElement() else { return nil }
        recent[situation] = Array(((recent[situation] ?? []) + [clip.line]).suffix(3))
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
        return clip
    }

    private func clips(_ situation: String, note: NoteName?) -> [Clip] {
        let tag = note.map(Self.fileTag)
        return (bank[situation] ?? []).filter { $0.note == tag }
    }

    /// "Fs" for F#, which can't be in a file name everywhere.
    private static func fileTag(_ name: NoteName) -> String {
        name == .fSharp ? "Fs" : name.rawValue
    }

    private static func loadBank() -> [String: [Clip]] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: "Voice") ?? []
        var bank: [String: [Clip]] = [:]
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "-").map(String.init)
            guard parts.count == 2 || parts.count == 3, let line = Int(parts[1]) else { continue }
            bank[parts[0], default: []].append(Clip(name: name, line: line, note: parts.count == 3 ? parts[2] : nil, url: url))
        }
        return bank
    }

    #if DEBUG
    /// Every situation the app can be asked to say, with every note a line can name,
    /// that has no clip.
    func audit() -> [String] {
        var speeches: [Speech] = [
            .hello, .listen, .twoAtOnce, .almost(.c, .middleC), .sharpHint(.fSharp), .hintListen, .hintLook,
            .oops, .keptTrying, .lookedCarefully, .holdLonger, .turnOnPiano, .sessionDone,
        ]
        for name in NoteName.allCases {
            speeches += [.meetNote(name), .hintShow(name), .almost(name, .higher), .almost(name, .lower)]
        }
        var asks = speeches.map(Self.situation(of:))
        asks += ["hatch", "showGrownUp", "bye", "highFive", "oneMore"].map { ($0, nil) }
        return asks.filter { clips($0.0, note: $0.1).isEmpty }.map { $0.0 + ($0.1.map { " " + $0.rawValue } ?? "") }
    }
    #endif
}
