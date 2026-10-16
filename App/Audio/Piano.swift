import Accelerate
import AVFoundation
import NoteCore

/// A sampled piano for song time: the backing that follows him, and Listen.
///
/// The samples are 17 notes of the Salamander Grand Piano (Alexander Holm, CC BY 3.0,
/// see Resources/Piano/LICENSE.txt), C2 to C6 a minor third apart. Any key plays its
/// nearest sample pitched at most a tone and a half, so it still sounds like that piano.
/// The app's chime synth (Sounds.swift) is fine for a bell and a hint, but block chords
/// through it sound like an organ toy: a few sine harmonics, no hammer, no body.
///
/// Everything renders to plain mono sample arrays with vDSP. One function mixes a list of
/// notes, so a live chord, the whole Listen track and the files in
/// artifacts/free-play/renders all come out of the same code.
@MainActor
final class Piano {
    static let rate = 44_100.0
    static let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!

    /// Root key and samples, low to high.
    private let samples: [(midi: Int, data: [Float])]
    /// Each key once pitched, full length, unit gain.
    private var pitched: [Int: [Float]] = [:]

    /// One note to sound: when (seconds from the start of the mix), which key, how loud
    /// (linear), and how long it's held before the release.
    struct Note {
        var time: Double
        var midi: Int
        var gain: Double
        var length: Double
    }

    /// The release after a note is let go: a short fade, like a damper coming down.
    static let release = 0.22
    /// A rolled chord's notes, low to high, this far apart.
    static let roll = 0.04

    init?(bundle: Bundle = .main) {
        guard let folder = bundle.url(forResource: "Piano", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return nil }
        var loaded: [(midi: Int, data: [Float])] = []
        for url in files where url.pathExtension == "m4a" {
            // "C4", "Ds4" (D sharp), "Fs4"
            let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "s", with: "#")
            guard let pitch = Pitch(name), let data = Self.read(url) else { continue }
            loaded.append((pitch.midi, data))
        }
        guard !loaded.isEmpty else { return nil }
        samples = loaded.sorted { $0.midi < $1.midi }
    }

    private static func read(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData?[0]
        else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }

    /// The key at unit gain: its nearest sample, pitched by resampling.
    func key(_ midi: Int) -> [Float] {
        if let cached = pitched[midi] { return cached }
        let source = samples.min { abs($0.midi - midi) < abs($1.midi - midi) }!
        let ratio = Float(pow(2, Double(midi - source.midi) / 12))
        let count = Int(Float(source.data.count - 2) / ratio)
        var out = [Float](repeating: 0, count: max(0, count))
        guard count > 0 else { return out }
        var start: Float = 0, step = ratio
        var indices = [Float](repeating: 0, count: count)
        vDSP_vramp(&start, &step, &indices, 1, vDSP_Length(count))
        source.data.withUnsafeBufferPointer { table in
            vDSP_vlint(table.baseAddress!, indices, 1, &out, 1, vDSP_Length(count), vDSP_Length(table.count))
        }
        pitched[midi] = out
        return out
    }

    /// Mixes `notes` into a new track `duration` seconds long (longer if a note rings past it).
    func render(_ notes: [Note], duration: Double) -> [Float] {
        let end = notes.map { $0.time + $0.length + Self.release }.max() ?? 0
        var out = [Float](repeating: 0, count: Int((max(duration, end) + 0.05) * Self.rate))
        for note in notes { add(note, into: &out) }
        return out
    }

    /// Adds one note into `out`: held for its length at its gain, then a short fade.
    func add(_ note: Note, into out: inout [Float]) {
        let source = key(note.midi)
        let start = max(0, Int(note.time * Self.rate))
        guard start < out.count else { return }
        let held = min(source.count, Int(note.length * Self.rate), out.count - start)
        let fade = min(source.count - held, Int(Self.release * Self.rate), out.count - start - held)
        var gain = Float(note.gain)
        out.withUnsafeMutableBufferPointer { o in
            source.withUnsafeBufferPointer { s in
                if held > 0 {
                    vDSP_vsma(s.baseAddress!, 1, &gain, o.baseAddress! + start, 1, o.baseAddress! + start, 1, vDSP_Length(held))
                }
                guard fade > 0 else { return }
                var ramp = [Float](repeating: 0, count: fade)
                var one = gain, down = -gain / Float(fade)
                vDSP_vramp(&one, &down, &ramp, 1, vDSP_Length(fade))
                vDSP_vma(s.baseAddress! + held, 1, ramp, 1, o.baseAddress! + start + held, 1, o.baseAddress! + start + held, 1, vDSP_Length(fade))
            }
        }
    }

    /// The notes of a backing event at `time`, at `beat` seconds a quarter. Chords are
    /// shared out so a 4-note chord isn't 4 times as loud as one note.
    static func notes(_ event: BackingEvent, at time: Double, beat: Double, gain: Double, length: Double? = nil) -> [Note] {
        let count = Double(event.pitches.count)
        let each = gain * event.level / count.squareRoot()
        // a little detached, like a pianist lifting between chords
        let held = length ?? max(0.12, event.length * beat * (event.part == .arpeggio ? 0.9 : 0.95))
        return event.pitches.enumerated().map { i, p in
            Note(time: time + (event.rolled ? Double(i) * roll : 0), midi: p.midi, gain: each, length: held)
        }
    }

    /// Mono samples as a buffer the engine can play.
    static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
