/// The app's piano part for a song, and how it follows him (artifacts/free-play/composer.md,
/// "following him"). Every event hangs off one of his melody notes, so nothing runs on a
/// clock he has to keep up with:
///
/// - levels 1-2, anchored: his note on beat 1 sounds the bass and the chord, his note on
///   beat 3 (4/4) the chord again. Nothing else
/// - level 3, oom-pah: the bass with his beat-1 note, short chords on the other beats
/// - level 4, a broken chord a beat at a time (root, 5th, 3rd, 5th)
/// - level 5, a light alberti in eighths
///
/// From level 3 the in-between parts are fillers: scheduled at his own beat from the key
/// he just played, never past the written end of that note, and dropped when his next key
/// comes. A wrong key plays nothing new, so the chord just keeps ringing.
///
/// The part sits away from the hand that's playing: under a treble tune (bass and chords
/// low), over a bass tune (chords high, no low bass).
public struct BackingEvent: Hashable, Sendable {
    public enum Part: String, Hashable, Sendable {
        /// a low root
        case bass
        /// a held or short chord
        case chord
        /// one note of a broken chord or alberti
        case arpeggio
        /// the V7-I tag after his last note
        case outro
    }

    /// Index in `Song.notes` of the melody note it hangs off.
    public let note: Int
    /// Beats after that note starts. 0 sounds with his key.
    public let offset: Double
    public let pitches: [Pitch]
    /// Written length in beats (how long it rings at his beat, before the release).
    public let length: Double
    public let part: Part
    /// Loudness inside the backing, 0...1.
    public let level: Double
    /// Rolled low to high, like a harp (the intro and the last chord).
    public let rolled: Bool

    public init(note: Int, offset: Double, pitches: [Pitch], length: Double, part: Part, level: Double, rolled: Bool = false) {
        self.note = note
        self.offset = offset
        self.pitches = pitches.sorted()
        self.length = length
        self.part = part
        self.level = level
        self.rolled = rolled
    }

    /// Sounds with his key rather than at his beat after it.
    public var isAnchored: Bool { offset == 0 }
}

public struct BackingPlan: Hashable, Sendable {
    public enum Pattern: String, Hashable, Sendable {
        case anchored, oomPah, broken, alberti

        public init(level: Int) {
            switch level {
            case ...2: self = .anchored
            case 3: self = .oomPah
            case 4: self = .broken
            default: self = .alberti
            }
        }
    }

    public let pattern: Pattern
    /// Sorted by note, then offset. The outro is in here too, on the last note.
    public let events: [BackingEvent]
    /// One soft rolled G chord to set the key before he starts (not a count-in).
    public let intro: BackingEvent
    /// Written beats from each note to the next (the last note: its own value).
    public let noteBeats: [Double]
    /// Where each note starts, in beats from the top of the song.
    public let startBeats: [Double]

    public init(song: Song) {
        pattern = Pattern(level: song.level)
        let notes = song.notes
        noteBeats = notes.map(\.span)
        startBeats = song.startBeats
        var events: [BackingEvent] = []
        var first = 0
        for bar in song.bars {
            let below = bar.clef == .treble
            let starts = bar.startBeats
            // the melody note sounding at a beat of this bar
            func at(_ beat: Double) -> (note: Int, offset: Double) {
                let i = starts.lastIndex { $0 <= beat + 1e-9 } ?? 0
                return (first + i, beat - starts[i])
            }
            for (beat, kind) in Self.positions(pattern, meter: song.meter, chords: bar.chords) {
                let chord = bar.chord(atBeat: beat)
                let (note, offset) = at(beat)
                // levels 1-2 only ever sound with one of his keys
                if pattern == .anchored, offset != 0 { continue }
                let v = Self.voicing(chord, below: below)
                let next = Self.positions(pattern, meter: song.meter, chords: bar.chords).map(\.beat).first { $0 > beat } ?? Double(song.meter.beats)
                let ring = next - beat
                switch kind {
                case .bassAndChord:
                    if let bass = v.bass { events.append(BackingEvent(note: note, offset: offset, pitches: [bass], length: ring, part: .bass, level: 0.8)) }
                    events.append(BackingEvent(note: note, offset: offset, pitches: v.chord, length: ring, part: .chord, level: 0.6))
                case .chord:
                    events.append(BackingEvent(note: note, offset: offset, pitches: v.chord, length: ring, part: .chord, level: pattern == .anchored ? 0.55 : 0.42))
                case .bass:
                    if let bass = v.bass { events.append(BackingEvent(note: note, offset: offset, pitches: [bass], length: ring, part: .bass, level: 0.75)) }
                case .arpeggio(let step):
                    let line = Self.arpeggio(chord, below: below, alberti: pattern == .alberti)
                    events.append(BackingEvent(note: note, offset: offset, pitches: [line[step % line.count]], length: ring,
                                               part: .arpeggio, level: pattern == .alberti ? 0.38 : 0.5))
                }
            }
            first += bar.notes.count
        }
        // after his last G: V7, then I rolled and held, at his tempo
        let last = notes.count - 1
        let below = song.bars[song.bars.count - 1].clef == .treble
        let tag = min(notes[last].value.beats, 2)
        let v7 = Self.voicing(.V7, below: below), one = Self.voicing(.I, below: below)
        events.append(BackingEvent(note: last, offset: tag, pitches: (v7.bass.map { [$0] } ?? []) + v7.chord, length: 1, part: .outro, level: 0.55))
        events.append(BackingEvent(note: last, offset: tag + 1, pitches: (one.bass.map { [$0] } ?? []) + one.chord, length: 3, part: .outro,
                                   level: 0.6, rolled: true))
        self.events = events.sorted { ($0.note, $0.offset) < ($1.note, $1.offset) }
        let start = Self.voicing(.I, below: song.bars[0].clef == .treble)
        intro = BackingEvent(note: 0, offset: 0, pitches: (start.bass.map { [$0] } ?? []) + start.chord, length: 3, part: .chord,
                             level: 0.5, rolled: true)
    }

    /// What hangs off note `index`.
    public func events(for index: Int) -> [BackingEvent] { events.filter { $0.note == index } }

    // MARK: patterns

    enum Kind: Hashable {
        case bassAndChord, chord, bass
        case arpeggio(Int)
    }

    /// Where in a bar the pattern plays, in beats.
    static func positions(_ pattern: Pattern, meter: Meter, chords: [Chord]) -> [(beat: Double, kind: Kind)] {
        let four = meter == .fourFour
        switch pattern {
        case .anchored:
            return four ? [(0, .bassAndChord), (2, chords.count > 1 ? .bassAndChord : .chord)] : [(0, .bassAndChord)]
        case .oomPah:
            return four ? [(0, .bass), (1, .chord), (2, .bass), (3, .chord)] : [(0, .bass), (1, .chord), (2, .chord)]
        case .broken:
            return (0..<meter.beats).map { (Double($0), .arpeggio($0)) }
        case .alberti:
            return (0..<(meter.beats * 2)).map { (Double($0) / 2, .arpeggio($0)) }
        }
    }

    /// Bass and chord for a chord, under a treble tune or over a bass tune (no low bass then:
    /// his notes are the bass).
    public static func voicing(_ chord: Chord, below: Bool) -> (bass: Pitch?, chord: [Pitch]) {
        let p = { (name: String) in Pitch(name)! }
        if below {
            switch chord {
            case .I: return (p("G2"), [p("G3"), p("B3"), p("D4")])
            case .IV: return (p("C3"), [p("G3"), p("C4"), p("E4")])
            case .V: return (p("D3"), [p("F#3"), p("A3"), p("D4")])
            case .V7: return (p("D3"), [p("F#3"), p("A3"), p("C4")])
            }
        }
        switch chord {
        case .I: return (nil, [p("B4"), p("D5"), p("G5")])
        case .IV: return (nil, [p("C5"), p("E5"), p("G5")])
        case .V: return (nil, [p("A4"), p("D5"), p("F#5")])
        case .V7: return (nil, [p("A4"), p("C5"), p("F#5")])
        }
    }

    /// A broken chord's notes, one a beat (root, 5th, 3rd, 5th), or an alberti in eighths
    /// (low, high, middle, high). Over a bass tune it starts above his note.
    static func arpeggio(_ chord: Chord, below: Bool, alberti: Bool) -> [Pitch] {
        let p = { (name: String) in Pitch(name)! }
        if below {
            if alberti {
                switch chord {
                case .I: return ["G3", "D4", "B3", "D4"].map(p)
                case .IV: return ["G3", "E4", "C4", "E4"].map(p)
                case .V: return ["F#3", "D4", "A3", "D4"].map(p)
                case .V7: return ["F#3", "C4", "A3", "C4"].map(p)
                }
            }
            switch chord {
            case .I: return ["G2", "D3", "B2", "D3"].map(p)
            case .IV: return ["C3", "G3", "E3", "G3"].map(p)
            case .V: return ["D3", "A3", "F#3", "A3"].map(p)
            case .V7: return ["D3", "A3", "F#3", "C4"].map(p)
            }
        }
        switch chord {
        case .I: return ["B4", "G5", "D5", "G5"].map(p)
        case .IV: return ["C5", "G5", "E5", "G5"].map(p)
        case .V: return ["A4", "F#5", "D5", "F#5"].map(p)
        case .V7: return ["A4", "F#5", "C5", "F#5"].map(p)
        }
    }

    // MARK: listen

    /// The whole part at a steady `beat` (seconds a quarter), from the song's first note at
    /// time 0. The intro chord comes before it (negative time). For Listen and the renders.
    public func timeline(beat: Double, introLead: Double = 2) -> [TimedBackingEvent] {
        [TimedBackingEvent(event: intro, time: -introLead * beat)]
            + events.map { TimedBackingEvent(event: $0, time: (startBeats[$0.note] + $0.offset) * beat) }
    }
}

/// A backing event with the time to sound it, on the caller's clock.
public struct TimedBackingEvent: Hashable, Sendable {
    public let event: BackingEvent
    public let time: Double
}

/// Plays the part along with him. Call `played(_:at:)` on each right key. It returns what
/// to sound and when. Anything still waiting from an earlier key should be dropped first
/// (his next key, or a wrong one, always cancels fillers that haven't sounded).
///
/// His beat is the median of his last few gaps over their written lengths, clamped to
/// 0.35-1.5s a quarter. A gap more than 2.5 times what his beat expects is him reading,
/// not his tempo, so it doesn't count: the chord just decays while he looks.
public struct BackingFollower: Sendable {
    public private(set) var plan: BackingPlan
    /// Seconds a quarter, his tempo so far.
    public private(set) var beat: Double
    private var samples: [Double] = []
    private var last: (note: Int, time: Double)?

    public static let beatRange = 0.35...1.5
    static let window = 4
    static let readingPause = 2.5

    public init(plan: BackingPlan, startBeat: Double = 0.8) {
        self.plan = plan
        beat = startBeat
    }

    /// He stopped for something that isn't his tempo (the play button, the piano off):
    /// the gap to his next key isn't counted.
    public mutating func rest() {
        last = nil
    }

    /// The song grew (a come-back bar at the end): the same notes up to there, so his
    /// tempo and the last key carry over.
    public mutating func replan(_ plan: BackingPlan) {
        self.plan = plan
    }

    public mutating func played(_ index: Int, at time: Double) -> [TimedBackingEvent] {
        if let last, index == last.note + 1 {
            let written = plan.noteBeats[last.note]
            let sample = (time - last.time) / written
            if samples.count < 2 || sample <= Self.readingPause * beat {
                samples = Array((samples + [min(Self.beatRange.upperBound, max(Self.beatRange.lowerBound, sample))]).suffix(Self.window))
                beat = min(Self.beatRange.upperBound, max(Self.beatRange.lowerBound, median(samples)))
            }
        }
        last = (index, time)
        return plan.events(for: index).map { TimedBackingEvent(event: $0, time: time + $0.offset * beat) }
    }
}
