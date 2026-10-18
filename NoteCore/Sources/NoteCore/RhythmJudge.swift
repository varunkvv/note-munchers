public enum RhythmVerdict: String, Codable, Hashable, Sendable {
    /// About the written length at his tempo.
    case ok
    /// Inside the wide window but uneven. Still fine, nothing is said (sloppy is fine).
    case bitOff
    /// Wrong value, played short: clearly closer to half the written length (a half
    /// played as a quarter, a quarter as an eighth). Gets a replay and another go.
    case tooShort
    /// Wrong value, played long: near double the written length (an eighth played as a
    /// quarter, a quarter as a half). Only for eighths and quarters with no rest after
    /// them, never the last note, never a gap long enough to be him reading.
    case tooLong
    /// A gap far beyond the next value up: him reading the next note, not a rhythm. Not judged.
    case pause
    /// A note this level doesn't judge (level 3: anything but quarters and halves, and
    /// notes with a rest after them). Drawn, not listened to.
    case unjudged

    /// Played as a different value.
    public var isWrongValue: Bool { self == .tooShort || self == .tooLong }
}

public struct RhythmResult: Hashable, Codable, Sendable {
    /// One per written note.
    public let verdicts: [RhythmVerdict]
    /// His beat (seconds per quarter) for this run. Use it to play the line back at his tempo.
    public let beat: Double

    public init(verdicts: [RhythmVerdict], beat: Double) {
        self.verdicts = verdicts
        self.beat = beat
    }

    /// No wrong values. Sloppy, uneven and paused is all fine.
    public var isOK: Bool { !verdicts.contains(where: \.isWrongValue) }

    /// The first note played as a different value: a short one first, else a long one.
    public var nudgeIndex: Int? {
        verdicts.firstIndex(of: .tooShort) ?? verdicts.firstIndex(of: .tooLong)
    }
}

/// How much of the rhythm a level listens to (plans/2026-10-15-real-bars.md). Never
/// about perfection: the point is knowing a half from a quarter.
public enum RhythmCheck: String, Codable, Hashable, Sendable {
    /// Levels 1-2: values and rests are drawn, he plays at his own pace, only pitch is judged.
    case off
    /// Level 3: only "was the half clearly longer than the quarter". Quarters and halves
    /// with no rest after them, judged against his own quarters on the screen. Only a half
    /// played short is a wrong value. Wholes, dotted halves and rests are drawn, not judged.
    case halves
    /// Levels 4-5: every value, and rests count into the gap before the next key.
    case all
}

/// What the judge listens to on one screen: each note's written value, the beats from
/// it to the next key (its value plus any rests after it; the last note's own value),
/// and which notes are judged.
public struct RhythmLine: Hashable, Sendable {
    public let values: [NoteValue]
    public let gaps: [Double]
    public let judged: [Bool]
    public let check: RhythmCheck

    public init(values: [NoteValue], gaps: [Double]? = nil, judged: [Bool]? = nil, check: RhythmCheck = .all) {
        precondition(!values.isEmpty)
        self.values = values
        self.gaps = gaps ?? values.map(\.beats)
        self.judged = judged ?? values.map { _ in true }
        self.check = check
        precondition(self.gaps.count == values.count && self.judged.count == values.count)
    }

    /// Notes his beat is read from: his quarters in level 3, every judged note after that.
    var reference: [Bool] {
        zip(values, judged).map { value, judged in judged && (check != .halves || value == .quarter) }
    }
}

extension PracticeItem {
    /// What the judge listens to on this screen at `check`, or nil when nothing can be
    /// judged: no meter, rhythm off, fewer than 3 judged notes, one length only, or a
    /// line he could play all one length and pass (the judge's invariants,
    /// context/notecore-design.md). Level 3 also needs a quarter with a gap after it to
    /// read his beat from.
    public func rhythmLine(_ check: RhythmCheck) -> RhythmLine? {
        guard check != .off, meter != nil, notes.count >= 3 else { return nil }
        let last = notes.count - 1
        let gaps = gapBeats
        let judged = notes.indices.map { i -> Bool in
            switch check {
            case .off: false
            case .halves: (notes[i].value == .quarter || notes[i].value == .half) && (i == last || notes[i].restsAfter.isEmpty)
            case .all: true
            }
        }
        let indices = notes.indices.filter { judged[$0] }
        guard indices.count >= 3 else { return nil }
        switch check {
        case .off: return nil
        case .halves:
            let values = Set(indices.map { notes[$0].value })
            guard values == [.quarter, .half], indices.contains(where: { $0 != last && notes[$0].value == .quarter }) else { return nil }
        case .all:
            guard Set(indices.map { gaps[$0] }).count >= 2 else { return nil }
        }
        let line = RhythmLine(values: values, gaps: gaps, judged: judged, check: check)
        return RhythmJudge.telling(line) ? line : nil
    }
}

/// Loose rhythm judging at his own tempo. No metronome.
///
/// - only key-downs matter for every note but the last: the gap to the next key-down
///   is that note's length (its value plus any rests after it). Kids lift early, so hold
///   time is ignored
/// - the last note's length is how long he held it. It can be too short, never too long
/// - his beat is the (lower) median of what each reference note implies (gap / written
///   beats), so a whole phrase played slow or fast passes, and one shortened half stands
///   out. Level 3 reads it from his quarters only
/// - each length is ok between `minRatio` and `maxRatio` of its written length at his
///   beat, a bit off outside `rhythmEvenMin...rhythmEvenMax` (still fine). Shorter is a
///   wrong value (played as half its value); longer is a wrong value up to `pauseRatio`,
///   past that it's him reading the next note and isn't judged
///
/// Pitch is judged elsewhere. Nothing here can turn a right key into a wrong one.
public struct RhythmJudge: Sendable {
    public var minRatio: Double
    public var maxRatio: Double
    public var evenMin: Double
    public var evenMax: Double
    public var pauseRatio: Double

    public init(config: NoteCoreConfig = .default) {
        minRatio = config.rhythmMinRatio
        maxRatio = config.rhythmMaxRatio
        evenMin = config.rhythmEvenMin
        evenMax = config.rhythmEvenMax
        pauseRatio = config.rhythmPauseRatio
    }

    /// Every note judged, gaps = written values (no rests).
    public func judge(_ values: [NoteValue], onsets: [Double], release: Double) -> RhythmResult {
        judge(RhythmLine(values: values), onsets: onsets, release: release)
    }

    /// - onsets: key-down time of each note (same count as the line)
    /// - release: key-up time of the last note
    public func judge(_ line: RhythmLine, onsets: [Double], release: Double) -> RhythmResult {
        precondition(line.values.count == onsets.count)
        let last = onsets.count - 1
        let lengths = zip(onsets, onsets.dropFirst() + [release]).map { max(0, $1 - $0) }
        let beat = estimateBeat(line, lengths: lengths)
        guard beat > 0 else {
            return RhythmResult(verdicts: line.judged.map { $0 ? .ok : .unjudged }, beat: 0)
        }
        let verdicts = line.values.indices.map { i -> RhythmVerdict in
            guard line.judged[i] else { return .unjudged }
            let ratio = lengths[i] / (line.gaps[i] * beat)
            // level 3 only asks whether the half was clearly longer than his quarters
            let flags = line.check != .halves || line.values[i] == .half
            if i != last, ratio >= pauseRatio { return .pause }
            if ratio < minRatio { return flags ? .tooShort : .bitOff }
            // played long is only a wrong value for a short note with nothing after it (an
            // eighth as a quarter, a quarter as a half). After a half, a whole or a rest a
            // long gap is much more likely him reading the next bar
            if i != last, ratio > maxRatio {
                return flags && line.check != .halves && line.gaps[i] <= 1 ? .tooLong : .bitOff
            }
            if ratio < evenMin || (i != last && ratio > evenMax) { return .bitOff }
            return .ok
        }
        return RhythmResult(verdicts: verdicts, beat: beat)
    }

    /// After this time the result can't change however long he holds the last key,
    /// so the session can stop waiting for the key-up.
    public func settleTime(_ line: RhythmLine, onsets: [Double]) -> Double {
        precondition(line.values.count == onsets.count)
        let last = onsets.count - 1
        guard let cap = holdCap(line, lengths: zip(onsets, onsets.dropFirst()).map { $1 - $0 } + [0]) else {
            return onsets[last] + line.gaps[last] * 2 // single note: nothing to compare against
        }
        return onsets[last] + line.gaps[last] * cap
    }

    public func settleTime(_ values: [NoteValue], onsets: [Double]) -> Double {
        settleTime(RhythmLine(values: values), onsets: onsets)
    }

    /// The judge could tell this line from every note played the same length. A line
    /// where it can't (2 notes, or dh | h q, read as a fast dh and h and a long last
    /// quarter) isn't worth judging.
    public static func telling(_ line: RhythmLine) -> Bool {
        let onsets = line.values.indices.map(Double.init)
        return !RhythmJudge().judge(line, onsets: onsets, release: Double(line.values.count)).isOK
    }

    /// A long final hold must not stretch his beat, so the hold's sample is capped
    /// at the slowest beat any reference gap implied, times `maxRatio`.
    private func holdCap(_ line: RhythmLine, lengths: [Double]) -> Double? {
        let last = line.values.count - 1
        let samples = line.reference.indices.filter { line.reference[$0] && $0 != last }.map { lengths[$0] / line.gaps[$0] }
        return samples.max().map { $0 * maxRatio }
    }

    private func estimateBeat(_ line: RhythmLine, lengths: [Double]) -> Double {
        let last = line.values.count - 1
        var reference = line.reference
        if !reference.contains(true) { reference = line.judged }
        let cap = holdCap(line, lengths: lengths)
        var samples = reference.indices.filter { reference[$0] && $0 != last }.map { lengths[$0] / line.gaps[$0] }
        if reference[last] {
            let hold = lengths[last] / line.gaps[last]
            samples.append(cap.map { min(hold, $0) } ?? hold)
        }
        guard !samples.isEmpty else { return 0 }
        return lowerMedian(samples)
    }

    /// Lower median. On a tie between two readings of his tempo it picks the faster
    /// one, so an ambiguous run blames the long notes (too long) instead of telling him
    /// to hold a note he may have played right.
    private func lowerMedian(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }
}

/// Level 2 doesn't judge rhythm: it's drawn, he plays at his own pace, and with no voice
/// a judged rhythm would be replays and retries (heavy for level 2). On a screen whose two
/// bars share a rhythm it's measured silently for the parent dashboard (a piano teacher's
/// review, 2026-10-17): were the halves held longer than the quarters, and did bar 2 go
/// like bar 1. If he already does it, level 3's halves check is a non-event. From his
/// key-downs only (the last note's length isn't known).
public struct RhythmMeasure: Hashable, Codable, Sendable {
    /// Seconds from each key-down to the next, every note but the last.
    public var gaps: [Double]
    /// No half played short against his quarters on the screen, the way level 3's check
    /// reads it (a half and a quarter with nothing after them to compare). nil without both.
    public var halvesLonger: Bool?
    /// Each note of bar 2 took about as long as the same note of bar 1 (`barsMatchRange`).
    /// nil when bar 2 has nothing to compare (one note a bar).
    public var barsMatch: Bool?

    public init(gaps: [Double], halvesLonger: Bool?, barsMatch: Bool?) {
        self.gaps = gaps
        self.halvesLonger = halvesLonger
        self.barsMatch = barsMatch
    }

    /// Bar 2's note over bar 1's: inside this is "about as long".
    public static let barsMatchRange = (1.0 / 1.5)...1.5
}

extension RhythmJudge {
    /// The silent measure of a screen whose two bars share a rhythm, from his key-downs.
    /// nil for any other screen.
    public func measure(_ item: PracticeItem, onsets: [Double]) -> RhythmMeasure? {
        guard item.hasSameRhythmBars, onsets.count == item.notes.count, onsets.count >= 3 else { return nil }
        let gaps = zip(onsets, onsets.dropFirst()).map { $1 - $0 }
        let last = item.notes.count - 1
        // halves against his quarters, as level 3 reads them, the last note left out
        let judged = item.notes.indices.map { i in
            i != last && item.notes[i].restsAfter.isEmpty && (item.notes[i].value == .quarter || item.notes[i].value == .half)
        }
        var halvesLonger: Bool?
        let halves = item.notes.indices.filter { judged[$0] && item.notes[$0].value == .half }
        if !halves.isEmpty, item.notes.indices.contains(where: { judged[$0] && item.notes[$0].value == .quarter }) {
            let line = RhythmLine(values: item.values, gaps: item.gapBeats, judged: judged, check: .halves)
            let verdicts = judge(line, onsets: onsets, release: onsets[last]).verdicts
            let read = halves.filter { verdicts[$0] != .pause }
            halvesLonger = read.isEmpty ? nil : read.allSatisfy { verdicts[$0] != .tooShort }
        }
        // bar 2 against bar 1, note by note (bar 1's last gap crosses the bar line, bar 2's
        // last note has none)
        let k = item.bars[0]
        let pairs = (0..<max(0, k - 1)).map { (gaps[$0], gaps[k + $0]) }
        let barsMatch = pairs.isEmpty ? nil : pairs.allSatisfy { a, b in a > 0 && RhythmMeasure.barsMatchRange.contains(b / a) }
        return RhythmMeasure(gaps: gaps, halvesLonger: halvesLonger, barsMatch: barsMatch)
    }
}
