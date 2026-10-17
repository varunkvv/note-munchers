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
    /// The hand position each column is played in (finger numbers come from it). Every
    /// note of one staff on a screen is in one position, except a drill's shift screen.
    public var positions: [HandPosition] = []
    /// The drill's shape on a drill screen (and the warm-up's run), nil otherwise.
    public var drill: Drill?
}

/// Screen picking: which clef, an intro or a generated screen, and the notes on it.
///
/// - clef: one-clef lessons take the clef the session asks for (a session is two runs,
///   one per clef, see `PracticeSession`), or the other one when that clef has nothing
///   to show. Asked for nothing, weighted toward the weaker clef. Grand staff lessons:
///   which staff goes first, weighted toward the weaker clef, the focus clef counts
///   double, never 3 screens in a row starting on one clef
/// - a new note's intro is one note on its own. After an intro on a clef, at least
///   `introSpacing` screens on that clef before its next one (G, a couple of screens of
///   G, then A), unless there's nothing else to show. Paced lessons in their order
/// - a generated screen has `screenSize` notes, weighted toward low boxes, moving by
///   steps, skips and repeats in the lesson's mix. The newest notes get about 1 in 4
///   of the notes on their clef (1 in 3 in paced lessons). The same key never comes 3
///   times in a row (a clef with one note can't help it)
/// - one hand position per staff: when a clef's notes span more than five letters (level
///   3) the screen's notes on it stay inside one five-finger position (`HandPosition`)
/// - no screen identical to one of the recent ones (fewer when the pool is small)
/// - doing well: now and then one note more (stretch)
/// - every screen is whole bars of 3/4 or 4/4 (Bars.swift): the meter is rolled per
///   screen, the notes are written first, then each bar gets a rhythm that holds them
extension MasteryEngine {
    /// `clef`: the clef this part of the session is on (one-clef lessons). Ignored on
    /// the grand staff.
    public mutating func pickScreen(_ style: PickStyle = .normal, clef wanted: Clef? = nil,
                                    using rng: inout some RandomNumberGenerator) -> Pick {
        var style = style
        let wanted = lesson.layout == .alternating ? wanted : nil
        if style == .strongest || style == .warmUp,
           wanted.map({ strongestNotes($0).isEmpty }) ?? lesson.clefs.allSatisfy({ strongestNotes($0).isEmpty }) {
            // nothing played here yet: a normal screen, on the same clef
            style = .normal
        }
        let clef = chooseClef(style == .warmUp ? .strongest : style, wanted: wanted, using: &rng)
        if style == .warmUp {
            if let pick = warmUpPick(on: clef, using: &rng) { return remember(pick) }
            style = .strongest
        }
        // a drill lesson is all drills: no new notes, no new texture to show
        if style == .drill || (style == .normal && lesson.isDrillLesson && pendingIntros(clef).isEmpty) {
            let n: Int
            if lesson.isDrillLesson {
                n = lesson.texture.isRhythm ? lesson.drillSizes.lowerBound : state.screenSize
            } else {
                // a burst: a bit longer than his screens, now and then two more
                let base = lesson.texture.isRhythm ? lesson.drillSizes.lowerBound : state.screenSize + 1
                n = min(max(base + (unitInterval(&rng) < 0.3 ? 1 : 0), lesson.drillSizes.lowerBound), lesson.drillSizes.upperBound)
            }
            if let pick = drillPick(on: clef, size: n, using: &rng) { return remember(pick) }
            style = .normal
        }
        // a lesson with a new texture opens by showing him one (two at once, a rhythm)
        if style == .normal, !lesson.isDrillLesson, lesson.texture != .single, !state.introduced.contains(lessonIntroID), !playable(clef).isEmpty {
            return remember(lessonIntro(on: clef, using: &rng))
        }
        if style == .normal || playable(clef).isEmpty, let intro = introDue(on: clef, using: &rng) {
            // one bar, the note held for all of it: a whole note, or a dotted half in 3/4
            let meter = rollMeter(using: &rng)
            let note = WrittenNote(intro, meter == .fourFour ? .whole : .dottedHalf)
            let item = PracticeItem([note], layout: lesson.staff(for: clef), keySignature: lesson.keySignature, meter: meter)
            return remember(Pick(item: item, intro: intro, isLessonIntro: false, usedStrongest: false, isStretch: false, size: 1,
                                 positions: [Self.position(holding: [intro], on: clef)]))
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

    private func chooseClef(_ style: PickStyle, wanted: Clef?, using rng: inout some RandomNumberGenerator) -> Clef {
        let lesson = self.lesson
        var candidates = lesson.clefs.filter { clef in
            style == .strongest ? !strongestNotes(clef).isEmpty : !playable(clef).isEmpty || !pendingIntros(clef).isEmpty
        }
        if candidates.isEmpty {
            candidates = lesson.clefs.filter { !pool($0).isEmpty }
        }
        precondition(!candidates.isEmpty, "lesson \(lesson.id) has nothing unlocked")
        // the session's run: its clef, or the other one when it has nothing to show
        guard candidates.count > 1 else { return candidates[0] }
        if let wanted, candidates.contains(wanted) { return wanted }
        let last = state.recentScreens.suffix(2).compactMap(Self.leadingClef)
        if lesson.layout == .grand {
            // which staff goes first on the grand staff. focus lessons: the other clef never
            // twice in a row, the focus clef never 3 times, so it gets about 5 screens in 8
            if let focus = Clef(rawValue: lesson.focus.rawValue), let previous = last.last {
                if previous != focus { return focus }
                if last.count == 2, last[0] == focus, let other = candidates.first(where: { $0 != focus }) { return other }
            } else if last.count == 2, last[0] == last[1], let other = candidates.first(where: { $0 != last[0] }) {
                return other
            }
            if style == .strongest {
                return candidates.first { $0 != last.last } ?? candidates[0]
            }
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
        if !playable(clef).isEmpty, let gap = state.introGap[clef.rawValue], gap < config.introSpacing { return nil }
        if lesson.paced, let order = lesson.notes(clef)?.new {
            return pending.min { (order.firstIndex(of: $0.pitch) ?? 0) < (order.firstIndex(of: $1.pitch) ?? 0) }
        }
        return pending[min(pending.count - 1, Int(unitInterval(&rng) * Double(pending.count)))]
    }

    static func leadingClef(_ screenID: ItemID) -> Clef? {
        screenID.split(separator: ":").first.flatMap { Clef(rawValue: String($0)) }
    }

    // MARK: generating

    private func generate(on clef: Clef, strongest: Bool, using rng: inout some RandomNumberGenerator) -> Pick {
        var size = state.screenSize
        var stretch = false
        // no stretch on rhythm screens: a third bar wouldn't fit the staff. On reading
        // screens a stretch that doesn't fit the meter (7 notes in 3/4) comes out at his size
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

        var best: (item: PracticeItem, positions: [HandPosition])?
        var bestSeen = Int.max
        for _ in 0..<12 {
            let built = build(on: clef, size: size, notes: notes, withNewest: !strongest, using: &rng)
            guard let seen = avoid.lastIndex(of: built.item.id) else {
                best = built
                break
            }
            if best == nil || seen < bestSeen {
                best = built
                bestSeen = seen
            }
        }
        // a 3/4 screen holds at most 6 notes: a stretch that didn't fit is a normal screen
        let fitted = lesson.texture.isRhythm || best!.item.notes.count >= size
        return Pick(item: best!.item, intro: nil, isLessonIntro: false, usedStrongest: strongest, isStretch: stretch && fitted,
                    size: stretch && !fitted ? size - 1 : size, positions: best!.positions)
    }

    /// This clef's newest notes among `notes`, and the rest. While every note is new (a
    /// lesson's start set) there's nothing to set apart: no newest, all the rest.
    private func split(_ clef: Clef, _ notes: [NoteKey]) -> (newest: [NoteKey], others: [NoteKey]) {
        let newest = newestBatch(clef).filter(notes.contains)
        let others = notes.filter { !newest.contains($0) }
        return others.isEmpty ? ([], notes) : (newest, others)
    }

    /// The hand position for one staff of a screen, and the notes inside it. Notes that
    /// fit in one position stay as they are. Wider ones (level 3): one of the standard
    /// positions holding 2 or more of them, weighted by how many it holds and 3 times
    /// when it holds one of `newest`. `boost`: how much to scale the newest share inside
    /// the position so the newest keep their share over all screens (1 / the chance of a
    /// position with a newest note, 1 when there's none).
    func position(for notes: [NoteKey], newest: [NoteKey], on clef: Clef, mustHoldNewest: Bool = false,
                  using rng: inout some RandomNumberGenerator) -> (position: HandPosition, notes: [NoteKey], boost: Double) {
        if let one = HandPosition.holding(notes, on: clef) { return (one, notes, 1) }
        let low = notes.map(\.pitch.diatonicIndex).min() ?? 0, high = notes.map(\.pitch.diatonicIndex).max() ?? 0
        guard high - low > 4 else {
            // inside five letters but no standard position: one that starts on the lowest
            return (HandPosition(clef, low: notes.min()!.pitch), notes, 1)
        }
        let options = HandPosition.standard(clef)
        let held = options.map { position in notes.filter(position.contains) }
        let most = held.map(\.count).max() ?? 0
        let weights = zip(options, held).map { position, inside -> Double in
            guard inside.count >= min(2, most), !mustHoldNewest || newest.contains(where: position.contains) else { return 0 }
            return Double(inside.count) * (newest.contains(where: position.contains) ? 3 : 1)
        }
        let i = weightedIndex(weights, using: &rng)
        let withNewest = zip(options, weights).filter { position, _ in newest.contains(where: position.contains) }.reduce(0) { $0 + $1.1 }
        let total = weights.reduce(0, +)
        let boost = withNewest > 0 && newest.contains(where: options[i].contains) ? total / withNewest : 1
        return (options[i], held[i], boost)
    }

    /// Where a few notes are played: the standard position holding them (G position
    /// first), or one starting on the lowest.
    static func position(holding keys: [NoteKey], on clef: Clef) -> HandPosition {
        HandPosition.holding(keys, on: clef) ?? HandPosition(clef, low: keys.filter { $0.clef == clef }.min()?.pitch ?? HandPosition.g(clef).low)
    }

    /// One screen on `clef`: a meter, bars, then the notes in them. On the grand staff a
    /// bar on one staff, then a bar on the other (one staff while the other clef has
    /// nothing to show). Each staff's notes stay in one hand position.
    private func build(on clef: Clef, size: Int, notes: (Clef) -> [NoteKey], withNewest: Bool,
                       using rng: inout some RandomNumberGenerator) -> (item: PracticeItem, positions: [HandPosition]) {
        let lesson = self.lesson
        let other: Clef = clef == .treble ? .bass : .treble
        let twoStaves = lesson.layout == .grand && size >= 2 && !notes(clef).isEmpty && !notes(other).isEmpty
        let only = notes(clef).isEmpty ? other : clef
        var meter = rollMeter(using: &rng)
        let rhythms: [BarRhythm]
        if case .rhythm(let values, _) = lesson.texture {
            (meter, rhythms) = Self.rhythm(bars: twoStaves ? 2 : size, from: values, meter: meter, using: &rng)
        } else {
            rhythms = Self.readingRhythms(Self.barSizes(size, meter: meter, twoBars: twoStaves, using: &rng), meter: meter, using: &rng)
        }
        let staves = twoStaves ? [clef, other] : Array(repeating: only, count: rhythms.count)
        // one line per staff, so the contour runs on across a bar line on the same staff
        var columns: [WrittenNote] = []
        var positions: [HandPosition] = []
        var after = state.recentColumns
        var i = 0
        while i < rhythms.count {
            var j = i
            while j + 1 < rhythms.count, staves[j + 1] == staves[i] { j += 1 }
            let count = rhythms[i...j].reduce(0) { $0 + $1.count }
            // just after a new note's intro its screens are mostly that note (blocked, then mixed)
            let blocked = withNewest ? blockedNote(staves[i]) : nil
            let wanted = blocked.map { [$0] } ?? (withNewest ? split(staves[i], notes(staves[i])).newest : [])
            let (hand, all, boost) = position(for: notes(staves[i]), newest: wanted, on: staves[i], mustHoldNewest: blocked != nil, using: &rng)
            var (newest, others) = split(staves[i], all)
            var share = min(0.6, (lesson.paced ? config.pacedNewestShare : config.newestShare) * boost)
            if let blocked, all.contains(blocked) {
                newest = [blocked]
                others = all.count > 1 ? all.filter { $0 != blocked } : all
                share = config.blockedShare
            }
            let line = self.columns(count, on: staves[i], from: others, newest: withNewest ? newest : [], fallback: all, after: after,
                                    share: share, using: &rng)
            columns += line
            positions += Array(repeating: hand, count: line.count)
            after = (after + line.map(Self.columnID)).suffix(config.maxRepeats).map { $0 }
            i = j + 1
        }
        let written = Self.apply(rhythms, to: columns)
        let layout = lesson.layout == .grand ? StaffLayout.grand : lesson.staff(for: only)
        let item = PracticeItem(written, layout: layout, keySignature: lesson.keySignature, bars: rhythms.map(\.count), meter: meter)
        return (item, positions)
    }

    /// 4/4 or 3/4 for the next screen, rolled per screen so both come up in every lesson.
    func rollMeter(using rng: inout some RandomNumberGenerator) -> Meter {
        unitInterval(&rng) < config.fourFourShare ? .fourFour : .threeFour
    }

    /// `count` columns in the lesson's texture, no rhythm yet.
    private func columns(_ count: Int, on clef: Clef, from pool: [NoteKey], newest: [NoteKey], fallback: [NoteKey],
                         after: [ItemID], share: Double? = nil, using rng: inout some RandomNumberGenerator) -> [WrittenNote] {
        switch lesson.texture {
        case .single:
            return line(count, from: pool, newest: newest, fallback: fallback, after: after, share: share, using: &rng).map { WrittenNote($0) }
        case .dyads(let intervals):
            var keys = line(count, from: pool, newest: newest, fallback: fallback, after: after, share: share, using: &rng)
            // a line along the top of the range has nothing to put above it: swap one
            // note for the nearest one that can carry a second note
            let carriers = fallback.filter { low in fallback.contains { intervals.contains($0.pitch.diatonicIndex - low.pitch.diatonicIndex) } }
            let canCarry = { (k: NoteKey) in carriers.contains(k) }
            if !keys.contains(where: canCarry), !carriers.isEmpty {
                let i = min(keys.count - 1, Int(unitInterval(&rng) * Double(keys.count)))
                keys[i] = carriers.min { abs($0.pitch.diatonicIndex - keys[i].pitch.diatonicIndex) < abs($1.pitch.diatonicIndex - keys[i].pitch.diatonicIndex) }!
            }
            return dyads(keys, intervals: intervals, uppers: fallback, using: &rng)
        case .rhythm(_, let oneNote):
            let keys = oneNote
                ? Array(repeating: line(1, from: pool, newest: newest, fallback: fallback, after: after, using: &rng)[0], count: count)
                : line(count, from: pool, newest: newest, fallback: fallback, after: after, using: &rng)
            return keys.map { WrittenNote($0) }
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

    /// The first screen of a lesson with a new texture, shown to him before he plays:
    /// one dyad (a third when there is one) held for a bar, or one bar of rhythm.
    private func lessonIntro(on clef: Clef, using rng: inout some RandomNumberGenerator) -> Pick {
        let notes = playable(clef)
        let layout = lesson.staff(for: clef)
        var meter = rollMeter(using: &rng)
        let held: NoteValue = meter == .fourFour ? .whole : .dottedHalf
        var columns: [WrittenNote]
        var bars: [Int]? = nil
        switch lesson.texture {
        case .dyads(let intervals):
            let pairs = notes.flatMap { low in
                notes.filter { $0.pitch.diatonicIndex - low.pitch.diatonicIndex == (intervals.min() ?? 2) }.map { (low, $0) }
            }
            if let (low, high) = pairs.isEmpty ? nil : pairs[min(pairs.count - 1, Int(unitInterval(&rng) * Double(pairs.count)))] {
                columns = [WrittenNote(clef, [low.pitch, high.pitch], held)]
            } else {
                columns = [WrittenNote(notes[0], held)]
            }
        case .rhythm(let values, let oneNote):
            let rhythm: [BarRhythm]
            (meter, rhythm) = Self.rhythm(bars: 1, from: values, meter: meter, using: &rng)
            let count = rhythm[0].count
            let keys = oneNote ? Array(repeating: notes[min(notes.count - 1, Int(unitInterval(&rng) * Double(notes.count)))], count: count)
                : line(count, from: notes, newest: [], fallback: notes, after: state.recentColumns, using: &rng)
            columns = Self.apply(rhythm, to: keys.map { WrittenNote($0) })
            bars = [count]
        case .single:
            columns = [WrittenNote(notes[0], held)]
        }
        let item = PracticeItem(columns, layout: layout, keySignature: lesson.keySignature, bars: bars, meter: meter)
        let hand = Self.position(holding: item.keys, on: clef)
        return Pick(item: item, intro: nil, isLessonIntro: true, usedStrongest: false, isStretch: false, size: 1,
                    positions: Array(repeating: hand, count: columns.count))
    }

    enum Move { case same, step, skip }

    /// `count` notes in a row. Each slot is one of `newest` with chance `newestShare`
    /// (25%: the newest notes get about 1 in 4 of the notes he reads on that clef, which
    /// at one note a screen is 1 screen in 4; 1 in 3 in paced lessons), otherwise one of
    /// `pool`. Each move from the last note is a repeat, a step or a skip (third to
    /// fifth, only a third in the gentle contour), rolled from the lesson's contour mix,
    /// then a note that fits is picked by weight (6 - box). When no note fits, any note
    /// goes, except past the contour's widest move: a newest note that far away moves the
    /// line toward it and takes the next slot instead (a line that ends still owing it is
    /// drawn again starting on the newest). `after` is what came just before (column ids), so a run of
    /// the same key can't carry over from the last screen. `fallback` is used when the
    /// run rule leaves nothing to pick.
    /// `share`: the newest share, when it isn't the lesson's (a hand position picked for
    /// its newest note, the blocked screens after an intro).
    func line(_ count: Int, from pool: [NoteKey], newest: [NoteKey], fallback: [NoteKey], after: [ItemID], share: Double? = nil,
              using rng: inout some RandomNumberGenerator) -> [NoteKey] {
        let first = drawLine(count, from: pool, newest: newest, fallback: fallback, after: after, owing: false, share: share, using: &rng)
        guard first.owed, count > 1 else { return first.keys }
        return drawLine(count, from: pool, newest: newest, fallback: fallback, after: after, owing: true, share: share, using: &rng).keys
    }

    /// `line`, once. `owing`: the first note is one of the newest. Returns whether the
    /// line ended still owing a newest note.
    private func drawLine(_ count: Int, from pool: [NoteKey], newest: [NoteKey], fallback: [NoteKey], after: [ItemID], owing: Bool,
                          share: Double?, using rng: inout some RandomNumberGenerator) -> (keys: [NoteKey], owed: Bool) {
        precondition(!pool.isEmpty)
        var out: [NoteKey] = []
        let share = share ?? (lesson.paced ? config.pacedNewestShare : config.newestShare)
        let widest = lesson.contour.widest
        // a newest slot that couldn't be reached within the widest move goes to the next note
        var owed = owing
        for _ in 0..<count {
            let history = (after + out.map(\.id)).suffix(config.maxRepeats)
            let blocked = history.count == config.maxRepeats && Set(history).count == 1 ? history.last : nil
            var source = pool
            if !newest.isEmpty, unitInterval(&rng) < share || owed {
                source = newest
            }
            owed = false
            var candidates = source.filter { $0.id != blocked }
            if candidates.isEmpty { candidates = fallback.filter { $0.id != blocked } }
            if candidates.isEmpty { candidates = fallback }
            if let previous = out.last {
                if let widest {
                    // never further than the contour allows: from these, else from the rest
                    let near = { (keys: [NoteKey]) in
                        keys.filter { abs($0.pitch.diatonicIndex - previous.pitch.diatonicIndex) <= widest }
                    }
                    if near(candidates).isEmpty, source == newest {
                        // the newest is too far: a move toward it now, the newest next
                        let toward = near(pool.filter { $0.id != blocked })
                        let distance = { (k: NoteKey) in newest.map { abs($0.pitch.diatonicIndex - k.pitch.diatonicIndex) }.min() ?? 0 }
                        if let best = toward.map(distance).min() {
                            candidates = toward.filter { distance($0) == best }
                            owed = true
                        }
                    }
                    let close = [candidates, pool.filter { $0.id != blocked }, fallback.filter { $0.id != blocked }, fallback]
                        .lazy.map(near).first { !$0.isEmpty }
                    if let close { candidates = close }
                }
                let move = rollMove(using: &rng)
                let fitting = candidates.filter { Self.fits(move, from: previous, to: $0, widest: widest) }
                if !fitting.isEmpty { candidates = fitting }
            }
            let weights = candidates.map { Double(config.boxCount + 1 - stats(for: $0).box) }
            out.append(candidates[weightedIndex(weights, using: &rng)])
        }
        return (out, owed)
    }

    private func rollMove(using rng: inout some RandomNumberGenerator) -> Move {
        let (same, step): (Double, Double) = switch lesson.contour {
        case .mixed: (0.15, 0.45)
        case .steps: (0.15, 0.70)
        case .skips: (0.10, 0.20)
        // the rest are thirds (more come from moving toward a newest note out of reach)
        case .gentle: (0.25, 0.62)
        }
        let roll = unitInterval(&rng)
        return roll < same ? .same : roll < same + step ? .step : .skip
    }

    /// `widest`: the widest skip in letters (2 = a third), nil for up to a fifth.
    static func fits(_ move: Move, from a: NoteKey, to b: NoteKey, widest: Int? = nil) -> Bool {
        let distance = abs(a.pitch.diatonicIndex - b.pitch.diatonicIndex)
        switch move {
        case .same: return a == b
        case .step: return distance == 1
        case .skip: return (2...(widest ?? 4)).contains(distance)
        }
    }

    private mutating func remember(_ pick: Pick) -> Pick {
        if let drill = pick.drill { state.lastDrill = drill }
        state.recentScreens = Array((state.recentScreens + [pick.item.id]).suffix(max(2, config.recentScreens)))
        let columns = pick.item.notes.map(Self.columnID)
        state.recentColumns = Array((state.recentColumns + columns).suffix(max(1, config.maxRepeats)))
        // screens on each clef since its last intro
        if let intro = pick.intro {
            state.introGap[intro.clef.rawValue] = 0
            state.lastIntro[intro.clef.rawValue] = intro.id
        } else {
            for clef in pick.item.clefs {
                if let gap = state.introGap[clef.rawValue] { state.introGap[clef.rawValue] = gap + 1 }
            }
        }
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
