/// The familiar tunes shelf (plans/2026-10-16-progress-and-tunes.md, section 4): now and
/// then song time gives him a real tune instead of a made-up one, as a "Mystery song!".
/// The end card reveals its name.
///
/// - about 1 song in 6 (`tuneChance`), only after `madeUpBeforeTunes` made-up songs, never
///   two tunes in a row
/// - only a tune whose every note he's solid on in that clef (`solidNotes`), from its
///   level up
/// - the one he has had least lately, in the clef his last song wasn't in when it fits both
/// - same pages, backing and end card as every song, unjudged. Tunes are curated, so the
///   generator's hard rules don't apply to them
extension MasteryEngine {
    /// How often a song is a tune, once he can have one.
    public static let tuneChance = 1.0 / 6
    /// Made-up songs he has had (in `recentSongs`) before the first tune.
    public static let madeUpBeforeTunes = 3
    /// What the title card says for a tune.
    public static let mysteryTitle = "Mystery song!"

    /// Tunes he could play right now, with the clefs they fit (every key solid there).
    public var familiarTunes: [(tune: Tune, clefs: [Clef])] {
        let clefs = songClefs
        return Tune.all.filter { $0.level <= lesson.level }.compactMap { tune in
            let fits = clefs.filter { clef in tune.allKeys(clef).isSubset(of: Set(solidNotes(clef))) }
            return fits.isEmpty ? nil : (tune, fits)
        }
    }

    /// A tune for this seed, or nil (most of the time: a made-up song then).
    public func familiarTune(seed: UInt64) -> Song? {
        let recent = state.recentSongs
        guard recent.filter({ $0.tune == nil }).count >= Self.madeUpBeforeTunes, recent.last?.tune == nil else { return nil }
        var rng = SeededRandom(seed: seed ^ 0x54_554E_4553) // "TUNES", so it doesn't echo the other dice
        guard unitInterval(&rng) < Self.tuneChance else { return nil }
        let options = familiarTunes
        guard !options.isEmpty else { return nil }
        // the one he has had least lately (never is least of all)
        let last = { (tune: Tune) in recent.lastIndex { $0.tune == tune.name } ?? -1 }
        let oldest = options.map { last($0.tune) }.min()!
        let pick = options.filter { last($0.tune) == oldest }
        let (tune, clefs) = pick[min(pick.count - 1, Int(unitInterval(&rng) * Double(pick.count)))]
        // take turns between the clefs, like level 1's made-up songs
        let previous = recent.last?.hands.first
        let clef = clefs.first { $0 != previous } ?? clefs[0]
        return song(tune, clef: clef, seed: seed)
    }

    /// `tune` as a song in `clef` at his level: his level's key signature and backing,
    /// one staff, "Mystery song!" on the title card.
    public func song(_ tune: Tune, clef: Clef, seed: UInt64) -> Song {
        let keys = tune.keys(clef)
        let bars = tune.bars.indices.map { b in
            SongBar(zip(keys[b], tune.bars[b]).map { WrittenNote($0.0, $0.1.value) }, chords: tune.chords[b])
        }
        let level = lesson.level
        return Song(seed: seed, level: level, meter: tune.meter, keySignature: level >= 3 ? .gMajor : .none,
                    form: tune.bars.count <= 5 ? .ab : .abac, bars: bars, title: Self.mysteryTitle,
                    layout: clef == .treble ? .treble : .bass, tune: tune.name)
    }
}
