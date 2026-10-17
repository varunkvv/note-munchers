/// A drill screen's shape (plans/2026-10-16-drills-and-habit.md section 2: eye to finger
/// in every level). The notes stay ones he has met, everything around them varies:
/// the shape, the meter, the length, where G sits.
///
/// Every drill screen stays in one hand position per bar (a shift screen moves it once),
/// so the finger order lines up with the staff.
public enum Drill: String, CaseIterable, Codable, Hashable, Sendable {
    /// Steps that keep going and turn at the edge: G A B C D C B. Finger order 1-5 (5-1
    /// in the left hand) tied to the staff.
    case run
    /// A 2-3 note cell, then the same cell a step away, turned around, or with one note
    /// changed: G A B | A B C. Reading shapes, not names, lets the eye get ahead of the
    /// hand (Faber's sightreading books, Sloboda's eye-hand span).
    case motif
    /// Every other note is the home note: G A G B G C. Each note read as a distance from
    /// it (G, or middle C in level 3's positions lesson).
    case home
    /// One note for a whole bar: B B B B. One finger landing in time.
    case repeatNote
    /// Grand staff: bar 2 is bar 1's letters in the other clef. G is line 2 in treble
    /// and line 1 in bass, the confusion to watch.
    case echo
    /// Each bar in a different hand position (level 3's positions lesson).
    case shift
    /// Two at once moved by step: G+B, A+C, B+D (level 4's drill lesson).
    case movedTwo
    /// A pair one at a time, then together: G B G+B (level 4's drill lesson).
    case brokenTwo
    /// A one-bar rhythm, then again a step higher or the same notes with a new rhythm,
    /// rhythm judged (level 5's drill lesson).
    case rhythmMotif
    /// A bit of a tune he may know (`Tune.all`), now and then.
    case tune
}

/// A drill screen before its rhythm: columns (no values yet), bars, a hand position
/// per column, and the bars' rhythms when the drill sets them.
struct DrillDraft {
    var columns: [WrittenNote]
    var bars: [Int]
    var positions: [HandPosition]
    /// Both bars get one rhythm (a motif, an echo), so they read as the same shape.
    var sameRhythm = false
    var rhythms: [BarRhythm]?
    var meter: Meter?
    var layout: StaffLayout?
}

extension Curriculum {
    /// Every note of the lessons up to and including `id`.
    func keys(through id: LessonID) -> Set<NoteKey> {
        guard let last = index(of: id) else { return [] }
        return Set(lessons[...last].flatMap(\.keys))
    }
}

extension MasteryEngine {
    /// Notes a drill screen on `clef` can use: what he can play in this lesson, and every
    /// note he has met in this lesson or an earlier one, so level 3's notes come back in
    /// levels 4-5. Never a note waiting for its intro, never one from a later lesson (an
    /// old save can hold met notes that level 1 hasn't reached yet).
    public func drillNotes(_ clef: Clef) -> [NoteKey] {
        let upTo = curriculum.keys(through: lesson.id)
        let met = metNotes.filter { $0.clef == clef && upTo.contains($0) && isUnlocked($0) && !needsIntro($0) }
        return Array(Set(playable(clef)).union(met)).sorted()
    }

    /// How much a note wants practice on a drill screen: low boxes more, and the further
    /// a note is from habit the more (up to 10 times a note that's habit).
    func drillWeight(_ key: NoteKey) -> Double {
        Double(config.boxCount + 1 - stats(for: key).box) * (1 + 9 * (1 - habit(key).fraction)) * comeBackWeight(key)
    }

    /// The key that can't come next (it was the last `maxRepeats` columns), if any.
    var blockedColumn: ItemID? {
        let history = state.recentColumns.suffix(config.maxRepeats)
        return history.count == config.maxRepeats && Set(history).count == 1 ? history.last : nil
    }

    /// Hand positions a drill on `clef` can use: the lesson's own, or the standard ones.
    func drillPositionOptions(_ clef: Clef) -> [HandPosition] {
        let own = lesson.drillPositions?.filter { $0.clef == clef } ?? []
        return own.isEmpty ? HandPosition.standard(clef) : own
    }

    /// A hand position on `clef` and the notes of `notes` inside it: one of `options`
    /// holding 3 or more of them (2 when none does), weighted by how much there is to
    /// practise in it. Notes that already fit in one standard position stay there.
    func drillPosition(_ notes: [NoteKey], on clef: Clef, options: [HandPosition]? = nil, holding: Pitch? = nil,
                       using rng: inout some RandomNumberGenerator) -> (position: HandPosition, notes: [NoteKey])? {
        if options == nil, holding == nil, lesson.drillPositions == nil, let one = HandPosition.holding(notes, on: clef) {
            return notes.count >= 2 ? (one, notes) : nil
        }
        let options = (options ?? drillPositionOptions(clef)).filter { holding.map($0.contains) ?? true }
        let held = options.map { position in notes.filter(position.contains) }
        let most = held.map(\.count).max() ?? 0
        guard most >= 2 else { return nil }
        let floor = min(3, most)
        let weights = held.map { inside in inside.count >= floor ? inside.reduce(0.0) { $0 + drillWeight($1) } : 0 }
        let i = weightedIndex(weights, using: &rng)
        return (options[i], held[i])
    }

    // MARK: picking

    /// The session's opener: a run of his strongest notes on `clef`, in one hand
    /// position, a little longer than his screens. nil when he has fewer than 2 strong
    /// notes there (the caller falls back to a screen of his strongest).
    mutating func warmUpPick(on clef: Clef, using rng: inout some RandomNumberGenerator) -> Pick? {
        guard let (position, notes) = drillPosition(strongestNotes(clef), on: clef, using: &rng) else { return nil }
        let base = lesson.texture.isRhythm ? lesson.drillSizes.lowerBound : state.screenSize
        let n = min(max(base, lesson.drillSizes.lowerBound), lesson.drillSizes.upperBound)
        let meter = rollMeter(using: &rng)
        guard let keys = runKeys(min(n, MasteryEngine.maxNotes(meter)), from: notes, using: &rng) else { return nil }
        let draft = DrillDraft(columns: keys.map { WrittenNote($0) }, bars: Self.barSizes(keys.count, meter: meter, twoBars: false, using: &rng),
                               positions: Array(repeating: position, count: keys.count))
        return finish(draft, drill: .run, meter: meter, clef: clef, size: n, strongest: true, using: &rng)
    }

    /// A drill screen on `clef`: one of the lesson's drills that works with his notes,
    /// never the same as the last one when there's another, `size` notes (bars in a
    /// rhythm drill lesson). Falls back to a run, then nil.
    mutating func drillPick(on clef: Clef, size: Int, using rng: inout some RandomNumberGenerator) -> Pick? {
        var options = lesson.drills.filter { $0 != state.lastDrill }
        if options.isEmpty { options = lesson.drills }
        // a tune is a now-and-then surprise. A repeat reads one note (nothing in-line for
        // habit to measure), so it comes a bit less often than the others
        var order: [Drill] = []
        var weights = options.map { $0 == .tune ? 0.35 : $0 == .repeatNote ? 0.6 : 1.0 }
        while !weights.allSatisfy({ $0 == 0 }) {
            let i = weightedIndex(weights, using: &rng)
            order.append(options[i])
            weights[i] = 0
        }
        // the last drill again only when nothing else works, a run as the last resort
        let last = state.lastDrill.flatMap { lesson.drills.contains($0) && !order.contains($0) ? [$0] : nil } ?? []
        for drill in order + last + [.run] {
            let meter = rollMeter(using: &rng)
            if let draft = draft(drill, on: clef, size: size, meter: meter, using: &rng) {
                return finish(draft, drill: drill, meter: draft.meter ?? meter, clef: clef, size: size, strongest: false, using: &rng)
            }
        }
        return nil
    }

    /// A drill screen of one shape on `clef` (the run's clef; the grand staff picks its
    /// own), at the size a burst would use, or nil when this lesson's notes can't make it.
    /// For galleries, demos and tests: sessions pick their drills themselves.
    public mutating func pickDrill(_ drill: Drill, on clef: Clef? = nil, using rng: inout some RandomNumberGenerator) -> Pick? {
        let clef = clef ?? lesson.clefs.first { drillNotes($0).count >= 2 } ?? lesson.clefs[0]
        let base = lesson.isDrillLesson ? state.screenSize : state.screenSize + 1
        let n = min(max(lesson.texture.isRhythm ? lesson.drillSizes.lowerBound : base, lesson.drillSizes.lowerBound), lesson.drillSizes.upperBound)
        for _ in 0..<20 {
            let meter = rollMeter(using: &rng)
            if let draft = draft(drill, on: clef, size: n, meter: meter, using: &rng) {
                let pick = finish(draft, drill: drill, meter: draft.meter ?? meter, clef: clef, size: n, strongest: false, using: &rng)
                state.lastDrill = drill
                return pick
            }
        }
        return nil
    }

    /// The same screen again, straight after (`PickStyle.again` in the session): a second
    /// read of a chunk. It skips the no-repeat window on purpose.
    mutating func again(_ pick: Pick) -> Pick {
        let columns = pick.item.notes.map(Self.columnID)
        state.recentColumns = Array((state.recentColumns + columns).suffix(max(1, config.maxRepeats)))
        var again = Pick(item: pick.item, intro: nil, isLessonIntro: false, usedStrongest: false, isStretch: false, size: pick.size,
                         positions: pick.positions)
        again.drill = pick.drill
        return again
    }

    // MARK: building

    private func draft(_ drill: Drill, on clef: Clef, size n: Int, meter: Meter,
                       using rng: inout some RandomNumberGenerator) -> DrillDraft? {
        let notes = drillNotes(clef)
        guard notes.count >= 2 || drill == .repeatNote, !notes.isEmpty else { return nil }
        let beats = meter.beats
        func inPosition() -> (HandPosition, [NoteKey])? {
            drillPosition(notes, on: clef, using: &rng)
        }
        func single(_ keys: [NoteKey], _ position: HandPosition, bars: [Int]? = nil, same: Bool = false) -> DrillDraft {
            DrillDraft(columns: keys.map { WrittenNote($0) },
                       bars: bars ?? Self.barSizes(keys.count, meter: meter, twoBars: false, using: &rng),
                       positions: Array(repeating: position, count: keys.count), sameRhythm: same)
        }
        switch drill {
        case .run:
            guard let (position, inside) = inPosition(), let keys = runKeys(min(n, Self.maxNotes(meter)), from: inside, using: &rng) else { return nil }
            return single(keys, position)
        case .motif:
            // two cells, one a bar each
            let cell = min(beats, n >= 6 ? 3 : 2)
            guard let (position, inside) = inPosition(), let keys = motifKeys(cell: cell, from: inside, using: &rng) else { return nil }
            return single(keys, position, bars: [cell, cell], same: true)
        case .home:
            // G in the hand position, or the lesson's own home note in any position that has it
            let target = lesson.home
            let found = target.map { drillPosition(notes, on: clef, options: HandPosition.standard(clef) + drillPositionOptions(clef),
                                                   holding: $0, using: &rng) } ?? inPosition()
            guard let (position, inside) = found,
                  let home = inside.first(where: { key in target.map { key.pitch == $0 } ?? (key.pitch.letter == .g) }),
                  let keys = homeKeys(min(n, Self.maxNotes(meter)), home: home, from: inside, using: &rng) else { return nil }
            return single(keys, position)
        case .repeatNote:
            guard let (position, inside) = inPosition() ?? HandPosition.holding(notes, on: clef).map({ ($0, notes) }) else { return nil }
            let two = n >= 2 * beats && 2 * beats <= Self.maxNotes(meter)
            let candidates = inside.filter { $0.id != blockedColumn }
            guard !candidates.isEmpty else { return nil }
            // any note alike: a repeated key has nothing in-line to measure, so leaning the
            // repeats toward weak notes would only slow their habit down
            let boxWeight = { (_: NoteKey) in 1.0 }
            let first = candidates[weightedIndex(candidates.map(boxWeight), using: &rng)]
            var keys = Array(repeating: first, count: beats)
            if two {
                let near = inside.filter { $0 != first && abs($0.pitch.diatonicIndex - first.pitch.diatonicIndex) <= 2 }
                guard !near.isEmpty else { return single(keys, position, bars: [beats]) }
                keys += Array(repeating: near[weightedIndex(near.map(boxWeight), using: &rng)], count: beats)
            }
            return single(keys, position, bars: two ? [beats, beats] : [beats])
        case .echo:
            return echoDraft(size: n, meter: meter, using: &rng)
        case .shift:
            return shiftDraft(on: clef, size: n, meter: meter, using: &rng)
        case .movedTwo, .brokenTwo:
            return twoDraft(drill, on: clef, size: n, meter: meter, using: &rng)
        case .rhythmMotif:
            return rhythmMotifDraft(on: clef, meter: meter, using: &rng)
        case .tune:
            return tuneDraft(on: clef, size: n, using: &rng)
        }
    }

    /// Writes the bars' rhythms and makes the screen.
    private func finish(_ draft: DrillDraft, drill: Drill, meter: Meter, clef: Clef, size: Int, strongest: Bool,
                                 using rng: inout some RandomNumberGenerator) -> Pick {
        let rhythms: [BarRhythm]
        if let given = draft.rhythms {
            rhythms = given
        } else if draft.sameRhythm, draft.bars.count == 2, draft.bars[0] == draft.bars[1] {
            let one = Self.readingRhythms([draft.bars[0]], meter: meter, using: &rng)[0]
            rhythms = [one, one]
        } else {
            rhythms = Self.readingRhythms(draft.bars, meter: meter, using: &rng)
        }
        let written = Self.apply(rhythms, to: draft.columns)
        let layout = draft.layout ?? (lesson.layout == .grand ? .grand : lesson.staff(for: clef))
        let item = PracticeItem(written, layout: layout, keySignature: lesson.keySignature, bars: rhythms.map(\.count), meter: meter)
        // a drill lesson's screens are at his size, so it can grow there
        var pick = Pick(item: item, intro: nil, isLessonIntro: false, usedStrongest: strongest, isStretch: false,
                        size: lesson.isDrillLesson && !strongest ? state.screenSize : size, positions: draft.positions)
        pick.drill = drill
        return pick
    }

    // MARK: shapes

    /// `n` notes stepping through `notes` (low to high), turning at each end. Next-door
    /// letters when there's a stretch of 3 or more, otherwise every note in order. Where
    /// it starts and which way it goes leans toward runs that read the notes needing it
    /// most (a five-note run from G rarely gets to D otherwise), and toward starting at
    /// an end, the way a five-finger run goes.
    func runKeys(_ n: Int, from notes: [NoteKey], using rng: inout some RandomNumberGenerator) -> [NoteKey]? {
        let sorted = notes.sorted()
        guard sorted.count >= 2, n >= 2 else { return nil }
        var best = [sorted[0]], current = [sorted[0]]
        for key in sorted.dropFirst() {
            current = key.pitch.diatonicIndex - current.last!.pitch.diatonicIndex == 1 ? current + [key] : [key]
            if current.count > best.count { best = current }
        }
        let steps = best.count >= 3 ? best : sorted
        func walk(from start: Int, _ direction: Int) -> [NoteKey] {
            var index = start, direction = direction
            var out: [NoteKey] = []
            for _ in 0..<n {
                out.append(steps[index])
                if !steps.indices.contains(index + direction) { direction = -direction }
                index += direction
            }
            return out
        }
        // every start and direction, weighted by what the notes after the first read
        // (the first one's time includes taking in the screen), a little more from an end
        var options: [[NoteKey]] = []
        var weights: [Double] = []
        for start in steps.indices {
            for direction in [1, -1] where steps.indices.contains(start + direction) {
                let keys = walk(from: start, direction)
                guard keys[0].id != blockedColumn else { continue }
                let end = start == 0 || start == steps.count - 1
                options.append(keys)
                weights.append(keys.dropFirst().reduce(0.0) { $0 + drillWeight($1) } * (end ? 1.3 : 1))
            }
        }
        guard !options.isEmpty else { return walk(from: 0, 1) }
        return options[weightedIndex(weights, using: &rng)]
    }

    /// A cell of `cell` notes, then the same cell a step away, turned around, or with one
    /// note changed. Every note from `notes` (one hand position). nil when nothing fits.
    func motifKeys(cell: Int, from notes: [NoteKey], using rng: inout some RandomNumberGenerator) -> [NoteKey]? {
        guard notes.count >= 2 else { return nil }
        let byStep = Dictionary(notes.map { ($0.pitch.diatonicIndex, $0) }, uniquingKeysWith: { a, _ in a })
        let shapes: [[Int]] = cell == 2
            ? [[0, 1], [0, -1], [0, 2], [0, -2]]
            : [[0, 1, 2], [0, -1, -2], [0, 2, 1], [0, -2, -1], [0, 1, -1], [0, -1, 1], [0, 2, 4], [0, -2, -4], [0, 1, 0], [0, -1, 0]]
        func keys(_ offsets: [Int], from start: Int) -> [NoteKey]? {
            let found = offsets.compactMap { byStep[start + $0] }
            return found.count == offsets.count ? found : nil
        }
        for _ in 0..<60 {
            let shape = shapes[min(shapes.count - 1, Int(unitInterval(&rng) * Double(shapes.count)))]
            let start = notes[weightedIndex(notes.map(drillWeight), using: &rng)].pitch.diatonicIndex
            guard let first = keys(shape, from: start) else { continue }
            let roll = unitInterval(&rng)
            let way = unitInterval(&rng) < 0.5 ? 1 : -1
            var second: [NoteKey]?
            if roll < 0.45 {
                second = keys(shape, from: start + way) ?? keys(shape, from: start - way) // moved a step
            } else if roll < 0.75 {
                second = Array(first.reversed()) // turned around
            } else {
                var changed = shape
                let j = 1 + min(shape.count - 2, Int(unitInterval(&rng) * Double(shape.count - 1)))
                changed[j] += way
                second = keys(changed, from: start) // one note changed
            }
            guard let second, second != first else { continue }
            let line = first + second
            guard line[0].id != blockedColumn, maxRepeatRun(line) <= config.maxRepeats else { continue }
            return line
        }
        return nil
    }

    /// Every other note is `home`, the others going out from it (nearest first) or
    /// mixed: G A G B G C.
    func homeKeys(_ n: Int, home: NoteKey, from notes: [NoteKey], using rng: inout some RandomNumberGenerator) -> [NoteKey]? {
        let away = notes.filter { $0 != home }
        guard !away.isEmpty, n >= 3 else { return nil }
        let distance = { (k: NoteKey) in abs(k.pitch.diatonicIndex - home.pitch.diatonicIndex) }
        // the away notes it has room for, the ones needing it most first, then half the
        // time put in order going out from home
        var order: [NoteKey] = []
        var left = away
        while !left.isEmpty, order.count < max(1, n / 2) {
            let i = weightedIndex(left.map(drillWeight), using: &rng)
            order.append(left.remove(at: i))
        }
        if unitInterval(&rng) < 0.5 {
            order.sort { distance($0) < distance($1) }
        }
        // starts on home unless home can't come next
        let homeFirst = home.id != blockedColumn
        var out: [NoteKey] = []
        var a = 0
        for i in 0..<n {
            if (i % 2 == 0) == homeFirst {
                out.append(home)
            } else {
                out.append(order[a % order.count])
                a += 1
            }
        }
        return out
    }

    /// Grand staff: a bar on one staff, then the same letters on the other, both bars in
    /// one rhythm.
    private func echoDraft(size n: Int, meter: Meter, using rng: inout some RandomNumberGenerator) -> DrillDraft? {
        guard lesson.layout == .grand else { return nil }
        let k = min(meter.beats, max(2, n / 2))
        let first: Clef = unitInterval(&rng) < 0.5 ? .treble : .bass
        let second: Clef = first == .treble ? .bass : .treble
        guard let (posA, notesA) = drillPosition(drillNotes(first), on: first, using: &rng) else { return nil }
        // a bar of one key repeated echoes nothing
        var bar = line(k, from: notesA, newest: [], fallback: notesA, after: state.recentColumns, using: &rng)
        for _ in 0..<8 where Set(bar).count < 2 {
            bar = line(k, from: notesA, newest: [], fallback: notesA, after: state.recentColumns, using: &rng)
        }
        guard Set(bar).count >= 2 else { return nil }
        let other = drillNotes(second)
        // the same letters, in a hand position on the other staff that holds them all
        for posB in HandPosition.standard(second) + drillPositionOptions(second) {
            let echo = bar.compactMap { key in other.first { posB.contains($0) && $0.pitch.pitchClass == key.pitch.pitchClass } }
            guard echo.count == bar.count else { continue }
            return DrillDraft(columns: (bar + echo).map { WrittenNote($0) }, bars: [k, k],
                              positions: Array(repeating: posA, count: k) + Array(repeating: posB, count: k), sameRhythm: true,
                              layout: .grand)
        }
        return nil
    }

    /// Two bars in two hand positions on one staff. Bar 2 starts on a note only the new
    /// position reaches, so the hand has to move.
    private func shiftDraft(on clef: Clef, size n: Int, meter: Meter, using rng: inout some RandomNumberGenerator) -> DrillDraft? {
        let notes = drillNotes(clef)
        let options = drillPositionOptions(clef).filter { position in notes.filter(position.contains).count >= 3 }
        guard options.count >= 2 else { return nil }
        let k = min(meter.beats, max(2, n / 2))
        let shuffledOptions = shuffled(options, using: &rng)
        let (a, b) = (shuffledOptions[0], shuffledOptions[1])
        guard let bar1 = runKeys(k, from: notes.filter(a.contains), using: &rng) else { return nil }
        for _ in 0..<12 {
            guard let bar2 = runKeys(k, from: notes.filter(b.contains), using: &rng) else { return nil }
            if !a.contains(bar2[0]), bar2[0] != bar1[bar1.count - 1] {
                return DrillDraft(columns: (bar1 + bar2).map { WrittenNote($0) }, bars: [k, k],
                                  positions: Array(repeating: a, count: k) + Array(repeating: b, count: k))
            }
        }
        return nil
    }

    /// Level 4's drill lesson: a two at once moved by step (G+B, A+C, B+D and back), or a
    /// pair broken then together (G B G+B | A C A+C).
    private func twoDraft(_ drill: Drill, on clef: Clef, size n: Int, meter: Meter,
                          using rng: inout some RandomNumberGenerator) -> DrillDraft? {
        guard case .dyads(let intervals) = lesson.texture else { return nil }
        let notes = drillNotes(clef)
        guard let (position, inside) = drillPosition(notes, on: clef, using: &rng) else { return nil }
        let pairsOf = { (interval: Int) in
            inside.compactMap { low -> (NoteKey, NoteKey)? in
                inside.first { $0.pitch.diatonicIndex - low.pitch.diatonicIndex == interval }.map { (low, $0) }
            }
        }
        // moved: thirds (G+B, A+C, B+D). broken: any of the lesson's, so fifths come up too
        let usable = intervals.filter { pairsOf($0).count >= (drill == .movedTwo ? 2 : 1) }
        guard !usable.isEmpty else { return nil }
        let interval = drill == .movedTwo && usable.contains(2) ? 2
            : usable[min(usable.count - 1, Int(unitInterval(&rng) * Double(usable.count)))]
        let pairs = pairsOf(interval)
        let dyad = { (p: (NoteKey, NoteKey)) in WrittenNote(clef, [p.0.pitch, p.1.pitch]) }
        if drill == .movedTwo {
            // the pairs as one run: up a step each column, turning at the ends
            let lows = pairs.map(\.0)
            guard let walk = runKeys(min(n, Self.maxNotes(meter)), from: lows, using: &rng) else { return nil }
            let columns = walk.map { low in dyad(pairs.first { $0.0 == low }!) }
            return DrillDraft(columns: columns, bars: Self.barSizes(columns.count, meter: meter, twoBars: false, using: &rng),
                              positions: Array(repeating: position, count: columns.count))
        }
        // broken then together, once or twice (moved a step), a bar each
        let start = min(pairs.count - 1, Int(unitInterval(&rng) * Double(pairs.count)))
        var cells = [pairs[start]]
        if n >= 6, pairs.count >= 2 {
            let next = start + 1 < pairs.count ? start + 1 : start - 1
            cells.append(pairs[next])
        }
        let columns = cells.flatMap { [WrittenNote($0.0), WrittenNote($0.1), dyad($0)] }
        return DrillDraft(columns: columns, bars: Array(repeating: 3, count: cells.count),
                          positions: Array(repeating: position, count: columns.count), sameRhythm: true)
    }

    /// Level 5's drill lesson: one bar of rhythm, then the same rhythm a step higher (or
    /// lower), or the same notes in a new rhythm.
    private func rhythmMotifDraft(on clef: Clef, meter: Meter, using rng: inout some RandomNumberGenerator) -> DrillDraft? {
        guard case .rhythm(let values, _) = lesson.texture else { return nil }
        let notes = drillNotes(clef)
        guard let (position, inside) = drillPosition(notes, on: clef, using: &rng) else { return nil }
        let byStep = Dictionary(inside.map { ($0.pitch.diatonicIndex, $0) }, uniquingKeysWith: { a, _ in a })
        for _ in 0..<20 {
            let (m, one) = Self.rhythm(bars: 1, from: values, meter: meter, using: &rng)
            let cell = one[0]
            let first = line(cell.count, from: inside, newest: [], fallback: inside, after: state.recentColumns, using: &rng)
            var bars = [cell, cell]
            var second: [NoteKey]?
            if unitInterval(&rng) < 0.5 {
                for way in [1, -1] {
                    let moved = first.compactMap { byStep[$0.pitch.diatonicIndex + way] }
                    if moved.count == first.count { second = moved; break }
                }
            }
            if second == nil {
                // the same notes, a new rhythm with as many notes
                for _ in 0..<30 {
                    let (m2, other) = Self.rhythm(bars: 1, from: values, meter: m, using: &rng)
                    if m2 == m, other[0].count == cell.count, other[0] != cell {
                        bars[1] = other[0]
                        second = first
                        break
                    }
                }
            }
            guard let second, RhythmJudge.telling(Self.rhythmLine(bars)), maxRepeatRun(first + second) <= config.maxRepeats else { continue }
            return DrillDraft(columns: (first + second).map { WrittenNote($0) }, bars: bars.map(\.count),
                              positions: Array(repeating: position, count: first.count + second.count), rhythms: bars, meter: m)
        }
        return nil
    }

    /// The first bar or two of a tune whose every note he has on this clef, as many bars
    /// as fit in `size` notes (at least one).
    private func tuneDraft(on clef: Clef, size n: Int, using rng: inout some RandomNumberGenerator) -> DrillDraft? {
        let notes = Set(drillNotes(clef))
        let limit = max(n, lesson.drillSizes.upperBound)
        var fits: [(tune: Tune, keys: [[NoteKey]])] = []
        for tune in Tune.all {
            var taken: [[NoteKey]] = []
            for bar in tune.keys(clef).prefix(2) {
                guard taken.joined().count + bar.count <= limit, bar.allSatisfy(notes.contains) else { break }
                taken.append(bar)
            }
            if !taken.isEmpty { fits.append((tune, taken)) }
        }
        guard !fits.isEmpty else { return nil }
        let (tune, keys) = fits[min(fits.count - 1, Int(unitInterval(&rng) * Double(fits.count)))]
        guard keys[0][0].id != blockedColumn else { return nil }
        let rhythms = tune.bars.prefix(keys.count).map { BarRhythm($0.map(\.value)) }
        let columns = keys.joined().map { WrittenNote($0) }
        return DrillDraft(columns: columns, bars: keys.map(\.count),
                          positions: Array(repeating: HandPosition.g(clef), count: columns.count), rhythms: rhythms, meter: tune.meter)
    }
}

/// Longest run of the same key in a row.
func maxRepeatRun(_ keys: [NoteKey]) -> Int {
    var best = 0, run = 0
    var last: NoteKey?
    for key in keys {
        run = key == last ? run + 1 : 1
        last = key
        best = max(best, run)
    }
    return best
}
