public enum RhythmVerdict: String, Codable, Hashable, Sendable {
    case ok
    /// Next key came (or the last key lifted) clearly too early for the written length.
    case tooShort
    /// Next key came clearly too late. Never given for the last note.
    case tooLong
}

public struct RhythmResult: Hashable, Codable, Sendable {
    /// One per written note.
    public let verdicts: [RhythmVerdict]
    /// His beat (seconds per quarter) for this run. Use it to play the line back at his tempo.
    public let beat: Double

    public var isOK: Bool { verdicts.allSatisfy { $0 == .ok } }

    /// The note to nudge about: the first too-short one, else the first too-long one.
    public var nudgeIndex: Int? {
        verdicts.firstIndex(of: .tooShort) ?? verdicts.firstIndex(of: .tooLong)
    }
}

/// Loose rhythm judging at his own tempo. No metronome.
///
/// - only key-downs matter for every note but the last: the gap to the next key-down
///   is that note's length. Kids lift early, so hold time is ignored
/// - the last note's length is how long he held it. It can be too short, never too long
/// - his beat is the (lower) median of what each note implies (gap / written beats),
///   so a whole phrase played slow or fast passes, and one shortened half stands out
/// - each length passes between `minRatio` and `maxRatio` of the written length at his beat
///
/// Pitch is judged elsewhere. Nothing here can turn a right key into a wrong one.
public struct RhythmJudge: Sendable {
    public var minRatio: Double
    public var maxRatio: Double

    public init(config: NoteCoreConfig = .default) {
        minRatio = config.rhythmMinRatio
        maxRatio = config.rhythmMaxRatio
    }

    /// - values: written lengths, in order
    /// - onsets: key-down time of each note (same count as values)
    /// - release: key-up time of the last note
    public func judge(_ values: [NoteValue], onsets: [Double], release: Double) -> RhythmResult {
        precondition(!values.isEmpty && values.count == onsets.count)
        let lengths = zip(onsets, onsets.dropFirst() + [release]).map { max(0, $1 - $0) }
        let beat = estimateBeat(values, lengths: lengths)
        guard beat > 0 else {
            return RhythmResult(verdicts: values.map { _ in .ok }, beat: 0)
        }
        let verdicts = zip(values, lengths).enumerated().map { index, pair in
            let ratio = pair.1 / (pair.0.beats * beat)
            if ratio < minRatio { return RhythmVerdict.tooShort }
            if ratio > maxRatio, index < values.count - 1 { return .tooLong }
            return .ok
        }
        return RhythmResult(verdicts: verdicts, beat: beat)
    }

    /// After this time the result can't change however long he holds the last key,
    /// so the session can stop waiting for the key-up.
    public func settleTime(_ values: [NoteValue], onsets: [Double]) -> Double {
        precondition(!values.isEmpty && values.count == onsets.count)
        let last = onsets[onsets.count - 1]
        let gaps = zip(onsets, onsets.dropFirst()).map { $1 - $0 }
        guard let cap = holdCap(gapSamples: zip(gaps, values).map { $0 / $1.beats }) else {
            return last + values[values.count - 1].beats * 2 // single note: nothing to compare against
        }
        return last + values[values.count - 1].beats * cap
    }

    /// A long final hold must not stretch his beat, so the hold's sample is capped
    /// at the slowest beat any gap implied, times `maxRatio`.
    private func holdCap(gapSamples: [Double]) -> Double? {
        gapSamples.max().map { $0 * maxRatio }
    }

    private func estimateBeat(_ values: [NoteValue], lengths: [Double]) -> Double {
        let samples = zip(lengths, values).map { $0 / $1.beats }
        let gapSamples = Array(samples.dropLast())
        guard let cap = holdCap(gapSamples: gapSamples) else { return samples[0] }
        return lowerMedian(gapSamples + [min(samples[samples.count - 1], cap)])
    }

    /// Lower median. On a tie between two readings of his tempo it picks the faster
    /// one, so an ambiguous run blames the long notes (too long, not voiced) instead
    /// of telling him to hold a note he may have played right.
    private func lowerMedian(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }
}
