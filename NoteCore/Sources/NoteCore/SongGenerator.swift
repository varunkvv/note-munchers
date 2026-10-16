/// What a song is made from: his level, the meter, which hand plays each phrase and the
/// notes he's solid on in each clef. `MasteryEngine.songRequest(seed:)` makes one.
public struct SongRequest: Hashable, Sendable {
    public var level: Int
    public var meter: Meter
    /// Phrase 1's hand, then phrase 2's. The same clef twice is a one-staff song.
    public var hands: [Clef]
    /// His notes in each clef the song may use, low to high.
    public var treble: [Pitch]
    public var bass: [Pitch]
    /// 4 or 8.
    public var bars: Int
    /// Signatures of his recent songs (`Song.signature`). A new song is never one of them.
    public var recent: [String]

    public init(level: Int, meter: Meter, hands: [Clef], treble: [Pitch] = [], bass: [Pitch] = [], bars: Int,
                recent: [String] = []) {
        precondition(hands.count == 2 && (bars == 4 || bars == 8))
        self.level = level
        self.meter = meter
        self.hands = hands
        self.treble = treble.sorted()
        self.bass = bass.sorted()
        self.bars = bars
        self.recent = recent
    }

    public func notes(_ clef: Clef) -> [Pitch] { clef == .treble ? treble : bass }

    /// No key signature in levels 1-2, G major from level 3 (as in the lessons).
    public var keySignature: KeySignature { level >= 3 ? .gMajor : .none }

    public var layout: StaffLayout {
        hands[0] != hands[1] ? .grand : hands[0] == .treble ? .treble : .bass
    }
}

/// Makes songs (artifacts/free-play/composer.md): pick a form and chords, then 64
/// candidate melodies; drop any that break a hard rule, keep the best scoring one. A
/// hand-written fallback means it never fails. The same seed always makes the same song.
///
/// Hard rules (`violations`): start on G, B or D. Phrase 1 ends on a half cadence (D or A
/// over V, F# too from level 3, or B or D over I), phrase 2 on a long G on a strong beat
/// reached from A, F# or D. Beat 1 is always a chord tone, other notes are chord tones or
/// stepped into and out of. Both ends of a skip are chord tones, a 4th or 5th steps back,
/// no C-F# leap, the same key at most 4 times running. Only his notes, every one of them,
/// moves no bigger than a 2nd in level 1 (a 3rd across a note he doesn't have) and a 5th
/// from level 2.
///
/// Repetition is the point, so the practice generator's "no screen like the last ones"
/// and "no key 3 times running" rules don't apply.
public enum SongGenerator {
    public static let candidateCount = 64
    /// Rounds of new chords before the hand-written fallback.
    static let rounds = 3

    public static func song(_ request: SongRequest, seed: UInt64) -> Song {
        var rng = SeededRandom(seed: seed)
        let title = title(meter: request.meter, using: &rng)
        var good: [(song: Song, score: Double)] = []
        var heardBefore: [Song] = []
        // a form and chords, then 64 tries at a melody. A few notes he doesn't have yet
        // can make one set of chords impossible (no C3 for a bass IV bar): then new chords
        for round in 0..<rounds where good.isEmpty {
            let form: SongForm = request.bars == 4 ? .ab : unitInterval(&rng) < 0.6 ? .abac : .aaba
            var chords = template(form: form, meter: request.meter, bars: request.bars, using: &rng)
            if round == rounds - 1 {
                // the last try leaves out IV, whose C and E he may not have in that hand
                chords = chords.map { bar in bar == [.IV, .V] ? [.V] : bar.map { $0 == .IV ? .I : $0 } }
            }
            for _ in 0..<candidateCount {
                guard let song = candidate(request, form: form, chords: chords, title: title, seed: seed, using: &rng),
                      violations(song, notes: request.notes).isEmpty
                else { continue }
                if !request.recent.isEmpty, request.recent.contains(song.signature) {
                    heardBefore.append(song)
                    continue
                }
                good.append((song, score(song)))
            }
        }
        guard let best = good.map(\.score).max() else {
            // three notes and steps only can make fewer than 20 songs: then the one he
            // heard longest ago, rather than the plain fallback every time
            let oldest = heardBefore.min { request.recent.firstIndex(of: $0.signature)! < request.recent.firstIndex(of: $1.signature)! }
            return oldest ?? fallback(request, title: title, seed: seed)
        }
        // the best, or one within a point of it: with 3 notes and steps only the very best
        // song turns up for most seeds, and then every song is the same song
        let near = good.filter { $0.score >= best - nearBest }
        return near[weightedIndex(near.map { $0.score == best ? 2 : 1 }, using: &rng)].song
    }

    /// How far under the best score a song can be and still be picked.
    static let nearBest = 1.0

    // MARK: form and harmony

    /// One chord list per bar. Bar 1 is always I, phrase 1 ends on V (or I), the last bar is I.
    static func template(form: SongForm, meter: Meter, bars: Int, using rng: inout SeededRandom) -> [[Chord]] {
        let four = meter == .fourFour
        switch form {
        case .ab:
            // a: I V or I IV-V (4/4) / I I (3/4), b: V7 I
            if unitInterval(&rng) < 0.5 { return [[.I], [.V], [.V7], [.I]] }
            return four ? [[.I], [.IV, .V], [.V7], [.I]] : [[.I], [.I], [.V7], [.I]]
        case .abac:
            // antecedent I IV I V or I I IV V, consequent copies bars 1-2 then V7 I or IV-V I
            let opening: [[Chord]] = unitInterval(&rng) < 0.5 ? [[.I], [.IV]] : [[.I], [.I]]
            let middle: [[Chord]] = opening[1] == [.IV] ? [[.I], [.V]] : [[.IV], [.V]]
            let close: [[Chord]] = four && unitInterval(&rng) < 0.35 ? [[.IV, .V], [.I]] : [[.V7], [.I]]
            return opening + middle + opening + close
        case .aaba:
            return [[.I], [.V], [.I], [.V], [.IV], [.V], four ? [.I, .V7] : [.V7], [.I]]
        }
    }

    /// Rhythm cells (composer.md): body bars, the bar that ends phrase 1, the last bar.
    static func bodyCells(_ meter: Meter, level: Int) -> [(cell: [NoteValue], weight: Double)] {
        let q = NoteValue.quarter, h = NoteValue.half, e = NoteValue.eighth
        var cells: [(cell: [NoteValue], weight: Double)] = meter == .fourFour
            ? [([q, q, h], 1), ([q, q, q, q], 0.8), ([h, q, q], 0.8), ([h, h], 0.5)]
            : [([q, q, q], 1), ([h, q], 0.8), ([q, h], 0.6)]
        if level >= 5 {
            cells += meter == .fourFour ? [([q, e, e, h], 0.6), ([e, e, q, q, q], 0.5)] : [([e, e, q, q], 0.6), ([q, e, e, q], 0.5)]
        }
        return cells
    }

    static func phraseEndCells(_ meter: Meter) -> [[NoteValue]] {
        meter == .fourFour ? [[.quarter, .quarter, .half], [.half, .half]] : [[.dottedHalf]]
    }

    static func finalCells(_ meter: Meter) -> [[NoteValue]] {
        meter == .fourFour ? [[.whole], [.quarter, .quarter, .half]] : [[.dottedHalf]]
    }

    /// Which earlier bar each bar copies, if any: `a b a c` brings units 1 back as unit 3,
    /// `a a' b a''` starts units 2 and 4 like unit 1.
    static func copies(_ form: SongForm) -> [Int: Int] {
        switch form {
        case .ab: [:]
        case .abac: [4: 0, 5: 1]
        case .aaba: [2: 0, 6: 0]
        }
    }

    // MARK: one candidate

    private struct Slot {
        let bar: Int
        let beat: Double
        let value: NoteValue
        let chord: Chord
        let clef: Clef
    }

    private static func rhythms(_ request: SongRequest, form: SongForm, chords: [[Chord]], copy: Bool,
                                using rng: inout SeededRandom) -> [[NoteValue]] {
        let n = request.bars
        let body = bodyCells(request.meter, level: request.level)
        var out: [[NoteValue]] = []
        var phraseCells: [[NoteValue]] = []
        for bar in 0..<n {
            if bar == n / 2 { phraseCells = [] }
            if copy, let source = copies(form)[bar] {
                out.append(out[source])
                if phraseCells.count < 2, !phraseCells.contains(out[source]) { phraseCells.append(out[source]) }
                continue
            }
            var options: [(cell: [NoteValue], weight: Double)]
            if bar == n - 1 {
                options = finalCells(request.meter).map { ($0, 1) }
            } else if bar == n / 2 - 1 {
                options = phraseEndCells(request.meter).map { ($0, 1) }
            } else if phraseCells.count >= 2 {
                // at most 2 body cells a phrase, so bars share rhythms
                options = phraseCells.map { ($0, 1) }
            } else {
                options = body
            }
            // a chord change at beat 3 needs a note starting there
            if chords[bar].count > 1 { options = options.filter { onsets($0.cell).contains(2) } }
            let cell = options[weightedIndex(options.map(\.weight), using: &rng)].cell
            if bar != n - 1, bar != n / 2 - 1, !phraseCells.contains(cell) { phraseCells.append(cell) }
            out.append(cell)
        }
        return out
    }

    static func onsets(_ cell: [NoteValue]) -> [Double] {
        var beat = 0.0
        return cell.map { value in
            defer { beat += value.beats }
            return beat
        }
    }

    private static func candidate(_ request: SongRequest, form: SongForm, chords: [[Chord]], title: String, seed: UInt64,
                                  using rng: inout SeededRandom) -> Song? {
        let n = request.bars
        let copy = unitInterval(&rng) < 0.7
        let rhythm = rhythms(request, form: form, chords: chords, copy: copy, using: &rng)
        let handOf = { (bar: Int) in bar < n / 2 ? request.hands[0] : request.hands[1] }
        var slots: [Slot] = []
        var barStart: [Int] = []
        for bar in 0..<n {
            barStart.append(slots.count)
            for (value, beat) in zip(rhythm[bar], onsets(rhythm[bar])) {
                let chord = chords[bar].count > 1 && beat >= 2 ? chords[bar][1] : chords[bar][0]
                slots.append(Slot(bar: bar, beat: beat, value: value, chord: chord, clef: handOf(bar)))
            }
        }
        let midSlot = barStart[n / 2] - 1
        let finalSlot = slots.count - 1
        let copyMap = copies(form)

        // per slot, fixed from the rhythm: the hand's notes, the previous slot in the same
        // hand, how many of this hand's slots come after it
        let sets = slots.map { request.notes($0.clef) }
        let prevSlot = slots.indices.map { i in i > 0 && slots[i - 1].clef == slots[i].clef ? i - 1 : -1 }
        let handLeft = slots.indices.map { i in slots[(i + 1)...].filter { $0.clef == slots[i].clef }.count }
        let midGoals = sets[midSlot].filter { midCadenceAllowed($0, chord: slots[midSlot].chord, level: request.level) }
        let finalGoals = sets[finalSlot].filter(approachesFinal)

        // what can go at slot i after `melody` (slots 0..<i), best guess first
        func options(_ i: Int, _ melody: [Pitch], using rng: inout SeededRandom) -> [Pitch] {
            let slot = slots[i]
            let set = sets[i]
            let pi = prevSlot[i]
            let prev: Pitch? = pi >= 0 ? melody[pi] : nil
            let prevMove: Int? = pi >= 0 && prevSlot[pi] >= 0 ? melody[pi].diatonicIndex - melody[prevSlot[pi]].diatonicIndex : nil
            let prevChordTone = pi >= 0 ? slots[pi].chord.contains(melody[pi]) : true
            // after a non-chord tone, in an eighth pair, and right after one: a step
            let stepOnly = !prevChordTone
                || (slot.value == .eighth && pi >= 0 && slots[pi].value == .eighth && slots[pi].bar == slot.bar)
                || (pi >= 0 && slots[pi].value == .eighth && slot.value != .eighth)
            // the notes this hand hasn't played yet: they have to fit in the slots left
            var unused = set
            var j = pi
            while j >= 0, !unused.isEmpty {
                if let k = unused.firstIndex(of: melody[j]) { unused.remove(at: k) }
                j = prevSlot[j]
            }

            func fits(_ p: Pitch) -> Bool {
                let isChordTone = slot.chord.contains(p)
                if slot.beat == 0, !isChordTone { return false }
                let stillUnused = unused.count - (unused.contains(p) ? 1 : 0)
                if stillUnused > handLeft[i] { return false }
                guard let prev else {
                    // a hand's first note: a chord tone (the song's first: G, B or D)
                    return isChordTone
                }
                let d = p.diatonicIndex - prev.diatonicIndex
                if !moveAllowed(from: prev, to: p, level: request.level, set: set) { return false }
                if let prevMove, abs(prevMove) >= 3, !(abs(d) == 1 && d.signum() == -prevMove.signum()) { return false }
                if stepOnly, abs(d) != 1 { return false }
                if abs(d) >= 2, !(isChordTone && prevChordTone) { return false }
                if !isChordTone, abs(d) != 1 { return false }
                if p.pitchClass + prev.pitchClass == 6, p.pitchClass * prev.pitchClass == 0 { return false } // C-F#
                // the same key at most 4 times running
                var run = 1
                var j = pi
                while j >= 0, melody[j] == p { run += 1; j = prevSlot[j] }
                return run <= 4
            }

            // fixed slots
            var allowed = set.filter(fits)
            if i == 0 {
                allowed = allowed.filter { [.g, .b, .d].contains($0.letter) }
            } else if i == midSlot {
                allowed = isLong(slot) ? allowed.filter { midGoals.contains($0) } : []
            } else if i == finalSlot {
                allowed = allowed.filter { $0.letter == .g }
            } else if i == finalSlot - 1, slots[finalSlot].clef == slot.clef {
                allowed = allowed.filter { p in
                    finalGoals.contains(p) && set.contains { $0.letter == .g && moveAllowed(from: p, to: $0, level: request.level, set: set) }
                }
            } else {
                // keep the next fixed note in reach
                let target = i < midSlot ? midSlot : finalSlot - 1
                if slots[target].clef == slot.clef {
                    let goals = target == midSlot ? midGoals : finalGoals
                    let left = target - i
                    allowed = allowed.filter { p in goals.contains { reach(from: p, to: $0, level: request.level, set: set) <= left } }
                }
            }
            guard !allowed.isEmpty else { return [] }
            // notes this hand hasn't played yet come up more, so every one of his notes gets in
            var ordered = order(allowed, from: prev, level: request.level, favour: { unused.contains($0) }, using: &rng)

            // a copied bar: the source note, in this hand's octave, first when it fits
            if copy, let source = copyMap[slot.bar], rhythm[source] == rhythm[slot.bar] {
                let original = melody[barStart[source] + i - barStart[slot.bar]]
                let shift = slots[barStart[source]].clef == slot.clef ? 0 : (slot.clef == .bass ? -24 : 24)
                if let echo = ordered.firstIndex(where: { $0.midi == original.midi + shift }) {
                    ordered.insert(ordered.remove(at: echo), at: 0)
                }
            }
            return ordered
        }

        // depth first with a budget: a dead end steps back instead of throwing the
        // candidate away
        var melody: [Pitch] = []
        var stack: [[Pitch]] = [options(0, [], using: &rng)]
        var budget = 200
        while melody.count < slots.count {
            if stack[melody.count].isEmpty {
                stack.removeLast()
                guard !melody.isEmpty else { return nil }
                melody.removeLast()
                continue
            }
            budget -= 1
            guard budget > 0 else { return nil }
            melody.append(stack[melody.count].removeFirst())
            if melody.count < slots.count { stack.append(options(melody.count, melody, using: &rng)) }
        }

        // write it out
        var bars: [SongBar] = []
        for bar in 0..<n {
            let range = barStart[bar]..<(bar + 1 < n ? barStart[bar + 1] : slots.count)
            let notes = range.map { WrittenNote(slots[$0].clef, [melody[$0]], slots[$0].value) }
            bars.append(SongBar(notes, chords: chords[bar]))
        }
        if request.level >= 4 {
            bars = addDyads(bars, request: request, using: &rng)
        }
        return Song(seed: seed, level: request.level, meter: request.meter, keySignature: request.keySignature, form: form,
                    bars: bars, title: title, layout: request.layout)
    }

    private static func isLong(_ slot: Slot) -> Bool {
        slot.value.beats >= 2 && (slot.beat == 0 || slot.beat == 2)
    }

    /// Every allowed note, in a random order weighted by composer.md's mix of repeats,
    /// steps and skips (no skips in level 1), and toward notes `favour` picks.
    private static func order(_ allowed: [Pitch], from prev: Pitch?, level: Int, favour: (Pitch) -> Bool,
                              using rng: inout SeededRandom) -> [Pitch] {
        let kinds = allowed.map { p in prev.map { kind(abs(p.diatonicIndex - $0.diatonicIndex), level: level) } ?? 1 }
        var counts = [0, 0, 0]
        for k in kinds { counts[k] += 1 }
        var weights = allowed.indices.map { i -> Double in
            let boost = favour(allowed[i]) ? 2.5 : 1
            guard prev != nil else { return boost }
            let share = [0.15, 0.6, 0.25][kinds[i]]
            return boost * share / Double(counts[kinds[i]])
        }
        var left = allowed
        var out: [Pitch] = []
        while !left.isEmpty {
            let i = weightedIndex(weights, using: &rng)
            out.append(left.remove(at: i))
            weights.remove(at: i)
        }
        return out
    }

    /// 0 repeat, 1 step, 2 skip. In level 1 a 3rd across a gap in his notes is his step.
    private static func kind(_ d: Int, level: Int) -> Int {
        d == 0 ? 0 : d == 1 || level == 1 ? 1 : 2
    }

    /// Level 1: a 2nd, or a 3rd over a note he doesn't have. From level 2: up to a 5th.
    static func moveAllowed(from a: Pitch, to b: Pitch, level: Int, set: [Pitch]) -> Bool {
        let d = abs(b.diatonicIndex - a.diatonicIndex)
        if level >= 2 { return d <= 4 }
        if d <= 1 { return true }
        guard d == 2 else { return false }
        let between = min(a.diatonicIndex, b.diatonicIndex) + 1
        return !set.contains { $0.diatonicIndex == between }
    }

    /// Fewest moves from `a` to `b`.
    private static func reach(from a: Pitch, to b: Pitch, level: Int, set: [Pitch]) -> Int {
        if level >= 2 { return (abs(b.diatonicIndex - a.diatonicIndex) + 3) / 4 }
        guard let i = set.firstIndex(of: a), let j = set.firstIndex(of: b) else { return Int.max }
        return abs(i - j)
    }

    static func midCadenceAllowed(_ p: Pitch, chord: Chord, level: Int) -> Bool {
        guard let name = NoteName(p), name != .g else { return false }
        if chord.isDominant { return name == .d || name == .a || (level >= 3 && name == .fSharp) }
        if chord == .I { return name == .b || name == .d }
        return false
    }

    static func approachesFinal(_ p: Pitch) -> Bool {
        guard let name = NoteName(p) else { return false }
        return name == .a || name == .fSharp || name == .d
    }

    // MARK: two at once (level 4)

    /// Level 4: phrase ends and some first beats get a second note from the bar's chord, a
    /// 3rd to a 5th apart. Melody on top, except the last G, which gets a B over it.
    private static func addDyads(_ bars: [SongBar], request: SongRequest, using rng: inout SeededRandom) -> [SongBar] {
        let n = bars.count
        return bars.indices.map { b in
            let bar = bars[b]
            let set = request.notes(bar.clef)
            let starts = bar.startBeats
            let notes = bar.notes.indices.map { i -> WrittenNote in
                let note = bar.notes[i]
                let p = note.pitches[0]
                let chord = bar.chord(atBeat: starts[i])
                let isFinal = b == n - 1 && i == bar.notes.count - 1
                let isMid = b == n / 2 - 1 && i == bar.notes.count - 1
                // phrase ends often, other first beats now and then (not the song's first note)
                let chance = isFinal || isMid ? 0.75 : i == 0 && b > 0 ? 0.3 : 0
                guard chance > 0, unitInterval(&rng) < chance else { return note }
                let partners = set.filter { q in
                    // the last G gets the B above it (G+B), everything else a note below
                    let d = isFinal ? q.diatonicIndex - p.diatonicIndex : p.diatonicIndex - q.diatonicIndex
                    return (isFinal ? 2...2 : 2...4).contains(d) && chord.contains(q) && chord.contains(p)
                }
                guard !partners.isEmpty else { return note }
                let partner = partners[min(partners.count - 1, Int(unitInterval(&rng) * Double(partners.count)))]
                return WrittenNote(note.clef, [p, partner], note.value, rests: note.restsAfter)
            }
            return SongBar(notes, chords: bar.chords)
        }
    }

    // MARK: hard rules

    /// The note he follows in a column: the top one, except the last column's G.
    static func melody(_ note: WrittenNote, isFinal: Bool) -> Pitch {
        if isFinal, let g = note.pitches.first(where: { $0.letter == .g }) { return g }
        return note.pitches.last!
    }

    /// Every hard rule the song breaks, in words (empty = a good song). `notes` gives his
    /// notes per clef.
    public static func violations(_ song: Song, notes setFor: (Clef) -> [Pitch]) -> [String] {
        var out: [String] = []
        let notes = song.notes
        let n = notes.count
        let barOf = song.barOfNote
        let starts = song.bars.flatMap(\.startBeats)
        let chordAt = notes.indices.map { song.bars[barOf[$0]].chord(atBeat: starts[$0]) }
        let line = notes.indices.map { melody(notes[$0], isFinal: $0 == n - 1) }
        let clefs = notes.map(\.clef)
        let midIndex = song.barStarts[song.phraseOneEnd + 1] - 1

        // what he can play at his level
        if song.level < 5, notes.contains(where: { $0.value == .eighth }) { out.append("eighths before level 5") }
        if song.level < 4, notes.contains(where: \.isChord) { out.append("two at once before level 4") }
        if song.level < 3, notes.contains(where: { $0.pitches.contains { !$0.isWhiteKey } }) { out.append("F# before level 3") }
        for (b, bar) in song.bars.enumerated() where bar.chords.count > 1 {
            if b != song.phraseOneEnd, b < song.bars.count - 2 { out.append("bar \(b + 1): a chord change away from a cadence") }
        }
        // his notes, all of them
        for clef in Clef.allCases where clefs.contains(clef) {
            let set = setFor(clef)
            let used = Set(notes.filter { $0.clef == clef }.flatMap(\.pitches))
            for p in used where !set.contains(p) { out.append("\(clef.rawValue) \(p.name) isn't one of his notes") }
            for p in set where !used.contains(p) { out.append("\(clef.rawValue) \(p.name) is never used") }
        }
        // start and the two cadences
        if ![Letter.g, .b, .d].contains(line[0].letter) { out.append("starts on \(line[0].name)") }
        let strong = { (i: Int) in starts[i] == 0 || (song.meter == .fourFour && starts[i] == 2) }
        if !strong(midIndex) || notes[midIndex].value.beats < 2 { out.append("phrase 1 doesn't end on a long note on a strong beat") }
        if !midCadenceAllowed(line[midIndex], chord: chordAt[midIndex], level: song.level) {
            out.append("phrase 1 ends on \(line[midIndex].name) over \(chordAt[midIndex].rawValue)")
        }
        if line[n - 1].letter != .g { out.append("ends on \(line[n - 1].name)") }
        if !strong(n - 1) { out.append("the last note isn't on a strong beat") }
        if notes.contains(where: { $0.value.beats > notes[n - 1].value.beats }) { out.append("the last note isn't the longest") }
        if let approach = line[..<(n - 1)].last(where: { $0.letter != .g }), !approachesFinal(approach) {
            out.append("the last G comes from \(approach.name)")
        }
        // harmony and moves, one hand at a time
        var run = 1
        for i in 0..<n {
            let chord = chordAt[i]
            let tones = notes[i].pitches
            if starts[i] == 0, !tones.allSatisfy(chord.contains) { out.append("bar \(barOf[i] + 1) beat 1: \(line[i].name) isn't in \(chord.rawValue)") }
            if tones.count > 1, !tones.allSatisfy(chord.contains) { out.append("note \(i + 1): two at once outside \(chord.rawValue)") }
            let hasPrev = i > 0 && clefs[i - 1] == clefs[i]
            let hasNext = i + 1 < n && clefs[i + 1] == clefs[i]
            let into = hasPrev ? line[i].diatonicIndex - line[i - 1].diatonicIndex : nil
            let out_ = hasNext ? line[i + 1].diatonicIndex - line[i].diatonicIndex : nil
            if !chord.contains(line[i]) {
                // stepped into, and out by step (or held into the next chord, like Ode to Joy's bar 4)
                let leftOK = out_.map { abs($0) == 1 || ($0 == 0 && chordAt[i + 1].contains(line[i + 1]) && starts[i + 1] != starts[i]) } ?? false
                if into.map({ abs($0) != 1 }) ?? true || !leftOK { out.append("note \(i + 1): \(line[i].name) isn't in \(chord.rawValue) and isn't stepped") }
            }
            guard let d = into else { run = 1; continue }
            let set = setFor(clefs[i])
            if !moveAllowed(from: line[i - 1], to: line[i], level: song.level, set: set) { out.append("note \(i + 1): a move of \(abs(d) + 1)") }
            if abs(d) >= 2, !(chordAt[i - 1].contains(line[i - 1]) && chord.contains(line[i])) { out.append("note \(i + 1): a skip between non-chord tones") }
            if Set([line[i].pitchClass, line[i - 1].pitchClass]) == [0, 6] { out.append("note \(i + 1): a C-F# leap") }
            if i >= 2, clefs[i - 2] == clefs[i] {
                let before = line[i - 1].diatonicIndex - line[i - 2].diatonicIndex
                if abs(before) >= 3, !(abs(d) == 1 && d.signum() == -before.signum()) { out.append("note \(i + 1): no step back after a leap") }
            }
            run = d == 0 && line[i] == line[i - 1] ? run + 1 : 1
            if run > 4 { out.append("note \(i + 1): the same key \(run) times") }
        }
        return out
    }

    // MARK: score

    /// Higher sounds more like a song (composer.md). Moves are counted inside each hand,
    /// and echoes across a hand flip compare letters, not keys.
    public static func score(_ song: Song) -> Double {
        let notes = song.notes
        let n = notes.count
        let line = notes.indices.map { melody(notes[$0], isFinal: $0 == n - 1) }
        let clefs = notes.map(\.clef)
        var s = 0.0

        // unit 3 back to unit 1 (a b a c), units 2 and 4 starting like unit 1 (a a' b a'')
        let letters = { (bar: Int) in song.bars[bar].notes.map { "\($0.pitches.last!.naturalLetter)\($0.pitches.last!.isWhiteKey ? "" : "#")/\($0.value.rawValue)" } }
        let near = { (a: [String], b: [String]) in a.count == b.count && zip(a, b).filter { $0 != $1 }.count <= 1 }
        switch song.form {
        case .ab: break
        case .abac:
            if near(letters(0) + letters(1), letters(4) + letters(5)) { s += 3 }
        case .aaba:
            s += (near(letters(0), letters(2)) ? 1.5 : 0) + (near(letters(0), letters(6)) ? 1.5 : 0)
        }
        // bars sharing rhythm cells
        let n2 = song.bars.count
        let body = song.bars.indices.filter { $0 != n2 - 1 && $0 != n2 / 2 - 1 }.map { song.bars[$0].notes.map(\.value) }
        let distinct = body.reduce(into: [[NoteValue]]()) { if !$0.contains($1) { $0.append($1) } }.count
        if distinct <= 2 { s += 2 } else if distinct <= 3 { s += 1 }
        // A or F# right before the last G, the line coming down into it
        if let approach = line[..<(n - 1)].last(where: { $0.letter != .g }) {
            if approach.letter == .a || !approach.isWhiteKey { s += 2 }
        }
        if n >= 3, clefs[n - 3] == clefs[n - 1], line[n - 3] >= line[n - 2], line[n - 2] > line[n - 1] { s += 1 }
        // the top note arrives late
        let height = line.indices.map { line[$0].diatonicIndex - (clefs[$0] == .treble ? 32 : 18) } // G4 / G2
        if let top = height.max(), let first = height.firstIndex(of: top), Double(first) >= Double(n) * 0.4 { s += 1 }

        // moves, inside each hand
        var moves: [Int] = []
        for i in 1..<n where clefs[i] == clefs[i - 1] { moves.append(line[i].diatonicIndex - line[i - 1].diatonicIndex) }
        if !moves.isEmpty {
            let m = Double(moves.count)
            let steps = Double(moves.filter { abs($0) == 1 }.count) / m
            if song.level >= 2, (0.55...0.8).contains(steps) { s += 1 }
            if Double(moves.filter { $0 == 0 }.count) / m > 0.25 { s -= 2 }
            if maxRun(moves.map { $0.signum() }.filter { $0 != 0 }) >= 5 { s -= 1 }
            if zigzag(moves) >= 4 { s -= 1 }
        }
        let counts = Dictionary(grouping: line, by: { $0 }).values.map(\.count)
        if let most = counts.max(), Double(most) / Double(n) > 0.35 { s -= 1 }
        return s
    }

    private static func maxRun(_ values: [Int]) -> Int {
        var best = 0, run = 0
        var last: Int?
        for v in values {
            run = v == last ? run + 1 : 1
            last = v
            best = max(best, run)
        }
        return best
    }

    /// Longest run of direction changes in a row.
    private static func zigzag(_ moves: [Int]) -> Int {
        let dirs = moves.map { $0.signum() }.filter { $0 != 0 }
        var best = 0, run = 0
        for i in dirs.indices.dropFirst() {
            run = dirs[i] != dirs[i - 1] ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    // MARK: fallback

    /// Hand-written songs for when every candidate broke a rule: G and the note next to
    /// it (A, or the F# under G in level 3's upper five), and B when he has it. Plain, but
    /// always a song.
    static func fallback(_ request: SongRequest, title: String, seed: UInt64) -> Song {
        let q = NoteValue.quarter, h = NoteValue.half, w = NoteValue.whole, dh = NoteValue.dottedHalf
        // 0 = G, 1 = its neighbour (A or F#), 2 = B (or G again)
        typealias Bar = (chords: [Chord], notes: [(Int, NoteValue)])
        let four = request.meter == .fourFour
        let bars: [Bar]
        if request.bars == 4 {
            bars = four
                ? [([.I], [(0, q), (1, q), (2, h)]), ([.V], [(1, q), (2, q), (1, h)]), ([.V7], [(1, h), (2, q), (1, q)]), ([.I], [(0, w)])]
                : [([.I], [(0, q), (1, q), (2, q)]), ([.V], [(1, dh)]), ([.V7], [(1, q), (2, q), (1, q)]), ([.I], [(0, dh)])]
        } else {
            let a: [Bar] = four
                ? [([.I], [(0, q), (1, q), (2, h)]), ([.IV], [(0, q), (1, q), (0, h)])]
                : [([.I], [(0, q), (1, q), (2, q)]), ([.IV], [(0, dh)])]
            let b: [Bar] = four
                ? [([.I], [(2, q), (1, q), (0, h)]), ([.V], [(1, q), (2, q), (1, h)])]
                : [([.I], [(2, q), (1, q), (0, q)]), ([.V], [(1, dh)])]
            let c: [Bar] = four
                ? [([.V7], [(1, h), (2, q), (1, q)]), ([.I], [(0, w)])]
                : [([.V7], [(1, q), (2, q), (1, q)]), ([.I], [(0, dh)])]
            bars = a + b + a + c
        }
        let n = bars.count
        let songBars = bars.enumerated().map { b, bar in
            let clef = b < n / 2 ? request.hands[0] : request.hands[1]
            let set = request.notes(clef)
            let g = set.first { $0.letter == .g } ?? (clef == .treble ? Pitch(.g, 4) : Pitch(.g, 2))
            let up = set.first { $0.diatonicIndex == g.diatonicIndex + 1 }
            let neighbour = up ?? set.first { $0.diatonicIndex == g.diatonicIndex - 1 } ?? Pitch(.a, g.octave)
            let third = up != nil ? set.first { $0.diatonicIndex == g.diatonicIndex + 2 } ?? g : g
            let notes = bar.notes.map { step, value in WrittenNote(clef, [[g, neighbour, third][step]], value) }
            return SongBar(notes, chords: bar.chords)
        }
        return Song(seed: seed, level: request.level, meter: request.meter, keySignature: request.keySignature,
                    form: request.bars == 4 ? .ab : .abac, bars: songBars, title: title, layout: request.layout, isFallback: true)
    }

    // MARK: titles

    /// First grade words: a colour or a food, an animal or a thing, and a way of moving
    /// that fits the meter ("Blue Bug Hop", "Pickle Sway"). Never a praise word.
    static let colours = ["Red", "Blue", "Green", "Pink", "Purple", "Orange", "Yellow", "Gold"]
    static let foods = ["Pickle", "Muffin", "Noodle", "Pancake", "Cookie", "Banana", "Waffle", "Popcorn", "Jelly", "Taco"]
    static let things = ["Bug", "Frog", "Duck", "Cat", "Pig", "Bee", "Fox", "Owl", "Hen", "Moon", "Star", "Boat", "Sock", "Hat", "Fish", "Bear"]
    static let fourFourMoves = ["Hop", "March", "Stomp", "Parade"]
    static let threeFourMoves = ["Sway", "Waltz", "Swing"]

    public static func title(meter: Meter, using rng: inout SeededRandom) -> String {
        func any(_ words: [String]) -> String { words[min(words.count - 1, Int(unitInterval(&rng) * Double(words.count)))] }
        let move = any(meter == .fourFour ? fourFourMoves : threeFourMoves)
        let roll = unitInterval(&rng)
        if roll < 0.45 { return "\(any(colours)) \(any(things)) \(move)" }
        if roll < 0.75 { return "\(any(foods)) \(move)" }
        return "\(any(foods)) \(any(things)) \(move)"
    }
}
