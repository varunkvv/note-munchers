/// Song time (plans/2026-10-16-free-play.md): a short made-up song at his level that he
/// reads and plays while the app plays a piano part that follows him.
///
/// A song is real bars in G (no key signature in levels 1-2, G major from level 3), one
/// chord a bar (two at a 4/4 cadence), in a period form: `a b` (4 bars) or `a b a c` /
/// `a a' b a''` (8 bars). The letters are 2-bar units. Phrase 1 is the first half and
/// ends on a half cadence, phrase 2 ends on a long G.

/// A chord of G major, as the song's harmony names it.
public enum Chord: String, CaseIterable, Codable, Hashable, Sendable {
    case I, IV, V, V7

    /// Pitch classes of its tones: I = G B D, IV = C E G, V = D F# A, V7 = D F# A C.
    public var pitchClasses: [Int] {
        switch self {
        case .I: [7, 11, 2]
        case .IV: [0, 4, 7]
        case .V: [2, 6, 9]
        case .V7: [2, 6, 9, 0]
        }
    }

    public func contains(_ pitch: Pitch) -> Bool {
        let pc = pitch.pitchClass
        switch self {
        case .I: return pc == 7 || pc == 11 || pc == 2
        case .IV: return pc == 0 || pc == 4 || pc == 7
        case .V: return pc == 2 || pc == 6 || pc == 9
        case .V7: return pc == 2 || pc == 6 || pc == 9 || pc == 0
        }
    }

    public var isDominant: Bool { self == .V || self == .V7 }
}

/// The shape of a song in 2-bar units.
public enum SongForm: String, CaseIterable, Codable, Hashable, Sendable {
    /// 4 bars: a question and an answer.
    case ab = "a b"
    /// 8 bars, a parallel period: unit 3 comes back to unit 1.
    case abac = "a b a c"
    /// 8 bars, a mini AABA: units 2 and 4 start like unit 1.
    case aaba = "a a' b a''"
}

/// One bar of a song: its notes (all on one staff, the hand playing) and its chord.
public struct SongBar: Hashable, Codable, Sendable {
    public let notes: [WrittenNote]
    /// One chord for the bar, or two in 4/4 (the second from beat 3).
    public let chords: [Chord]

    public init(_ notes: [WrittenNote], chords: [Chord]) {
        precondition(!notes.isEmpty && !chords.isEmpty && chords.count <= 2)
        precondition(Set(notes.map(\.clef)).count == 1, "a bar's notes are on one staff")
        self.notes = notes
        self.chords = chords
    }

    public var clef: Clef { notes[0].clef }

    /// Beat offset of each note in the bar.
    public var startBeats: [Double] {
        var beat = 0.0
        return notes.map { note in
            defer { beat += note.span }
            return beat
        }
    }

    /// The chord sounding at `beat` (0 = the bar's first beat).
    public func chord(atBeat beat: Double) -> Chord {
        chords.count > 1 && beat >= 2 ? chords[1] : chords[0]
    }
}

/// A song he plays once through. Pure data: what's written, the chords, the title.
public struct Song: Hashable, Codable, Sendable {
    public let seed: UInt64
    public let level: Int
    public let meter: Meter
    public let keySignature: KeySignature
    public let form: SongForm
    public let bars: [SongBar]
    public let title: String
    /// One clef (level 1, or one hand only), or the grand staff for call and response.
    public let layout: StaffLayout
    /// Made from the hand-written fallback (every candidate broke a rule). Should be rare.
    public let isFallback: Bool
    /// The bar that comes back once at the end, as its own page (`withComeBack`): the bar
    /// he needed the band's help with. nil for the song as written.
    public let comeBack: Int?
    /// A familiar tune's real name (the end card reveals it), nil for a made-up song.
    public let tune: String?

    public init(seed: UInt64, level: Int, meter: Meter, keySignature: KeySignature, form: SongForm, bars: [SongBar],
                title: String, layout: StaffLayout, isFallback: Bool = false, comeBack: Int? = nil, tune: String? = nil) {
        precondition(!bars.isEmpty)
        for bar in bars {
            precondition(bar.notes.reduce(0) { $0 + $1.span } == Double(meter.beats), "a \(meter.rawValue) bar")
            precondition(layout.contains(bar.clef))
            precondition(bar.chords.count == 1 || meter == .fourFour, "a half-bar chord change only in 4/4")
        }
        self.seed = seed
        self.level = level
        self.meter = meter
        self.keySignature = keySignature
        self.form = form
        self.bars = bars
        self.title = title
        self.layout = layout
        self.isFallback = isFallback
        self.comeBack = comeBack
        self.tune = tune
    }

    /// The song with bar `bar` once more after its last bar, on a page of its own: the bar
    /// he needed the band's help with ("come back to it later on", varun). The tag at the
    /// end moves to after it. Once a song: a song that already has one stays as it is.
    public func withComeBack(bar: Int) -> Song {
        guard comeBack == nil, bars.indices.contains(bar) else { return self }
        return Song(seed: seed, level: level, meter: meter, keySignature: keySignature, form: form, bars: bars + [bars[bar]],
                    title: title, layout: layout, isFallback: isFallback, comeBack: bar, tune: tune)
    }

    /// Bars of the song as written (not the come-back bar).
    public var writtenBars: Int { comeBack == nil ? bars.count : bars.count - 1 }

    /// Notes of the song as written: the come-back bar's notes start here.
    public var writtenNotes: Int { bars.prefix(writtenBars).reduce(0) { $0 + $1.notes.count } }

    /// Every note, in the order he plays them.
    public var notes: [WrittenNote] { bars.flatMap(\.notes) }

    /// Index of each bar's first note in `notes`.
    public var barStarts: [Int] {
        var start = 0
        return bars.map { bar in
            defer { start += bar.notes.count }
            return start
        }
    }

    /// The bar each note is in.
    public var barOfNote: [Int] { bars.indices.flatMap { b in Array(repeating: b, count: bars[b].notes.count) } }

    /// The hand (clef) of phrase 1 and phrase 2.
    public var hands: [Clef] { [bars[0].clef, bars[writtenBars - 1].clef] }

    /// The last bar of phrase 1 (its last note is the half cadence).
    public var phraseOneEnd: Int { writtenBars / 2 - 1 }

    /// What the song is, note for note: clef, keys and value of every note, and the
    /// meter. Two seeds that make the same song have the same signature, so "not one of
    /// his last 20 songs" is about the song, not the seed.
    public var signature: String {
        bars.map { bar in
            bar.clef.rawValue + ":" + bar.notes.map { note in
                note.pitches.map(\.name).joined(separator: "+") + "/" + note.value.rawValue
            }.joined(separator: "-")
        }.joined(separator: " ") + " " + meter.rawValue
    }

    // MARK: pages

    /// How the song is laid out to read: 2 bars a system. A one-staff song puts 2
    /// systems on a page, so a 4 bar song is one page he sees whole. A grand staff song
    /// is one system a page. The come-back bar is a page of its own.
    public var pages: [SongPage] {
        let systemsPerPage = layout == .grand ? 1 : 2
        var pages: [SongPage] = []
        var systems: [PracticeItem] = []
        var first = 0
        var next = 0
        let written = writtenBars
        for start in stride(from: 0, to: written, by: 2) {
            let pair = Array(bars[start..<min(start + 2, written)])
            let item = PracticeItem(pair.flatMap(\.notes), layout: layout, keySignature: keySignature,
                                    bars: pair.map(\.notes.count), meter: meter)
            systems.append(item)
            next += item.notes.count
            if systems.count == systemsPerPage {
                pages.append(SongPage(systems: systems, firstNote: first))
                systems = []
                first = next
            }
        }
        if !systems.isEmpty { pages.append(SongPage(systems: systems, firstNote: first)) }
        if comeBack != nil, let bar = bars.last {
            let item = PracticeItem(bar.notes, layout: layout, keySignature: keySignature, bars: [bar.notes.count], meter: meter)
            pages.append(SongPage(systems: [item], firstNote: next))
        }
        return pages
    }

    /// The page note `index` is on.
    public func page(ofNote index: Int) -> Int {
        let pages = self.pages
        return pages.lastIndex { $0.firstNote <= index } ?? 0
    }

    /// The written song as one schedule at `beat` seconds a quarter (Listen).
    public func playback(beat: Double) -> [ScheduledNote] {
        var start = 0.0
        return notes.map { note in
            defer { start += note.span }
            return ScheduledNote(pitches: note.pitches, start: start * beat, duration: note.value.beats * beat)
        }
    }

    /// Beat offset of every note from the start of the song.
    public var startBeats: [Double] {
        var beat = 0.0
        return notes.map { note in
            defer { beat += note.span }
            return beat
        }
    }

    public var totalBeats: Double { Double(bars.count * meter.beats) }
}

/// What one page shows: one or two systems of up to 2 bars each.
public struct SongPage: Hashable, Sendable {
    /// Top to bottom.
    public let systems: [PracticeItem]
    /// Index in `Song.notes` of the page's first note.
    public let firstNote: Int

    public var noteCount: Int { systems.reduce(0) { $0 + $1.notes.count } }

    /// Index in `Song.notes` of each system's first note.
    public var systemStarts: [Int] {
        var start = firstNote
        return systems.map { item in
            defer { start += item.notes.count }
            return start
        }
    }
}

/// A song he has played (or started), remembered so the next ones are different.
public struct PlayedSong: Hashable, Codable, Sendable {
    public var seed: UInt64
    /// `Song.signature`.
    public var signature: String
    /// The hands it used, phrase 1 then phrase 2.
    public var hands: [Clef]
    /// A familiar tune's name, nil for a made-up song.
    public var tune: String?

    public init(seed: UInt64, signature: String, hands: [Clef], tune: String? = nil) {
        self.seed = seed
        self.signature = signature
        self.hands = hands
        self.tune = tune
    }

    public init(_ song: Song) {
        self.init(seed: song.seed, signature: song.signature, hands: song.hands, tune: song.tune)
    }
}
