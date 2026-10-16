/// A screen the engine picked, and what kind it is.
public struct Pick: Hashable, Sendable {
    public let item: PracticeItem
    /// The note this screen introduces (one note, keyboard picture up), if it's an intro.
    public let intro: NoteKey?
    /// The first screen of a lesson with a new texture (two at once, rhythm), played to
    /// him before he reads it.
    public let isLessonIntro: Bool
    /// Made from his strongest notes (`.strongest`, unless it had to fall back).
    public let usedStrongest: Bool
    /// One note more than his current size.
    public let isStretch: Bool
    /// In the lesson's unit: columns, or bars on rhythm screens.
    public let size: Int
}

/// Screen picking: which clef, an intro or a generated screen, and the notes on it.
///
/// - clef: weighted toward the weaker clef (lower boxes, notes still to come), the
///   lesson's focus clef counts double, never 3 screens in a row on one clef
/// - a new note's intro is one note on its own. Once a clef has 2 notes he has met,
///   intros on it never come back to back, so there's reading in between
/// - a generated screen has `screenSize` notes, weighted toward low boxes, moving by
///   steps, skips and repeats in the lesson's mix. The newest notes get about 1 in 4
///   of the notes on their clef. The same key never comes 3 times in a row
/// - no screen identical to one of the recent ones (fewer when the pool is small)
/// - doing well: now and then one note more (stretch)
extension MasteryEngine {
    public mutating func pickScreen(_ style: PickStyle = .normal, using rng: inout some RandomNumberGenerator) -> Pick {
        var style = style
        if style == .strongest, lesson.clefs.allSatisfy({ strongestNotes($0).isEmpty }) {
            style = .normal // nothing played here yet
        }
        let clef = chooseClef(style, using: &rng)
        // a lesson with a new texture opens by showing him one (two at once, a rhythm)
        if style == .normal, lesson.texture != .single, !state.introduced.contains(lessonIntroID), !playable(clef).isEmpty {
            return remember(lessonIntro(on: clef, using: &rng))
        }
        if style == .normal || playable(clef).isEmpty, let intro = introDue(on: clef, using: &rng) {
            let item = PracticeItem(intro, layout: lesson.staff(for: clef), keySignature: lesson.keySignature)
            return remember(Pick(item: item, intro: intro, isLessonIntro: false, usedStrongest: false, isStretch: false, size: 1))
        }
        return remember(generate(on: clef, strongest: style == .strongest, using: &rng))
    }

    /// His strongest notes on a clef: the top two boxes among notes he has played here,
    /// at least 2 notes when he has played 2.
    public func strongestNotes(_ clef: Clef) -> [NoteKey] {
        let played = playable(clef).filter { stats(for: $0).attempts > 0 }
        let ranked = played.sorted { a, b in
            let sa = stats(for: a), sb = stats(for: b)
            if sa.box != sb.box { return sa.box > sb.box }
            return (sa.recentFirstTryRate ?? 0) > (sb.recentFirstTryRate ?? 0)
        }
        guard let top = ranked.first.map({ stats(for: $0).box }) else { return [] }
        let tier = ranked.filter { stats(for: $0).box >= top - 1 }
        return tier.count >= 2 ? tier : Array(ranked.prefix(2))
    }

    // MARK: clef and intros

    private func chooseClef(_ style: PickStyle, using rng: inout some RandomNumberGenerator) -> Clef {
        let lesson = self.lesson
        var candidates = lesson.clefs.filter { clef in
            style == .strongest ? !strongestNotes(clef).isEmpty : !playable(clef).isEmpty || !pendingIntros(clef).isEmpty
        }
        if candidates.isEmpty {
            candidates = lesson.clefs.filter { !pool($0).isEmpty }
        }
        precondition(!candidates.isEmpty, "lesson \(lesson.id) has nothing unlocked")
        guard candidates.count > 1 else { return candidates[0] }
        let last = state.recentScreens.suffix(2).compactMap(Self.leadingClef)
        if let focus = Clef(rawValue: lesson.focus.rawValue), let previous = last.last {
            // focus lessons: the other clef never twice in a row, the focus clef never 3
            // times, so it gets about 5 screens in 8
            if previous != focus { return focus }
            if last.count == 2, last[0] == focus, let other = candidates.first(where: { $0 != focus }) { return other }
        } else if last.count == 2, last[0] == last[1], let other = candidates.first(where: { $0 != last[0] }) {
            return other
        }
        if style == .strongest {
            return candidates.first { $0 != last.last } ?? candidates[0]
        }
        let weights = candidates.map { clef in
            weakness(clef) * (lesson.focus.rawValue == clef.rawValue ? 2 : 1)
        }
        return candidates[weightedIndex(weights, using: &rng)]
    }

    /// Higher for a clef he's weaker on: the average of (6 - box) over its notes, plus
    /// one while it still has notes to meet.
    private func weakness(_ clef: Clef) -> Double {
        let notes = playable(clef)
        let average = notes.isEmpty ? Double(config.boxCount)
            : notes.reduce(0.0) { $0 + Double(config.boxCount + 1 - stats(for: $1).box) } / Double(notes.count)
        let waiting = pendingIntros(clef).isEmpty && lockedNew(clef).isEmpty ? 0.0 : 1.0
        return average + waiting
    }

    private func introDue(on clef: Clef, using rng: inout some RandomNumberGenerator) -> NoteKey? {
        let pending = pendingIntros(clef)
        guard !pending.isEmpty else { return nil }
        if state.lastScreenWasIntro, playable(clef).count >= 2 { return nil }
        return pending[min(pending.count - 1, Int(unitInterval(&rng) * Double(pending.count)))]
    }

    static func leadingClef(_ screenID: ItemID) -> Clef? {
        screenID.split(separator: ":").first.flatMap { Clef(rawValue: String($0)) }
    }

    // MARK: generating

    private func generate(on clef: Clef, strongest: Bool, using rng: inout some RandomNumberGenerator) -> Pick {
        var size = state.screenSize
        var stretch = false
        // no stretch on rhythm screens: a third bar wouldn't fit the staff
        if !strongest, !lesson.texture.isRhythm, isDoingWell, unitInterval(&rng) < config.stretchChance, size < lesson.sizes.upperBound + 1 {
            size += 1
            stretch = true
        }
        let notes = { (c: Clef) in strongest ? strongestNotes(c) : playable(c) }

        // how many different screens this pool can make, roughly, sets how far back to
        // look for a repeat: a 3-note pool with 1 note per screen can only avoid the last one
        let poolSize = Double(Set(lesson.clefs.flatMap(notes)).count)
        var possible = 1.0
        for _ in 0..<size { possible = min(1e6, possible * max(1, poolSize)) }
        let window = min(config.recentScreens, max(1, Int(possible / 3)))
        let avoid = state.recentScreens.suffix(window)

        var best: PracticeItem?
        var bestSeen = Int.max
        for _ in 0..<12 {
            let item = build(on: clef, size: size, notes: notes, withNewest: !strongest, using: &rng)
            guard let seen = avoid.lastIndex(of: item.id) else {
                best = item
                break
            }
            if best == nil || seen < bestSeen {
                best = item
                bestSeen = seen
            }
        }
        return Pick(item: best!, intro: nil, isLessonIntro: false, usedStrongest: strongest, isStretch: stretch, size: size)
    }

    /// This clef's newest notes among `notes`, and the rest. While every note is new (a
    /// lesson's start set) there's nothing to set apart: no newest, all the rest.
    private func split(_ clef: Clef, _ notes: [NoteKey]) -> (newest: [NoteKey], others: [NoteKey]) {
        let newest = newestBatch(clef).filter(notes.contains)
        let others = notes.filter { !newest.contains($0) }
        return others.isEmpty ? ([], notes) : (newest, others)
    }

    private func build(on clef: Clef, size: Int, notes: (Clef) -> [NoteKey], withNewest: Bool, using rng: inout some RandomNumberGenerator) -> PracticeItem {
        let lesson = self.lesson
        let rhythm = lesson.texture.isRhythm
        func bar(_ count: Int, _ c: Clef, after: [ItemID], using rng: inout some RandomNumberGenerator) -> [WrittenNote] {
            let all = notes(c)
            let (newest, others) = split(c, all)
            return columns(count, on: c, from: others, newest: withNewest ? newest : [], fallback: all, after: after, using: &rng)
        }
        if lesson.layout == .grand {
            // a bar on one staff, then a bar on the other. falls back to one staff
            // while the other clef has nothing to show
            let other: Clef = clef == .treble ? .bass : .treble
            if size >= 2, !notes(clef).isEmpty, !notes(other).isEmpty {
                let a = (size + 1) / 2, b = size - a
                let barA = bar(a, clef, after: state.recentColumns, using: &rng)
                let barB = bar(b, other, after: barA.map(Self.columnID), using: &rng)
                return PracticeItem(barA + barB, layout: .grand, keySignature: lesson.keySignature,
                                    bars: rhythm ? nil : [barA.count, barB.count])
            }
            let only = notes(clef).isEmpty ? other : clef
            let line = bar(size, only, after: state.recentColumns, using: &rng)
            return PracticeItem(line, layout: .grand, keySignature: lesson.keySignature, bars: rhythm ? nil : Self.bars(line.count))
        }
        let line = bar(size, clef, after: state.recentColumns, using: &rng)
        return PracticeItem(line, layout: lesson.staff(for: clef), keySignature: lesson.keySignature, bars: rhythm ? nil : Self.bars(line.count))
    }

    /// One bar's worth (or `count` columns) in the lesson's texture.
    private func columns(_ count: Int, on clef: Clef, from pool: [NoteKey], newest: [NoteKey], fallback: [NoteKey],
                         after: [ItemID], using rng: inout some RandomNumberGenerator) -> [WrittenNote] {
        switch lesson.texture {
        case .single:
            return line(count, from: pool, newest: newest, fallback: fallback, after: after, using: &rng).map { WrittenNote($0) }
        case .dyads(let intervals):
            var keys = line(count, from: pool, newest: newest, fallback: fallback, after: after, using: &rng)
            // a line along the top of the range has nothing to put above it: swap one
            // note for the nearest one that can carry a second note
            let carriers = fallback.filter { low in fallback.contains { intervals.contains($0.pitch.diatonicIndex - low.pitch.diatonicIndex) } }
            let canCarry = { (k: NoteKey) in carriers.contains(k) }
            if !keys.contains(where: canCarry), !carriers.isEmpty {
                let i = min(keys.count - 1, Int(unitInterval(&rng) * Double(keys.count)))
                keys[i] = carriers.min { abs($0.pitch.diatonicIndex - keys[i].pitch.diatonicIndex) < abs($1.pitch.diatonicIndex - keys[i].pitch.diatonicIndex) }!
            }
            return dyads(keys, intervals: intervals, uppers: fallback, using: &rng)
        case .rhythm(let values, let oneNote):
            let lengths = Self.rhythm(bars: count, from: values, using: &rng)
            let keys = oneNote
                ? Array(repeating: line(1, from: pool, newest: newest, fallback: fallback, after: after, using: &rng)[0], count: lengths.count)
                : line(lengths.count, from: pool, newest: newest, fallback: fallback, after: after, using: &rng)
            return zip(keys, lengths).map { WrittenNote($0, $1) }
        }
    }

    /// About half the notes get a second note above them, `intervals` letters up, from
    /// `uppers` (notes he has). At least one dyad when any note can take one.
    private func dyads(_ keys: [NoteKey], intervals: [Int], uppers: [NoteKey], using rng: inout some RandomNumberGenerator) -> [WrittenNote] {
        let options = keys.map { key in
            uppers.filter { intervals.contains($0.pitch.diatonicIndex - key.pitch.diatonicIndex) }
        }
        func dyad(_ i: Int, using rng: inout some RandomNumberGenerator) -> WrittenNote {
            let weights = options[i].map { Double(config.boxCount + 1 - stats(for: $0).box) }
            let upper = options[i][weightedIndex(weights, using: &rng)]
            return WrittenNote(keys[i].clef, [keys[i].pitch, upper.pitch])
        }
        var out = keys.map { WrittenNote($0) }
        for i in keys.indices where !options[i].isEmpty && unitInterval(&rng) < 0.5 {
            out[i] = dyad(i, using: &rng)
        }
        let eligible = keys.indices.filter { !options[$0].isEmpty }
        if !out.contains(where: \.isChord), !eligible.isEmpty {
            let i = eligible[min(eligible.count - 1, Int(unitInterval(&rng) * Double(eligible.count)))]
            out[i] = dyad(i, using: &rng)
        }
        return out
    }

    /// `bars` bars of 4/4 from quarters, halves and beamed eighth pairs (at most one pair
    /// a bar, on a beat). Always 3+ notes and at least two different lengths, or the
    /// rhythm judge can't tell anything at his tempo (context/notecore-design.md).
    static func rhythm(bars: Int, from allowed: [NoteValue], using rng: inout some RandomNumberGenerator) -> [NoteValue] {
        for _ in 0..<40 {
            var values: [NoteValue] = []
            for _ in 0..<max(1, bars) { values += rhythmBar(allowed, using: &rng) }
            if values.count >= 3, Set(values).count >= 2 { return values }
        }
        return Array([[NoteValue]](repeating: [.quarter, .quarter, .half], count: max(1, bars)).joined())
    }

    private static func rhythmBar(_ allowed: [NoteValue], using rng: inout some RandomNumberGenerator) -> [NoteValue] {
        var beats = 0.0
        var out: [NoteValue] = []
        var pair = false
        while beats < 4 {
            var cells: [[NoteValue]] = []
            var weights: [Double] = []
            if allowed.contains(.quarter) { cells.append([.quarter]); weights.append(0.45) }
            if allowed.contains(.half), beats + 2 <= 4 { cells.append([.half]); weights.append(0.3) }
            if allowed.contains(.eighth), !pair { cells.append([.eighth, .eighth]); weights.append(0.25) }
            if cells.isEmpty { cells = [[.quarter]]; weights = [1] }
            let cell = cells[weightedIndex(weights, using: &rng)]
            pair = pair || cell.first == .eighth
            out += cell
            beats += cell.reduce(0) { $0 + $1.beats }
        }
        return out
    }

    /// The first screen of a lesson with a new texture, shown to him before he plays:
    /// one dyad (a third when there is one), or one bar of rhythm.
    private func lessonIntro(on clef: Clef, using rng: inout some RandomNumberGenerator) -> Pick {
        let notes = playable(clef)
        let layout = lesson.staff(for: clef)
        var columns: [WrittenNote]
        switch lesson.texture {
        case .dyads(let intervals):
            let pairs = notes.flatMap { low in
                notes.filter { $0.pitch.diatonicIndex - low.pitch.diatonicIndex == (intervals.min() ?? 2) }.map { (low, $0) }
            }
            if let (low, high) = pairs.isEmpty ? nil : pairs[min(pairs.count - 1, Int(unitInterval(&rng) * Double(pairs.count)))] {
                columns = [WrittenNote(clef, [low.pitch, high.pitch])]
            } else {
                columns = [WrittenNote(notes[0])]
            }
        case .rhythm(let values, let oneNote):
            let lengths = Self.rhythm(bars: 1, from: values, using: &rng)
            let keys = oneNote ? Array(repeating: notes[min(notes.count - 1, Int(unitInterval(&rng) * Double(notes.count)))], count: lengths.count)
                : line(lengths.count, from: notes, newest: [], fallback: notes, after: state.recentColumns, using: &rng)
            columns = zip(keys, lengths).map { WrittenNote($0, $1) }
        case .single:
            columns = [WrittenNote(notes[0])]
        }
        let item = PracticeItem(columns, layout: layout, keySignature: lesson.keySignature, bars: lesson.texture.isRhythm ? nil : [columns.count])
        return Pick(item: item, intro: nil, isLessonIntro: true, usedStrongest: false, isStretch: false, size: 1)
    }

    /// Up to 4 notes in one bar, more split into even bars: 5 -> 3 + 2, 8 -> 4 + 4.
    public static func bars(_ count: Int) -> [Int] {
        guard count > 4 else { return [count] }
        let bars = (count + 3) / 4
        return (0..<bars).map { count / bars + ($0 < count % bars ? 1 : 0) }
    }

    enum Move { case same, step, skip }

    /// `count` notes in a row. Each slot is one of `newest` with chance `newestShare`
    /// (25%: the newest notes get about 1 in 4 of the notes he reads on that clef, which
    /// at one note a screen is 1 screen in 4), otherwise one of `pool`. Each move from the
    /// last note is a repeat, a step or a skip (third to fifth), rolled from the lesson's
    /// contour mix, then a note that fits is picked by weight (6 - box). When no note
    /// fits, any note goes. `after` is what came just before (column ids), so a run of
    /// the same key can't carry over from the last screen. `fallback` is used when the
    /// run rule leaves nothing to pick.
    func line(_ count: Int, from pool: [NoteKey], newest: [NoteKey], fallback: [NoteKey], after: [ItemID], using rng: inout some RandomNumberGenerator) -> [NoteKey] {
        precondition(!pool.isEmpty)
        var out: [NoteKey] = []
        for _ in 0..<count {
            let history = (after + out.map(\.id)).suffix(config.maxRepeats)
            let blocked = history.count == config.maxRepeats && Set(history).count == 1 ? history.last : nil
            var source = pool
            if !newest.isEmpty, unitInterval(&rng) < config.newestShare {
                source = newest
            }
            var candidates = source.filter { $0.id != blocked }
            if candidates.isEmpty { candidates = fallback.filter { $0.id != blocked } }
            if candidates.isEmpty { candidates = fallback }
            if let previous = out.last {
                let move = rollMove(using: &rng)
                let fitting = candidates.filter { Self.fits(move, from: previous, to: $0) }
                if !fitting.isEmpty { candidates = fitting }
            }
            let weights = candidates.map { Double(config.boxCount + 1 - stats(for: $0).box) }
            out.append(candidates[weightedIndex(weights, using: &rng)])
        }
        return out
    }

    private func rollMove(using rng: inout some RandomNumberGenerator) -> Move {
        let (same, step): (Double, Double) = switch lesson.contour {
        case .mixed: (0.15, 0.45)
        case .steps: (0.15, 0.70)
        case .skips: (0.10, 0.20)
        }
        let roll = unitInterval(&rng)
        return roll < same ? .same : roll < same + step ? .step : .skip
    }

    static func fits(_ move: Move, from a: NoteKey, to b: NoteKey) -> Bool {
        let distance = abs(a.pitch.diatonicIndex - b.pitch.diatonicIndex)
        switch move {
        case .same: return a == b
        case .step: return distance == 1
        case .skip: return (2...4).contains(distance)
        }
    }

    private mutating func remember(_ pick: Pick) -> Pick {
        state.recentScreens = Array((state.recentScreens + [pick.item.id]).suffix(max(2, config.recentScreens)))
        let columns = pick.item.notes.map(Self.columnID)
        state.recentColumns = Array((state.recentColumns + columns).suffix(max(1, config.maxRepeats)))
        state.lastScreenWasIntro = pick.intro != nil || pick.isLessonIntro
        return pick
    }

    /// `"treble:G4"`, or `"treble:G4+B4"` for a dyad.
    static func columnID(_ note: WrittenNote) -> ItemID {
        "\(note.clef.rawValue):" + note.pitches.map(\.name).joined(separator: "+")
    }
}

/// Index picked with probability proportional to its weight.
func weightedIndex(_ weights: [Double], using rng: inout some RandomNumberGenerator) -> Int {
    let total = weights.reduce(0, +)
    guard total > 0 else { return 0 }
    var target = unitInterval(&rng) * total
    for (i, w) in weights.enumerated() {
        if target < w { return i }
        target -= w
    }
    return weights.count - 1
}
