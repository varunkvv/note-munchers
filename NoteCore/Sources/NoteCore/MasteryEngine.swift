public struct AttemptSample: Hashable, Codable, Sendable {
    public var firstTry: Bool
    public var responseTime: Double

    public init(firstTry: Bool, responseTime: Double) {
        self.firstTry = firstTry
        self.responseTime = responseTime
    }
}

/// Rolling stats for one item. Value type, Codable - lives inside `MasteryState`.
public struct ItemStats: Hashable, Codable, Sendable {
    /// Leitner box, 1...boxCount. Right first try moves up one, a miss moves down one.
    public var box = 1
    /// Last `solidWindow` attempts, oldest first. Intros are not in here.
    public var recent: [AttemptSample] = []
    public var attempts = 0
    public var firstTryCount = 0

    /// Rhythm items only: the separate rhythm track.
    public var rhythmBox = 1
    public var rhythmRecent: [Bool] = []
    public var rhythmAttempts = 0

    /// Highest fluency ever reached (0...1). Never goes down, so his muncher for this
    /// note never shrinks.
    public var peakFluency = 0.0

    public init() {}

    public var medianResponse: Double? {
        recent.isEmpty ? nil : median(recent.map(\.responseTime))
    }

    public var recentFirstTryRate: Double? {
        recent.isEmpty ? nil : Double(recent.filter(\.firstTry).count) / Double(recent.count)
    }
}

/// Everything the engine remembers. The app saves this (e.g. JSON-encoded in one
/// SwiftData record) after every item and restores it with `MasteryEngine(state:)`.
public struct MasteryState: Hashable, Codable, Sendable {
    /// Current unit number.
    public var unit = 1
    /// Per unit number: how many of its new items are unlocked. Items never re-lock.
    public var unlockedCounts: [Int: Int] = [:]
    public var completedUnits: Set<Int> = []
    public var stats: [ItemID: ItemStats] = [:]
    /// Items that have had their intro.
    public var introduced: Set<ItemID> = []
    /// Last `solidWindow` attempts in the current unit. Reset when the unit changes.
    public var unitRecent: [AttemptSample] = []
    /// Last few picks, for the no-repeat rule.
    public var recentPicks: [ItemID] = []

    public init() {}
}

/// What changed after recording an attempt.
public struct MasteryUpdate: Hashable, Codable, Sendable {
    /// Newly unlocked items (a new egg hatches for each).
    public var unlocked: [ItemID] = []
    public var completedUnit: Int?
    /// Set when the engine moved to another unit.
    public var enteredUnit: Int?
    public init() {}
}

/// How to pick the next item.
public enum PickStyle: String, Codable, Hashable, Sendable {
    /// Intros first, then the newest share and low boxes.
    case normal
    /// His strongest items: highest box among items he has already played, a different
    /// one from the last pick when there's a choice. Used for the warm-up, easing after
    /// misses, and the easy items at the end. No intros. Falls back to `normal` when he
    /// hasn't played anything in this pool yet.
    case strongest
}

public enum UnitStatus: String, Codable, Hashable, Sendable {
    case completed, current, skipped, upcoming
}

/// Progress for one item, for the munchers view and the parent dashboard.
public struct NoteProgress: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public let kind: PracticeItem.Kind
    /// The unit that introduces it.
    public let unit: Int
    public let box: Int
    public let isSolid: Bool
    public let attempts: Int
    /// Over the last `solidWindow` attempts.
    public let recentFirstTryRate: Double?
    public let medianResponse: Double?
    /// Rhythm items only.
    public let rhythmBox: Int?
    /// 0...1 from the leitner box and how fast he finds it. Can dip after misses.
    public let fluency: Double
    /// Highest `fluency` ever. Use this to size his muncher so it never shrinks.
    public let peakFluency: Double
}

/// Leitner boxes, the unlock gate, unit progression and the next-item picker.
///
/// Pure value type. No clock, no randomness of its own - `pickNext` takes the generator.
public struct MasteryEngine: Sendable {
    public let curriculum: Curriculum
    public var config: NoteCoreConfig
    public private(set) var state: MasteryState

    public init(curriculum: Curriculum = .standard, config: NoteCoreConfig = .default, state: MasteryState = MasteryState()) {
        precondition(!curriculum.units.isEmpty)
        self.curriculum = curriculum
        self.config = config
        self.state = state
        let unitNumber = curriculum.unitNumbers.contains(state.unit) ? state.unit : 1
        _ = enter(unitNumber, resetWindow: unitNumber != state.unit)
    }

    // MARK: reading

    public var unit: Unit { curriculum.unit(state.unit)! }

    public func unlockedCount(_ unitNumber: Int) -> Int {
        guard let unit = curriculum.unit(unitNumber) else { return 0 }
        return min(state.unlockedCounts[unitNumber] ?? 0, unit.newItems.count)
    }

    /// Items the picker draws from: the current unit's unlocked items plus every item
    /// of the units it reviews.
    public var pool: [PracticeItem] {
        let own = Array(unit.newItems.prefix(unlockedCount(unit.number)))
        let reviewed = unit.reviews.flatMap { curriculum.unit($0)?.newItems ?? [] }
        return own + reviewed
    }

    /// The most recently unlocked item, or the starting batch if nothing has unlocked
    /// since the unit began. Empty for a review-only unit.
    public var newestBatch: [PracticeItem] {
        let count = unlockedCount(unit.number)
        guard count > 0 else { return [] }
        if count <= unit.startCount {
            return Array(unit.newItems.prefix(count))
        }
        return [unit.newItems[count - 1]]
    }

    public func stats(for id: ItemID) -> ItemStats { state.stats[id] ?? ItemStats() }

    /// 7 of the last 8 right first try with median response under 4s, or the fast
    /// track: the last 5 all right first try, each under 2s.
    public func isPitchSolid(_ id: ItemID) -> Bool {
        let recent = stats(for: id).recent
        return isSolid(recent)
    }

    /// Rhythm track: 6 of the last 8 judged runs fully ok, or the last 5 all ok.
    public func isRhythmSolid(_ id: ItemID) -> Bool {
        let recent = stats(for: id).rhythmRecent.suffix(config.solidWindow)
        if recent.filter({ $0 }).count >= config.rhythmSolidRequired { return true }
        return recent.count >= config.fastTrackCount && recent.suffix(config.fastTrackCount).allSatisfy { $0 }
    }

    /// Pitch solid, and rhythm solid too for rhythm items.
    public func isSolid(item: PracticeItem) -> Bool {
        isPitchSolid(item.id) && (!item.isRhythm || isRhythmSolid(item.id))
    }

    /// The unlock gate: newest item(s) solid AND nothing in the pool below box 3.
    /// Only the pitch box counts here, so a rhythm slip never holds anything back.
    public var isGateOpen: Bool {
        newestBatch.allSatisfy { isSolid(item: $0) }
            && pool.allSatisfy { stats(for: $0.id).box >= config.gateMinBox }
    }

    /// Does this item get the intro treatment (keyboard picture up front) next time?
    public func needsIntro(_ item: PracticeItem) -> Bool {
        unit.newItems.contains(item) && !state.introduced.contains(item.id)
    }

    public func status(ofUnit number: Int) -> UnitStatus {
        if number == state.unit { return .current }
        if state.completedUnits.contains(number) { return .completed }
        return number < state.unit ? .skipped : .upcoming
    }

    public var isCurriculumComplete: Bool { state.completedUnits.contains(curriculum.units.count) }

    public func progress(for id: ItemID) -> NoteProgress? {
        guard let item = curriculum.item(id), let unitNumber = curriculum.unitNumber(of: id) else { return nil }
        let s = stats(for: id)
        return NoteProgress(
            id: id, kind: item.kind, unit: unitNumber, box: s.box, isSolid: isSolid(item: item),
            attempts: s.attempts, recentFirstTryRate: s.recentFirstTryRate, medianResponse: s.medianResponse,
            rhythmBox: item.isRhythm ? s.rhythmBox : nil, fluency: fluency(s), peakFluency: s.peakFluency
        )
    }

    /// Every item he has played at least once (not counting intros), in curriculum order.
    public var allProgress: [NoteProgress] {
        curriculum.allItems.filter { stats(for: $0.id).attempts > 0 }.compactMap { progress(for: $0.id) }
    }

    /// 0...1. 60% from the leitner box, 40% from speed: full marks at half the
    /// fast-track time or quicker, none at the solid threshold or slower.
    public func fluency(_ s: ItemStats) -> Double {
        guard s.attempts > 0 else { return 0 }
        let boxPart = Double(s.box - 1) / Double(max(1, config.boxCount - 1))
        var speedPart = 0.0
        if let m = s.medianResponse {
            let fast = config.fastTrackResponse / 2
            let slow = config.solidMedianResponse
            speedPart = min(1, max(0, (slow - m) / (slow - fast)))
        }
        return 0.6 * boxPart + 0.4 * speedPart
    }

    // MARK: changing

    /// Records one finished item and opens the gate if it's ready.
    @discardableResult
    public mutating func record(_ attempt: AttemptResult) -> MasteryUpdate {
        var update = MasteryUpdate()
        guard let item = curriculum.item(attempt.itemID) else { return update }
        state.introduced.insert(item.id)
        var s = stats(for: item.id)
        if attempt.wasIntro {
            return update
        }

        let sample = AttemptSample(firstTry: attempt.firstTry, responseTime: max(0, attempt.responseTime))
        s.recent = Array((s.recent + [sample]).suffix(config.solidWindow))
        // stuck isn't wrong: a hint from being stuck alone holds the box where it is
        if attempt.firstTry {
            s.box = min(config.boxCount, s.box + 1)
        } else if attempt.wrongPresses > 0 {
            s.box = max(1, s.box - 1)
        }
        s.attempts += 1
        s.firstTryCount += attempt.firstTry ? 1 : 0
        if item.isRhythm, let rhythm = attempt.rhythm {
            s.rhythmRecent = Array((s.rhythmRecent + [rhythm.isOK]).suffix(config.solidWindow))
            s.rhythmBox = rhythm.isOK ? min(config.boxCount, s.rhythmBox + 1) : max(1, s.rhythmBox - 1)
            s.rhythmAttempts += 1
        }
        s.peakFluency = max(s.peakFluency, fluency(s))
        state.stats[item.id] = s

        if pool.contains(item) {
            state.unitRecent = Array((state.unitRecent + [sample]).suffix(config.solidWindow))
        }
        advance(&update)
        return update
    }

    private mutating func advance(_ update: inout MasteryUpdate) {
        guard isGateOpen else { return }
        let current = unit
        let count = unlockedCount(current.number)
        if count < current.newItems.count {
            state.unlockedCounts[current.number] = count + 1
            update.unlocked.append(current.newItems[count].id)
            return
        }
        // everything in the unit is out. the unit is done once its recent attempts are solid too
        guard isSolid(state.unitRecent) else { return }
        state.completedUnits.insert(current.number)
        update.completedUnit = current.number
        // move on to the next unit not done yet (a parent may have moved him back)
        guard let next = curriculum.units.first(where: {
            $0.number > current.number && !state.completedUnits.contains($0.number)
        }) else { return }
        update.enteredUnit = next.number
        update.unlocked += enter(next.number, resetWindow: true)
    }

    /// Parent skip forward or back. Earlier units are not marked done by skipping
    /// ahead. Going back to a unit means he plays it until it's solid again (fresh
    /// attempts), then moves on to the first unit that isn't done.
    @discardableResult
    public mutating func moveToUnit(_ number: Int) -> [ItemID] {
        guard curriculum.unitNumbers.contains(number), number != state.unit else { return [] }
        return enter(number, resetWindow: true)
    }

    /// Returns the ids that unlocked on entry.
    private mutating func enter(_ number: Int, resetWindow: Bool) -> [ItemID] {
        let unit = curriculum.unit(number)!
        state.unit = number
        if resetWindow {
            state.unitRecent = []
        }
        let before = unlockedCount(number)
        let after = max(before, unit.startCount)
        state.unlockedCounts[number] = after
        return unit.newItems[before..<after].map(\.id)
    }

    /// Pool items he has played at least once (intros don't count). These are what a
    /// `.strongest` pick chooses from.
    public var playedPool: [PracticeItem] {
        pool.filter { stats(for: $0.id).attempts > 0 && !needsIntro($0) }
    }

    /// Picks the next item to show.
    ///
    /// - a new item that hasn't had its intro goes first, in curriculum order
    /// - otherwise the newest batch shares `newestShare` (25%), the rest share what's
    ///   left, weighted toward low boxes (weight 6 - box, so box 1 is 5x box 5)
    /// - `.strongest` skips both and takes one of his highest-box items instead
    /// - an item picked `maxRepeats` (2) times in a row is never picked a third time
    ///   while the pool has 2+ items
    public mutating func pickNext(_ style: PickStyle = .normal, using rng: inout some RandomNumberGenerator) -> PracticeItem {
        let pool = self.pool
        precondition(!pool.isEmpty, "unit \(unit.number) has an empty pool")
        let recent = state.recentPicks.suffix(config.maxRepeats)
        var blocked: ItemID?
        if pool.count > 1, recent.count == config.maxRepeats, Set(recent).count == 1 {
            blocked = recent.first
        }
        let picked: PracticeItem
        if style == .strongest, let strong = strongestPick(blocked: blocked, using: &rng) {
            picked = strong
        } else if let intro = pool.first(where: { $0.id != blocked && needsIntro($0) }) {
            picked = intro
        } else {
            // weigh the whole pool, then drop the blocked item, so blocking one item
            // doesn't hand its share to whichever item happens to be left in its group
            let newestIDs = Set(newestBatch.map(\.id))
            let newest = pool.filter { newestIDs.contains($0.id) }
            let others = pool.filter { !newestIDs.contains($0.id) }
            var weighted: [(PracticeItem, Double)]
            if newest.isEmpty || others.isEmpty {
                weighted = pool.map { ($0, boxWeight($0)) }
            } else {
                let otherTotal = others.reduce(0) { $0 + boxWeight($1) }
                weighted = newest.map { ($0, config.newestShare / Double(newest.count)) }
                weighted += others.map { ($0, (1 - config.newestShare) * boxWeight($0) / otherTotal) }
            }
            picked = weightedPick(weighted.filter { $0.0.id != blocked }, using: &rng)
        }
        state.recentPicks = Array((state.recentPicks + [picked.id]).suffix(max(1, config.maxRepeats)))
        return picked
    }

    private func strongestPick(blocked: ItemID?, using rng: inout some RandomNumberGenerator) -> PracticeItem? {
        var eligible = playedPool.filter { $0.id != blocked }
        if eligible.count > 1, let last = state.recentPicks.last {
            eligible.removeAll { $0.id == last }
        }
        guard let top = eligible.map(effectiveBox).max() else { return nil }
        let tier = eligible.filter { effectiveBox($0) == top }
        return tier[min(tier.count - 1, Int(unitInterval(&rng) * Double(tier.count)))]
    }

    /// The pitch box, or the lower of pitch and rhythm boxes for rhythm items.
    private func effectiveBox(_ item: PracticeItem) -> Int {
        let s = stats(for: item.id)
        return item.isRhythm ? min(s.box, s.rhythmBox) : s.box
    }

    private func boxWeight(_ item: PracticeItem) -> Double {
        Double(config.boxCount + 1 - effectiveBox(item))
    }

    private func weightedPick(_ weighted: [(PracticeItem, Double)], using rng: inout some RandomNumberGenerator) -> PracticeItem {
        let total = weighted.reduce(0) { $0 + $1.1 }
        var target = unitInterval(&rng) * total
        for (item, weight) in weighted {
            if target < weight { return item }
            target -= weight
        }
        return weighted[weighted.count - 1].0
    }

    private func isSolid(_ recent: [AttemptSample]) -> Bool {
        let window = recent.suffix(config.solidWindow)
        let firstTries = window.filter(\.firstTry).count
        if firstTries >= config.solidRequired, median(window.map(\.responseTime)) < config.solidMedianResponse {
            return true
        }
        let streak = window.suffix(config.fastTrackCount)
        return streak.count == config.fastTrackCount
            && streak.allSatisfy { $0.firstTry && $0.responseTime < config.fastTrackResponse }
    }
}

/// [0, 1) from 53 random bits. Our own, so picks don't depend on stdlib internals.
func unitInterval(_ rng: inout some RandomNumberGenerator) -> Double {
    Double(rng.next() >> 11) * 0x1p-53
}

func median(_ values: [Double]) -> Double {
    precondition(!values.isEmpty)
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

// see LenientDecoding.swift
extension MasteryState {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MasteryState()
        unit = try c.value(.unit, or: d.unit)
        unlockedCounts = try c.value(.unlockedCounts, or: d.unlockedCounts)
        completedUnits = try c.value(.completedUnits, or: d.completedUnits)
        stats = try c.value(.stats, or: d.stats)
        introduced = try c.value(.introduced, or: d.introduced)
        unitRecent = try c.value(.unitRecent, or: d.unitRecent)
        recentPicks = try c.value(.recentPicks, or: d.recentPicks)
    }
}

extension ItemStats {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ItemStats()
        box = try c.value(.box, or: d.box)
        recent = try c.value(.recent, or: d.recent)
        attempts = try c.value(.attempts, or: d.attempts)
        firstTryCount = try c.value(.firstTryCount, or: d.firstTryCount)
        rhythmBox = try c.value(.rhythmBox, or: d.rhythmBox)
        rhythmRecent = try c.value(.rhythmRecent, or: d.rhythmRecent)
        rhythmAttempts = try c.value(.rhythmAttempts, or: d.rhythmAttempts)
        peakFluency = try c.value(.peakFluency, or: d.peakFluency)
    }
}
