/// When song time shows up and what a song is made from (plans/2026-10-16-free-play.md).
///
/// - only notes he's solid on: met, box 3 or more, never the newest batch, inside the
///   song range for his level (G position, an octave G to G in level 3)
/// - a clef qualifies with 3 or more of those, G and A among them. Every song ends on G,
///   and in level 1 (steps only) the last G comes from A
/// - level 1: one clef a song, taking turns, the weaker clef a bit more often. Level 2+:
///   call and response, phrase 1 in one hand and phrase 2 in the other, when both clefs
///   qualify (otherwise one clef)
/// - 4 bars in level 1 or while his notes per screen are under 3, else 8
extension MasteryEngine {
    /// How many songs are remembered (a new song is never one of these).
    public static let recentSongCount = 20

    /// The keys a song may use in `clef` at `level`, low to high.
    public static func songRange(level: Int, clef: Clef) -> [Pitch] {
        let gPosition = clef == .treble ? Curriculum.trebleG : Curriculum.bassG
        guard level == 3 else { return gPosition }
        // G major, one octave: the lessons' F# and the notes up to the next G
        return clef == .treble ? gPosition + [Curriculum.e5, Curriculum.fs5, Curriculum.g5]
            : gPosition + [Curriculum.e3, Curriculum.fs3, Curriculum.g3]
    }

    /// Notes he's solid on in `clef` for songs: in his lesson, met and played, box 3 or
    /// more, not in the newest batch (unless a paced lesson has given it its plays), inside the
    /// song range for his level. Low to high. So level 1 songs open in 1.2, once B is drilled.
    public func solidNotes(_ clef: Clef) -> [NoteKey] {
        let newest = Set(newestBatch(clef).filter { !hasMinPlays($0) })
        let lessonKeys = Set(lesson.keys)
        return Self.songRange(level: lesson.level, clef: clef).map { NoteKey(clef, $0) }.filter { key in
            let s = stats(for: key)
            return lessonKeys.contains(key) && isUnlocked(key) && s.attempts > 0 && s.box >= config.gateMinBox && !newest.contains(key)
        }
    }

    /// Clefs a song can be in right now: 3 or more solid notes, G and A among them.
    public var songClefs: [Clef] {
        Clef.allCases.filter { clef in
            let notes = solidNotes(clef)
            return notes.count >= 3 && notes.contains { $0.pitch.letter == .g } && notes.contains { $0.pitch.letter == .a }
        }
    }

    /// Song time shows on home and at the end of a session. Never a lock: it just isn't
    /// there before.
    public var canPlaySongs: Bool { !songClefs.isEmpty }

    /// Everything the generator needs for his next song, or nil before song time.
    public func songRequest(seed: UInt64) -> SongRequest? {
        let clefs = songClefs
        guard !clefs.isEmpty else { return nil }
        var rng = SeededRandom(seed: seed ^ 0x50_4E47_5449_4D45) // "SONGTIME", so it doesn't echo the song's own dice
        let level = lesson.level
        let meter: Meter = unitInterval(&rng) < 0.5 ? .fourFour : .threeFour
        let short = level == 1 || (!lesson.texture.isRhythm && state.screenSize < 3)
        let hands: [Clef]
        if level >= 2, clefs.count == 2 {
            hands = unitInterval(&rng) < 0.5 ? [.treble, .bass] : [.bass, .treble]
        } else {
            let clef = clefs.count == 1 ? clefs[0] : levelOneClef(using: &rng)
            hands = [clef, clef]
        }
        // level 3's octave is too many notes for every one to fit a 4 bar phrase: a song
        // takes its upper five (C to G, with the F#) or G position
        let upper = unitInterval(&rng) < 0.6
        let notes = { (c: Clef) -> [Pitch] in
            guard hands.contains(c) else { return [] }
            let all = solidNotes(c).map(\.pitch)
            guard level == 3 else { return all }
            let range = Self.songRange(level: 3, clef: c)
            let windows = [Array(range.suffix(5)), Array(range.prefix(5))]
            for window in upper ? windows : windows.reversed() {
                let mine = all.filter(window.contains)
                // G and the note next to it (A, or the F# under the top G), for the ending
                guard mine.count >= 3, let g = mine.first(where: { $0.letter == .g }),
                      mine.contains(where: { abs($0.diatonicIndex - g.diatonicIndex) == 1 }) else { continue }
                return mine
            }
            return all.filter(Array(range.prefix(5)).contains)
        }
        return SongRequest(level: level, meter: meter, hands: hands, treble: notes(.treble), bass: notes(.bass),
                           bars: short ? 4 : 8, recent: state.recentSongs.map(\.signature))
    }

    /// Both clefs qualify: take turns, weighted to the weaker clef, never 3 songs in a
    /// row in one clef.
    private func levelOneClef(using rng: inout some RandomNumberGenerator) -> Clef {
        let last = state.recentSongs.suffix(2).map { $0.hands[0] }
        if last.count == 2, last[0] == last[1] { return last[0] == .treble ? .bass : .treble }
        let weights = Clef.allCases.map { clef -> Double in
            let notes = solidNotes(clef)
            let weakness = notes.reduce(0.0) { $0 + Double(config.boxCount + 1 - stats(for: $1).box) } / Double(max(1, notes.count))
            return (1 + weakness) * (clef == last.last ? 0.4 : 1)
        }
        return Clef.allCases[weightedIndex(weights, using: &rng)]
    }

    /// The next song for this seed, or nil before song time.
    public func makeSong(seed: UInt64) -> Song? {
        songRequest(seed: seed).map { SongGenerator.song($0, seed: seed) }
    }

    /// Remember a song he was given, so the next ones are different. Keeps the last 20.
    public mutating func rememberSong(_ song: Song) {
        state.recentSongs = Array((state.recentSongs + [PlayedSong(song)]).suffix(Self.recentSongCount))
    }
}
