import AVFoundation
import NoteCore

/// Song time's sound, built on `Piano`.
///
/// - Listen (the end card): the written song with its backing at a gentle steady beat,
///   mixed into one track. `artifacts/free-play/renders` are this same track saved
///   to files, so what varun hears there is what nirvaan hears when he taps Listen
/// - live: one backing event at a time as he plays (`backing`), rendered when it's due
///
/// Levels: the app can't hear his piano, so "8-10 dB under his piano" can't be measured.
/// The backing sits about 7 dB under the melody in Listen, and live it's a fixed level a
/// bit under the app's chime. The iPad's volume does the rest.
@MainActor
enum SongMix {
    /// Listen's tempo, seconds a quarter (about 96 a minute).
    static let listenBeat = 0.62
    static let melodyGain = 0.7
    /// About 7 dB under the melody.
    static let backingGain = 0.3
    /// The live backing, under the app's own chime and his piano.
    static let liveGain = 0.34
    /// Live chords on his beat-1 notes keep ringing this long, so a chord is still there
    /// while he looks for the next key.
    static let anchoredRing = 2.8

    struct Track {
        let samples: [Float]
        /// Seconds into the track where the song's first note sounds (after the intro chord).
        let songStart: Double
        let beat: Double
    }

    /// The whole song for Listen: the intro chord, his notes, the backing, the tag.
    static func listen(_ song: Song, piano: Piano, beat: Double = listenBeat) -> Track {
        let plan = BackingPlan(song: song)
        let lead = 2 * beat + 0.3
        var notes: [Piano.Note] = []
        for note in song.playback(beat: beat) {
            let each = melodyGain / Double(note.pitches.count).squareRoot()
            for p in note.pitches {
                notes.append(Piano.Note(time: lead + note.start, midi: p.midi, gain: each, length: note.duration * 0.92))
            }
        }
        for timed in plan.timeline(beat: beat) {
            notes += Piano.notes(timed.event, at: lead + timed.time, beat: beat, gain: backingGain)
        }
        var samples = piano.render(notes, duration: lead + song.totalBeats * beat + 4)
        limit(&samples, to: 0.9)
        return Track(samples: samples, songStart: lead, beat: beat)
    }

    /// One moment of the live backing: the events that sound together, as one buffer.
    static func backing(_ events: [BackingEvent], beat: Double, piano: Piano) -> AVAudioPCMBuffer? {
        var notes: [Piano.Note] = []
        for event in events {
            let ring: Double? = event.isAnchored && event.part != .arpeggio ? max(event.length * beat, anchoredRing) : nil
            notes += Piano.notes(event, at: 0, beat: beat, gain: liveGain, length: ring)
        }
        var samples = piano.render(notes, duration: 0)
        limit(&samples, to: 0.9)
        return Piano.buffer(samples)
    }

    /// The intro: one soft rolled G chord, to set the key.
    static func intro(_ song: Song, piano: Piano) -> AVAudioPCMBuffer? {
        let notes = Piano.notes(BackingPlan(song: song).intro, at: 0, beat: 0.8, gain: liveGain, length: 2.4)
        return Piano.buffer(piano.render(notes, duration: 0))
    }

    /// Scales the track down if it peaks over `peak`.
    static func limit(_ samples: inout [Float], to peak: Float) {
        let top = samples.reduce(0) { max($0, abs($1)) }
        guard top > peak else { return }
        let k = peak / top
        for i in samples.indices { samples[i] *= k }
    }
}

#if DEBUG
/// `-renderSongs <dir>` (mac build): writes one generated song per level with its backing,
/// the Listen track, as m4a, plus the same chords through the old synth and through the
/// piano to compare, and a README listing what's in each file. Then quits.
@MainActor
enum SongRenders {
    static func write(to folder: String) {
        let dir = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let piano = Piano() else {
            print("renders: no piano samples in the bundle")
            return
        }
        var readme = ["# song time renders (\(Date().formatted(date: .abbreviated, time: .shortened)))", "",
                      "one generated song per level, with its backing, exactly as the end card's Listen plays it",
                      "(\(Int(60 / SongMix.listenBeat)) a minute, backing about 7 dB under the melody). made by `-renderSongs` in a mac debug build.", ""]
        let plans: [(level: Int, meter: Meter, hands: [Clef], seed: UInt64)] = [
            (1, .fourFour, [.treble, .treble], 21), (2, .threeFour, [.treble, .bass], 22), (3, .fourFour, [.bass, .treble], 23),
            (4, .threeFour, [.treble, .bass], 24), (5, .fourFour, [.treble, .bass], 25),
        ]
        for plan in plans {
            let range = { (clef: Clef) in Array(MasteryEngine.songRange(level: plan.level, clef: clef).suffix(5)) }
            let request = SongRequest(level: plan.level, meter: plan.meter, hands: plan.hands, treble: range(.treble), bass: range(.bass),
                                      bars: plan.level == 1 ? 4 : 8)
            let song = SongGenerator.song(request, seed: plan.seed)
            let track = SongMix.listen(song, piano: piano)
            let name = "level-\(plan.level)-" + song.title.lowercased().replacingOccurrences(of: " ", with: "-") + ".m4a"
            save(track.samples, to: dir.appendingPathComponent(name))
            readme += ["## \(name)", "",
                       "- \"\(song.title)\", level \(song.level), \(song.meter.rawValue), \(song.form.rawValue), \(song.bars.count) bars, "
                           + "\(BackingPlan.Pattern(level: song.level).rawValue) backing, \(String(format: "%.0f", Double(track.samples.count) / Piano.rate))s",
                       "- chords: " + song.bars.map { $0.chords.map(\.rawValue).joined(separator: "-") }.joined(separator: " | "),
                       "- notes: " + song.bars.map { bar in "\(bar.clef == .treble ? "R" : "L") " + bar.notes.map { $0.pitches.map(\.name).joined(separator: "+") + $0.value.rawValue }.joined(separator: " ") }.joined(separator: " | "),
                       ""]
            print("renders: wrote \(name)")
        }
        // the same four chords (I V V7 I under a treble tune), old synth then piano
        let chords: [Chord] = [.I, .V, .V7, .I]
        var synth: [Float] = []
        for chord in chords {
            let v = BackingPlan.voicing(chord, below: true)
            if let b = Synth.tone(([v.bass!] + v.chord).map(\.midi), duration: 1.0, format: Piano.format), let data = b.floatChannelData?[0] {
                synth += Array(UnsafeBufferPointer(start: data, count: Int(b.frameLength))).prefix(Int(1.2 * Piano.rate))
            }
        }
        var notes: [Piano.Note] = []
        for (i, chord) in chords.enumerated() {
            let v = BackingPlan.voicing(chord, below: true)
            let event = BackingEvent(note: 0, offset: 0, pitches: [v.bass!] + v.chord, length: 1.6, part: .chord, level: 0.8)
            notes += Piano.notes(event, at: 1.0 + Double(chords.count) * 1.2 + Double(i) * 1.2, beat: 0.6, gain: 0.8, length: 1.0)
        }
        var both = piano.render(notes, duration: 1.0 + Double(chords.count) * 2.4 + 1)
        for (i, s) in synth.enumerated() where i < both.count { both[i] += s }
        SongMix.limit(&both, to: 0.9)
        save(both, to: dir.appendingPathComponent("compare-synth-then-piano.m4a"))
        readme += ["## compare-synth-then-piano.m4a", "",
                   "- I V V7 I as block chords: first through the app's old synth (Sounds.swift), then through the sampled piano (Salamander Grand, CC BY 3.0)", ""]
        try? readme.joined(separator: "\n").write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        print("renders: done -> \(dir.path)")
    }

    private static func save(_ samples: [Float], to url: URL) {
        guard let buffer = Piano.buffer(samples) else { return }
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Piano.rate, AVNumberOfChannelsKey: 1,
                                       AVEncoderBitRateKey: 128_000]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        } catch {
            print("renders: couldn't write \(url.lastPathComponent): \(error)")
        }
    }
}
#endif
