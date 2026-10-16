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
        if !strongest, isDoingWell, unitInterval(&rng) < config.stretchChance, size < lesson.sizes.upperBound + 1 {
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
        func bar(_ count: Int, _ c: Clef, newest include: Bool, after: [ItemID], using rng: inout some RandomNumberGenerator) -> [NoteKey] {
            let all = notes(c)
            let (newest, others) = split(c, all)
            return line(count, from: others, newest: include ? newest : [], fallback: all, after: after, using: &rng)
        }
        if lesson.layout == .grand {
            // a bar on one staff, then a bar on the other. falls back to one staff
            // while the other clef has nothing to show
            let other: Clef = clef == .treble ? .bass : .treble
            if size >= 2, !notes(clef).isEmpty, !notes(other).isEmpty {
                let a = (size + 1) / 2, b = size - a
                let barA = bar(a, clef, newest: withNewest, after: state.recentColumns, using: &rng)
                let barB = bar(b, other, newest: withNewest, after: barA.map(\.id), using: &rng)
                return PracticeItem((barA + barB).map { WrittenNote($0) }, layout: .grand, keySignature: lesson.keySignature, bars: [a, b])
            }
            let only = notes(clef).isEmpty ? other : clef
            let keys = bar(size, only, newest: withNewest, after: state.recentColumns, using: &rng)
            return PracticeItem(keys.map { WrittenNote($0) }, layout: .grand, keySignature: lesson.keySignature, bars: Self.bars(size))
        }
        let keys = bar(size, clef, newest: withNewest, after: state.recentColumns, using: &rng)
        return PracticeItem(keys.map { WrittenNote($0) }, layout: lesson.staff(for: clef), keySignature: lesson.keySignature, bars: Self.bars(size))
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
