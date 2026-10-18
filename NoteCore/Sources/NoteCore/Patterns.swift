/// A pattern screen's shape (plans/2026-10-17-reset-and-repetition.md section 2, from a
/// piano teacher's review: artifacts/reviews/2026-10-17-piano-teacher-in-screen-repetition.md).
///
/// Always two bars holding as many notes each (2+2 or 3+3; two bars in level 5). Bar 1
/// is made fresh like any screen, bar 2 is made from it, so bar 1 is read and bar 2 is a
/// check: the same, moved, or what changed. The repeated rhythm is the cue (stems, open
/// heads and rests line up before he reads a pitch), and every bar has a long note or a
/// rest, so his eye gets a beat or two to reach bar 2 before his hand does (Furneaux &
/// Land 1999: eyes run about a second ahead of the hands).
///
/// Not "turned around" (hard to see as the same): that stays a drill (`Drill.motif`).
public enum PatternShape: String, CaseIterable, Codable, Hashable, Sendable {
    /// The same rhythm, new notes. Every level, the most.
    case frame
    /// Bar 1's rhythm and shape a step away: G A | A B. Levels 1-4, the most. Two at
    /// once move together in level 4.
    case moved
    /// Bar 1 again but the last note, which is G (now and then not, so he checks the
    /// end). Levels 2-5. Ends on a two at once in level 4.
    case answer
    /// Bar 2 is bar 1 exactly. Now and then in level 1, rarely after.
    case twin
    /// One note a bar: G G | A A. Level 1, right after a new note's intro.
    case oneNote
    /// The same notes in a new rhythm: q q h | h q q. Rarely in levels 1-2, more in 3-5.
    case newRhythm

    /// Bar 2 plays bar 1's notes again where they line up: from memory, not read.
    public var repeatsNotes: Bool { self == .twin || self == .answer || self == .newRhythm }
}

extension PracticeItem {
    /// Two bars holding as many notes, in one rhythm (values and rests).
    public var hasSameRhythmBars: Bool {
        guard bars.count == 2, bars[0] == bars[1] else { return false }
        let ranges = barRanges
        return zip(notes[ranges[0]], notes[ranges[1]]).allSatisfy { $0.value == $1.value && $0.restsAfter == $1.restsAfter }
    }

    /// Columns of bar 2 with bar 1's notes at the same spot.
    public var repeatedColumns: [Int] {
        guard bars.count == 2 else { return [] }
        let second = barRanges[1]
        return second.filter { i in
            let j = i - second.lowerBound
            return j < bars[0] && notes[j].clef == notes[i].clef && notes[j].pitches == notes[i].pitches
        }
    }
}

extension MasteryEngine {
    // MARK: picking

    /// The chance the next normal screen on `clef` is a pattern screen: 1 in 4 in levels
    /// 1-2, 1 in 5 after, more on a new note's blocked screens right after its intro.
    func patternChance(on clef: Clef) -> Double {
        if blockedNote(clef) != nil { return config.patternIntroShare }
        return lesson.level <= 2 ? config.patternShare : config.patternShareLater
    }

    /// The shapes this lesson's pattern screens use and how often: the most (1), often
    /// (0.7), now and then (0.45), rarely (0.15). `introWindow`: right after a new note's
    /// intro, where a twin brings the new note back exactly and level 1 gets one note a bar.
    func patternShapes(introWindow: Bool) -> [(shape: PatternShape, weight: Double)] {
        // one key all through (5.1, 5.2): only the rhythm can repeat or change
        if case .rhythm(_, true) = lesson.texture { return [(.frame, 1), (.newRhythm, 0.4)] }
        let level = lesson.level
        var shapes: [(shape: PatternShape, weight: Double)] = [(.frame, 1)]
        if level <= 4 { shapes.append((.moved, 1)) }
        if level >= 2 { shapes.append((.answer, 0.7)) }
        shapes.append((.twin, introWindow ? 1 : level == 1 ? 0.45 : 0.15))
        if level == 1, introWindow { shapes.append((.oneNote, 0.6)) }
        shapes.append((.newRhythm, level <= 2 ? 0.15 : 0.4))
        return shapes
    }

    /// A pattern screen on `clef`: one of this lesson's shapes, never the last one when
    /// another works, bar 1 never one of the recent pattern screens' (shape and bar 1) when
    /// the notes allow it. `only`: that shape, whatever the lesson (demos, tests). nil when
    /// his notes there can't make one.
    mutating func patternPick(on clef: Clef, only: PatternShape? = nil, using rng: inout some RandomNumberGenerator) -> Pick? {
        guard !lesson.isDrillLesson, Set(playable(clef)).count >= 2 else { return nil }
        var order: [PatternShape]
        if let only {
            order = [only]
        } else {
            let shapes = patternShapes(introWindow: blockedNote(clef) != nil)
            var options = shapes.filter { $0.shape != state.lastShape }
            if options.isEmpty { options = shapes }
            order = []
            var weights = options.map(\.weight)
            while !weights.allSatisfy({ $0 == 0 }) {
                let i = weightedIndex(weights, using: &rng)
                order.append(options[i].shape)
                weights[i] = 0
            }
            // the last shape again only when nothing else can be made
            if let last = state.lastShape, shapes.contains(where: { $0.shape == last }), !order.contains(last) { order.append(last) }
        }
        for shape in order {
            var seen: Pick?
            for _ in 0..<10 {
                guard let pick = patternDraft(shape, on: clef, using: &rng) else { continue }
                if !isRecentPattern(pick) { return pick }
                seen = seen ?? pick
            }
            if let seen { return seen }
        }
        return nil
    }

    /// A pattern screen of one shape on `clef` (the grand staff: the first clef with 2+
    /// notes), or nil when this lesson's notes can't make it. For galleries, demos and
    /// tests: sessions pick their pattern screens themselves.
    public mutating func pickPattern(_ shape: PatternShape, on clef: Clef? = nil, using rng: inout some RandomNumberGenerator) -> Pick? {
        let clef = clef ?? lesson.clefs.first { playable($0).count >= 2 } ?? lesson.clefs[0]
        guard let pick = patternPick(on: clef, only: shape, using: &rng) else { return nil }
        return remember(pick)
    }

    /// `"moved treble:G4/h-A4/h 4/4"`: the shape and bar 1, what the no-repeat window
    /// compares for a pattern screen (bar 2 follows from them).
    func patternMemo(_ pick: Pick) -> String? {
        guard let shape = pick.pattern, let meter = pick.item.meter, pick.item.bars.count == 2 else { return nil }
        let item = pick.item
        let bar1 = PracticeItem(Array(item.notes[item.barRanges[0]]), layout: item.layout, keySignature: item.keySignature, meter: meter)
        return "\(shape.rawValue) \(bar1.id)"
    }

    /// Bar rhythms of a pattern screen (`"4/4 q q h"`): bar 1's, and bar 2's when it has
    /// another.
    static func patternCellIDs(_ item: PracticeItem) -> [String] {
        guard let meter = item.meter else { return [] }
        var cells: [String] = []
        for range in item.barRanges {
            let bar = item.notes[range]
            let cell = cellID(BarRhythm(bar.map(\.value), rests: bar.last?.restsAfter ?? []), meter: meter)
            if !cells.contains(cell) { cells.append(cell) }
        }
        return cells
    }

    /// The same shape and bar 1 came up on a recent pattern screen. How far back to look
    /// counts the bar 1s the notes can make (notes in the hand position ^ notes in bar 1),
    /// not whole screens, so a small pool only avoids the last one or two.
    func isRecentPattern(_ pick: Pick) -> Bool {
        guard let memo = patternMemo(pick), let hand = pick.positions.first else { return false }
        let inHand = Double(max(1, Set(playable(hand.clef).filter(hand.contains)).count))
        var possible = 1.0, screens = 1.0
        for _ in 0..<pick.item.bars[0] { possible = min(1e6, possible * inHand) }
        for _ in 0..<pick.item.notes.count { screens = min(1e6, screens * inHand) }
        let window = min(config.recentScreens, max(1, Int(possible / 3)))
        // nor the same screen as a recent one of any kind (a frame can come out as a recent
        // normal screen)
        let screenWindow = min(config.recentScreens, max(1, Int(screens / 3)))
        return state.recentPatterns.suffix(window).contains(memo) || state.recentScreens.suffix(screenWindow).contains(pick.item.id)
    }

    // MARK: building

    /// One pattern screen of `shape` on `clef`, or nil when this try can't make it (the
    /// caller tries again: bar 1 is random).
    private func patternDraft(_ shape: PatternShape, on clef: Clef, using rng: inout some RandomNumberGenerator) -> Pick? {
        let lesson = self.lesson
        let notes = playable(clef)
        let blocked = blockedNote(clef)
        // the bar rhythms first: they set how many notes a bar holds
        guard let (meter, first, second) = patternCells(shape, using: &rng) else { return nil }
        let k = first.count
        // bar 1 like any screen's notes: one hand position, the newest notes their share,
        // the note just introduced the most
        let wanted = blocked.map { [$0] } ?? split(clef, notes).newest
        let (hand, all, boost) = position(for: notes, newest: wanted, on: clef, mustHoldNewest: blocked != nil, using: &rng)
        guard Set(all).count >= 2 else { return nil }
        var (newest, others) = split(clef, all)
        var share = min(0.6, (lesson.paced ? config.pacedNewestShare : config.newestShare) * boost)
        if let blocked, all.contains(blocked) {
            newest = [blocked]
            others = all.filter { $0 != blocked }
            share = config.blockedShare
        }
        let oneKey: Bool = if case .rhythm(_, true) = lesson.texture { true } else { false }
        var bar1: [WrittenNote]
        // a frame's two bars are one line, so the contour runs on across the bar line
        var line: [WrittenNote] = []
        if shape == .oneNote {
            guard k >= 2, lesson.texture == .single else { return nil }
            let x = blocked ?? all[weightedIndex(all.map { Double(config.boxCount + 1 - stats(for: $0).box) }, using: &rng)]
            bar1 = Array(repeating: WrittenNote(x), count: k)
        } else if shape == .frame, !oneKey {
            line = columns(2 * k, on: clef, from: others, newest: newest, fallback: all, after: state.recentColumns, share: share, using: &rng)
            bar1 = Array(line.prefix(k))
        } else {
            bar1 = columns(k, on: clef, from: others, newest: newest, fallback: all, after: state.recentColumns, share: share, using: &rng)
        }
        // the new note in bar 1, the shape brings it back in bar 2
        if let blocked, !bar1.contains(where: { $0.keys.contains(blocked) }) { return nil }

        var bar2: [WrittenNote]
        switch shape {
        case .frame:
            bar2 = oneKey ? bar1 : Array(line.suffix(k))
            guard oneKey || bar2 != bar1 else { return nil }
        case .moved:
            // a bar of one key moved is one note a bar
            guard Set(bar1).count >= 2 else { return nil }
            var ways = unitInterval(&rng) < 0.5 ? [1, -1] : [-1, 1]
            // the way that keeps the new note in bar 2 first
            let keeps = { (way: Int) in blocked.map { b in Self.shifted(bar1, by: way, within: all)?.contains { $0.keys.contains(b) } ?? false } ?? false }
            if !keeps(ways[0]), keeps(ways[1]) { ways.reverse() }
            guard let moved = ways.lazy.compactMap({ Self.shifted(bar1, by: $0, within: all) }).first else { return nil }
            bar2 = moved
        case .answer:
            guard let end = answerEnd(bar1, all: all, using: &rng) else { return nil }
            bar2 = Array(bar1.dropLast()) + [end]
        case .twin, .newRhythm:
            bar2 = bar1
        case .oneNote:
            let x = bar1[0].keys[0]
            let near = all.filter { $0 != x && abs($0.pitch.diatonicIndex - x.pitch.diatonicIndex) <= 2 }
            guard !near.isEmpty else { return nil }
            let y = near[weightedIndex(near.map { Double(config.boxCount + 1 - stats(for: $0).box) }, using: &rng)]
            bar2 = Array(repeating: WrittenNote(y), count: second.count)
        }
        // right after its intro the shape brings the new note back in bar 2 (one note a bar
        // has it all through bar 1 instead)
        if let blocked, shape != .oneNote, !bar2.contains(where: { $0.keys.contains(blocked) }) { return nil }
        // no key 3 times in a row on the screen. One note a bar is a shape of its own (G G |
        // A A, a bar that's one key), and a one-key rhythm lesson repeats on purpose
        if shape != .oneNote, !oneKey, maxRepeatRun((bar1 + bar2).map(Self.columnID)) > config.maxRepeats { return nil }
        // never further than the contour allows from one note to the next (level 1: a
        // third), across the bar line too (a moved bar starts a step off)
        if let widest = lesson.contour.widest {
            let lows = (bar1 + bar2).map { $0.pitches[0].diatonicIndex }
            if zip(lows, lows.dropFirst()).contains(where: { abs($0 - $1) > widest }) { return nil }
        }
        let rhythms = [first, second]
        if lesson.texture.isRhythm, !RhythmJudge.telling(Self.rhythmLine(rhythms)) { return nil }
        let written = Self.apply(rhythms, to: bar1 + bar2)
        let item = PracticeItem(written, layout: lesson.staff(for: clef), keySignature: lesson.keySignature,
                                bars: [first.count, second.count], meter: meter)
        var pick = Pick(item: item, intro: nil, isLessonIntro: false, usedStrongest: false, isStretch: false,
                        size: lesson.texture.isRhythm ? 2 : written.count, positions: Array(repeating: hand, count: written.count))
        pick.pattern = shape
        return pick
    }

    /// The bar rhythms of a pattern screen and its meter: bar 1's, and bar 2's (the same,
    /// but for a new-rhythm screen). Reading screens: a bar from `readingBars` with a long
    /// note or a rest in it, 2 notes a bar in level 1 (the drill sizes' 4: level 1 screens
    /// of 2-3 can't make two matching bars) and half his size after that (2+2, or 3+3,
    /// which only fits 4/4 with a long note). Never a rhythm of the last few pattern screens
    /// while there are others.
    func patternCells(_ shape: PatternShape, using rng: inout some RandomNumberGenerator) -> (meter: Meter, first: BarRhythm, second: BarRhythm)? {
        if case .rhythm(let values, _) = lesson.texture { return rhythmPatternCells(shape, values: values, using: &rng) }
        let perBar = lesson.level == 1 ? 2 : min(3, max(2, (state.screenSize + 1) / 2))
        var options: [(meter: Meter, rhythm: BarRhythm, weight: Double)] = []
        for meter in Meter.allCases where perBar <= meter.beats {
            let share = meter == .fourFour ? config.fourFourShare : 1 - config.fourFourShare
            for option in Self.readingBars(notes: perBar, meter: meter) where Self.isPatternCell(option.rhythm) {
                // an answer ends on a long note when it can
                let longEnd = shape == .answer && (option.rhythm.values.last?.beats ?? 0) >= 2
                options.append((meter, option.rhythm, option.weight * share * (longEnd ? 3 : 1)))
            }
        }
        let fresh = freshCells(options.map { Self.cellID($0.rhythm, meter: $0.meter) })
        let usable = options.indices.filter { fresh.contains(Self.cellID(options[$0].rhythm, meter: options[$0].meter)) }
        guard !usable.isEmpty else { return nil }
        let pick = options[usable[weightedIndex(usable.map { options[$0].weight }, using: &rng)]]
        guard shape == .newRhythm else { return (pick.meter, pick.rhythm, pick.rhythm) }
        let others = options.filter { $0.meter == pick.meter && $0.rhythm != pick.rhythm && $0.rhythm.count == pick.rhythm.count }
        guard !others.isEmpty else { return nil }
        return (pick.meter, pick.rhythm, others[weightedIndex(others.map(\.weight), using: &rng)].rhythm)
    }

    /// Level 5: one bar from the lesson's values with a long note or a rest in it (a frame
    /// in an eighths lesson has the pair, so it sits in the same spot in both bars).
    private func rhythmPatternCells(_ shape: PatternShape, values: [NoteValue],
                                    using rng: inout some RandomNumberGenerator) -> (meter: Meter, first: BarRhythm, second: BarRhythm)? {
        let recent = state.recentCells.suffix(config.patternFreshCells)
        var found: (meter: Meter, bar: BarRhythm)?
        for attempt in 0..<20 {
            let (meter, bars) = Self.rhythm(bars: 1, from: values, meter: rollMeter(using: &rng), using: &rng)
            let bar = bars[0]
            guard Self.isPatternCell(bar) else { continue }
            let picky = attempt < 14
            if picky, shape == .frame, values.contains(.eighth), !bar.values.contains(.eighth) { continue }
            if picky, recent.contains(Self.cellID(bar, meter: meter)) { continue }
            found = (meter, bar)
            break
        }
        guard let (meter, first) = found else { return nil }
        guard shape == .newRhythm else { return (meter, first, first) }
        for _ in 0..<30 {
            let (other, bars) = Self.rhythm(bars: 1, from: values, meter: meter, using: &rng)
            if other == meter, bars[0].count == first.count, bars[0] != first, Self.isPatternCell(bars[0]) {
                return (meter, first, bars[0])
            }
        }
        return nil
    }

    /// Of `cells`, the ones the last `patternFreshCells` pattern screens didn't use,
    /// forgetting the oldest of those while fewer than half are left.
    func freshCells(_ cells: [String]) -> Set<String> {
        let all = Set(cells)
        var recent = Array(state.recentCells.suffix(config.patternFreshCells))
        while !recent.isEmpty, all.subtracting(recent).count < (all.count + 1) / 2 {
            recent.removeFirst()
        }
        return all.subtracting(recent)
    }

    /// A bar a pattern screen can use: a long note (a half or longer) or a rest in it, so
    /// his eye gets time to reach the next bar.
    static func isPatternCell(_ bar: BarRhythm) -> Bool {
        !bar.rests.isEmpty || bar.values.contains { $0.beats >= 2 }
    }

    /// `"4/4 q q h"`, `"3/4 q q rq"`.
    static func cellID(_ bar: BarRhythm, meter: Meter) -> String {
        ([meter.rawValue] + bar.values.map(\.rawValue) + bar.rests.map { "r" + $0.rawValue }).joined(separator: " ")
    }

    /// The last note of an answer: G in the hand position (a two at once on G in a
    /// two-at-once lesson), now and then another note near the one before it, so he checks
    /// the end. Never bar 1's last note.
    private func answerEnd(_ bar1: [WrittenNote], all: [NoteKey], using rng: inout some RandomNumberGenerator) -> WrittenNote? {
        guard bar1.count >= 2, let last = bar1.last else { return nil }
        let before = bar1[bar1.count - 2].pitches[0]
        var options: [WrittenNote]
        if case .dyads(let intervals) = lesson.texture {
            options = all.flatMap { low in
                all.filter { intervals.contains($0.pitch.diatonicIndex - low.pitch.diatonicIndex) }.map { WrittenNote(low.clef, [low.pitch, $0.pitch]) }
            }
        } else {
            options = all.map { WrittenNote($0) }
        }
        options = options.filter { $0 != last }
        let widest = lesson.contour.widest ?? 4
        let home = options.filter { $0.pitches[0].letter == .g }
        let away = options.filter { $0.pitches[0].letter != .g && abs($0.pitches[0].diatonicIndex - before.diatonicIndex) <= widest }
        let pool = unitInterval(&rng) < config.answerAwayChance ? away : home
        guard !pool.isEmpty else { return nil }
        return pool[min(pool.count - 1, Int(unitInterval(&rng) * Double(pool.count)))]
    }

    /// Every column a step up (`way` 1) or down (-1), two at once together, each key one of
    /// `notes`. nil when one would leave them.
    static func shifted(_ columns: [WrittenNote], by way: Int, within notes: [NoteKey]) -> [WrittenNote]? {
        var out: [WrittenNote] = []
        for column in columns {
            var pitches: [Pitch] = []
            for pitch in column.pitches {
                guard let moved = notes.first(where: { $0.clef == column.clef && $0.pitch.diatonicIndex == pitch.diatonicIndex + way }) else {
                    return nil
                }
                pitches.append(moved.pitch)
            }
            out.append(WrittenNote(column.clef, pitches))
        }
        return out
    }
}
