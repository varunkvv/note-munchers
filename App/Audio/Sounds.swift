import AVFoundation
import NoteCore

/// Chime, chomp, hint pitches and phrase playback.
///
/// Every sound is rendered up front into a PCM buffer and played on a small pool of
/// player nodes, so there's no render callback and no audio-thread state to guard.
@MainActor
final class Sounds {
    /// DEBUG demo runs are silent unless asked, so screenshot runs don't make noise.
    var isMuted = false

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    /// Song time: short backing parts (fillers), each on its own node so one never cuts another.
    private var backingPlayers: [AVAudioPlayerNode] = []
    private var nextBacking = 0
    /// Song time: the chord that rings with his key. Two, so the old one can be damped
    /// while the new one starts.
    private var heldPlayers: [AVAudioPlayerNode] = []
    private var nextHeld = 0
    /// Song time: the whole Listen track.
    private let trackPlayer = AVAudioPlayerNode()
    private var dampTask: Task<Void, Never>?

    init() {
        for _ in 0..<8 {
            players.append(attach())
        }
        for _ in 0..<10 { backingPlayers.append(attach()) }
        for _ in 0..<2 { heldPlayers.append(attach()) }
        engine.attach(trackPlayer)
        engine.connect(trackPlayer, to: engine.mainMixerNode, format: format)
    }

    private func attach() -> AVAudioPlayerNode {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        return player
    }

    // MARK: what the app plays

    /// Right key: a soft two-note bell.
    func chime() {
        play(cached("chime") { Synth.chime(format: $0) })
    }

    /// A muncher eats the note.
    func chomp() {
        play(cached("chomp") { Synth.chomp(format: $0) })
    }

    /// A high five.
    func clap() {
        play(cached("clap") { Synth.clap(format: $0) })
    }

    /// An egg hatches.
    func pop() {
        play(cached("pop") { Synth.pop(format: $0) })
    }

    /// Hint: the right key(s), sounded together.
    func play(_ pitches: [Pitch]) {
        let key = "pitch:" + pitches.map { String($0.midi) }.joined(separator: ",")
        play(cached(key) { Synth.tone(pitches.map(\.midi), duration: 1.2, format: $0) })
    }

    /// Plays an item back (rhythm lines get played to him before he tries them).
    func play(_ phrase: [ScheduledNote]) {
        guard let buffer = Synth.phrase(phrase, format: format) else { return }
        play(buffer)
    }

    // MARK: song time

    /// A moment of the song's backing (Piano + SongMix), at `time` on the host clock or
    /// now. `held`: the chord that sounds with his key and rings while he looks for the
    /// next one. The one before it is damped (a quick fade, like lifting the hands).
    func playBacking(_ buffer: AVAudioPCMBuffer?, at time: Double? = nil, held: Bool) {
        guard !isMuted, let buffer, ensureRunning() else { return }
        let player: AVAudioPlayerNode
        if held {
            let old = heldPlayers[nextHeld]
            nextHeld = (nextHeld + 1) % heldPlayers.count
            player = heldPlayers[nextHeld]
            damp(old)
            player.stop()
            player.volume = 1
        } else {
            player = backingPlayers[nextBacking]
            nextBacking = (nextBacking + 1) % backingPlayers.count
            player.stop()
        }
        player.scheduleBuffer(buffer, at: time.map { AVAudioTime(hostTime: HostClock.hostTime(seconds: $0)) }, options: [])
        player.play()
    }

    /// Fades a node out over ~0.15s, then stops it.
    private func damp(_ player: AVAudioPlayerNode) {
        guard player.isPlaying else { return }
        dampTask?.cancel()
        dampTask = Task { @MainActor in
            for step in 1...6 {
                try? await Task.sleep(for: .milliseconds(25))
                guard !Task.isCancelled else { break }
                player.volume = Float(1 - Double(step) / 6)
            }
            player.stop()
            player.volume = 1
        }
    }

    /// Everything the song's backing has playing or waiting stops (leaving the song).
    func stopBacking() {
        dampTask?.cancel()
        for player in backingPlayers + heldPlayers {
            player.stop()
            player.volume = 1
        }
    }

    /// Listen: the whole song as one track.
    func playTrack(_ buffer: AVAudioPCMBuffer?) {
        guard !isMuted, let buffer, ensureRunning() else { return }
        trackPlayer.stop()
        trackPlayer.scheduleBuffer(buffer, at: nil, options: [])
        trackPlayer.play()
    }

    func stopTrack() {
        trackPlayer.stop()
    }

    /// Call when the app comes back to the foreground.
    func resume() {
        _ = ensureRunning()
    }

    // MARK: plumbing

    private func cached(_ key: String, render: (AVAudioFormat) -> AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
        if let buffer = cache[key] { return buffer }
        let buffer = render(format)
        cache[key] = buffer
        return buffer
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard !isMuted, let buffer, ensureRunning() else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            #endif
            try engine.start()
            return true
        } catch {
            // the simulator sometimes has no output. never crash over a sound
            print("audio: engine start failed: \(error)")
            return false
        }
    }
}

/// Offline synthesis of the app's few sounds. Mono float buffers.
enum Synth {
    static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    private static func buffer(seconds: Double, format: AVAudioFormat, fill: (UnsafeMutablePointer<Float>, Int, Double) -> Void) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }
        fill(data, Int(frames), format.sampleRate)
        return buffer
    }

    /// Piano-ish: a few harmonics, quick attack, the higher ones die faster.
    private static func addTone(_ data: UnsafeMutablePointer<Float>, frames: Int, rate: Double, midi: Int, start: Int, duration: Double, gain: Double) {
        let f = frequency(midi)
        let harmonics: [(Double, Double)] = [(1, 1), (2, 0.42), (3, 0.2), (4, 0.09), (5, 0.04)]
        let length = min(frames - start, Int((duration + 0.5) * rate))
        guard length > 0 else { return }
        let release = Int(duration * rate)
        for i in 0..<length {
            let t = Double(i) / rate
            let attack = min(1, t / 0.004)
            var tail = 1.0
            if i > release { tail = max(0, 1 - Double(i - release) / (0.5 * rate)) }
            var sample = 0.0
            for (n, amp) in harmonics where f * n < rate / 2 {
                sample += amp * exp(-t * (1.6 + n * 1.1)) * sin(2 * .pi * f * n * t)
            }
            data[start + i] += Float(sample * attack * tail * gain)
        }
    }

    static func tone(_ midis: [Int], duration: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        buffer(seconds: duration + 0.5, format: format) { data, frames, rate in
            let gain = 0.45 / Double(max(1, midis.count))
            for midi in midis {
                addTone(data, frames: frames, rate: rate, midi: midi, start: 0, duration: duration, gain: gain)
            }
        }
    }

    static func phrase(_ notes: [ScheduledNote], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let last = notes.map({ $0.start + $0.duration }).max() else { return nil }
        return buffer(seconds: last + 0.6, format: format) { data, frames, rate in
            for note in notes {
                let gain = 0.45 / Double(max(1, note.pitches.count))
                for pitch in note.pitches {
                    // release a touch early so repeated notes are heard as separate presses
                    addTone(data, frames: frames, rate: rate, midi: pitch.midi, start: Int(note.start * rate),
                            duration: max(0.05, note.duration * 0.85), gain: gain)
                }
            }
        }
    }

    /// Soft bell: C6 then G6, sine plus a faint inharmonic partial.
    static func chime(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        buffer(seconds: 1.1, format: format) { data, frames, rate in
            for (f, offset) in [(1046.5, 0.0), (1568.0, 0.07)] {
                let start = Int(offset * rate)
                for i in 0..<(frames - start) {
                    let t = Double(i) / rate
                    let env = min(1, t / 0.003) * exp(-t * 4.5)
                    let s = sin(2 * .pi * f * t) + 0.15 * sin(2 * .pi * f * 2.76 * t) * exp(-t * 8)
                    data[start + i] += Float(0.12 * env * s)
                }
            }
        }
    }

    /// "nom nom": two short low bites with a little crunch.
    static func chomp(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        buffer(seconds: 0.4, format: format) { data, frames, rate in
            var seed: UInt32 = 12345
            for offset in [0.0, 0.17] {
                let start = Int(offset * rate)
                let length = Int(0.12 * rate)
                var phase = 0.0
                for i in 0..<min(length, frames - start) {
                    let t = Double(i) / rate
                    let f = 230 - 1000 * t // falls ~230 -> 110 Hz
                    phase += 2 * .pi * f / rate
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
                    let env = min(1, t / 0.005) * max(0, 1 - t / 0.12)
                    data[start + i] += Float(env * (0.32 * sin(phase) + 0.07 * noise))
                }
            }
        }
    }

    /// A clap: a short bright noise burst.
    static func clap(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        buffer(seconds: 0.25, format: format) { data, frames, rate in
            var seed: UInt32 = 987_654
            var low = 0.0
            for i in 0..<frames {
                let t = Double(i) / rate
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
                low += 0.25 * (noise - low)
                let env = min(1, t / 0.002) * exp(-t * 38)
                data[i] += Float(0.5 * env * (noise - low))
            }
        }
    }

    /// A quick rising pop for an egg hatching.
    static func pop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        buffer(seconds: 0.25, format: format) { data, frames, rate in
            var phase = 0.0
            for i in 0..<frames {
                let t = Double(i) / rate
                phase += 2 * .pi * (420 + 2400 * t) / rate
                let env = min(1, t / 0.004) * exp(-t * 14)
                data[i] += Float(0.25 * env * sin(phase))
            }
        }
    }
}
